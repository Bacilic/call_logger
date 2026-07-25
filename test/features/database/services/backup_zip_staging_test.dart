// Επιθεώρηση αντιγράφου .zip πριν αγγιχτεί ο προορισμός.
//
//   flutter test test/features/database/services/backup_zip_staging_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:call_logger/core/database/database_file_classifier.dart';
import 'package:call_logger/core/services/building_map_storage.dart';
import 'package:call_logger/features/database/services/backup_zip_manifest.dart';
import 'package:call_logger/features/database/services/backup_zip_staging.dart';
import 'package:call_logger/features/database/services/database_zip_pick_restore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Future<void> _writeZip(String zipPath, Archive archive) async {
  final bytes = ZipEncoder().encode(archive);
  await File(zipPath).writeAsBytes(bytes, flush: true);
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('backup_zip_staging_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'η απογραφή δεν διαλέγει μόνη της· η εξαγωγή δέχεται ρητή εγγραφή',
    () async {
      final zipPath = p.join(tempDir.path, 'backup.zip');
      final destination = p.join(tempDir.path, 'live', 'call_logger.db');
      await Directory(p.dirname(destination)).create(recursive: true);
      await File(destination).writeAsString('DO_NOT_TOUCH');

      final archive = Archive();
      archive.addFile(
        ArchiveFile(
          BuildingMapStorage.backupZipDbFileName,
          8,
          utf8.encode('STAGEDDB'),
        ),
      );
      archive.addFile(
        ArchiveFile('other.db', 5, utf8.encode('OTHER')),
      );
      final manifest = BackupZipManifest(
        originalDatabasePath: r'D:\old\call_logger.db',
        databaseFileName: 'call_logger.db',
        createdAt: DateTime.utc(2026, 7, 25),
        appVersion: '0.21.4',
        schemaVersion: 41,
      );
      final manifestBytes = utf8.encode(manifest.toJsonString());
      archive.addFile(
        ArchiveFile(
          BackupZipManifest.zipEntryName,
          manifestBytes.length,
          manifestBytes,
        ),
      );
      await _writeZip(zipPath, archive);

      final inventory = await inspectBackupZip(
        zipPath,
        profile: (_) async =>
            const DatabaseFileProfile(kind: DatabaseFileKind.callLogger),
      );

      expect(inventory.eligibleCandidates, hasLength(2));
      expect(await File(destination).readAsString(), 'DO_NOT_TOUCH');
      expect(
        File(DatabaseZipPickRestore.targetDatabasePathFor(zipPath)).existsSync(),
        isFalse,
        reason: 'η απογραφή δεν εξάγει μόνιμα την επιλεγμένη βάση',
      );

      final expectedExtracted = DatabaseZipPickRestore.targetDatabasePathFor(
        zipPath,
        preferredDatabaseFileName: BuildingMapStorage.backupZipDbFileName,
      );
      var profilerCalls = 0;

      final result = await extractSelectedBackupZipEntry(
        zipPath,
        databaseEntryName: BuildingMapStorage.backupZipDbFileName,
        preferredOutputFileName: BuildingMapStorage.backupZipDbFileName,
        profile: (path) async {
          profilerCalls++;
          expect(path, expectedExtracted);
          return const DatabaseFileProfile(kind: DatabaseFileKind.callLogger);
        },
      );

      expect(result.success, isTrue);
      expect(result.extractedDatabasePath, expectedExtracted);
      expect(await File(expectedExtracted).readAsString(), 'STAGEDDB');
      expect(result.manifest?.isKnown, isTrue);
      expect(result.manifest?.originalDatabasePath, r'D:\old\call_logger.db');
      expect(profilerCalls, 1);
      expect(await File(destination).readAsString(), 'DO_NOT_TOUCH');
    },
  );

  test('χωρίς αρχείο βάσης στο zip → άδεια απογραφή', () async {
    final zipPath = p.join(tempDir.path, 'empty.zip');
    final archive = Archive();
    archive.addFile(ArchiveFile('readme.txt', 4, utf8.encode('hi')));
    await _writeZip(zipPath, archive);

    final inventory = await inspectBackupZip(
      zipPath,
      profile: (_) async =>
          const DatabaseFileProfile(kind: DatabaseFileKind.callLogger),
    );

    expect(inventory.totalDatabaseEntries, 0);
    expect(inventory.eligibleCandidates, isEmpty);
  });

  test('εξαγωγή ανύπαρκτης εγγραφής → αποτυχία', () async {
    final zipPath = p.join(tempDir.path, 'one.zip');
    final archive = Archive();
    archive.addFile(
      ArchiveFile(
        BuildingMapStorage.backupZipDbFileName,
        4,
        utf8.encode('data'),
      ),
    );
    await _writeZip(zipPath, archive);

    final result = await extractSelectedBackupZipEntry(
      zipPath,
      databaseEntryName: 'missing.db',
      profile: (_) async =>
          const DatabaseFileProfile(kind: DatabaseFileKind.callLogger),
    );

    expect(result.success, isFalse);
    expect(result.errorMessage, contains('επιλεγμένη'));
  });
}
