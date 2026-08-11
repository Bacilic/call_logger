// Μήνυμα του φρουρού αναντιστοιχίας σχήματος — διαφορετικές διέξοδοι ανά
// κατεύθυνση:
//
// • Αρχείο ΝΕΟΤΕΡΟ από την εφαρμογή: πιθανότερο αίτιο το ξεχασμένο παλαιότερο
//   αντίγραφο· οι διέξοδοι είναι η νεότερη εγκατάσταση, άλλο αρχείο,
//   αντίγραφο ασφαλείας ή υποβάθμιση — ΠΟΤΕ «script μετασχηματισμού», γιατί
//   δεν υπάρχει τέτοιο πράγμα προς τα πίσω.
// • Αρχείο ΠΑΛΑΙΟΤΕΡΟ: οι κλασικές διέξοδοι (script, εντοπισμός, νέα βάση).
//
//   flutter test test/core/database/schema_version_mismatch_message_test.dart

import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('schemaVersionMismatchUserMessage', () {
    test('newer file than app → stale-app hint, σωστές διέξοδοι, όχι script',
        () {
      final message = schemaVersionMismatchUserMessage(
        fileName: 'hosp.db',
        fileUserVersion: 37,
        appSchemaVersion: 36,
      );

      expect(message, contains('hosp.db'));
      expect(message, contains('έκδοση 37'));
      expect(message, contains('την έκδοση 36'));
      expect(message, contains('νεότερης έκδοσης'));
      expect(message, contains('παλαιότερο αντίγραφο της εφαρμογής'));
      expect(message, contains('Αντίγραφα της εφαρμογής'));
      expect(message, contains('Μπορείτε να:'));
      expect(message, contains('αντίγραφο ασφαλείας'));
      expect(message, contains('Υποβαθμίσετε'));
      // Δεν υπάρχει «script» προς τα πίσω — λάθος και τρομακτική συμβουλή.
      expect(message, isNot(contains('script')));
      expect(message, isNot(contains('νέα βάση χωρίς δεδομένα')));
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
      expect(message, contains('νέα βάση χωρίς δεδομένα'));
    });
  });
}
