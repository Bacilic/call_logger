// Καθαρή λογική σχεδίου επαναφοράς — χωρίς αρχεία και χωρίς UI.
//
// Συμβόλαιο: η επαναφορά γράφει πάντα στον φάκελο της τρέχουσας βάσης·
// η επιλογή του χρήστη αφορά μόνο το όνομα του αρχείου (τρέχον ή του αντιγράφου).
//
//   flutter test test/features/database/services/restore_plan_test.dart

import 'package:call_logger/features/database/services/restore_plan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  const current = r'C:\app\data\integrity_debug.db';

  test('προεπιλογή είναι η τρέχουσα βάση', () {
    expect(
      RestoreDestinationChoice.defaultChoice,
      RestoreDestinationChoice.currentDatabase,
    );
  });

  test('η τρέχουσα βάση επιστρέφει την ίδια διαδρομή', () {
    expect(
      resolveRestoreTargetPath(
        choice: RestoreDestinationChoice.currentDatabase,
        currentDatabasePath: current,
        backupDatabaseFileName: 'call_logger.db',
      ),
      current,
    );
  });

  test('το όνομα του αντιγράφου πάει ΠΑΝΤΑ στον φάκελο της τρέχουσας βάσης', () {
    final target = resolveRestoreTargetPath(
      choice: RestoreDestinationChoice.backupName,
      currentDatabasePath: current,
      backupDatabaseFileName: 'call_logger.db',
    );
    expect(p.dirname(target), p.dirname(current));
    expect(p.basename(target), 'call_logger.db');
  });

  test('όνομα αντιγράφου χωρίς .db συμπληρώνεται και καθαρίζεται από φακέλους', () {
    final target = resolveRestoreTargetPath(
      choice: RestoreDestinationChoice.backupName,
      currentDatabasePath: current,
      backupDatabaseFileName: r'backups\call_logger_old',
    );
    expect(p.dirname(target), p.dirname(current));
    expect(p.basename(target), 'call_logger_old.db');
  });

  test('χωρίς αξιοποιήσιμο όνομα αντιγράφου μένει μόνο η τρέχουσα βάση', () {
    expect(
      availableRestoreDestinations(
        currentDatabasePath: current,
        backupDatabaseFileName: null,
      ),
      [RestoreDestinationChoice.currentDatabase],
    );
    expect(
      availableRestoreDestinations(
        currentDatabasePath: current,
        backupDatabaseFileName: '  ',
      ),
      [RestoreDestinationChoice.currentDatabase],
    );
  });

  test('ίδιο όνομα με την τρέχουσα → οι επιλογές ταυτίζονται, μένει μία', () {
    expect(
      availableRestoreDestinations(
        currentDatabasePath: current,
        backupDatabaseFileName: 'integrity_debug.db',
      ),
      [RestoreDestinationChoice.currentDatabase],
    );
    expect(
      availableRestoreDestinations(
        currentDatabasePath: current,
        backupDatabaseFileName: 'INTEGRITY_DEBUG.DB',
      ),
      [RestoreDestinationChoice.currentDatabase],
      reason: 'τα ονόματα αρχείων στα Windows δεν διακρίνουν πεζά/κεφαλαία',
    );
  });

  test('διαφορετικό όνομα → και οι δύο επιλογές, με πρώτη την τρέχουσα', () {
    expect(
      availableRestoreDestinations(
        currentDatabasePath: current,
        backupDatabaseFileName: 'call_logger.db',
      ),
      [
        RestoreDestinationChoice.currentDatabase,
        RestoreDestinationChoice.backupName,
      ],
    );
  });
}
