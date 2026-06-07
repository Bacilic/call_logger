import 'dart:io';

import 'package:call_logger/features/database/utils/backup_destination_folder_validator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('BackupDestinationFolderValidator', () {
    test('missing directory is reported distinctly from invalid path', () async {
      final missing = p.join(
        Directory.systemTemp.path,
        'call_logger_missing_dir_test_xyz',
      );
      final result = await BackupDestinationFolderValidator.validate(missing);
      expect(result.kind, BackupDestinationValidationKind.missingDirectory);
      expect(result.errorMessage, 'Ο φάκελος δεν υπάρχει');
    });

    test('empty path is ok', () async {
      final result = await BackupDestinationFolderValidator.validate('   ');
      expect(result.kind, BackupDestinationValidationKind.ok);
    });

    test('inspectDestinationContent folderMissing', () async {
      final missing = p.join(
        Directory.systemTemp.path,
        'call_logger_content_missing_xyz',
      );
      final result =
          await BackupDestinationFolderValidator.inspectDestinationContent(
        destinationDirectory: missing,
        dbBaseName: 'call_logger',
      );
      expect(result.kind, BackupDestinationContentKind.folderMissing);
    });

    test('inspectDestinationContent folderEmptyNoFiles', () async {
      final dir = await Directory(
        p.join(
          Directory.systemTemp.path,
          'call_logger_content_empty_${DateTime.now().microsecondsSinceEpoch}',
        ),
      ).create(recursive: true);
      addTearDown(() async {
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      });
      final result =
          await BackupDestinationFolderValidator.inspectDestinationContent(
        destinationDirectory: dir.path,
        dbBaseName: 'call_logger',
      );
      expect(result.kind, BackupDestinationContentKind.folderEmptyNoFiles);
    });

    test('inspectDestinationContent folderOk', () async {
      final dir = await Directory(
        p.join(
          Directory.systemTemp.path,
          'call_logger_content_ok_${DateTime.now().microsecondsSinceEpoch}',
        ),
      ).create(recursive: true);
      addTearDown(() async {
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      });
      final file = File(
        p.join(dir.path, '2026-06-06_18-12_call_logger.zip'),
      );
      await file.writeAsString('x');
      final result =
          await BackupDestinationFolderValidator.inspectDestinationContent(
        destinationDirectory: dir.path,
        dbBaseName: 'call_logger',
      );
      expect(result.kind, BackupDestinationContentKind.folderOk);
      expect(result.matchingBackupFileCount, 1);
      expect(result.latestBackupModified, isNotNull);
    });

    test('isBackupArtifactFileName', () {
      expect(
        BackupDestinationFolderValidator.isBackupArtifactFileName(
          '2026-06-06_18-12_call_logger.zip',
          'call_logger',
        ),
        isTrue,
      );
      expect(
        BackupDestinationFolderValidator.isBackupArtifactFileName(
          'random.txt',
          'call_logger',
        ),
        isFalse,
      );
    });
  });
}
