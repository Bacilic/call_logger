import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import '../../../core/database/database_maintenance_repository.dart';
import '../../../core/database/sqlite_types.dart';

import '../../../core/config/app_config.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/old_database/lamp_settings_store.dart';
import '../../../core/services/building_map_storage.dart';
import '../../../core/services/core_lexicon_service.dart';
import '../../../core/services/portable_lamp_storage.dart';
import '../../../core/services/portable_tool_image_storage.dart';
import '../models/database_backup_settings.dart';
import '../utils/backup_destination_folder_validator.dart';
import '../utils/portable_backup_availability.dart';
import 'database_backup_audit.dart';

/// Κωδικοί αποτυχίας backup (για UI / scheduler).
abstract final class DatabaseBackupFailureCode {
  static const String folderMissing = 'folder_missing';
}

/// Αποτέλεσμα χειροκίνητου ή προγραμματισμένου backup.
class DatabaseBackupResult {
  const DatabaseBackupResult({
    required this.success,
    this.outputPath,
    this.message,
    this.failureCode,
  });

  final bool success;
  final String? outputPath;
  final String? message;
  final String? failureCode;
}

/// Αποτέλεσμα επαναφοράς από zip αντιγράφου.
class DatabaseRestoreResult {
  const DatabaseRestoreResult({
    required this.success,
    this.databasePath,
    this.message,
    this.imagesRelinked = 0,
    this.mapImagesCopied = 0,
    this.toolImagesCopied = 0,
    this.dictionaryFilesCopied = 0,
    this.lampDbRestored = false,
  });

  final bool success;
  final String? databasePath;
  final String? message;
  final int imagesRelinked;
  final int mapImagesCopied;
  final int toolImagesCopied;
  final int dictionaryFilesCopied;
  final bool lampDbRestored;
}

/// Αφαιρετική κλάση εκτέλεσης αντιγράφου: φάκελος προορισμού, μορφή ονομασίας, zip (μέσω [DatabaseBackupService]).
class DatabaseBackupFileOperation {
  DatabaseBackupFileOperation._();

  /// Εκτελεί το αντίγραφο και επιστρέφει [DatabaseBackupResult] (επιτυχία / μήνυμα σφάλματος).
  static Future<DatabaseBackupResult> run(
    DatabaseBackupSettings settings, {
    BackupAuditTrigger auditTrigger = BackupAuditTrigger.manual,
  }) =>
      DatabaseBackupService.runBackup(
        settings,
        auditTrigger: auditTrigger,
      );

  static Future<DatabaseBackupResult> runCreatingFolderIfNeeded(
    DatabaseBackupSettings settings, {
    BackupAuditTrigger auditTrigger = BackupAuditTrigger.manual,
  }) =>
      DatabaseBackupService.runBackupCreatingFolderIfNeeded(
        settings,
        auditTrigger: auditTrigger,
      );

