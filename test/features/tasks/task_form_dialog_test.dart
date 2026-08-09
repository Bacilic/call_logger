// Widget test: επεξεργασία σημειώσεων αναβολών στον διάλογο εκκρεμότητας.
//
//   flutter test test/features/tasks/task_form_dialog_test.dart

import 'dart:convert';

import 'package:call_logger/core/providers/settings_provider.dart';
import 'package:call_logger/core/providers/spell_check_provider.dart';
import 'package:call_logger/core/services/spell_check_service.dart';
import 'package:call_logger/core/widgets/lexicon_spell_text_form_field.dart';
import 'package:call_logger/core/widgets/resizable_text_area.dart';
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
      {'snoozedAt': _snooze2AtIso, 'dueAt': '2026-06-04T08:00:00.000'},
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

/// Δοχείο για το αποτέλεσμα της φόρμας: γεμίζει όταν ο διάλογος κλείσει,
/// ώστε το τεστ να αλληλεπιδράσει πρώτα και να διαβάσει μετά.
class _FormResultHolder {
  TaskFormResult? value;
}

Future<_FormResultHolder> _openTaskFormDialog(
  WidgetTester tester, {
  Task? task,
}) async {
  final holder = _FormResultHolder();

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
                  holder.value = await showTaskFormDialog(context, task: task);
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

  return holder;
}

class _TestTaskSettingsConfigNotifier extends TaskSettingsConfigNotifier {
  @override
  Future<TaskSettingsConfig> build() async =>
      TaskSettingsConfig.defaultConfig();
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

