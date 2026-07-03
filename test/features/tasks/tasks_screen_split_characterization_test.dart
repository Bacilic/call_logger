// Τεστ χαρακτηρισμού πριν τη διάσπαση του tasks_screen.dart.
//
//   flutter test test/features/tasks/tasks_screen_split_characterization_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/features/tasks/models/task.dart';
import 'package:call_logger/features/tasks/providers/tasks_provider.dart';
import 'package:call_logger/features/tasks/screens/task_card.dart';
import 'package:call_logger/features/tasks/screens/tasks_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

const _kCharSplitTaskTitle = 'CharSplitTaskMarker999';

Future<int> _seedOpenTask({required String title}) async {
  final db = await DatabaseHelper.instance.database;
  final now = DateTime.now();
  final due = now.add(const Duration(hours: 4));
  final iso = now.toIso8601String();
  return db.insert('tasks', {
    'title': title,
    'description': 'characterization split test',
    'due_date': due.toIso8601String(),
    'status': 'open',
    'origin': Task.originManualFab,
    'created_at': iso,
    'updated_at': iso,
    'is_deleted': 0,
  });
}

Future<Map<String, Object?>?> _readTaskRow(int id) async {
  final db = await DatabaseHelper.instance.database;
  final rows = await db.query('tasks', where: 'id = ?', whereArgs: [id], limit: 1);
  return rows.isEmpty ? null : rows.first;
}

Future<void> _pumpTasksScreen(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: callLoggerTestProviderOverrides(),
        child: const MaterialApp(home: TasksScreen()),
      ),
    );
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    await container.read(tasksProvider.future);
    await container.read(totalTasksCountProvider.future);
    await pumpUntilSettledLong(tester);
  });
}

Finder _completeButtonForTask(String title) {
  return find.descendant(
    of: find.ancestor(
      of: find.text(title),
      matching: find.byType(TaskCard),
    ),
    matching: find.byTooltip('Ολοκλήρωση'),
  );
}

Finder _actionsMenuForTask(String title) {
  return find.descendant(
    of: find.ancestor(
      of: find.text(title),
      matching: find.byType(TaskCard),
    ),
    matching: find.byTooltip('Ενέργειες'),
  );
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('TasksScreen split characterization', () {
    setUp(() async {
      await seedIsolatedTestDatabase();
    });

    testWidgets('αποδίδεται και εμφανίζει εκκρεμότητα από τη βάση', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.runAsync(() => _seedOpenTask(title: _kCharSplitTaskTitle));
      await _pumpTasksScreen(tester);

      expect(find.byType(TasksScreen), findsOneWidget);
      expect(find.text('Εκκρεμότητες'), findsOneWidget);
      expect(find.text(_kCharSplitTaskTitle), findsOneWidget);
      await flushCallLoggerSqfliteLockTimers(tester);
    });

    testWidgets('ολοκλήρωση μαρκάρει την εργασία ως closed στη βάση', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      late int taskId;
      await tester.runAsync(() async {
        taskId = await _seedOpenTask(title: _kCharSplitTaskTitle);
      });
      await _pumpTasksScreen(tester);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );
      await tester.runAsync(() async {
        await tester.tap(_completeButtonForTask(_kCharSplitTaskTitle));
        await pumpUntilSettled(tester);

        expect(find.text('Ολοκλήρωση εκκρεμότητας'), findsOneWidget);
        const solution = 'Λύση δοκιμής χαρακτηρισμού';
        final solutionField = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        );
        await tester.tap(solutionField);
        await tester.enterText(solutionField, solution);
        await pumpUntilSettled(tester);
        await tester.tap(
          find.widgetWithText(FilledButton, 'Κλείσιμο εκκρεμότητας'),
        );
        // Μέσα σε runAsync οι πραγματικές ασύγχρονες κλήσεις (βάση) τρέχουν
        // κανονικά — δίνουμε χρόνο στην αλυσίδα του _onComplete να ολοκληρωθεί.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await pumpUntilSettled(tester, steps: 60);
        expect(find.byType(AlertDialog), findsNothing);
        await container.read(tasksProvider.future);
      });

      // Το snackbar εμφανίζεται ΜΟΝΟ αν η αλυσίδα του _onComplete έφτασε ως το τέλος.
      expect(find.text('Εκκρεμότητα ολοκληρώθηκε.'), findsOneWidget);

      final row = await tester.runAsync(() => _readTaskRow(taskId));
      expect(row?['status'], 'closed');
      await flushCallLoggerSqfliteLockTimers(tester);
    });

    testWidgets('αναβολή ανοίγει διάλογο με τις γρήγορες επιλογές', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.runAsync(() => _seedOpenTask(title: _kCharSplitTaskTitle));
      await _pumpTasksScreen(tester);

      await tester.tap(_actionsMenuForTask(_kCharSplitTaskTitle));
      await pumpUntilSettled(tester);
      await tester.tap(find.text('Αναβολή'));
      await pumpUntilSettled(tester);

      expect(find.text('Αναβολή'), findsWidgets);
      expect(find.text('+1 ώρα'), findsOneWidget);
      expect(find.text('Μέσα στο ωράριο'), findsOneWidget);
      expect(find.text('Επόμενη εργάσιμη'), findsOneWidget);
      expect(find.text('Άλλη ημερομηνία…'), findsOneWidget);
      await flushCallLoggerSqfliteLockTimers(tester);
    });

    testWidgets(
      'διαγραφή εμφανίζει snackbar αντίστροφης μέτρησης και η αναίρεση επαναφέρει',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        late int taskId;
        await tester.runAsync(() async {
          taskId = await _seedOpenTask(title: _kCharSplitTaskTitle);
        });
        await _pumpTasksScreen(tester);

        await tester.tap(_actionsMenuForTask(_kCharSplitTaskTitle));
        await pumpUntilSettled(tester);
        await tester.tap(find.text('Διαγραφή'));
        await pumpUntilSettled(tester);

        expect(find.text('Διαγραφή εκκρεμότητας'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Ναι'));
        await pumpUntilSettled(tester);

        expect(find.textContaining('θα διαγραφεί σε:'), findsOneWidget);
        expect(find.text('Αναίρεση'), findsOneWidget);

        await tester.tap(find.text('Αναίρεση'));
        await pumpUntilSettled(tester);

        final row = await tester.runAsync(() => _readTaskRow(taskId));
        expect(row?['is_deleted'], 0);
        expect(find.text(_kCharSplitTaskTitle), findsOneWidget);
        await flushCallLoggerSqfliteLockTimers(tester);
      },
    );
  });
}
