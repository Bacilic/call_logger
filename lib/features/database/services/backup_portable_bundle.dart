/// Το «πλήρες» αντίγραφο: η βάση μαζί με τα φορητά αρχεία, σε ένα `.zip`.
///
/// **Γιατί ξεχωριστά από τη ροή δημιουργίας:** εδώ ζει το μοναδικό σημείο που
/// ξέρει *ποια* φορητά υπάρχουν και *πώς* μπαίνουν μέσα. Κάθε νέο είδος
/// περιεχομένου προσθέτει γραμμές **εδώ**, όχι στη μέση της ροής που
/// ενορχηστρώνει αντιγραφή, επαλήθευση και εκκαθάριση.
///
/// **Το συμβόλαιο που επιβάλλει:** ό,τι δηλώνεται ως περιεχόμενο μπήκε
/// πράγματι μέσα. Ένα κομμάτι που ζητήθηκε αλλά δεν διαβάστηκε δεν ρίχνει το
/// αντίγραφο — η βάση έχει ήδη μπει και αξίζει να σωθεί — αλλά ούτε σιωπά:
/// καταλήγει στα [BackupBundleOutcome.missingParts] με την αιτία μαζί.
library;

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import '../../../core/config/app_config.dart';
import '../../../core/database/database_schema_version.dart';
import '../../../core/services/building_map_storage.dart';
import '../../../core/services/portable_lamp_storage.dart';
import '../../../core/services/portable_tool_image_storage.dart';
import '../models/database_backup_settings.dart';
import '../utils/portable_backup_availability.dart';
import 'backup_completion_message.dart';
import 'backup_zip_manifest.dart';

/// Τι μπήκε και τι έλειψε από ένα πλήρες αντίγραφο.
class BackupBundleOutcome {
  const BackupBundleOutcome({
    required this.includedParts,
    required this.missingParts,
  });

  /// Τα περιεχόμενα όπως θα τα διαβάσει ο χειριστής — μόνο ό,τι μπήκε.
  final List<String> includedParts;

  /// Ό,τι ζητήθηκε και δεν μπήκε, με την αιτία δίπλα.
  final List<String> missingParts;
}

/// Χτίζει το `.zip` του πλήρους αντιγράφου γύρω από ένα ήδη γραμμένο `.db`.
///
/// Πετάει αν αποτύχει το ίδιο το γράψιμο του αρχείου — τότε δεν υπάρχει
/// αντίγραφο και ο καλών οφείλει να το μάθει. Αποτυχία **ενός φορητού
/// κομματιού** δεν πετάει: επιστρέφεται στα `missingParts`.
Future<BackupBundleOutcome> writeFullBackupArchive({
  required String archivePath,
  required String databaseFilePath,
  required String sourceDatabasePath,
  required DatabaseBackupSettings settings,
  required PortableBackupAvailability availability,
}) async {
  final archive = Archive();

  final dbBytes = await File(databaseFilePath).readAsBytes();
  archive.addFile(
    ArchiveFile(
      BuildingMapStorage.backupZipDbFileName,
      dbBytes.length,
      dbBytes,
    ),
  );

  // Manifest στη ρίζα: παλιότερες εκδόσεις αγνοούν μη-.db εγγραφές κατά την
  // επιλογή βάσης της επαναφοράς.
  archive.addFile(
    BackupZipManifest.toArchiveFile(
      await buildBackupZipManifest(sourceDatabasePath),
    ),
  );

  final included = <String>[];
  final missing = <String>[];

  /// Περνά το αποτέλεσμα από την κρίση και το γράφει στη σωστή λίστα.
  ///
  /// Ένα σημείο για τα τρία κομμάτια: όσο καθένα έγραφε μόνο του στο
  /// `included`, το τρίτο ήταν πάντα ένα αντιγραμμένο `add` που κανείς δεν
  /// ξαναδιάβαζε.
  void record(String label, String emptyReason, PortablePartOutcome outcome) {
    final verdict = judgePortablePart(
      label: label,
      emptyReason: emptyReason,
      outcome: outcome,
    );
    if (verdict.included != null) included.add(verdict.included!);
    if (verdict.missing != null) missing.add(verdict.missing!);
  }

  if (settings.effectiveIncludeMapImagesInBackup(availability)) {
    record(
      'εικόνες χαρτών',
      'δεν βρέθηκε καμία',
      await _addFilesToArchive(
        archive,
        await BuildingMapStorage.listPortableImageFiles(),
        BuildingMapStorage.backupZipMapsFolderName,
      ),
    );
  }

  if (settings.effectiveIncludeToolImages(availability)) {
    record(
      'εικονίδια εργαλείων',
      'δεν βρέθηκε κανένα',
      await _addFilesToArchive(
        archive,
        await PortableToolImageStorage.listPortableImageFiles(),
        AppConfig.portableImagesDirName,
      ),
    );
  }

  if (settings.effectiveIncludeLexicon(availability)) {
    record(
      'λεξικό',
      'δεν βρέθηκε αρχείο λεξικού',
      await _addDirectoryTreeToArchive(
        archive,
        AppConfig.portableDictionariesDirectory,
        AppConfig.portableDictionariesDirName,
      ),
    );
  }

  if (settings.effectiveIncludeLampDb(availability)) {
    // Η Λάμπα είναι το μόνο φορητό που ζει σε **ένα** αρχείο εκτός των δικών
    // μας φακέλων: μπορεί να είναι κλειδωμένο ή σε δίσκο που δεν απαντά.
    final lampPath = await PortableLampStorage.portableLampDbPathForBackup();
    if (lampPath == null) {
      missing.add('βάση Λάμπας (δεν βρέθηκε το αρχείο της)');
    } else {
      try {
        final bytes = await File(lampPath).readAsBytes();
        final entryName = p.posix.join(
          PortableLampStorage.backupZipLampDbFolderName,
          p.basename(lampPath),
        );
        archive.addFile(ArchiveFile(entryName, bytes.length, bytes));
        included.add('βάση Λάμπας');
      } catch (e) {
        missing.add('βάση Λάμπας ($e)');
      }
    }
  }

  await File(
    archivePath,
  ).writeAsBytes(ZipEncoder().encode(archive), flush: true);

  return BackupBundleOutcome(includedParts: included, missingParts: missing);
}

