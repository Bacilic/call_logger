// Επαναφορά επιλεγμένου .zip ΕΞΩ από το widget: η αποτυχία κλεισίματος
// σύνδεσης δεν καταπίνεται σιωπηλά, και το αποτέλεσμα είναι είτε διαδρομή
// είτε μήνυμα — ποτέ και τα δύο.
//
//   flutter test test/features/database/services/database_zip_pick_restore_test.dart

import 'package:call_logger/features/database/services/database_backup_service.dart';
import 'package:call_logger/features/database/services/database_zip_pick_restore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _zipPath = r'E:\call logger\backup\call_logger_2026-07-25.zip';

ZipRestoreRunner _runnerReturning(DatabaseRestoreResult result,
    {List<String>? capturedTargets}) {
  return (String zipPath, {
    required String targetDatabasePath,
    String? databaseEntryName,
  }) async {
    capturedTargets?.add(targetDatabasePath);
    return result;
  };
}

Future<void> _closesFine() async {}

Future<void> _closeThrows() async =>
    throw StateError('database is locked (errno = 32)');

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

  group('DatabaseZipPickRestore.restore', () {
    test('επιτυχία: επιστρέφει τη διαδρομή της επαναφερμένης βάσης', () async {
      final targets = <String>[];
      final outcome = await DatabaseZipPickRestore.restore(
        _zipPath,
        closeConnection: _closesFine,
        runRestore: _runnerReturning(
          const DatabaseRestoreResult(
            success: true,
            databasePath: r'E:\call logger\backup\call_logger.db',
          ),
          capturedTargets: targets,
        ),
      );

      expect(outcome.isRestored, isTrue);
      expect(outcome.databasePath, r'E:\call logger\backup\call_logger.db');
      expect(outcome.errorMessage, isNull);
      expect(
        targets.single,
        DatabaseZipPickRestore.targetDatabasePathFor(_zipPath),
        reason: 'ο στόχος υπολογίζεται από την υπηρεσία, όχι από τον καλούντα',
      );
    });

    test('αποτυχία: επιστρέφει το μήνυμα της υπηρεσίας χωρίς διαδρομή',
        () async {
      final outcome = await DatabaseZipPickRestore.restore(
        _zipPath,
        closeConnection: _closesFine,
        runRestore: _runnerReturning(
          const DatabaseRestoreResult(
            success: false,
            message: 'Το αρχείο zip δεν βρέθηκε.',
          ),
        ),
      );

      expect(outcome.isRestored, isFalse);
      expect(outcome.databasePath, isNull);
      expect(outcome.errorMessage, 'Το αρχείο zip δεν βρέθηκε.');
    });

    test('success true αλλά χωρίς διαδρομή μετράει ως αποτυχία', () async {
      final outcome = await DatabaseZipPickRestore.restore(
        _zipPath,
        closeConnection: _closesFine,
        runRestore: _runnerReturning(
          const DatabaseRestoreResult(success: true),
        ),
      );

      expect(outcome.isRestored, isFalse);
      expect(outcome.errorMessage, 'Αποτυχία επαναφοράς από zip.');
    });

    test(
        'αποτυχία κλεισίματος σύνδεσης ΔΕΝ καταπίνεται: μπαίνει στο μήνυμα '
        'όταν αποτύχει και η επαναφορά', () async {
      final outcome = await DatabaseZipPickRestore.restore(
        _zipPath,
        closeConnection: _closeThrows,
        runRestore: _runnerReturning(
          const DatabaseRestoreResult(
            success: false,
            message: 'Αποτυχία αντικατάστασης αρχείου βάσης.',
          ),
        ),
      );

      expect(outcome.isRestored, isFalse);
      expect(outcome.errorMessage, contains('Αποτυχία αντικατάστασης'));
      expect(outcome.errorMessage, contains('κλείσιμο της τρέχουσας σύνδεσης'));
      expect(outcome.errorMessage, contains('κλειδωμένο'));
    });

    test(
        'αποτυχία κλεισίματος δεν ενοχλεί τον χρήστη όταν η επαναφορά πέτυχε',
        () async {
      final outcome = await DatabaseZipPickRestore.restore(
        _zipPath,
        closeConnection: _closeThrows,
        runRestore: _runnerReturning(
          const DatabaseRestoreResult(
            success: true,
            databasePath: r'E:\call logger\backup\call_logger.db',
          ),
        ),
      );

      expect(outcome.isRestored, isTrue);
      expect(outcome.errorMessage, isNull);
    });
  });
}
