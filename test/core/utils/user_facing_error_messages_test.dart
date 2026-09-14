import 'dart:io';

import 'package:call_logger/core/directory/phone_department_policy.dart';
import 'package:call_logger/core/utils/user_facing_error_messages.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common/sqlite_api.dart';

/// Ελάχιστη υλοποίηση για δοκιμές — το `SqfliteDatabaseException` δεν εξάγεται δημόσια.
class _TestDatabaseException extends DatabaseException {
  _TestDatabaseException(super.message);

  @override
  int? getResultCode() => null;

  @override
  Object? get result => null;
}

void main() {
  group('humanizeUserFacingError', () {
    test(
      'PhoneDepartmentPolicyException → μήνυμα με αριθμό, χωρίς Exception',
      () {
        final error = PhoneDepartmentPolicyException([
          const PhoneDepartmentConflict(
            phone: '2917',
            hasDepartmentLocationConflict: true,
            hasOtherUserOwners: false,
          ),
        ]);

        final message = humanizeUserFacingError(error);

        expect(message, contains('2917'));
        expect(message, contains('άλλο τμήμα'));
        expect(message.toLowerCase(), isNot(contains('exception')));
      },
    );

    test('DatabaseException locked/busy → απασχολημένη βάση', () {
      final locked = _TestDatabaseException('database is locked');
      final busy = _TestDatabaseException('SQLITE_BUSY');

      expect(humanizeUserFacingError(locked), contains('απασχολημένη'));
      expect(humanizeUserFacingError(busy), contains('απασχολημένη'));
    });

    test('DatabaseException database_closed → ανανέωση σύνδεσης', () {
      final error = _TestDatabaseException('database_closed');

      expect(humanizeUserFacingError(error), contains('ανανεώθηκε'));
    });

    test('FileSystemException → πρόσβαση αρχείου', () {
      final error = const FileSystemException(
        'Permission denied',
        r'C:\tmp\db',
      );

      expect(humanizeUserFacingError(error), contains('πρόσβαση'));
    });

    test('άγνωστο σφάλμα → γενικό μήνυμα με τεχνικές λεπτομέρειες', () {
      final error = Exception('xyz_unique_detail_token_for_support');

      final message = humanizeUserFacingError(error);

      expect(message, startsWith('Απρόβλεπτο σφάλμα. Τεχνικές λεπτομέρειες:'));
      expect(message, contains('xyz_unique_detail_token_for_support'));
    });

    group('φθορά περιεχομένου', () {
      // Το πραγματικό μήνυμα της οθόνης «Βάση Δεδομένων» (13/09): από πάνω
      // «η σύνδεση πέτυχε», από κάτω τρεις σειρές αγγλικού SQL.
      const raw =
          'SqfliteFfiException(sqlite_error: 11, SqliteException(11): while '
          'selecting from statement, database disk image is malformed, '
          'malformed database (code 11) Causing statement: '
          'SELECT COUNT(*) AS c FROM "audit_log"';

      test('το «malformed» γίνεται ελληνική πρόταση, χωρίς ωμό SQL', () {
        final message = humanizeUserFacingError(Exception(raw));

        expect(message, contains('δεν διαβάζεται'));
        expect(message, contains('αντίγραφο ασφαλείας'));
        for (final word in const <String>[
          'malformed',
          'SELECT',
          'sqlite',
          'Causing',
        ]) {
          expect(message, isNot(contains(word)));
        }
      });

      test('δεν ισχυρίζεται ότι η σύνδεση απέτυχε', () {
        // Η αντίφαση που γέννησε το εύρημα: η σύνδεση ΟΝΤΩΣ πέτυχε. Το
        // μήνυμα οφείλει να συμφωνεί με την ένδειξη από πάνω, όχι να τη
        // διαψεύδει.
        final message = humanizeUserFacingError(Exception(raw));
        expect(message, startsWith('Η βάση απαντά'));
      });

      test('δεν ισχυρίζεται την ΑΙΤΙΑ — η ίδια φωνή έχει δύο γονείς', () {
        // Το ίδιο μήνυμα βγάζει και αρχείο που αντικαταστάθηκε κάτω από
        // ανοιχτή σύνδεση, που θεραπεύεται με επανεκκίνηση. Η οριστική
        // ενέργεια μένει δεύτερη και υπό όρο.
        final message = humanizeUserFacingError(Exception(raw));
        expect(message, contains('Αν το πρόβλημα συνεχιστεί'));
        expect(message, isNot(contains('φθορά στο αρχείο')));
      });

      test('«invalid rootpage»: ίδια οικογένεια, ίδιο μήνυμα', () {
        final message = humanizeUserFacingError(
          Exception(
            'DatabaseException(malformed database schema '
            '(call_external_links) - invalid rootpage)',
          ),
        );
        expect(message, contains('δεν διαβάζεται'));
      });
    });
  });
}
