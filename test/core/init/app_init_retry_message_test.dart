// Μήνυμα αποτυχίας της επαναδοκιμής αρχικοποίησης.
//
// Ολόκληρο αρχείο (από ρίζα έργου):
//   flutter test test/core/init/app_init_retry_message_test.dart

import 'package:call_logger/core/init/app_init_retry_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Μήνυμα αποτυχίας επαναδοκιμής αρχικοποίησης', () {
    test('χωρίς αποτυχία κλεισίματος επιστρέφει σκέτο το βασικό μήνυμα', () {
      final message = composeAppInitRetryFailureMessage(
        base: 'Η βάση δεν βρέθηκε.',
        closeFailure: null,
      );

      expect(message, 'Η βάση δεν βρέθηκε.');
    });

    test('με αποτυχία κλεισίματος εξηγεί και το κλείδωμα του αρχείου', () {
      final message = composeAppInitRetryFailureMessage(
        base: 'Η βάση δεν βρέθηκε.',
        closeFailure: Exception('database is locked'),
      );

      expect(message, startsWith('Η βάση δεν βρέθηκε.'));
      expect(message, contains('Το κλείσιμο της τρέχουσας σύνδεσης απέτυχε'));
      expect(message, contains('άλλο ανοιχτό αντίγραφο'));
    });
  });

  group('Αποτέλεσμα επαναδοκιμής', () {
    test('η επιτυχία δεν κουβαλά μήνυμα σφάλματος', () {
      const outcome = AppInitRetryOutcome.success();

      expect(outcome.succeeded, isTrue);
      expect(outcome.errorMessage, isNull);
    });

    test('η αποτυχία κουβαλά το μήνυμα προς εμφάνιση', () {
      const outcome = AppInitRetryOutcome.failure('Κάτι πήγε στραβά.');

      expect(outcome.succeeded, isFalse);
      expect(outcome.errorMessage, 'Κάτι πήγε στραβά.');
    });
  });
}
