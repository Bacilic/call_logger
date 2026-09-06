import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import '../../../core/database/database_maintenance_repository.dart';
import '../../../core/database/database_schema_migrations.dart';
import '../../../core/database/sqlite_types.dart';

import '../../../core/config/app_config.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/old_database/lamp_settings_store.dart';
import '../../../core/services/building_map_storage.dart';
import '../../../core/services/core_lexicon_service.dart';
import '../../../core/services/portable_lamp_storage.dart';
import '../../../core/services/portable_tool_image_storage.dart';
import '../../../core/utils/user_facing_error_messages.dart';
import '../models/database_backup_settings.dart';
import '../utils/backup_destination_folder_validator.dart';
import '../utils/portable_backup_availability.dart';
import 'backup_retention.dart';
import 'backup_zip_manifest.dart';
import 'database_backup_audit.dart';
import 'portable_content_fingerprint.dart';
import 'restore_report.dart';

/// Κωδικοί αποτυχίας backup (για UI / scheduler).
abstract final class DatabaseBackupFailureCode {
  static const String folderMissing = 'folder_missing';
}

/// Συντόμευση για χρήση μέσα στο αρχείο, ώστε οι κλήσεις να μένουν σε μία
/// γραμμή.
const String failureCodeFolderMissing = DatabaseBackupFailureCode.folderMissing;

/// Αποτέλεσμα χειροκίνητου ή προγραμματισμένου backup.
class DatabaseBackupResult {
  const DatabaseBackupResult({
    required this.success,
    this.outputPath,
    this.message,
    this.failureCode,
    this.isFullBackup = false,
    this.portableFingerprint,
  });

  final bool success;
  final String? outputPath;
  final String? message;
  final String? failureCode;

  /// True όταν το αντίγραφο ήταν ΠΛΗΡΕΣ (.zip με φορητά) — Φάση 5.
  final bool isFullBackup;

  /// Το αποτύπωμα των φορητών που μπήκαν στο πλήρες αντίγραφο· ο καλών το
  /// αποθηκεύει στις ρυθμίσεις ώστε το επόμενο ίδιο περιεχόμενο να δώσει
  /// γρήγορο αντίγραφο. `null` σε γρήγορο ή αποτυχημένο.
  final String? portableFingerprint;
}

/// Αποτέλεσμα επαναφοράς φορητών αρχείων μετά την τοποθέτηση της βάσης.
///
/// Τα [reportItems] είναι η δομημένη αναφορά ανά στοιχείο (βάση, κατόψεις,
/// εικονίδια, λεξικό, Λάμπα) — κενή λίστα μόνο όταν το zip δεν διαβάστηκε
/// καθόλου, οπότε ισχύει μόνο το [message].
class RestorePortablesOutcome {
  const RestorePortablesOutcome({
    required this.message,
    required this.warnings,
    this.reportItems = const <RestoreReportItem>[],
  });

  final String message;
  final List<String> warnings;
  final List<RestoreReportItem> reportItems;
}

/// Αφαιρετική κλάση εκτέλεσης αντιγράφου: φάκελος προορισμού, μορφή ονομασίας, zip (μέσω [DatabaseBackupService]).
class DatabaseBackupFileOperation {
  DatabaseBackupFileOperation._();

  /// Εκτελεί το αντίγραφο και επιστρέφει [DatabaseBackupResult] (επιτυχία / μήνυμα σφάλματος).
  static Future<DatabaseBackupResult> run(
    DatabaseBackupSettings settings, {
    BackupAuditTrigger auditTrigger = BackupAuditTrigger.manual,
  }) => DatabaseBackupService.runBackup(settings, auditTrigger: auditTrigger);

  static Future<DatabaseBackupResult> runCreatingFolderIfNeeded(
    DatabaseBackupSettings settings, {
    BackupAuditTrigger auditTrigger = BackupAuditTrigger.manual,
  }) => DatabaseBackupService.runBackupCreatingFolderIfNeeded(
    settings,
    auditTrigger: auditTrigger,
  );
}

/// Δημιουργία αντιγράφων με `VACUUM INTO` (ατομικό, ενσωματώνει WAL/SHM),
/// προαιρετική συμπίεση zip και εφαρμογή πολιτικής διατήρησης.
class DatabaseBackupService {
  DatabaseBackupService._();

