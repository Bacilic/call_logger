// Widget test: εκκρεμότητα (pending) — checkbox, υποβολή μέσω notifier, έλεγχος calls/tasks στη βάση.
//
// Ολόκληρο αρχείο:
//   flutter test test/pending_task_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/features/calls/provider/call_entry_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'call_logger_test_material_app.dart';
import 'test_reporter.dart';
import 'test_setup.dart';

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('Ροή εκκρεμότητας (widget)', () {
    // Ενεργοποίηση pending, submitCall μέσω provider, επαλήθευση κλήσης pending και δημιουργίας task.
    //   flutter test test/pending_task_test.dart --plain-name "Ενεργοποίηση εκκρεμότητας, υποβολή κλήσης και εγγραφή task"
    testWidgets(
      'Ενεργοποίηση εκκρεμότητας, υποβολή κλήσης και εγγραφή task',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final reporter = GreekTestReportCollector();
        final sw = Stopwatch()..start();

        reporter.logStep('Φόρτωση εφαρμογής για ροή εκκρεμότητας');
        await tester.pumpWidget(
          ProviderScope(
            overrides: callLoggerTestProviderOverrides(),
            child: const CallLoggerTestMaterialApp(),
          ),
        );
        await tester.pump();
        await pumpUntilSettledLong(tester);

        final phoneField = callLoggerPhoneTextField();
        reporter.logStep('Πληκτρολόγηση τηλεφώνου και lookup');
        await tester.tap(phoneField);
        await pumpUntilSettled(tester);
        await tester.enterText(phoneField, kTestPhoneDigits);
        await pumpUntilSettled(tester);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
        await pumpUntilSettled(tester);

        final notesFinder = find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              (w.decoration?.hintText?.contains('Σημειώσεις') ?? false),
        );
        final pendingNotes = '$kTestHistorySearchMarker εκκρεμότητα ροή';
        reporter.logStep('Συμπλήρωση σημειώσεων (υποχρεωτικό για ενεργό checkbox)');
        await tester.tap(notesFinder);
        await pumpUntilSettled(tester);
        await tester.enterText(notesFinder, pendingNotes);
        await pumpUntilSettled(tester);

        final checkboxFinder = find.byType(Checkbox);
        expect(
          checkboxFinder,
          findsWidgets,
          reason: greekExpectMsg('Checkbox εκκρεμότητας στη μπάρα κατάστασης'),
        );
        reporter.logStep('Ενεργοποίηση checkbox Εκκρεμότητα');
        await tester.tap(checkboxFinder.first);
        await pumpUntilSettled(tester);

        final submitFinder = find.widgetWithText(ElevatedButton, 'Καταγραφή');
        expect(
          tester.widget<ElevatedButton>(submitFinder).onPressed,
          isNotNull,
          reason: greekExpectMsg('Κουμπί υποβολής με συμπληρωμένο τηλέφωνο'),
        );

        sw.reset();
        sw.start();
        reporter.logStep('Υποβολή κλήσης με σημαία εκκρεμότητας');
        final scopeCtx = tester.element(submitFinder);
        final container = ProviderScope.containerOf(scopeCtx);
        expect(
          container.read(callEntryProvider).isPending,
          isTrue,
          reason: greekExpectMsg('Η εκκρεμότητα πρέπει να είναι ενεργή πριν την υποβολή'),
        );
        // Άμεση κλήση submitCall μέσω notifier (ίδιο ref με το provider) + runAsync για I/O SQLite.
        final submitOk = await tester.runAsync(() async {
          return container.read(callEntryProvider.notifier).submitCall();
        });
        expect(
          submitOk,
          isTrue,
          reason: greekExpectMsg('Η υποβολή κλήσης πρέπει να ολοκληρωθεί επιτυχώς'),
        );
        await tester.pump();
        reporter.logTiming('Υποβολή κλήσης με εκκρεμότητα (UI + SQLite)', sw.elapsed);

        // Έλεγχοι βάσης σε runAsync ώστε το sqflite να μην κολλάει στο fake clock του binding.
        final verification = await tester.runAsync(() async {
          final db = await DatabaseHelper.instance.database;
          final calls = await db.query(
            'calls',
            where: 'issue = ? AND status = ?',
            whereArgs: [pendingNotes, 'pending'],
            orderBy: 'id DESC',
            limit: 1,
          );
          if (calls.isEmpty) {
            return (<Map<String, Object?>>[], <Map<String, Object?>>[]);
          }
          final callId = calls.first['id'];
          final tasks = await db.query(
            'tasks',
            where: 'call_id = ? AND COALESCE(is_deleted, 0) = 0',
            whereArgs: [callId],
          );
          return (calls, tasks);
        });
        await tester.pump();
        expect(verification, isNotNull, reason: greekExpectMsg('Έλεγχος βάσης μέσω runAsync'));
        final calls = verification!.$1;
        final tasks = verification.$2;
        expect(
          calls,
          isNotEmpty,
          reason: greekExpectMsg('Η κλήση πρέπει να αποθηκευτεί ως εκκρεμής (pending)'),
        );
        expect(
          tasks,
          isNotEmpty,
          reason: greekExpectMsg('Πρέπει να δημιουργηθεί εγγραφή εκκρεμότητας (tasks)'),
        );

        reporter.recordPass('Εκκρεμότητα με απομονωμένη βάση');
      },
      semanticsEnabled: false,
    );
  });
}
