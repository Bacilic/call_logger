// Ποια οθόνη δείχνει το κέλυφος για κάθε είδος μοιραίου σφάλματος.
//
// Συμβόλαιο: η βάση που δεν ανοίγει παίρνει την οθόνη σφάλματος βάσης — με τις
// διεξόδους της — ακόμη κι όταν σκάει ΜΕΤΑ την εκκίνηση. Εύρημα 13/09/2026:
// έπαιρνε τη γενική κόκκινη οθόνη, της οποίας η «Επαναδοκιμή» ξαναβρίσκει το
// ίδιο πρόβλημα, και η μόνη έξοδος ήταν επανεκκίνηση.
//
// Ελέγχεται η ΑΠΟΦΑΣΗ, όχι το χτίσιμο: η οθόνη σφάλματος βάσης διαβάζει δίσκο
// μόλις εμφανιστεί, και ένα τεστ που την έχτιζε θα κρεμούσε στον εικονικό
// χρόνο.
//
//   flutter test test/core/widgets/app_shell_fatal_error_routing_test.dart

import 'package:call_logger/core/database/database_init_result.dart';
import 'package:call_logger/core/errors/app_error_result.dart';
import 'package:call_logger/core/errors/fatal_error_routing.dart';
import 'package:call_logger/core/widgets/app_shell_with_global_fatal_error.dart';
import 'package:call_logger/core/widgets/database_error_screen.dart';
import 'package:call_logger/core/widgets/fatal_error_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _databaseFailure = DatabaseInitResult(
  status: DatabaseStatus.corruptedOrInvalid,
  message:
      'Το αρχείο «Hospital.db» είναι ελλιπής βάση της Καταγραφής Κλήσεων — '
      'λείπουν οι πίνακες: phones, departments.',
  path: r'C:\data\Hospital.db',
  recoveryKind: DatabaseInitRecoveryKind.wrongDatabaseUnknown,
);

const _child = Text('η εφαρμογή');

Widget _screenFor(FatalErrorState? state) => screenForFatalError(
  state,
  child: _child,
  onRetryDatabase: () async {},
);

void main() {
  test('χωρίς σφάλμα, το κέλυφος δείχνει την εφαρμογή', () {
    expect(_screenFor(null), same(_child));
  });

  test('σφάλμα βάσης μετά την εκκίνηση δείχνει την οθόνη σφάλματος ΒΑΣΗΣ', () {
    final screen = _screenFor(const DatabaseFatalError(_databaseFailure));

    expect(
      screen,
      isA<DatabaseErrorScreen>(),
      reason: 'Η γενική οθόνη δεν έχει διέξοδο για χαλασμένη βάση',
    );
    expect(screen, isNot(isA<FatalErrorScreen>()));
  });

  test('η οθόνη σφάλματος βάσης παίρνει το μήνυμα και τη διαδρομή', () {
    final screen =
        _screenFor(const DatabaseFatalError(_databaseFailure))
            as DatabaseErrorScreen;

    expect(screen.result.message, contains('phones'));
    expect(screen.dbPath, r'C:\data\Hospital.db');
  });

  test('σφάλμα που δεν αφορά τη βάση δείχνει τη γενική οθόνη', () {
    final screen = _screenFor(
      GeneralFatalError(
        AppErrorResult.fromException(
          StateError('κάτι εντελώς άλλο'),
          StackTrace.current,
        ),
      ),
    );

    expect(screen, isA<FatalErrorScreen>());
    expect(screen, isNot(isA<DatabaseErrorScreen>()));
  });

  test('η επαναδοκιμή της βάσης φτάνει ακέραιη στην οθόνη', () async {
    var retries = 0;
    final screen =
        screenForFatalError(
              const DatabaseFatalError(_databaseFailure),
              child: _child,
              onRetryDatabase: () async => retries++,
            )
            as DatabaseErrorScreen;

    await screen.onRetry();

    expect(
      retries,
      1,
      reason: 'Χωρίς αυτό, το κουμπί της οθόνης δεν κάνει τίποτα',
    );
  });
}