  /// Διαδρομή για SQLite: forward slashes, απόλυτη.
  static String _sqlitePathLiteral(String absoluteNativePath) {
    final abs = p.isAbsolute(absoluteNativePath)
        ? absoluteNativePath
        : p.absolute(absoluteNativePath);
    return abs.replaceAll('\\', '/');
  }

  static Future<DatabaseBackupResult> runBackup(
    DatabaseBackupSettings settings, {
    bool requireDestination = true,
    BackupAuditTrigger auditTrigger = BackupAuditTrigger.manual,
  }) async {
    Future<void> auditFailure(String message, {String? outputPath}) =>
        DatabaseBackupAudit.logRunResult(
          trigger: auditTrigger,
          success: false,
          message: message,
          destination: settings.destinationDirectory.trim(),
          outputPath: outputPath,
        );

    if (!settings.backupOnExit) {
      const message =
          'Η λειτουργία αντιγράφων ασφαλείας είναι απενεργοποιημένη στις ρυθμίσεις.';
      await auditFailure(message);
      return const DatabaseBackupResult(success: false, message: message);
    }

    final dest = settings.destinationDirectory.trim();
    if (dest.isEmpty) {
      if (requireDestination) {
        const message = 'Ορίστε φάκελο προορισμού.';
        await auditFailure(message);
        return const DatabaseBackupResult(success: false, message: message);
      }
      await auditFailure('Δεν ορίστηκε φάκελος προορισμού.');
      return const DatabaseBackupResult(success: false);
    }

    final db = await DatabaseHelper.instance.database;
    final baseName = p.basenameWithoutExtension(db.path);
    final content =
        await BackupDestinationFolderValidator.inspectDestinationContent(
          destinationDirectory: dest,
          dbBaseName: baseName,
        );
    if (content.kind == BackupDestinationContentKind.folderMissing) {
      const message =
          'Ο φάκελος προορισμού δεν υπάρχει. Δημιουργήστε τον ρητά πριν το αντίγραφο.';
      await auditFailure(message);
      return const DatabaseBackupResult(
        success: false,
        message: message,
        failureCode: DatabaseBackupFailureCode.folderMissing,
      );
    }

    return _executeBackup(
      settings: settings,
      dest: dest,
      auditTrigger: auditTrigger,
      db: db,
      baseName: baseName,
    );
  }

  /// Backup με δημιουργία φακέλου προορισμού — μόνο με ρητή επιβεβαίωση χρήστη.
  static Future<DatabaseBackupResult> runBackupCreatingFolderIfNeeded(
    DatabaseBackupSettings settings, {
    bool requireDestination = true,
    BackupAuditTrigger auditTrigger = BackupAuditTrigger.manual,
  }) async {
    // Το ημερολόγιο κρατά το μήνυμα, που ήδη λέει τι απέτυχε· ο κωδικός
    // αποτυχίας ταξιδεύει στο αποτέλεσμα, για τον καλούντα.
    Future<void> auditFailure(String message) =>
        DatabaseBackupAudit.logRunResult(
          trigger: auditTrigger,
          success: false,
          message: message,
          destination: settings.destinationDirectory.trim(),
        );

    if (!settings.backupOnExit) {
      const message =
          'Η λειτουργία αντιγράφων ασφαλείας είναι απενεργοποιημένη στις ρυθμίσεις.';
      await auditFailure(message);
      return const DatabaseBackupResult(success: false, message: message);
    }

    final dest = settings.destinationDirectory.trim();
    if (dest.isEmpty) {
      if (requireDestination) {
        const message = 'Ορίστε φάκελο προορισμού.';
        await auditFailure(message);
        return const DatabaseBackupResult(success: false, message: message);
      }
      await auditFailure('Δεν ορίστηκε φάκελος προορισμού.');
      return const DatabaseBackupResult(success: false);
    }

    final destDir = Directory(dest);
    try {
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
      }
    } catch (e) {
      final message = 'Δεν ήταν δυνατή η δημιουργία φακέλου: $e';
      await auditFailure(message);
      // Ο κωδικός δηλώνει ΤΙ απέτυχε, όχι μόνο ότι απέτυχε. Χωρίς αυτόν, η
      // αποτυχημένη δημιουργία φακέλου καταγραφόταν ως σκέτη αποτυχία, η
      // κατάσταση γύριζε από «λείπει ο φάκελος» σε «απέτυχε», και ο φρουρός
      // «μία φορά ανά συμβάν» έβλεπε δύο διαφορετικά συμβάντα εκεί που
      // υπήρχε ένα.
      return DatabaseBackupResult(
        success: false,
        message: message,
        failureCode: failureCodeFolderMissing,
      );
    }

