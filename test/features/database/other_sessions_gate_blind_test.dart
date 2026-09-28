// Widget tests: ο φρουρός «ποιος άλλος έχει τη βάση» όταν ΔΕΝ βλέπει.
//
// Τα ίχνη παρουσίας ζουν στον φάκελο logs δίπλα στη βάση. Όταν εκείνος δεν
// απαντά, η λίστα βγαίνει κενή για λάθος λόγο — και ένας φρουρός που διαβάζει
// «κενή» ως «είσαι μόνος» αφήνει να περάσει ακριβώς η μη αναστρέψιμη ενέργεια
// που υπάρχει για να σταματήσει.
//
//   flutter test test/features/database/other_sessions_gate_blind_test.dart

import 'package:call_logger/features/database/services/active_sessions.dart';
import 'package:call_logger/features/database/widgets/other_sessions_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _kOpen = 'OPEN';

Future<bool?> _runGate(
  WidgetTester tester, {
  required bool canObserve,
  List<ActiveSession> sessions = const [],
}) async {
  bool? outcome;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                outcome = await confirmDespiteOtherSessions(
                  context,
                  actionLabel: 'Μόνιμη αναβάθμιση σχήματος',
                  canObserve: () => canObserve,
                  loadSessions: () async => sessions,
                );
              },
              child: const Text(_kOpen),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text(_kOpen));
  await tester.pumpAndSettle();
  return outcome;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('χωρίς ορατότητα: ρωτά αντί να περάσει σιωπηλά', (tester) async {
    await _runGate(tester, canObserve: false);

    expect(find.text('Δεν φαίνεται ποιος άλλος δουλεύει'), findsOneWidget);
    expect(
      find.textContaining('δεν αναιρείται'),
      findsOneWidget,
      reason: 'ο χρήστης πρέπει να ξέρει ότι αποφασίζει στα τυφλά',
    );
  });

  testWidgets('χωρίς ορατότητα: η ακύρωση σταματά την ενέργεια', (
    tester,
  ) async {
    await _runGate(tester, canObserve: false);
    await tester.tap(find.text('Ακύρωση'));
    await tester.pumpAndSettle();

    expect(find.text('Δεν φαίνεται ποιος άλλος δουλεύει'), findsNothing);
  });

  testWidgets('με ορατότητα και κανέναν άλλο: καμία διακοπή', (tester) async {
    final outcome = await _runGate(tester, canObserve: true);

    expect(outcome, isTrue);
    expect(find.text('Δεν φαίνεται ποιος άλλος δουλεύει'), findsNothing);
    expect(find.text('Η βάση είναι ανοιχτή αλλού'), findsNothing);
  });
}