    testWidgets('η σημείωση αναβολής έχει ορθογραφικό έλεγχο', (tester) async {
      await _openTaskFormDialog(tester, task: _taskWithTwoSnoozes());

      final noteField = find.byKey(const ValueKey('snooze_note_0'));
      expect(noteField, findsOneWidget);
      // Το πεδίο μεγαλώνει και σέρνεται, αλλά ο ορθογραφικός έλεγχος μένει.
      expect(tester.widget(noteField), isA<ResizableTextArea>());
      expect(
        find.descendant(
          of: noteField,
          matching: find.byType(LexiconSpellTextFormField),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Ακύρωση'));
      await pumpUntilSettled(tester, steps: 10);
      await flushCallLoggerSqfliteLockTimers(tester);
    });

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
        TaskFormResult? saved;
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
        expect(saved!.task.snoozeEntries, hasLength(2));
        expect(saved!.task.snoozeEntries[0].note, 'σημείωση 1');
        expect(saved!.task.snoozeEntries[1].note, 'ενημερωμένη σημείωση 2');
        expect(
          saved!.closedMode,
          isNull,
          reason: 'Αναβληθείσα, όχι ολοκληρωμένη — δεν τίθεται απόφαση',
        );
        await flushCallLoggerSqfliteLockTimers(tester);
      },
    );
  });

  group('showTaskFormDialog για ολοκληρωμένη εκκρεμότητα', () {
    setUp(() async {
      await seedIsolatedTestDatabase();
    });

    Task closedTask() => Task(
      id: 55,
      title: 'Κλειστή εκκρεμότητα',
      description: 'Περιγραφή',
      dueDate: '2026-08-01T09:00:00.000',
      status: 'closed',
      solutionNotes: 'Αντικαταστάθηκε το τόνερ.',
      createdAt: '2026-07-30T08:00:00.000',
      updatedAt: '2026-08-01T10:00:00.000',
      completedAt: '2026-08-01T10:00:00.000',
    );

    testWidgets(
      'προεπιλογή «Παραμένει ολοκληρωμένη»: κρυφή προθεσμία, κλειδωμένη '
      'προτεραιότητα, αποθήκευση επιστρέφει stayClosed',
      (tester) async {
        final holder = await _openTaskFormDialog(tester, task: closedTask());

        // Η φόρμα δηλώνει τι επεξεργάζεται και δείχνει τη σύνοψη.
        expect(find.text('Ολοκληρωμένη'), findsOneWidget);
        expect(find.text('Ολοκληρώθηκε'), findsOneWidget);
        expect(find.text('Αντικαταστάθηκε το τόνερ.'), findsOneWidget);
        expect(find.text('Με την αποθήκευση:'), findsOneWidget);

        // Προθεσμία κρυφή — δεν έχει νόημα σε κλειστή υπόθεση.
        expect(find.text('Ημερομηνία / ώρα λήξης'), findsNothing);
        expect(find.text('Γρήγορη προθεσμία'), findsNothing);

        // Προτεραιότητα κλειδωμένη.
        final priorityDropdown = tester.widget<DropdownButtonFormField<int>>(
          find.byWidgetPredicate((w) => w is DropdownButtonFormField<int>),
        );
        expect(priorityDropdown.onChanged, isNull);

        await tester.tap(find.widgetWithText(FilledButton, 'Αποθήκευση'));
        await pumpUntilSettled(tester, steps: 20);

        final result = holder.value;
        expect(result, isNotNull);
        expect(result!.closedMode, ClosedTaskSaveMode.stayClosed);
        expect(result.task.status, 'closed');
        await flushCallLoggerSqfliteLockTimers(tester);
      },
    );

    testWidgets(
      '«Ξανανοίγει»: εμφανίζεται η προθεσμία, το κουμπί αλλάζει ετικέτα και '
      'επιστρέφεται reopen',
      (tester) async {
        final holder = await _openTaskFormDialog(tester, task: closedTask());

        await tester.ensureVisible(find.text('Ξανανοίγει'));
        await tester.tap(find.text('Ξανανοίγει'));
        await pumpUntilSettled(tester, steps: 10);

        expect(find.text('Ημερομηνία / ώρα λήξης'), findsOneWidget);
        expect(
          find.widgetWithText(FilledButton, 'Αποθήκευση και άνοιγμα'),
          findsOneWidget,
        );

        await tester.tap(
          find.widgetWithText(FilledButton, 'Αποθήκευση και άνοιγμα'),
        );
        await pumpUntilSettled(tester, steps: 20);

        expect(holder.value!.closedMode, ClosedTaskSaveMode.reopen);
        await flushCallLoggerSqfliteLockTimers(tester);
      },
    );

    testWidgets('«Εκ νέου»: το κουμπί δηλώνει δημιουργία και επιστρέφει '
        'recreate', (tester) async {
      final holder = await _openTaskFormDialog(tester, task: closedTask());

      await tester.ensureVisible(find.text('Εκ νέου'));
      await tester.tap(find.text('Εκ νέου'));
      await pumpUntilSettled(tester, steps: 10);

      await tester.tap(
        find.widgetWithText(FilledButton, 'Δημιουργία νέας εκκρεμότητας'),
      );
      await pumpUntilSettled(tester, steps: 20);

      expect(holder.value!.closedMode, ClosedTaskSaveMode.recreate);
      await flushCallLoggerSqfliteLockTimers(tester);
    });

    testWidgets(
      '«Ξανανοίγει με αναβολή»: λόγος και νέα λήξη μέσα στη φόρμα, χωρίς '
      'δεύτερο παράθυρο',
      (tester) async {
        final holder = await _openTaskFormDialog(tester, task: closedTask());

        // Ως τώρα ο λόγος ζητιόταν σε ξεχωριστό διάλογο μετά την αποθήκευση.
        expect(find.text('Λόγος αναβολής (προαιρετικό)'), findsNothing);

        await tester.ensureVisible(find.text('Ξανανοίγει με αναβολή'));
        await tester.tap(find.text('Ξανανοίγει με αναβολή'));
        await pumpUntilSettled(tester, steps: 10);

        expect(find.text('Λόγος αναβολής (προαιρετικό)'), findsOneWidget);
        expect(find.text('Γρήγορη νέα λήξη'), findsOneWidget);
        expect(find.text('Νέα λήξη'), findsOneWidget);

        await tester.enterText(
          find.byKey(const ValueKey('snooze_reason')),
          'Περιμένω ανταλλακτικό',
        );
        await pumpUntilSettled(tester, steps: 5);

        await tester.tap(
          find.widgetWithText(FilledButton, 'Αποθήκευση και αναβολή'),
        );
        await pumpUntilSettled(tester, steps: 20);

        final result = holder.value;
        expect(result!.closedMode, ClosedTaskSaveMode.snoozeAgain);
        expect(result.snoozeReason, 'Περιμένω ανταλλακτικό');
        await flushCallLoggerSqfliteLockTimers(tester);
      },
    );

    testWidgets('ο λόγος αναβολής δεν ταξιδεύει σε άλλη επιλογή', (
      tester,
    ) async {
      final holder = await _openTaskFormDialog(tester, task: closedTask());

      await tester.ensureVisible(find.text('Ξανανοίγει με αναβολή'));
      await tester.tap(find.text('Ξανανοίγει με αναβολή'));
      await pumpUntilSettled(tester, steps: 10);
      await tester.enterText(
        find.byKey(const ValueKey('snooze_reason')),
        'Γράφτηκε κατά λάθος',
      );
      await pumpUntilSettled(tester, steps: 5);

      await tester.ensureVisible(find.text('Ξανανοίγει'));
      await tester.tap(find.text('Ξανανοίγει'));
      await pumpUntilSettled(tester, steps: 10);

      await tester.tap(
        find.widgetWithText(FilledButton, 'Αποθήκευση και άνοιγμα'),
      );
      await pumpUntilSettled(tester, steps: 20);

      expect(holder.value!.closedMode, ClosedTaskSaveMode.reopen);
      expect(holder.value!.snoozeReason, isNull);
      await flushCallLoggerSqfliteLockTimers(tester);
    });

    testWidgets('ανοιχτή εκκρεμότητα: χωρίς επιλογέα, με ορατή προθεσμία', (
      tester,
    ) async {
      await _openTaskFormDialog(tester, task: _taskWithoutSnoozes());

      expect(find.text('Με την αποθήκευση:'), findsNothing);
      expect(find.text('Ημερομηνία / ώρα λήξης'), findsOneWidget);
      expect(find.text('Ανοιχτή'), findsOneWidget);

      await tester.tap(find.text('Ακύρωση'));
      await pumpUntilSettled(tester, steps: 10);
      await flushCallLoggerSqfliteLockTimers(tester);
    });
  });
}