    final db = await DatabaseHelper.instance.database;
    final baseName = p.basenameWithoutExtension(db.path);
    return _executeBackup(
      settings: settings,
      dest: dest,
      auditTrigger: auditTrigger,
      db: db,
      baseName: baseName,
    );
  }

  static Future<DatabaseBackupResult> _executeBackup({
    required DatabaseBackupSettings settings,
    required String dest,
    required BackupAuditTrigger auditTrigger,
    required Database db,
    required String baseName,
  }) async {
    Future<void> auditFailure(String message, {String? outputPath}) =>
        DatabaseBackupAudit.logRunResult(
          trigger: auditTrigger,
          success: false,
          message: message,
          destination: dest,
          outputPath: outputPath,
        );

    final destDir = Directory(dest);
    final stamp = DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now());
    final stem =
        settings.namingFormat == DatabaseBackupNamingFormat.dateTimeThenBase
        ? '${stamp}_$baseName'
        : '${baseName}_$stamp';
    final dbFileName = '$stem.db';

    final outDbPath = p.join(dest, dbFileName);
    final outDbFile = File(outDbPath);
    try {
      if (await outDbFile.exists()) {
        await outDbFile.delete();
      }
    } catch (e) {
      final message = 'Δεν ήταν δυνατή η διαγραφή υπάρχοντος αρχείου: $e';
      await auditFailure(message);
      return DatabaseBackupResult(success: false, message: message);
    }

    try {
      await DatabaseBackupRepository(
        db,
      ).vacuumInto(_sqlitePathLiteral(outDbPath));
    } catch (e) {
      try {
        if (await outDbFile.exists()) await outDbFile.delete();
      } catch (_) {}
      final message = 'Το VACUUM INTO απέτυχε: $e';
      await auditFailure(message);
      return DatabaseBackupResult(success: false, message: message);
    }

    final portableAvailability = await PortableBackupAvailability.load(
      lexiconLoaded: CoreLexiconService.instance.state.loaded,
    );
    final wantBundle = settings.effectiveIncludesPortableBundleInZip(
      portableAvailability,
    );
    // Φάση 5 — το έξυπνο «τι»: πλήρες (.zip με φορητά) ΜΟΝΟ όταν το αποτύπωμα
    // των φορητών άλλαξε από το τελευταίο πλήρες· αλλιώς γρήγορο (.db, μόνο
    // βάση). Κανένα αντίγραφο δεν εξαρτάται από άλλο — το πλήρες είναι πάντα
    // αυτοτελές.
    String? currentFingerprint;
    var isFull = false;
    if (wantBundle) {
      currentFingerprint = await PortableContentFingerprint.compute(
        settings: settings,
        availability: portableAvailability,
      );
      isFull = settings.lastFullBackupFingerprint != currentFingerprint;
    }
    var finalPath = outDbPath;

    if (isFull) {
      final zipPath = p.join(dest, '$stem.zip');
      try {
        final archive = Archive();
        final dbBytes = await outDbFile.readAsBytes();
        archive.addFile(
          ArchiveFile(
            BuildingMapStorage.backupZipDbFileName,
            dbBytes.length,
            dbBytes,
          ),
        );
        // Manifest στη ρίζα: παλιότερες εκδόσεις αγνοούν μη-.db εγγραφές
        // κατά την επιλογή βάσης της επαναφοράς.
        archive.addFile(
          BackupZipManifest.toArchiveFile(await _buildBackupManifest(db.path)),
        );

        if (settings.effectiveIncludeMapImagesInBackup(portableAvailability)) {
          await _addFilesToArchive(
            archive,
            await BuildingMapStorage.listPortableImageFiles(),
            BuildingMapStorage.backupZipMapsFolderName,
          );
        }

        if (settings.effectiveIncludeToolImages(portableAvailability)) {
          await _addFilesToArchive(
            archive,
            await PortableToolImageStorage.listPortableImageFiles(),
            AppConfig.portableImagesDirName,
          );
        }

        if (settings.effectiveIncludeLexicon(portableAvailability)) {
          await _addDirectoryTreeToArchive(
            archive,
            AppConfig.portableDictionariesDirectory,
            AppConfig.portableDictionariesDirName,
          );
        }

        if (settings.effectiveIncludeLampDb(portableAvailability)) {
          final lampPath =
              await PortableLampStorage.portableLampDbPathForBackup();
          if (lampPath != null) {
            try {
              final bytes = await File(lampPath).readAsBytes();
              final entryName = p.posix.join(
                PortableLampStorage.backupZipLampDbFolderName,
                p.basename(lampPath),
              );
              archive.addFile(ArchiveFile(entryName, bytes.length, bytes));
            } catch (_) {}
          }
        }

        final zipped = ZipEncoder().encode(archive);
        await File(zipPath).writeAsBytes(zipped, flush: true);
        try {
          await outDbFile.delete();
        } catch (_) {}
        finalPath = zipPath;
      } catch (e) {
        final message = 'Η συμπίεση zip (βάση + φορητά αρχεία) απέτυχε: $e';
        await auditFailure(message, outputPath: outDbPath);
        return DatabaseBackupResult(
          success: false,
          message: message,
          outputPath: outDbPath,
        );
      }
    }

    try {
      await BackupRetention.apply(
        destDir: destDir,
        baseName: baseName,
        settings: settings,
      );
    } catch (_) {}

    final parts = <String>[];
    if (isFull) {
      if (settings.effectiveIncludeMapImagesInBackup(portableAvailability)) {
        parts.add('εικόνες χαρτών');
      }
      if (settings.effectiveIncludeToolImages(portableAvailability)) {
        parts.add('εικονίδια εργαλείων');
      }
      if (settings.effectiveIncludeLexicon(portableAvailability)) {
        parts.add('λεξικό');
      }
      if (settings.effectiveIncludeLampDb(portableAvailability)) {
        parts.add('βάση Λάμπας');
      }
    }
    final tail = parts.isEmpty ? '' : ' (${parts.join(', ')})';
    final message = isFull
        ? 'Το πλήρες αντίγραφο ολοκληρώθηκε$tail.'
        : (wantBundle
              ? 'Το γρήγορο αντίγραφο ολοκληρώθηκε — τα φορητά αρχεία δεν '
                    'έχουν αλλάξει από το τελευταίο πλήρες.'
              : 'Το αντίγραφο ολοκληρώθηκε.');
    await DatabaseBackupAudit.logRunResult(
      trigger: auditTrigger,
      success: true,
      message: message,
      destination: dest,
      outputPath: finalPath,
    );
    return DatabaseBackupResult(
      success: true,
      outputPath: finalPath,
      message: message,
      isFullBackup: isFull,
      portableFingerprint: isFull ? currentFingerprint : null,
    );
  }

  static Future<void> _addFilesToArchive(
    Archive archive,
    List<File> files,
    String zipFolderName,
  ) async {
    for (final file in files) {
      try {
        final bytes = await file.readAsBytes();
        final entryName = p.posix.join(zipFolderName, p.basename(file.path));
        archive.addFile(ArchiveFile(entryName, bytes.length, bytes));
      } catch (_) {}
    }
  }

  static Future<void> _addDirectoryTreeToArchive(
    Archive archive,
    String rootDir,
    String zipFolderName,
  ) async {
    final dir = Directory(rootDir);
    if (!await dir.exists()) return;
    final rootNorm = p.normalize(rootDir);
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      try {
        final rel = p.relative(entity.path, from: rootNorm);
        final entryName = p.posix.join(
          zipFolderName,
          rel.replaceAll('\\', '/'),
        );
        final bytes = await entity.readAsBytes();
        archive.addFile(ArchiveFile(entryName, bytes.length, bytes));
      } catch (_) {}
    }
  }

  /// Αντιγραφή φορητών αρχείων από το αρχείο zip (κατόψεις, εικονίδια, λεξικό, Λάμπα).
  ///
  /// Οι αποτυχίες μετριούνται ΑΝΑ κατηγορία — αλλιώς μια αποτυχημένη αντιγραφή
  /// θα εμφανιζόταν ψευδώς ως «δεν βρέθηκε στο αντίγραφο».
  static Future<
    ({
      int mapImagesCopied,
      int mapImagesFailed,
      int toolImagesCopied,
      int toolImagesFailed,
      int dictionaryFilesCopied,
      int dictionaryFilesFailed,
      String? restoredLampDbPath,
      bool lampDbFailed,
      List<String> warnings,
    })
  >
  _copyPortableEntriesFromArchive({
    required Archive archive,
    required String mapsRoot,
    required String imagesRoot,
    required String dictionariesRoot,
    required String lampDataBaseRoot,
  }) async {
    var mapImagesCopied = 0;
    var mapImagesFailed = 0;
    var toolImagesCopied = 0;
    var toolImagesFailed = 0;
    var dictionaryFilesCopied = 0;
    var dictionaryFilesFailed = 0;
    String? restoredLampDbPath;
    var lampDbFailed = false;
    final warnings = <String>[];

    final mapsPrefix = '${BuildingMapStorage.backupZipMapsFolderName}/';
    final imagesPrefix = '${AppConfig.portableImagesDirName}/';
    final dictPrefix = '${AppConfig.portableDictionariesDirName}/';
    final lampPrefix = '${PortableLampStorage.backupZipLampDbFolderName}/';

    for (final f in archive.files) {
      if (!f.isFile) continue;
      final name = f.name.replaceAll('\\', '/');
      try {
        if (name.startsWith(mapsPrefix)) {
          final rel = name.substring(mapsPrefix.length);
          if (rel.isEmpty) continue;
          await AppConfig.ensureDirectoryExists(mapsRoot);
          final dest = File(p.join(mapsRoot, rel.replaceAll('/', p.separator)));
          await dest.parent.create(recursive: true);
          await dest.writeAsBytes(Uint8List.fromList(f.content), flush: true);
          mapImagesCopied++;
        } else if (name.startsWith(imagesPrefix)) {
          final rel = name.substring(imagesPrefix.length);
          if (rel.isEmpty) continue;
          await AppConfig.ensureDirectoryExists(imagesRoot);
          final dest = File(
            p.join(imagesRoot, rel.replaceAll('/', p.separator)),
          );
          await dest.parent.create(recursive: true);
          await dest.writeAsBytes(Uint8List.fromList(f.content), flush: true);
          toolImagesCopied++;
        } else if (name.startsWith(dictPrefix)) {
          final rel = name.substring(dictPrefix.length);
          if (rel.isEmpty) continue;
          await AppConfig.ensureDirectoryExists(dictionariesRoot);
          final dest = File(
            p.join(dictionariesRoot, rel.replaceAll('/', p.separator)),
          );
          await dest.parent.create(recursive: true);
          await dest.writeAsBytes(Uint8List.fromList(f.content), flush: true);
          dictionaryFilesCopied++;
        } else if (name.startsWith(lampPrefix)) {
          final rel = name.substring(lampPrefix.length);
          if (rel.isEmpty) continue;
          await AppConfig.ensureDirectoryExists(lampDataBaseRoot);
          final dest = File(
            p.join(lampDataBaseRoot, rel.replaceAll('/', p.separator)),
          );
          await dest.parent.create(recursive: true);
          await dest.writeAsBytes(Uint8List.fromList(f.content), flush: true);
          restoredLampDbPath = dest.path;
        }
      } catch (e) {
        if (name.startsWith(mapsPrefix)) {
          mapImagesFailed++;
        } else if (name.startsWith(imagesPrefix)) {
          toolImagesFailed++;
        } else if (name.startsWith(dictPrefix)) {
          dictionaryFilesFailed++;
        } else if (name.startsWith(lampPrefix)) {
          lampDbFailed = true;
        }
        warnings.add(
          'Αποτυχία αντιγραφής «${p.basename(name)}»: '
          '${humanizeUserFacingError(e)}',
        );
      }
    }

    return (
      mapImagesCopied: mapImagesCopied,
      mapImagesFailed: mapImagesFailed,
      toolImagesCopied: toolImagesCopied,
      toolImagesFailed: toolImagesFailed,
      dictionaryFilesCopied: dictionaryFilesCopied,
      dictionaryFilesFailed: dictionaryFilesFailed,
      restoredLampDbPath: restoredLampDbPath,
      lampDbFailed: lampDbFailed,
      warnings: warnings,
    );
  }

  /// Δημιουργεί manifest για εγγραφή στο zip (ανεκτικό σε αποτυχία PackageInfo).
  static Future<BackupZipManifest> _buildBackupManifest(String dbPath) async {
    String appVersion = 'unknown';
    try {
      final info = await PackageInfo.fromPlatform();
      appVersion = info.version;
    } catch (_) {}
    return BackupZipManifest(
      originalDatabasePath: p.normalize(p.absolute(dbPath)),
      databaseFileName: p.basename(dbPath),
      createdAt: DateTime.now().toUtc(),
      appVersion: appVersion,
      schemaVersion: kDatabaseSchemaVersion,
    );
  }

  /// Επαναφέρει μόνο φορητά αρχεία και επανασύνδεση κατόψεων (χωρίς εγγραφή βάσης).
  ///
  /// Χρησιμοποιείται όταν η βάση έχει ήδη τοποθετηθεί από staging/αντικατάσταση.
  static Future<RestorePortablesOutcome> restorePortablesFromBackupZip(
    String zipPath, {
    required String restoredDatabasePath,
  }) async {
    final warnings = <String>[];
    final zipFile = File(zipPath);
    if (!await zipFile.exists()) {
      return RestorePortablesOutcome(
        message: 'Το αρχείο zip δεν βρέθηκε.',
        warnings: warnings,
      );
    }

    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(await zipFile.readAsBytes());
    } catch (e) {
      return RestorePortablesOutcome(
        message: 'Αποτυχία ανάγνωσης zip για φορητά αρχεία: $e',
        warnings: warnings,
      );
    }

    final portable = await _copyPortableEntriesFromArchive(
      archive: archive,
      mapsRoot: AppConfig.portableMapsDirectory,
      imagesRoot: AppConfig.portableImagesDirectory,
      dictionariesRoot: AppConfig.portableDictionariesDirectory,
      lampDataBaseRoot: AppConfig.portableDataBaseDirectory,
    );
    warnings.addAll(portable.warnings);

    if (portable.restoredLampDbPath != null) {
      try {
        final lampStore = LampSettingsStore();
        final read = await lampStore.getReadPathRaw();
        final output = await lampStore.getOutputPathRaw();
        final restoredBase = p.basename(portable.restoredLampDbPath!);
        if (read != null && p.basename(read) == restoredBase) {
          await lampStore.setReadPath(portable.restoredLampDbPath!);
        }
        if (output != null && p.basename(output) == restoredBase) {
          await lampStore.setOutputPath(portable.restoredLampDbPath!);
        }
      } catch (e) {
        warnings.add(
          'Οι διαδρομές της Λάμπας δεν ενημερώθηκαν: '
          '${humanizeUserFacingError(e)}',
        );
      }
    }

    var relinked = 0;
    try {
      final restoredDb = await openDatabase(
        restoredDatabasePath,
        readOnly: false,
        singleInstance: false,
      );
      try {
        relinked =
            await BuildingMapStorage.relinkMissingFloorImagesAfterRestore(
              restoredDb,
            );
      } finally {
        await restoredDb.close();
      }
    } catch (e) {
      warnings.add(
        'Η επανασύνδεση κατόψεων απέτυχε: ${humanizeUserFacingError(e)}',
      );
    }

    final reportItems = buildRestoreReportItems(
      mapImagesCopied: portable.mapImagesCopied,
      mapImagesFailed: portable.mapImagesFailed,
      toolImagesCopied: portable.toolImagesCopied,
      toolImagesFailed: portable.toolImagesFailed,
      dictionaryFilesCopied: portable.dictionaryFilesCopied,
      dictionaryFilesFailed: portable.dictionaryFilesFailed,
      lampDbRestored: portable.restoredLampDbPath != null,
      lampDbFailed: portable.lampDbFailed,
      imagesRelinked: relinked,
    );

    return RestorePortablesOutcome(
      message: restoreReportPlainText(reportItems),
      warnings: warnings,
      reportItems: reportItems,
    );
  }
}
