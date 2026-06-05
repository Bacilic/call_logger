import 'package:call_logger/core/database/old_database/lamp_old_db_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LampOldDbValidator.pathsReferToSameFile', () {
    test('matches normalized paths on Windows', () {
      expect(
        LampOldDbValidator.pathsReferToSameFile(
          r'C:\Data\lampa_test.db',
          r'c:\data\lampa_test.db',
        ),
        isTrue,
      );
    });

    test('returns false when paths differ', () {
      expect(
        LampOldDbValidator.pathsReferToSameFile(
          r'C:\Data\a.db',
          r'C:\Data\b.db',
        ),
        isFalse,
      );
    });
  });

  group('LampOldDbCheckResult pendingCreation message', () {
    test('with Excel file', () {
      const result = LampOldDbCheckResult(
        LampOldDbStatus.pendingCreation,
        pendingDbFileName: 'lampa_test.db',
        pendingFolderPath: r'C:\Users\test\Documents',
        pendingExcelFileName: 'αρχείο.xlsx',
      );
      expect(
        result.userMessageGreek,
        'Το αρχείο [lampa_test.db] θα δημιουργηθεί στον φάκελο '
        r'[C:\Users\test\Documents] μετά την επιτυχή εισαγωγή του Excel '
        '[αρχείο.xlsx] (κουμπί: $kLampExcelImportButtonLabel).',
      );
    });

    test('without Excel file', () {
      const result = LampOldDbCheckResult(
        LampOldDbStatus.pendingCreation,
        pendingDbFileName: 'lampa_test.db',
        pendingFolderPath: r'C:\Users\test\Documents',
      );
      expect(
        result.userMessageGreek,
        'Το αρχείο [lampa_test.db] θα δημιουργηθεί στον φάκελο '
        r'[C:\Users\test\Documents] όταν οριστεί αρχείο Excel και εκτελεστεί '
        'επιτυχώς η εισαγωγή (κουμπί: $kLampExcelImportButtonLabel).',
      );
    });
  });

  group('LampOldDbValidator.validateReadPath', () {
    late LampOldDbValidator validator;

    setUp(() {
      validator = LampOldDbValidator();
    });

    test('pendingCreation when read matches output and file is missing', () async {
      final result = await validator.validateReadPath(
        r'C:\missing\lampa_test.db',
        outputPath: r'C:\missing\lampa_test.db',
        excelPath: r'C:\import\αρχείο.xlsx',
      );
      expect(result.status, LampOldDbStatus.pendingCreation);
      expect(result.pendingDbFileName, 'lampa_test.db');
      expect(result.pendingFolderPath, r'C:\missing');
      expect(result.pendingExcelFileName, 'αρχείο.xlsx');
    });

    test('fileMissing when read differs from output and file is missing', () async {
      final result = await validator.validateReadPath(
        r'C:\missing\read.db',
        outputPath: r'C:\missing\out.db',
        excelPath: r'C:\import\file.xlsx',
      );
      expect(result.status, LampOldDbStatus.fileMissing);
    });
  });
}
