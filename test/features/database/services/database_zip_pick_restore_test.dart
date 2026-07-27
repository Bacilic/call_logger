// Υπολογισμός διαδρομής στόχου για επαναφορά επιλεγμένου .zip.
//
//   flutter test test/features/database/services/database_zip_pick_restore_test.dart

import 'package:call_logger/features/database/services/database_zip_pick_restore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _zipPath = r'E:\call logger\backup\call_logger_2026-07-25.zip';

void main() {
  group('DatabaseZipPickRestore.targetDatabasePathFor', () {
    test('η βάση εξάγεται στον ίδιο φάκελο με το .zip', () {
      final target = DatabaseZipPickRestore.targetDatabasePathFor(_zipPath);

      expect(p.dirname(target), p.dirname(_zipPath));
      expect(
        p.basename(target),
        DatabaseZipPickRestore.restoredDatabaseFileName,
      );
    });

    test('κρατά το πραγματικό όνομα της εγγραφής όταν δίνεται', () {
      final target = DatabaseZipPickRestore.targetDatabasePathFor(
        _zipPath,
        preferredDatabaseFileName: 'giannis.db',
        fileExists: (_) => false,
      );

      expect(p.basename(target), 'giannis.db');
      expect(p.dirname(target), p.dirname(_zipPath));
    });

    test('ομώνυμο υπάρχον αρχείο → κλιμακούμενη ονομασία', () {
      final target = DatabaseZipPickRestore.targetDatabasePathFor(
        _zipPath,
        preferredDatabaseFileName: 'giannis.db',
        fileExists: (path) => p.basename(path) == 'giannis.db',
      );

      expect(p.basename(target), isNot('giannis.db'));
      expect(p.basename(target), startsWith('giannis_'));
      expect(p.basename(target), endsWith('.db'));
    });
  });
}
