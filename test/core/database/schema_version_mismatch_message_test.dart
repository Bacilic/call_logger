// Μήνυμα του φρουρού αναντιστοιχίας σχήματος: όταν το αρχείο βάσης είναι
// ΝΕΟΤΕΡΟ από την εφαρμογή (π.χ. «βάση σε 37, εφαρμογή σε 36»), το πιθανότερο
// αίτιο είναι ξεχασμένο παλαιότερο αντίγραφο της εφαρμογής — και το μήνυμα
// πρέπει να το λέει ρητά, με παραπομπή στην κάρτα «Αντίγραφα της εφαρμογής».
//
//   flutter test test/core/database/schema_version_mismatch_message_test.dart

import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('schemaVersionMismatchUserMessage', () {
    test('newer file than app → explicit stale-app hint with card pointer', () {
      final message = schemaVersionMismatchUserMessage(
        fileName: 'hosp.db',
        fileUserVersion: 37,
        appSchemaVersion: 36,
      );

      expect(message, contains('hosp.db'));
      expect(message, contains('έκδοση 37'));
      expect(message, contains('την έκδοση 36'));
      expect(message, contains('παλαιότερο αντίγραφο της εφαρμογής'));
      expect(message, contains('Αντίγραφα της εφαρμογής'));
      // Οι πάγιες διέξοδοι παραμένουν.
      expect(message, contains('Μπορείτε να:'));
      expect(message, contains('νέα βάση χωρίς δεδομένα'));
    });

    test('older file (upgrade direction) → no stale-app hint', () {
      final message = schemaVersionMismatchUserMessage(
        fileName: 'hosp.db',
        fileUserVersion: 20,
        appSchemaVersion: 36,
      );

      expect(message, isNot(contains('παλαιότερο αντίγραφο')));
      expect(message, isNot(contains('Αντίγραφα της εφαρμογής')));
      expect(message, contains('Μπορείτε να:'));
    });
  });
}