/// Η ταυτότητα του αντιγράφου, όπως τη διαβάζει η επαναφορά.
Future<BackupZipManifest> buildBackupZipManifest(String dbPath) async {
  var appVersion = 'unknown';
  try {
    final info = await PackageInfo.fromPlatform();
    appVersion = info.version;
  } catch (_) {
    // Η έκδοση είναι πληροφορία, όχι προϋπόθεση: ένα αντίγραφο χωρίς αυτήν
    // εξακολουθεί να επαναφέρεται.
  }
  return BackupZipManifest(
    originalDatabasePath: p.normalize(p.absolute(dbPath)),
    databaseFileName: p.basename(dbPath),
    createdAt: DateTime.now().toUtc(),
    appVersion: appVersion,
    schemaVersion: kDatabaseSchemaVersion,
  );
}

/// Βάζει μια λίστα αρχείων μέσα σε φάκελο του zip, με επίπεδη δομή.
///
/// Επιστρέφει πόσα μπήκαν και πόσα όχι. Η αποτυχία ενός αρχείου εξακολουθεί
/// να μη ρίχνει το αντίγραφο — αλλά παύει να είναι αόρατη: ο αριθμός φτάνει
/// ως το μήνυμα που διαβάζει ο χειριστής.
Future<PortablePartOutcome> _addFilesToArchive(
  Archive archive,
  List<File> files,
  String zipFolderName,
) async {
  var added = 0;
  var failed = 0;
  for (final file in files) {
    try {
      final bytes = await file.readAsBytes();
      final entryName = p.posix.join(zipFolderName, p.basename(file.path));
      archive.addFile(ArchiveFile(entryName, bytes.length, bytes));
      added++;
    } catch (_) {
      failed++;
    }
  }
  return PortablePartOutcome(added: added, failed: failed);
}

/// Βάζει ολόκληρο δέντρο φακέλων, διατηρώντας τη δομή του.
///
/// Φάκελος που δεν υπάρχει **δεν** είναι αποτυχία ανάγνωσης: είναι «δεν
/// βρέθηκε τίποτα», και η διάκριση φτάνει ως το μήνυμα.
Future<PortablePartOutcome> _addDirectoryTreeToArchive(
  Archive archive,
  String rootDir,
  String zipFolderName,
) async {
  final dir = Directory(rootDir);
  if (!await dir.exists()) return const PortablePartOutcome.nothingFound();
  final rootNorm = p.normalize(rootDir);
  var added = 0;
  var failed = 0;
  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    try {
      final rel = p.relative(entity.path, from: rootNorm);
      final entryName = p.posix.join(zipFolderName, rel.replaceAll('\\', '/'));
      final bytes = await entity.readAsBytes();
      archive.addFile(ArchiveFile(entryName, bytes.length, bytes));
      added++;
    } catch (_) {
      failed++;
    }
  }
  return PortablePartOutcome(added: added, failed: failed);
}
