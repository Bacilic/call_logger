import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import '../../../core/database/database_maintenance_repository.dart';
import '../../../core/database/sqlite_types.dart';

import '../../../core/config/app_config.dart';
import '../../../core/utils/zip_entry_safety.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/old_database/lamp_settings_store.dart';
import '../../../core/services/building_map_storage.dart';
import '../../../core/services/core_lexicon_service.dart';
import '../../../core/services/portable_lamp_storage.dart';
import '../../../core/utils/user_facing_error_messages.dart';
import '../models/database_backup_settings.dart';
import '../utils/backup_destination_folder_validator.dart';
import '../utils/portable_backup_availability.dart';
import 'backup_artifact_naming.dart';
import 'backup_completion_message.dart';
import 'backup_portable_bundle.dart';
import 'backup_retention.dart';
import 'backup_verification.dart';
import 'database_backup_audit.dart';
import 'portable_content_fingerprint.dart';
import 'restore_selection.dart';
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
    this.brokenArtifactPath,
  });

  final bool success;
  final String? outputPath;
  final String? message;
  final String? failureCode;

  /// Το αντίγραφο γράφτηκε αλλά δεν πέρασε τον έλεγχο, και το αρχείο φέρει
  /// πλέον τη σήμανση «ΧΑΛΑΣΜΕΝΟ» στο όνομά του.
  ///
  /// Χωρίζεται από το σκέτο [success] γιατί ο παραλήπτης είναι άλλος: εδώ
  /// υπάρχει **αρχείο στον δίσκο** για το οποίο ο χειριστής μπορεί να
  /// αποφασίσει, ενώ μια αποτυχία εγγραφής δεν αφήνει τίποτα πίσω της.
  bool get isVerifiedBroken => brokenArtifactPath != null;

  /// Πού κατέληξε το σημαδεμένο αρχείο· `null` σε κάθε άλλη έκβαση.
  final String? brokenArtifactPath;

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

  /// Ενορχηστρώνει τη δημιουργία ενός αντιγράφου, με δεσμευτική σειρά βημάτων.
  ///
  /// Κάθε βήμα ζει στο δικό του αρχείο· εδώ φαίνεται μόνο **η σειρά**, που
  /// είναι και το μόνο πράγμα που δεν επιτρέπεται να αλλάξει κατά λάθος:
  ///
  /// 1. **ονόματα** — υπολογίζονται μία φορά, ώστε `.db` και `.zip` να μη
  ///    διαφωνούν αν το λεπτό αλλάξει στη μέση,
  /// 2. **αντιγραφή της βάσης** με `VACUUM INTO`,
  /// 3. **απόφαση πλήρες/γρήγορο** από το αποτύπωμα των φορητών,
  /// 4. **συμπίεση** μαζί με τα φορητά, όταν το αντίγραφο βγαίνει πλήρες,
  /// 5. **επαλήθευση** — και σήμανση του αρχείου αν δεν περάσει,
  /// 6. **εκκαθάριση** παλαιών αντιγράφων,
  /// 7. **μήνυμα** από ό,τι πράγματι έγινε.
  ///
  /// Η **επαλήθευση πριν από την εκκαθάριση** δεν είναι προτίμηση ύφους: ένα
  /// χαλασμένο αντίγραφο που μετρά ως έγκυρο σπρώχνει παλαιότερα υγιή έξω από
  /// τα όρια διατήρησης, και η ζημιά γίνεται διπλή.
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

    // ── 1. Ονόματα ──────────────────────────────────────────────────────
    final paths = resolveBackupArtifactPaths(
      destinationDirectory: dest,
      baseName: baseName,
      namingFormat: settings.namingFormat,
      now: DateTime.now(),
    );
    final outDbFile = File(paths.databasePath);

    // ── 2. Αντιγραφή της βάσης ──────────────────────────────────────────
    try {
      if (await outDbFile.exists()) {
        await outDbFile.delete();
      }
    } catch (e) {
      final message = 'Δεν ήταν δυνατή η διαγραφή υπάρχοντος αρχείου: $e';
      await auditFailure(message);
      return DatabaseBackupResult(success: false, message: message);
    }

    DatabaseSnapshotStats? snapshotStats;
    try {
      snapshotStats = await DatabaseBackupRepository(
        db,
      ).vacuumInto(_sqlitePathLiteral(paths.databasePath));
    } catch (e) {
      try {
        if (await outDbFile.exists()) await outDbFile.delete();
      } catch (_) {
        // Το μισογραμμένο αρχείο δεν εμποδίζει την αναφορά της αποτυχίας.
      }
      final message = 'Το VACUUM INTO απέτυχε: $e';
      await auditFailure(message);
      return DatabaseBackupResult(success: false, message: message);
    }

    // ── 3. Πλήρες ή γρήγορο; ────────────────────────────────────────────
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

    // ── 4. Συμπίεση με τα φορητά ────────────────────────────────────────
    var finalPath = paths.databasePath;
    var includedParts = const <String>[];
    final missingParts = <String>[];

    if (isFull) {
      try {
        final bundle = await writeFullBackupArchive(
          archivePath: paths.archivePath,
          databaseFilePath: paths.databasePath,
          sourceDatabasePath: db.path,
          settings: settings,
          availability: portableAvailability,
        );
        includedParts = bundle.includedParts;
        missingParts.addAll(bundle.missingParts);

        try {
          await outDbFile.delete();
        } catch (_) {
          // Το ενδιάμεσο .db δίπλα στο .zip είναι ακαταστασία, όχι βλάβη.
        }
        finalPath = paths.archivePath;
      } catch (e) {
        // Το ενδιάμεσο `.db` **δεν** σβήνεται: είναι πλήρες αντίγραφο της
        // βάσης και ο χειριστής πρέπει να ξέρει ότι το έχει.
        final message = 'Η συμπίεση zip (βάση + φορητά αρχεία) απέτυχε: $e';
        await auditFailure(message, outputPath: paths.databasePath);
        return DatabaseBackupResult(
          success: false,
          message: message,
          outputPath: paths.databasePath,
        );
      }
    }

    // ── 5. Επαλήθευση ───────────────────────────────────────────────────
    final verification = await verifyBackupArtifact(finalPath);
    if (verification.isBroken) {
      final markedPath = await markBackupArtifactAsBroken(finalPath);
      final message = buildBrokenBackupMessage(
        reason: verification.message,
        wasMarked: markedPath != null,
        rawDetail: verification.rawDetail,
      );
      await auditFailure(message, outputPath: markedPath ?? finalPath);
      return DatabaseBackupResult(
        success: false,
        message: message,
        outputPath: markedPath ?? finalPath,
        brokenArtifactPath: markedPath,
      );
    }

    // ── 6. Εκκαθάριση παλαιών ───────────────────────────────────────────
    try {
      await BackupRetention.apply(
        destDir: Directory(dest),
        baseName: baseName,
        settings: settings,
      );
    } catch (e) {
      // Η εκκαθάριση δεν ρίχνει το αντίγραφο — αυτό έχει ήδη γραφτεί και
      // επαληθευτεί. Σιωπηλή όμως δεν μένει: ένας φάκελος που δεν αδειάζει
      // ποτέ γεμίζει τον δίσκο χωρίς καμία ένδειξη.
      missingParts.add('εκκαθάριση παλαιών αντιγράφων ($e)');
    }

    // ── 7. Μήνυμα ───────────────────────────────────────────────────────
    final message = buildBackupCompletionMessage(
      isFull: isFull,
      wantsBundle: wantBundle,
      includedParts: includedParts,
      missingParts: missingParts,
    );
    // Το Ιστορικό κρατά και πόσο κράτησε το κλείδωμα των συναδέλφων — η
    // μόνη μέτρηση που λέει, σε κάθε μηχάνημα και δίκτυο, αν το αντίγραφο
    // πάγωσε κάποιον. Η οθόνη δείχνει μόνο το μήνυμα.
    await DatabaseBackupAudit.logRunResult(
      trigger: auditTrigger,
      success: true,
      message: snapshotStats == null
          ? message
          : '$message (${snapshotStats.summary})',
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

  /// Αντιγραφή φορητών αρχείων από το αρχείο zip (κατόψεις, εικονίδια, λεξικό, Λάμπα).
  ///
  /// Οι αποτυχίες μετριούνται ΑΝΑ κατηγορία — αλλιώς μια αποτυχημένη αντιγραφή
  /// θα εμφανιζόταν ψευδώς ως «δεν βρέθηκε στο αντίγραφο».
  /// Αντιγράφει τα φορητά αρχεία ενός αντιγράφου στους φακέλους τους.
  ///
  /// Δημόσια επειδή οι ρίζες προορισμού δίνονται από τον καλούντα: έτσι η
  /// συμπεριφορά της —ιδίως ΠΟΥ καταλήγει κάθε εγγραφή— ελέγχεται σε
  /// προσωρινούς φακέλους, χωρίς να εξαρτάται από τον φάκελο εγκατάστασης.
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
  copyPortableEntriesFromArchive({
    required Archive archive,
    required String mapsRoot,
    required String imagesRoot,
    required String dictionariesRoot,
    required String lampDataBaseRoot,
    Set<RestorePortablePart> parts = const {
      RestorePortablePart.maps,
      RestorePortablePart.toolImages,
      RestorePortablePart.lexicon,
      RestorePortablePart.lampDatabase,
    },
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

    // Τα τέσσερα φορητά τμήματα διαφέρουν μόνο σε τρία πράγματα: από ποιον
    // φάκελο του zip έρχονται, σε ποιον φάκελο πάνε, και πώς μετριούνται. Ό,τι
    // άλλο —ο έλεγχος διαδρομής, η δημιουργία φακέλων, η εγγραφή, ο χειρισμός
    // αποτυχίας— ήταν γραμμένο τέσσερις φορές. Τώρα είναι γραμμένο μία: ο
    // κανόνας «μένει μέσα στον φάκελό του» δεν μπορεί να ισχύει για τρία από
    // τα τέσσερα.
    final destinations =
        <({String prefix, String root, void Function() copied})>[
          (
            prefix: '${BuildingMapStorage.backupZipMapsFolderName}/',
            root: mapsRoot,
            copied: () => mapImagesCopied++,
          ),
          (
            prefix: '${AppConfig.portableImagesDirName}/',
            root: imagesRoot,
            copied: () => toolImagesCopied++,
          ),
          (
            prefix: '${AppConfig.portableDictionariesDirName}/',
            root: dictionariesRoot,
            copied: () => dictionaryFilesCopied++,
          ),
          (
            prefix: '${PortableLampStorage.backupZipLampDbFolderName}/',
            root: lampDataBaseRoot,
            copied: () {},
          ),
        ];

    void countFailure(String prefix) {
      if (prefix.startsWith(BuildingMapStorage.backupZipMapsFolderName)) {
        mapImagesFailed++;
      } else if (prefix.startsWith(AppConfig.portableImagesDirName)) {
        toolImagesFailed++;
      } else if (prefix.startsWith(AppConfig.portableDictionariesDirName)) {
        dictionaryFilesFailed++;
      } else {
        lampDbFailed = true;
      }
    }

    for (final f in archive.files) {
      if (!f.isFile) continue;
      final name = f.name.replaceAll('\\', '/');
      if (!restoreEntryIsWanted(name, parts)) continue;

      final slot = destinations
          .where((d) => name.startsWith(d.prefix))
          .firstOrNull;
      if (slot == null) continue;

      final rel = name.substring(slot.prefix.length);
      if (rel.isEmpty) continue;

      // Ο κριτής πριν από κάθε εγγραφή, χωρίς εξαίρεση. Μια εγγραφή που
      // δείχνει έξω παραλείπεται και λέγεται — δεν ακυρώνει τις υπόλοιπες,
      // γιατί η επαναφορά γίνεται σε στιγμή ανάγκης και ό,τι σώζεται μετράει.
      final target = resolveZipEntryTarget(root: slot.root, entryPath: rel);
      switch (target) {
        case RejectedZipEntry(:final reason):
          countFailure(slot.prefix);
          warnings.add('Παραλείφθηκε: $reason');
        case SafeZipEntryTarget(:final absolutePath):
          try {
            await AppConfig.ensureDirectoryExists(slot.root);
            final dest = File(absolutePath);
            await dest.parent.create(recursive: true);
            await dest.writeAsBytes(Uint8List.fromList(f.content), flush: true);
            slot.copied();
            if (slot.prefix ==
                '${PortableLampStorage.backupZipLampDbFolderName}/') {
              restoredLampDbPath = dest.path;
            }
          } catch (e) {
            countFailure(slot.prefix);
            warnings.add(
              'Αποτυχία αντιγραφής «${p.basename(name)}»: '
              '${humanizeUserFacingError(e)}',
            );
          }
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
  /// Επαναφέρει μόνο φορητά αρχεία και επανασύνδεση κατόψεων (χωρίς εγγραφή βάσης).
  ///
  /// Χρησιμοποιείται όταν η βάση έχει ήδη τοποθετηθεί από staging/αντικατάσταση.
  static Future<RestorePortablesOutcome> restorePortablesFromBackupZip(
    String zipPath, {
    required String restoredDatabasePath,
    RestoreSelection? selection,
    bool databaseRestored = true,
  }) async {
    final wanted =
        selection?.parts ??
        const {
          RestorePortablePart.maps,
          RestorePortablePart.toolImages,
          RestorePortablePart.lexicon,
          RestorePortablePart.lampDatabase,
        };
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

    final portable = await copyPortableEntriesFromArchive(
      archive: archive,
      mapsRoot: AppConfig.portableMapsDirectory,
      imagesRoot: AppConfig.portableImagesDirectory,
      dictionariesRoot: AppConfig.portableDictionariesDirectory,
      lampDataBaseRoot: AppConfig.portableDataBaseDirectory,
      parts: wanted,
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
      databaseRestored: databaseRestored,
      mapsSkipped: !wanted.contains(RestorePortablePart.maps),
      toolImagesSkipped: !wanted.contains(RestorePortablePart.toolImages),
      lexiconSkipped: !wanted.contains(RestorePortablePart.lexicon),
      lampDbSkipped: !wanted.contains(RestorePortablePart.lampDatabase),
    );

    return RestorePortablesOutcome(
      message: restoreReportPlainText(reportItems),
      warnings: warnings,
      reportItems: reportItems,
    );
  }
}
