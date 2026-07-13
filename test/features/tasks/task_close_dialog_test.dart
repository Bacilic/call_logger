// Widget test: διάλογος ολοκλήρωσης εκκρεμότητας — οριοθετημένο πλάτος και αναδίπλωση κειμένου.
//
//   flutter test test/features/tasks/task_close_dialog_test.dart

import 'dart:convert';

import 'package:call_logger/core/providers/settings_provider.dart';
import 'package:call_logger/core/providers/spell_check_provider.dart';
import 'package:call_logger/core/services/spell_check_service.dart';
import 'package:call_logger/features/tasks/models/task.dart';
import 'package:call_logger/features/tasks/screens/task_close_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import '../../test_setup.dart';

const _kOpenDialogButton = 'OPEN_TASK_CLOSE_DIALOG';
const _kWideScreenWidth = 1200.0;
const _kWideScreenHeight = 800.0;
const _kMaxContentWidth = 420.0;
const _kMinMultilineFieldHeight = 72.0;

/// Πολύ μεγάλο κείμενο χωρίς χειροκίνητες αλλαγές γραμής (όχι `\n`).
String _veryLongSolutionNotes() =>
    List<String>.filled(120, 'σημείωση').join(' ');

Task _taskForTimingTest({
  required DateTime createdAt,
  List<Map<String, String>> snoozeEntries = const [],
}) {
  return Task(
    title: 'Δοκιμή χρόνων',
    dueDate: createdAt.add(const Duration(days: 1)).toIso8601String(),
    status: TaskStatus.open.toDbValue,
    createdAt: createdAt.toIso8601String(),
    snoozeHistoryJson:
        snoozeEntries.isEmpty ? null : jsonEncode(snoozeEntries),
  );
}

Future<void> _pumpTaskCloseDialog(
  WidgetTester tester, {
  required String initialSolutionNotes,
  Task? task,
}) async {
  await tester.binding.setSurfaceSize(
    const Size(_kWideScreenWidth, _kWideScreenHeight),
  );
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        enableSpellCheckProvider.overrideWith((ref) async => false),
        spellCheckServiceProvider.overrideWith((ref) async {
          final svc = LexiconSpellCheckService();
          await svc.init(lexiconVariants: {});
          return svc;
        }),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showTaskCloseDialog(
                  context,
                  initialSolutionNotes: initialSolutionNotes,
                  task: task,
                ),
                child: const Text(_kOpenDialogButton),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text(_kOpenDialogButton));
  await pumpUntilSettled(tester, steps: 20);
  expect(find.text('Ολοκλήρωση εκκρεμότητας'), findsOneWidget);
}

RenderBox _contentSizedBoxRenderBox(WidgetTester tester) {
  final sizedBoxFinder = find.byWidgetPredicate(
    (w) => w is SizedBox && w.width == _kMaxContentWidth,
  );
  expect(sizedBoxFinder, findsOneWidget);
  return tester.renderObject<RenderBox>(sizedBoxFinder);
}

RenderBox _notesFieldRenderBox(WidgetTester tester) {
  return tester.renderObject<RenderBox>(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextFormField),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('showTaskCloseDialog timing info', () {
    testWidgets('εμφανίζει πάντα γραμμή Δημιουργήθηκε', (tester) async {
      final createdAt = DateTime.now().subtract(const Duration(hours: 2));
      final task = _taskForTimingTest(createdAt: createdAt);

      await _pumpTaskCloseDialog(
        tester,
        initialSolutionNotes: '',
        task: task,
      );

      final createdLabel =
          DateFormat('dd/MM/yyyy HH:mm').format(createdAt);
      expect(
        find.textContaining('Δημιουργήθηκε: $createdLabel'),
        findsOneWidget,
      );
      expect(find.textContaining('Τελευταία αναβολή:'), findsNothing);

      await tester.tap(find.text('Ακύρωση'));
      await pumpUntilSettled(tester, steps: 10);
    });

    testWidgets(
      'εμφανίζει γραμμή Τελευταία αναβολή μόνο όταν υπάρχουν αναβολές',
      (tester) async {
        final createdAt = DateTime.now().subtract(const Duration(days: 3));
        final firstSnooze = DateTime.now().subtract(const Duration(days: 2));
        final lastSnooze = DateTime.now().subtract(const Duration(hours: 4));
        final task = _taskForTimingTest(
          createdAt: createdAt,
          snoozeEntries: [
            {
              'snoozedAt': firstSnooze.toIso8601String(),
              'dueAt': firstSnooze.add(const Duration(days: 1)).toIso8601String(),
            },
            {
              'snoozedAt': lastSnooze.toIso8601String(),
              'dueAt': lastSnooze.add(const Duration(hours: 6)).toIso8601String(),
            },
          ],
        );

        await _pumpTaskCloseDialog(
          tester,
          initialSolutionNotes: '',
          task: task,
        );

        final lastSnoozeLabel = DateFormat('dd/MM HH:mm').format(lastSnooze);
        expect(
          find.textContaining('Τελευταία αναβολή: $lastSnoozeLabel'),
          findsOneWidget,
        );
        expect(find.textContaining('(2 αναβολές συνολικά)'), findsOneWidget);

        await tester.tap(find.text('Ακύρωση'));
        await pumpUntilSettled(tester, steps: 10);
      },
    );
  });

  group('showTaskCloseDialog layout', () {
    testWidgets(
      'πολύ μεγάλο κείμενο σημειώσεων — οριοθετημένο πλάτος διαλόγου και πολλές γραμμές',
      (tester) async {
        await _pumpTaskCloseDialog(
          tester,
          initialSolutionNotes: _veryLongSolutionNotes(),
        );

        final fieldBox = _notesFieldRenderBox(tester);
        _contentSizedBoxRenderBox(tester);

        expect(
          fieldBox.size.width,
          lessThan(_kWideScreenWidth * 0.5),
          reason:
              'Το πεδίο σημειώσεων δεν πρέπει να επεκτείνεται στο πλάτος της οθόνης',
        );
        expect(
          fieldBox.size.height,
          greaterThan(_kMinMultilineFieldHeight),
          reason:
              'Το πολυγραμμικό πεδίο πρέπει να εμφανίζει το κείμενο σε πολλές γραμμές',
        );

        await tester.tap(find.text('Ακύρωση'));
        await pumpUntilSettled(tester, steps: 10);
        await tester.pumpWidget(const SizedBox.shrink());
        await pumpUntilSettled(tester, steps: 5);
      },
    );
  });
}
