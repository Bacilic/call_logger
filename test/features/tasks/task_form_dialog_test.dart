// Widget test: επεξεργασία σημειώσεων αναβολών στον διάλογο εκκρεμότητας.
//
//   flutter test test/features/tasks/task_form_dialog_test.dart

import 'dart:convert';

import 'package:call_logger/core/providers/settings_provider.dart';
import 'package:call_logger/core/providers/spell_check_provider.dart';
import 'package:call_logger/core/services/spell_check_service.dart';
import 'package:call_logger/core/widgets/lexicon_spell_text_form_field.dart';
import 'package:call_logger/features/tasks/models/task.dart';
import 'package:call_logger/features/tasks/models/task_settings_config.dart';
import 'package:call_logger/features/tasks/providers/task_settings_config_provider.dart';
import 'package:call_logger/features/tasks/screens/task_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import '../../test_setup.dart';

const _kOpenDialogButton = 'OPEN_TASK_FORM_DIALOG';
const _kDialogWidth = 1200.0;
const _kDialogHeight = 900.0;

const _snooze1AtIso = '2026-06-01T09:15:00.000';
const _snooze2AtIso = '2026-06-03T14:30:00.000';

final _snooze1At = DateTime.parse(_snooze1AtIso);
final _snooze2At = DateTime.parse(_snooze2AtIso);

Task _taskWithTwoSnoozes() {
  return Task(
    id: 42,
    title: 'Εκκρεμότητα επεξεργασίας',
    dueDate: '2026-06-05T17:00:00.000',
    status: 'snoozed',
    snoozeHistoryJson: jsonEncode([
      {
        'snoozedAt': _snooze1AtIso,
        'dueAt': '2026-06-02T12:00:00.000',
        'note': 'σημείωση 1',
      },
      {
        'snoozedAt': _snooze2AtIso,
        'dueAt': '2026-06-04T08:00:00.000',
      },
    ]),
  );
}

Task _taskWithoutSnoozes() {
  return Task(
    id: 7,
    title: 'Απλή εκκρεμότητα',
    dueDate: '2026-06-05T17:00:00.000',
    status: 'open',
  );
}

Future<Task?> _openTaskFormDialog(
  WidgetTester tester, {
  Task? task,
}) async {
  Task? result;

  await tester.binding.setSurfaceSize(
    const Size(_kDialogWidth, _kDialogHeight),
  );
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...callLoggerTestProviderOverrides(),
        enableSpellCheckProvider.overrideWith((ref) async => false),
        spellCheckServiceProvider.overrideWith((ref) async {
          final svc = LexiconSpellCheckService();
          await svc.init(lexiconVariants: {});
          return svc;
        }),
        taskSettingsConfigProvider.overrideWith(() {
          return _TestTaskSettingsConfigNotifier();
        }),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  result = await showTaskFormDialog(context, task: task);
                },
                child: const Text(_kOpenDialogButton),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text(_kOpenDialogButton));
  await pumpUntilSettled(tester, steps: 30);
  expect(find.text('Επεξεργασία εκκρεμότητας'), findsOneWidget);

  return result;
}

class _TestTaskSettingsConfigNotifier extends TaskSettingsConfigNotifier {
  @override
  Future<TaskSettingsConfig> build() async => TaskSettingsConfig.defaultConfig();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  registerCallLoggerIsolatedDatabaseHooks();

  group('showTaskFormDialog snooze notes section', () {
    setUp(() async {
      await seedIsolatedTestDatabase();
    });

    testWidgets(
      'με δύο αναβολές εμφανίζονται δύο πεδία και σωστές ετικέτες γραμμών',
      (tester) async {
        await _openTaskFormDialog(tester, task: _taskWithTwoSnoozes());

        expect(find.text('Αναβολές'), findsOneWidget);
        expect(
          find.textContaining(
            'Αναβολή 1 — ${DateFormat('dd/MM HH:mm').format(_snooze1At)}',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'Αναβολή 2 — ${DateFormat('dd/MM HH:mm').format(_snooze2At)}',
          ),
          findsOneWidget,
        );

        final noteFields = find.byKey(const ValueKey('snooze_note_0'));
        expect(noteFields, findsOneWidget);
        expect(find.byKey(const ValueKey('snooze_note_1')), findsOneWidget);

        await tester.tap(find.text('Ακύρωση'));
        await pumpUntilSettled(tester, steps: 10);
        await flushCallLoggerSqfliteLockTimers(tester);
      },
    );

    testWidgets(
      'σημείωση αναβολής χρησιμοποιεί LexiconSpellTextFormField',
      (tester) async {
        await _openTaskFormDialog(tester, task: _taskWithTwoSnoozes());

        final noteField = find.byKey(const ValueKey('snooze_note_0'));
        expect(noteField, findsOneWidget);
        expect(
          tester.widget(noteField),
          isA<LexiconSpellTextFormField>(),
        );

        await tester.tap(find.text('Ακύρωση'));
        await pumpUntilSettled(tester, steps: 10);
        await flushCallLoggerSqfliteLockTimers(tester);
      },
    );

    testWidgets('χωρίς αναβολές δεν εμφανίζεται η ενότητα Αναβολές', (
      tester,
    ) async {
      await _openTaskFormDialog(tester, task: _taskWithoutSnoozes());

      expect(find.text('Αναβολές'), findsNothing);
      expect(find.textContaining('Αναβολή 1 —'), findsNothing);

      await tester.tap(find.text('Ακύρωση'));
      await pumpUntilSettled(tester, steps: 10);
      await flushCallLoggerSqfliteLockTimers(tester);
    });

    testWidgets(
      'αλλαγή σημείωσης και αποθήκευση επιστρέφει Task με ενημερωμένη σημείωση',
      (tester) async {
        Task? saved;
        final task = _taskWithTwoSnoozes();

        await tester.binding.setSurfaceSize(
          const Size(_kDialogWidth, _kDialogHeight),
        );
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...callLoggerTestProviderOverrides(),
              enableSpellCheckProvider.overrideWith((ref) async => false),
              spellCheckServiceProvider.overrideWith((ref) async {
                final svc = LexiconSpellCheckService();
                await svc.init(lexiconVariants: {});
                return svc;
              }),
              taskSettingsConfigProvider.overrideWith(() {
                return _TestTaskSettingsConfigNotifier();
              }),
            ],
            child: MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: FilledButton(
                      onPressed: () async {
                        saved = await showTaskFormDialog(context, task: task);
                      },
                      child: const Text(_kOpenDialogButton),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text(_kOpenDialogButton));
        await pumpUntilSettled(tester, steps: 30);

        final noteField2 = find.byKey(const ValueKey('snooze_note_1'));
        expect(noteField2, findsOneWidget);

        await tester.enterText(noteField2, 'ενημερωμένη σημείωση 2');
        await pumpUntilSettled(tester, steps: 5);

        await tester.tap(find.widgetWithText(FilledButton, 'Αποθήκευση'));
        await pumpUntilSettled(tester, steps: 20);

        expect(saved, isNotNull);
        expect(saved!.snoozeEntries, hasLength(2));
        expect(saved!.snoozeEntries[0].note, 'σημείωση 1');
        expect(saved!.snoozeEntries[1].note, 'ενημερωμένη σημείωση 2');
        await flushCallLoggerSqfliteLockTimers(tester);
      },
    );
  });
}