  /// Επαναφορά από zip (βάση + εικόνες χαρτών).
  static Future<DatabaseRestoreResult> restoreFromZip(
    String zipPath, {
    required String targetDatabasePath,
  }) =>
      DatabaseBackupService.restoreFromBackupZip(
        zipPath,
        targetDatabasePath: targetDatabasePath,
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
    final content = await BackupDestinationFolderValidator.inspectDestinationContent(
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
    Future<void> auditFailure(String message, {String? failureCode}) =>
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
      return DatabaseBackupResult(success: false, message: message);
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
    final stem = settings.namingFormat ==
            DatabaseBackupNamingFormat.dateTimeThenBase
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
      await DatabaseBackupRepository(db).vacuumInto(_sqlitePathLiteral(outDbPath));
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
    final effectiveBundle =
        settings.effectiveIncludesPortableBundleInZip(portableAvailability);
    final useZipBundle = effectiveBundle || settings.zipOutput;
    var finalPath = outDbPath;

    if (useZipBundle) {
      final zipPath = p.join(dest, '$stem.zip');
      try {
        final archive = Archive();
        final dbBytes = await outDbFile.readAsBytes();
        final innerDbName = effectiveBundle
            ? BuildingMapStorage.backupZipDbFileName
            : dbFileName;
        archive.addFile(ArchiveFile(innerDbName, dbBytes.length, dbBytes));

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
          final lampPath = await PortableLampStorage.portableLampDbPathForBackup();
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
        final message = effectiveBundle
            ? 'Η συμπίεση zip (βάση + φορητά αρχεία) απέτυχε: $e'
            : 'Η συμπίεση zip απέτυχε: $e';
        await auditFailure(message, outputPath: outDbPath);
        return DatabaseBackupResult(
          success: false,
          message: message,
          outputPath: outDbPath,
        );
      }
    }

    try {
      await _applyRetention(destDir, baseName, settings);
    } catch (_) {}

    final parts = <String>[];
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
    final tail = parts.isEmpty ? '' : ' (${parts.join(', ')})';
    final message = 'Το αντίγραφο ολοκληρώθηκε$tail.';
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

  /// Αποσυμπίεση zip αντιγράφου· τοποθετεί `call_logger.db` και φορητά αρχεία στη ρίζα εφαρμογής.
  static Future<DatabaseRestoreResult> restoreFromBackupZip(
    String zipPath, {
    required String targetDatabasePath,
  }) async {
    final zipFile = File(zipPath);
    if (!await zipFile.exists()) {
      return const DatabaseRestoreResult(
        success: false,
        message: 'Το αρχείο zip δεν βρέθηκε.',
      );
    }

    final targetDb = p.normalize(p.absolute(targetDatabasePath));
    final targetDir = p.dirname(targetDb);
    final mapsRoot = AppConfig.portableMapsDirectory;
    final imagesRoot = AppConfig.portableImagesDirectory;
    final dictionariesRoot = AppConfig.portableDictionariesDirectory;
    final lampDataBaseRoot = AppConfig.portableDataBaseDirectory;

    try {
      await Directory(targetDir).create(recursive: true);
    } catch (e) {
      return DatabaseRestoreResult(
        success: false,
        message: 'Δεν ήταν δυνατή η δημιουργία φακέλων προορισμού: $e',
      );
    }

    Archive archive;
    try {
      final bytes = await zipFile.readAsBytes();
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      return DatabaseRestoreResult(
        success: false,
        message: 'Αποτυχία ανάγνωσης/αποσυμπίεσης zip: $e',
      );
    }

    ArchiveFile? dbEntry;
    final lampDbPrefix = '${PortableLampStorage.backupZipLampDbFolderName}/';
    for (final f in archive.files) {
      if (!f.isFile) continue;
      final name = f.name.replaceAll('\\', '/');
      if (!name.toLowerCase().endsWith('.db')) continue;
      if (name.startsWith(lampDbPrefix)) continue;
      if (name == BuildingMapStorage.backupZipDbFileName) {
        dbEntry = f;
        break;
      }
      dbEntry ??= f;
    }

    if (dbEntry == null) {
      return const DatabaseRestoreResult(
        success: false,
        message: 'Δεν βρέθηκε αρχείο βάσης (.db) μέσα στο zip.',
      );
    }

    try {
      final existingDb = File(targetDb);
      if (await existingDb.exists()) {
        await existingDb.delete();
      }
      await existingDb.writeAsBytes(
        Uint8List.fromList(dbEntry.content),
        flush: true,
      );
    } catch (e) {
      return DatabaseRestoreResult(
        success: false,
        message: 'Αποτυχία εγγραφής βάσης στον προορισμό: $e',
      );
    }

    var mapImagesCopied = 0;
    var toolImagesCopied = 0;
    var dictionaryFilesCopied = 0;
    String? restoredLampDbPath;

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
          final dest = File(p.join(imagesRoot, rel.replaceAll('/', p.separator)));
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
      } catch (_) {}
    }

    if (restoredLampDbPath != null) {
      try {
        final lampStore = LampSettingsStore();
        final read = await lampStore.getReadPathRaw();
        final output = await lampStore.getOutputPathRaw();
        final restoredBase = p.basename(restoredLampDbPath);
        if (read != null && p.basename(read) == restoredBase) {
          await lampStore.setReadPath(restoredLampDbPath);
        }
        if (output != null && p.basename(output) == restoredBase) {
          await lampStore.setOutputPath(restoredLampDbPath);
        }
      } catch (_) {}
    }

    var relinked = 0;
    try {
      final restoredDb = await openDatabase(
        targetDb,
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
    } catch (_) {}

    final notes = <String>[
      'βάση: επαναφέρθηκε',
      if (mapImagesCopied > 0)
        'κατόψεις: $mapImagesCopied'
      else
        'κατόψεις: δεν βρέθηκαν στο zip',
      if (toolImagesCopied > 0)
        'εικονίδια: $toolImagesCopied'
      else
        'εικονίδια: δεν βρέθηκαν στο zip',
      if (dictionaryFilesCopied > 0)
        'λεξικό: $dictionaryFilesCopied αρχεία'
      else
        'λεξικό: δεν βρέθηκε στο zip',
      if (restoredLampDbPath != null)
        'Λάμπα: ${p.basename(restoredLampDbPath)}'
      else
        'Λάμπα: δεν βρέθηκε στο zip',
      if (relinked > 0) 'σύνδεση κατόψεων: $relinked',
    ];

    return DatabaseRestoreResult(
      success: true,
      databasePath: targetDb,
      imagesRelinked: relinked,
      mapImagesCopied: mapImagesCopied,
      toolImagesCopied: toolImagesCopied,
      dictionaryFilesCopied: dictionaryFilesCopied,
      lampDbRestored: restoredLampDbPath != null,
      message: 'Η επαναφορά ολοκληρώθηκε.\n${notes.join(' · ')}',
    );
  }

  static Future<void> _applyRetention(
    Directory destDir,
    String baseName,
    DatabaseBackupSettings settings,
  ) async {
    if (!settings.retentionMaxAgeEnabled && !settings.retentionMaxCopiesEnabled) {
      return;
    }

    final escapedBase = RegExp.escape(baseName);
    final dateFirst = RegExp(
      '^(\\d{4}-\\d{2}-\\d{2}_\\d{2}-\\d{2})_$escapedBase\\.(db|zip)\$',
    );
    final baseFirst = RegExp(
      '^${escapedBase}_(\\d{4}-\\d{2}-\\d{2}_\\d{2}-\\d{2})\\.(db|zip)\$',
    );

    final backups = <File>[];
    await for (final entity in destDir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!dateFirst.hasMatch(name) && !baseFirst.hasMatch(name)) continue;
      backups.add(entity);
    }

    if (backups.isEmpty) return;

    if (settings.retentionMaxAgeEnabled) {
      final cutoff = DateTime.now().subtract(
        Duration(days: settings.retentionMaxAgeDays),
      );
      for (final f in backups) {
        try {
          final stat = await f.stat();
          if (stat.modified.isBefore(cutoff)) {
            await f.delete();
          }
        } catch (_) {}
      }
    }

    if (!settings.retentionMaxCopiesEnabled) return;

    final remaining = <File>[];
    await for (final entity in destDir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!dateFirst.hasMatch(name) && !baseFirst.hasMatch(name)) continue;
      remaining.add(entity);
    }
    if (remaining.length <= settings.retentionMaxCopies) return;

    remaining.sort((a, b) {
      try {
        return b.lastModifiedSync().compareTo(a.lastModifiedSync());
      } catch (_) {
        return 0;
      }
    });

    final excess = remaining.skip(settings.retentionMaxCopies);
    for (final f in excess) {
      try {
        await f.delete();
      } catch (_) {}
    }
  }
}
