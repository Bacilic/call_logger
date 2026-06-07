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

    test('invalidPathFormat when path lacks .db extension', () async {
      final result = await validator.validateReadPath(
        r'F:\Data\old_base_test',
        outputPath: r'F:\Data\old_base_test',
        excelPath: r'F:\Data\file.xlsx',
      );
      expect(result.status, LampOldDbStatus.invalidPathFormat);
      expect(
        result.userMessageGreek,
        'Η διαδρομή πρέπει να δείχνει σε αρχείο με κατάληξη .db',
      );
    });

    test('invalidPathFormat blocks pendingCreation for same missing path', () async {
      final result = await validator.validateReadPath(
        r'C:\missing\old_base_test',
        outputPath: r'C:\missing\old_base_test',
        excelPath: r'C:\import\file.xlsx',
      );
      expect(result.status, LampOldDbStatus.invalidPathFormat);
    });
  });

  group('LampOldDbValidator.validateDbPathFormat', () {
    test('returns null for empty path', () {
      expect(LampOldDbValidator.validateDbPathFormat(''), isNull);
      expect(LampOldDbValidator.validateDbPathFormat('   '), isNull);
    });

    test('returns null for valid .db path', () {
      expect(
        LampOldDbValidator.validateDbPathFormat(r'C:\Data\lampa_test.db'),
        isNull,
      );
    });

    test('returns error when extension is missing', () {
      expect(
        LampOldDbValidator.validateDbPathFormat(r'F:\Data\old_base_test'),
        'Η διαδρομή πρέπει να δείχνει σε αρχείο με κατάληξη .db',
      );
    });
  });
}
