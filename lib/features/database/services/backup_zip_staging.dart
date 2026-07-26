import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/database_file_classifier.dart';
import 'backup_zip_inventory.dart';
import 'backup_zip_manifest.dart';
import 'database_zip_pick_restore.dart';

export 'backup_zip_inventory.dart' show DatabaseFileProfiler;

/// Αποτέλεσμα εξαγωγής επιλεγμένης βάσης από αντίγραφο πριν αγγιχτεί ο προορισμός.
class BackupZipInspection {
  const BackupZipInspection._({
    required this.success,
    this.extractedDatabasePath,
    this.profile,
    this.manifest,
    this.errorMessage,
  });

  const BackupZipInspection.failure(String message)
    : this._(success: false, errorMessage: message);

  const BackupZipInspection.success({
    required String extractedDatabasePath,
    required DatabaseFileProfile profile,
    required BackupZipManifest manifest,
  }) : this._(
         success: true,
         extractedDatabasePath: extractedDatabasePath,
         profile: profile,
         manifest: manifest,
       );

  final bool success;
  final String? extractedDatabasePath;
  final DatabaseFileProfile? profile;
  final BackupZipManifest? manifest;
  final String? errorMessage;
}

/// Απογράφει το `.zip` χωρίς να διαλέξει υποψήφιο και χωρίς να αγγίξει προορισμό.
Future<BackupZipInventory> inspectBackupZip(
  String zipPath, {
  DatabaseFileProfiler? profile,
  void Function(int current, int total)? onProgress,
  int maxCandidatesToCheck = kBackupZipMaxCandidatesToCheck,
}) {
  return inventoryBackupZip(
    zipPath,
    profile: profile,
    onProgress: onProgress,
    maxCandidatesToCheck: maxCandidatesToCheck,
  );
}

/// Εξάγει ρητά την επιλεγμένη εγγραφή βάσης δίπλα στο zip και την προφιλάρει.
Future<BackupZipInspection> extractSelectedBackupZipEntry(
  String zipPath, {
  required String databaseEntryName,
  DatabaseFileProfiler? profile,
  String? preferredOutputFileName,
}) async {
  final zipFile = File(zipPath);
  if (!await zipFile.exists()) {
    return const BackupZipInspection.failure('Το αρχείο zip δεν βρέθηκε.');
  }

  Archive archive;
  try {
    final bytes = await zipFile.readAsBytes();
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (e) {
    return BackupZipInspection.failure(
      'Αποτυχία ανάγνωσης/αποσυμπίεσης zip: $e',
    );
  }

  final wanted = databaseEntryName.replaceAll('\\', '/');
  ArchiveFile? dbEntry;
  for (final f in archive.files) {
    if (!f.isFile) continue;
    final name = f.name.replaceAll('\\', '/');
    if (name == wanted) {
      dbEntry = f;
      break;
    }
  }

  if (dbEntry == null) {
    return BackupZipInspection.failure(
      'Δεν βρέθηκε η επιλεγμένη εγγραφή βάσης «$wanted» μέσα στο zip.',
    );
  }

  final outputName = preferredOutputFileName?.trim().isNotEmpty == true
      ? preferredOutputFileName!.trim()
      : p.basename(wanted);
  final extractedPath = DatabaseZipPickRestore.targetDatabasePathFor(
    zipPath,
    preferredDatabaseFileName: outputName,
  );

  try {
    await Directory(p.dirname(extractedPath)).create(recursive: true);
    await File(extractedPath).writeAsBytes(
      Uint8List.fromList(dbEntry.content as List<int>),
      flush: true,
    );
  } catch (e) {
    return BackupZipInspection.failure(
      'Αποτυχία εξαγωγής βάσης δίπλα στο αντίγραφο: $e',
    );
  }

  final manifest = BackupZipManifest.readFromArchive(archive);
  final fileProfile = await (profile ?? profileDatabaseFile)(extractedPath);

  return BackupZipInspection.success(
    extractedDatabasePath: extractedPath,
    profile: fileProfile,
    manifest: manifest,
  );
}

/// Καθαρίζει το εξαγμένο προσωρινό αρχείο βάσης (και sidecars αν υπάρχουν).
/// Επιστρέφει μήνυμα όταν ο καθαρισμός απέτυχε· αλλιώς `null`.
Future<String?> cleanupStagedDatabase(String? extractedPath) async {
  if (extractedPath == null || extractedPath.trim().isEmpty) return null;
  final path = extractedPath.trim();
  final failures = <String>[];
  for (final candidate in <String>[path, '$path-wal', '$path-shm']) {
    try {
      final f = File(candidate);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (e) {
      failures.add('${p.basename(candidate)}: $e');
    }
  }
  if (failures.isEmpty) return null;
  return 'Δεν καθαρίστηκε πλήρως το προσωρινό αρχείο εξαγωγής:\n'
      '${failures.join('\n')}';
}
