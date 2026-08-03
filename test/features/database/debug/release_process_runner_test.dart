// Εκτελεστής εξωτερικής εντολής για τη Δημοσίευση.
//
// Τρέχει ΠΡΑΓΜΑΤΙΚΗ διεργασία των Windows (το έργο είναι desktop Windows):
// μόνο έτσι αποδεικνύεται ότι δεν χάνονται γραμμές εξόδου — ακριβώς αυτό που
// έκρυβε η παλιά υλοποίηση μέσα στο widget.
//
//   flutter test test/features/database/debug/release_process_runner_test.dart

import 'package:call_logger/features/database/debug/release_process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../test_reporter.dart';

void main() {
  test('επιστρέφει τον κωδικό εξόδου της εντολής', () async {
    expect(await runReleaseProcess('cmd', ['/c', 'exit 0']), 0);
    expect(
      await runReleaseProcess('cmd', ['/c', 'exit 3']),
      3,
      reason: greekExpectMsg(
        'Χωρίς σωστό κωδικό εξόδου η δημοσίευση θα συνέχιζε πάνω σε αποτυχημένο build',
      ),
    );
  });

  test('όλες οι γραμμές εξόδου φτάνουν — και η τελευταία', () async {
    final lines = <String>[];
    final code = await runReleaseProcess(
      'cmd',
      ['/c', 'echo alpha& echo beta& echo omega'],
      onOutput: lines.add,
    );

    expect(code, 0);
    expect(
      lines.map((l) => l.trim()).toList(),
      ['alpha', 'beta', 'omega'],
      reason: greekExpectMsg(
        'Η τελευταία γραμμή είναι συνήθως αυτή που εξηγεί την αποτυχία — δεν '
        'επιτρέπεται να χάνεται επειδή η διεργασία τερμάτισε πρώτη',
      ),
    );
  });

  test('η έξοδος σφάλματος προωθείται μαζί με την κανονική', () async {
    final lines = <String>[];
    await runReleaseProcess(
      'cmd',
      ['/c', 'echo problem 1>&2'],
      onOutput: lines.add,
    );

    expect(lines.map((l) => l.trim()), contains('problem'));
  });

  test('κενές γραμμές δεν γεμίζουν το αρχείο καταγραφής', () async {
    final lines = <String>[];
    await runReleaseProcess(
      'cmd',
      ['/c', 'echo one& echo.& echo two'],
      onOutput: lines.add,
    );

    expect(lines.map((l) => l.trim()).toList(), ['one', 'two']);
  });
}
