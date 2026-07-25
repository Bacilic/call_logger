// Manifest αντιγράφου .zip — εγγραφή, ανάγνωση, ανεκτικότητα.
//
//   flutter test test/features/database/services/backup_zip_manifest_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:call_logger/features/database/services/backup_zip_manifest.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('backup_zip_manifest_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('εγγραφή και ανάγνωση manifest στρογγυλεύουν τα πεδία', () {
    final original = BackupZipManifest(
      originalDatabasePath: r'C:\data\call_logger.db',
      databaseFileName: 'call_logger.db',
      createdAt: DateTime.utc(2026, 7, 25, 11, 32),
      appVersion: '0.21.4',
      schemaVersion: 41,
    );

    final decoded = BackupZipManifest.parseJson(original.toJsonString());

    expect(decoded.isKnown, isTrue);
    expect(decoded.originalDatabasePath, r'C:\data\call_logger.db');
    expect(decoded.databaseFileName, 'call_logger.db');
    expect(decoded.createdAt, DateTime.utc(2026, 7, 25, 11, 32));
    expect(decoded.appVersion, '0.21.4');
    expect(decoded.schemaVersion, 41);
  });

  test('απουσία manifest → άγνωστη προέλευση, χωρίς εξαίρεση', () {
    final archive = Archive();
    archive.addFile(ArchiveFile('call_logger.db', 3, utf8.encode('abc')));

    final read = BackupZipManifest.readFromArchive(archive);

    expect(read.isKnown, isFalse);
    expect(read.originalDatabasePath, isNull);
  });

  test('χαλασμένο JSON στο zip → άγνωστη προέλευση, χωρίς εξαίρεση', () {
    final archive = Archive();
    archive.addFile(
      ArchiveFile(
        BackupZipManifest.zipEntryName,
        11,
        utf8.encode('not-json!!!'),
      ),
    );

    expect(() => BackupZipManifest.readFromArchive(archive), returnsNormally);
    final read = BackupZipManifest.readFromArchive(archive);
    expect(read.isKnown, isFalse);
  });

  test('κενό αρχείο manifest → άγνωστη προέλευση', () {
    final archive = Archive();
    archive.addFile(
      ArchiveFile(BackupZipManifest.zipEntryName, 0, Uint8List(0)),
    );

    final read = BackupZipManifest.readFromArchive(archive);
    expect(read.isKnown, isFalse);
  });

  test('ανάγνωση από αρχείο δίσκου είναι ανεκτική όταν λείπει', () async {
    final missing = p.join(tempDir.path, 'nope.json');
    final read = await BackupZipManifest.readFromFile(missing);
    expect(read.isKnown, isFalse);
  });
}
