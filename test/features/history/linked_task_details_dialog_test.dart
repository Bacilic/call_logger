// Ο διάλογος συνδεδεμένης εκκρεμότητας: πληροφορία πρώτα, ενέργειες μετά.
//
// Το σφάλμα που αντικαθιστά: το «Άνοιγμα» ρωτούσε «θέλετε να την επαναφέρετε
// ως…» πριν δείξει οτιδήποτε — ερώτηση αλλαγής για να δεις πληροφορία.
//
//   flutter test test/features/history/linked_task_details_dialog_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/features/history/widgets/linked_task_details_dialog.dart';
import 'package:call_logger/features/tasks/models/task.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

Task _task({
  required int id,
  String title = 'Παραγγελία μελανιού',
  String status = 'open',
  String? solutionNotes,
  String? createdAt,
  String? updatedAt,
}) {
  return Task(
    id: id,
    title: title,
    description: 'Τελείωσε το μαύρο μελάνι.',
    dueDate: '2026-07-30T12:00:00.000',
    status: status,
    callId: id * 100,
    userText: 'Νικολέτα Παπανδρεάδη',
    phoneText: '2895',
    departmentText: 'Χρηματικό',
    equipmentText: '446',
    solutionNotes: solutionNotes,
    createdAt: createdAt ?? '2026-07-28T18:23:00.000',
    updatedAt: updatedAt,
  );
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  Future<void> seedTask(WidgetTester tester, Task task) async {
    await tester.runAsync(() async {
      final db = await DatabaseHelper.instance.database;
      // Τα foreign keys είναι ενεργά: η εκκρεμότητα θέλει υπαρκτή κλήση.
      await db.insert('calls', {
        'id': task.callId,
        'date': '2026-07-28',
        'time': '18:23',
        'issue': 'Δοκιμή',
        'status': 'completed',
        'is_deleted': 0,
      });
      await db.insert('tasks', {
        'id': task.id,
        'call_id': task.callId,
        'title': task.title,
        'description': task.description,
        'due_date': task.dueDate,
        'status': task.status,
        'solution_notes': task.solutionNotes,
        'created_at': task.createdAt,
        'updated_at': task.updatedAt,
        'user_text': task.userText,
        'phone_text': task.phoneText,
        'department_text': task.departmentText,
        'equipment_text': task.equipmentText,
        'is_deleted': 0,
      });
    });
  }

  Future<void> pumpDialog(WidgetTester tester, Task task) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: callLoggerTestProviderOverrides(),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () =>
                    showLinkedTaskDetailsDialog(context, task: task),
                child: const Text('Άνοιγμα'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Άνοιγμα'));
    await pumpUntilSettled(tester);
  }

  group('Διάλογος συνδεδεμένης εκκρεμότητας', () {
    testWidgets(
      'ολοκληρωμένη: δείχνει τα στοιχεία και τη λύση ΧΩΡΙΣ ερώτηση επαναφοράς',
      (tester) async {
        final task = _task(
          id: 1,
          title: 'για να τι δουλεύει',
          status: 'closed',
          solutionNotes: 'δουλεύει;',
          updatedAt: '2026-07-28T20:11:00.000',
        );
        await seedTask(tester, task);
        await pumpDialog(tester, task);

        // Καμία ερώτηση αλλαγής δεν μεσολαβεί.
        expect(find.text('Επεξεργασία Εκκρεμότητας'), findsNothing);
        expect(find.text('Θέλετε να την επαναφέρετε ως:'), findsNothing);

        // Η πληροφορία είναι εκεί, με τη λύση ανοιχτή.
        expect(find.text('για να τι δουλεύει'), findsOneWidget);
        expect(find.text('ολοκληρωμένη'), findsOneWidget);
        expect(find.text('ΛΥΣΗ'), findsOneWidget);
        expect(find.text('δουλεύει;'), findsOneWidget);
        expect(find.text('Νικολέτα Παπανδρεάδη'), findsOneWidget);
        expect(find.textContaining('Ολοκληρώθηκε:'), findsOneWidget);

        await flushCallLoggerSqfliteLockTimers(tester);
      },
    );

    testWidgets('ολοκληρωμένη: η αναίρεση είναι επιλογή, όχι προαπαιτούμενο', (
      tester,
    ) async {
      final task = _task(
        id: 2,
        status: 'closed',
        solutionNotes: 'ok',
        updatedAt: '2026-07-28T20:11:00.000',
      );
      await seedTask(tester, task);
      await pumpDialog(tester, task);

      expect(
        find.widgetWithText(OutlinedButton, 'Αναίρεση ολοκλήρωσης'),
        findsOneWidget,
      );
      // Ενέργειες που δεν ταιριάζουν σε ολοκληρωμένη δεν εμφανίζονται.
      expect(find.widgetWithText(FilledButton, 'Ολοκλήρωση'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Αναβολή'), findsNothing);

      await flushCallLoggerSqfliteLockTimers(tester);
    });

    testWidgets('ανοιχτή: προσφέρει ολοκλήρωση και αναβολή επιτόπου', (
      tester,
    ) async {
      final task = _task(id: 3);
      await seedTask(tester, task);
      await pumpDialog(tester, task);

      expect(find.text('ανοιχτή'), findsOneWidget);
      expect(find.text('Ολοκλήρωση'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Αναβολή'), findsOneWidget);
      expect(find.text('Αναίρεση ολοκλήρωσης'), findsNothing);
      expect(find.textContaining('Λήγει:'), findsOneWidget);

      await flushCallLoggerSqfliteLockTimers(tester);
    });

    testWidgets('σε αναβολή: το κουμπί λέει «Αλλαγή αναβολής»', (tester) async {
      final task = _task(id: 4, status: 'snoozed');
      await seedTask(tester, task);
      await pumpDialog(tester, task);

      expect(find.text('σε αναβολή'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Αλλαγή αναβολής'),
        findsOneWidget,
      );

      await flushCallLoggerSqfliteLockTimers(tester);
    });

    testWidgets('το «Κλείσιμο» είναι ο τρόπος εξόδου — το φράγμα δεν κλείνει', (
      tester,
    ) async {
      final task = _task(id: 5);
      await seedTask(tester, task);
      await pumpDialog(tester, task);

      await tester.tapAt(const Offset(5, 5));
      await pumpUntilSettled(tester);
      expect(
        find.text('Συνδεδεμένη εκκρεμότητα'),
        findsOneWidget,
        reason: 'Κατά λάθος κλικ δεν κλείνει διάλογο με ενέργειες.',
      );

      await tester.tap(find.widgetWithText(TextButton, 'Κλείσιμο'));
      await pumpUntilSettled(tester);
      expect(find.text('Συνδεδεμένη εκκρεμότητα'), findsNothing);

      await flushCallLoggerSqfliteLockTimers(tester);
    });
  });
}
