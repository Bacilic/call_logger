// Πριν κλείσει εκκρεμότητα που ανήκει σε άλλον, η εφαρμογή ρωτά.
//
// Δεν είναι κλειδαριά: η ομάδα δουλεύει με βάρδιες και όποιος λύνει ένα θέμα
// πρέπει να μπορεί να το κλείσει. Είναι η στιγμή που το λέει δυνατά — και δεν
// ενοχλεί όταν δεν υπάρχει τίποτα να αναγγελθεί.
//
// Η ερώτηση προηγείται του πεδίου λύσης: ένα «όχι» μετά τη συγγραφή της λύσης
// θα πετούσε κείμενο που μόλις γράφτηκε.
//
//   flutter test test/features/tasks/foreign_task_close_confirm_test.dart

import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/providers/settings_provider.dart';
import 'package:call_logger/core/providers/spell_check_provider.dart';
import 'package:call_logger/core/services/current_operator.dart';
import 'package:call_logger/core/services/spell_check_service.dart';
import 'package:call_logger/features/operators/providers/operator_directory_providers.dart';
import 'package:call_logger/features/tasks/models/task.dart';
import 'package:call_logger/features/tasks/screens/tasks_screen_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _kCompleteButton = 'COMPLETE_TASK';
const _kConfirmTitle = 'Η εκκρεμότητα ανήκει σε άλλον';
const _kSolutionField = 'Λύση / Σημειώσεις Κλεισίματος';

Operator _person(int id, String name) =>
    Operator(id: id, displayName: name, createdAt: DateTime(2026, 1, 1));

Task _task({int? assignedTo}) => Task(
  id: 1,
  title: 'Δεν τυπώνει ο εκτυπωτής του ΤΕΠ',
  dueDate: '2026-09-01T10:00:00.000',
  status: 'open',
  createdByOperatorId: 11,
  assignedOperatorId: assignedTo,
);

Future<void> _tapComplete(WidgetTester tester, {required Task task}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        operatorNamesProvider.overrideWith(
          (ref) async => {11: 'Βασίλης', 22: 'Βλάσης'},
        ),
        enableSpellCheckProvider.overrideWith((ref) async => false),
        spellCheckServiceProvider.overrideWith((ref) async {
          final svc = LexiconSpellCheckService();
          await svc.init(lexiconVariants: {});
          return svc;
        }),
      ],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => completeTask(context, ref, task),
                child: const Text(_kCompleteButton),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text(_kCompleteButton));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => CurrentOperator.activate(_person(11, 'Βασίλης')));
  tearDown(CurrentOperator.reset);

  group('Ερώτηση πριν από κλείσιμο ξένης εκκρεμότητας', () {
    testWidgets('ανατεθειμένη σε άλλον: ρωτά, με τα δύο ονόματα', (
      tester,
    ) async {
      await _tapComplete(tester, task: _task(assignedTo: 22));

      expect(find.text(_kConfirmTitle), findsOneWidget);
      expect(find.text('Ανατεθειμένη σε: Βλάσης'), findsOneWidget);
      expect(
        find.text('Θέλετε να κλείσετε την εκκρεμότητα ως Βασίλης;'),
        findsOneWidget,
        reason: 'Η ερώτηση ονομάζει και ποιος θα σφραγίσει το κλείσιμο.',
      );
      expect(
        find.text(_kSolutionField),
        findsNothing,
        reason: 'Η ερώτηση προηγείται — το πεδίο λύσης δεν έχει ανοίξει ακόμη.',
      );
    });

    testWidgets('ανατεθειμένη σε εμένα: καμία ερώτηση', (tester) async {
      await _tapComplete(tester, task: _task(assignedTo: 11));

      expect(find.text(_kConfirmTitle), findsNothing);
      expect(find.text(_kSolutionField), findsOneWidget);
    });

    testWidgets('χωρίς ανάθεση: καμία ερώτηση', (tester) async {
      await _tapComplete(tester, task: _task());

      expect(
        find.text(_kConfirmTitle),
        findsNothing,
        reason: 'Η ανανάθετη δεν ανήκει σε κανέναν — δεν υπάρχει τι να πει.',
      );
      expect(find.text(_kSolutionField), findsOneWidget);
    });

    testWidgets('«Ακύρωση»: το πεδίο λύσης δεν ανοίγει καν', (tester) async {
      await _tapComplete(tester, task: _task(assignedTo: 22));

      await tester.tap(find.text('Ακύρωση'));
      await tester.pumpAndSettle();

      expect(find.text(_kConfirmTitle), findsNothing);
      expect(find.text(_kSolutionField), findsNothing);
    });

    testWidgets('«Κλείσιμο εκκρεμότητας»: προχωρά στη λύση', (tester) async {
      await _tapComplete(tester, task: _task(assignedTo: 22));

      await tester.tap(
        find.widgetWithText(FilledButton, 'Κλείσιμο εκκρεμότητας'),
      );
      await tester.pumpAndSettle();

      expect(find.text(_kConfirmTitle), findsNothing);
      expect(find.text(_kSolutionField), findsOneWidget);
    });

    testWidgets('χωρίς αναγνωρισμένο χειριστή: ρωτά, χωρίς το «ως»', (
      tester,
    ) async {
      CurrentOperator.reset();

      await _tapComplete(tester, task: _task(assignedTo: 22));

      expect(
        find.text(_kConfirmTitle),
        findsOneWidget,
        reason:
            'Δεν μπορούμε να ισχυριστούμε ότι είμαστε ο ανατεθειμένος όταν '
            'δεν ξέρουμε ποιοι είμαστε.',
      );
      expect(
        find.text('Θέλετε να κλείσετε την εκκρεμότητα;'),
        findsOneWidget,
        reason:
            'Η παύλα του «άγνωστου» δεν είναι όνομα — η ερώτηση παραλείπει το '
            '«ως» αντί να τη γράψει σαν να ήταν.',
      );
    });
  });
}
