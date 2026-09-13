// Πού πηγαίνει ένα μοιραίο σφάλμα.
//
// Συμβόλαιο: κάθε σφάλμα αρχικοποίησης βάσης οδηγεί στην οθόνη σφάλματος
// βάσης — με τις διεξόδους της — ανεξάρτητα από το πότε συνέβη. Εύρημα
// 13/09/2026: όταν η βάση σκάει ΜΕΤΑ την εκκίνηση, ο χρήστης έβλεπε τη γενική
// κόκκινη οθόνη με μόνο κουμπί την «Επαναδοκιμή», που ξαναβρίσκει το ίδιο
// πρόβλημα· η μόνη έξοδος ήταν επανεκκίνηση της εφαρμογής.
//
//   flutter test test/core/errors/fatal_error_routing_test.dart

import 'package:call_logger/core/database/database_init_result.dart';
import 'package:call_logger/core/errors/fatal_error_routing.dart';
import 'package:flutter_test/flutter_test.dart';

DatabaseInitResult _incompleteDatabase() => const DatabaseInitResult(
  status: DatabaseStatus.corruptedOrInvalid,
  message:
      'Το αρχείο «Hospital.db» είναι ελλιπής βάση της Καταγραφής Κλήσεων — '
      'λείπουν οι πίνακες: phones, departments.',
  path: r'C:\data\Hospital.db',
  recoveryKind: DatabaseInitRecoveryKind.wrongDatabaseUnknown,
);

void main() {
  test('σφάλμα βάσης πάει στην οθόνη σφάλματος βάσης, με το αποτέλεσμά του', () {
    final state = classifyFatalError(
      DatabaseInitException(_incompleteDatabase()),
      StackTrace.current,
    );

    expect(state, isA<DatabaseFatalError>());
    final database = state as DatabaseFatalError;
    expect(database.result.message, contains('phones'));
    expect(database.result.path, r'C:\data\Hospital.db');
  });

  test('σφάλμα βάσης τυλιγμένο σε άλλο σφάλμα αναγνωρίζεται κι αυτό', () {
    // Η αρχικοποίηση καλείται μέσα από providers· το σφάλμα φτάνει συχνά
    // τυλιγμένο, και η δρομολόγηση δεν επιτρέπεται να το χάσει.
    final state = classifyFatalError(
      _WrappedFailure(DatabaseInitException(_incompleteDatabase())),
      StackTrace.current,
    );

    expect(state, isA<DatabaseFatalError>());
  });

  test('οτιδήποτε άλλο πάει στη γενική οθόνη με την αναφορά του', () {
    final state = classifyFatalError(
      StateError('κάτι εντελώς άλλο'),
      StackTrace.current,
    );

    expect(state, isA<GeneralFatalError>());
    final general = state as GeneralFatalError;
    expect(general.result.friendlyTitle, isNotEmpty);
  });

  test('σκέτο κείμενο σφάλματος δεν περνά για σφάλμα βάσης', () {
    final state = classifyFatalError(
      'DatabaseInitException: κάτι',
      StackTrace.current,
    );

    expect(
      state,
      isA<GeneralFatalError>(),
      reason: 'Η αναγνώριση γίνεται από τον τύπο, όχι από το κείμενο',
    );
  });
}

/// Σφάλμα που κουβαλά μέσα του το αληθινό αίτιο.
class _WrappedFailure implements Exception {
  _WrappedFailure(this.cause);

  final Object cause;

  @override
  String toString() => 'Αποτυχία: $cause';
}
