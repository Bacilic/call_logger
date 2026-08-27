// Η ΑΙΤΙΑ μιας αποτυχημένης αλλαγής κατάστασης Lansweeper φτάνει στον χρήστη.
//
// Το συμβόλαιο: «Κάθε αποτυχία αλλαγής κατάστασης Lansweeper φτάνει στον
// χρήστη με την αιτία της — ποτέ σιωπηλά, ποτέ ανώνυμα.» Πριν, η αιτία
// σταματούσε στον κοινό εκτελεστή: η Αναφορά έλεγε «η εγγραφή δεν
// ολοκληρώθηκε» και το Ιστορικό δεν έλεγε τίποτα απολύτως.
//
//   flutter test test/features/history/lansweeper_write_failure_reaches_user_test.dart

import 'package:call_logger/features/history/services/lansweeper_state_actions.dart';
import 'package:call_logger/features/history/services/lansweeper_write_failure.dart';
import 'package:call_logger/features/history/widgets/lansweeper/lansweeper_registration_flow.dart';
import 'package:call_logger/features/history/widgets/lansweeper_registration_conflict_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _failure = LansweeperWriteFailure(
  message: 'Η βάση δεδομένων είναι προσωρινά απασχολημένη.',
  report: 'Lansweeper write failed\ncallId: 344\nerror: database is locked',
);

/// Τρέχει τον κοινό εκτελεστή μέσα σε πραγματικό δέντρο — χρειάζεται context
/// για τον διάλογο διένεξης, ακόμη κι όταν δεν εμφανίζεται.
Future<LansweeperChangeResult> _run(
  WidgetTester tester,
  Future<bool> Function({required bool force}) write,
) async {
  late LansweeperChangeResult result;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await applyLansweeperChangeWithConflictPrompt(
                context,
                write: write,
              );
            },
            child: const Text('go'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  group('Ο κοινός εκτελεστής μεταφέρει την αιτία', () {
    testWidgets('αποτυχία εγγραφής: το αποτέλεσμα κουβαλά την αιτία', (
      tester,
    ) async {
      final result = await _run(tester, ({required force}) async {
        throw _failure;
      });

      expect(result.outcome, LansweeperChangeOutcome.failed);
      expect(result.isApplied, isFalse);
      expect(result.failure, isNotNull);
      expect(result.failure!.message, contains('απασχολημένη'));
      expect(result.failure!.report, contains('database is locked'));
    });

    testWidgets('επιτυχία: κανένα σφάλμα να μεταφερθεί', (tester) async {
      final result = await _run(tester, ({required force}) async => true);

      expect(result.isApplied, isTrue);
      expect(result.failure, isNull);
    });

    testWidgets('«έτρεχε ήδη άλλη αποστολή»: αποτυχία ΧΩΡΙΣ αιτία', (
      tester,
    ) async {
      // Δεν είναι σφάλμα εγγραφής — δεν υπάρχει αιτία να δείξουμε, και δεν
      // πρέπει να εφευρεθεί.
      final result = await _run(tester, ({required force}) async => false);

      expect(result.outcome, LansweeperChangeOutcome.failed);
      expect(result.failure, isNull);
    });
  });

  group('Το μήνυμα της Αναφοράς λέει την αιτία', () {
    test('με γνωστή αιτία, αυτή εμφανίζεται αντί του «δεν ολοκληρώθηκε»', () {
      final message = registrationOutcomeMessage(
        registered: 0,
        skipped: 0,
        failed: 1,
        ticketId: '17132',
        failureReason: 'Η βάση δεδομένων είναι προσωρινά απασχολημένη.',
      );

      expect(message, contains('απασχολημένη'));
      expect(message, isNot(contains('δεν ολοκληρώθηκε')));
    });

    test('χωρίς γνωστή αιτία, μένει το παλιό μήνυμα', () {
      expect(
        registrationOutcomeMessage(
          registered: 0,
          skipped: 0,
          failed: 2,
          ticketId: '',
        ),
        '2 κλήσεις δεν σημάνθηκαν — η εγγραφή δεν ολοκληρώθηκε.',
      );
    });

    test('επιτυχίες και αποτυχία μαζί: λέγονται και τα δύο', () {
      final message = registrationOutcomeMessage(
        registered: 2,
        skipped: 0,
        failed: 1,
        ticketId: '17132',
        failureReason: 'Δεν υπάρχει πρόσβαση σε απαραίτητο αρχείο.',
      );

      expect(message, contains('2 κλήσεις επισημάνθηκαν'));
      expect(message, contains('Δεν υπάρχει πρόσβαση'));
    });
  });

  group('Το Ιστορικό δεν σιωπά ποτέ σε αποτυχία', () {
    test('επιτυχία: το μήνυμα επιτυχίας, χωρίς αναφορά σφάλματος', () {
      final message = LansweeperStateActions.announce(
        const LansweeperChangeResult(LansweeperChangeOutcome.applied),
        'Η κλήση εξαιρέθηκε από το Lansweeper.',
      );

      expect(message, isNotNull);
      expect(message!.text, 'Η κλήση εξαιρέθηκε από το Lansweeper.');
      expect(message.isFailure, isFalse);
    });

    test('ακύρωση του χρήστη: σιωπή — τίποτα δεν άλλαξε', () {
      expect(
        LansweeperStateActions.announce(
          const LansweeperChangeResult(LansweeperChangeOutcome.skippedByUser),
          'Η κλήση εξαιρέθηκε από το Lansweeper.',
        ),
        isNull,
      );
    });

    test('αποτυχία: ΜΗΝΥΜΑ με την αιτία, όχι σιωπή', () {
      final message = LansweeperStateActions.announce(
        const LansweeperChangeResult(
          LansweeperChangeOutcome.failed,
          failure: _failure,
        ),
        'Η κλήση εξαιρέθηκε από το Lansweeper.',
      );

      expect(message, isNotNull, reason: 'Η αποτυχία περνούσε αθόρυβα.');
      expect(message!.isFailure, isTrue);
      expect(message.text, contains('απασχολημένη'));
      expect(message.text, isNot(contains('εξαιρέθηκε')));
      expect(message.failureReport, contains('database is locked'));
    });

    test('αποτυχία χωρίς αιτία: λέει τουλάχιστον ότι δεν έγινε', () {
      final message = LansweeperStateActions.announce(
        const LansweeperChangeResult(LansweeperChangeOutcome.failed),
        'Η κλήση εξαιρέθηκε από το Lansweeper.',
      );

      expect(message, isNotNull);
      expect(message!.isFailure, isTrue);
      expect(message.text, contains('δεν έγινε'));
    });
  });
}
