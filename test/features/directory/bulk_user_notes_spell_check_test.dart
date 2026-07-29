// Widget test: το πεδίο σημειώσεων της μαζικής επεξεργασίας υπαλλήλων
// χρησιμοποιεί τον ορθογραφικό έλεγχο του Λεξικού (όχι σκέτο TextField —
// ο native έλεγχος είναι απενεργοποιημένος στα Windows).
//
//   flutter test test/features/directory/bulk_user_notes_spell_check_test.dart

import 'package:call_logger/core/providers/settings_provider.dart';
import 'package:call_logger/core/providers/spell_check_provider.dart';
import 'package:call_logger/core/services/spell_check_service.dart';
import 'package:call_logger/core/widgets/lexicon_spell_text_form_field.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/directory/providers/directory_provider.dart';
import 'package:call_logger/features/directory/screens/widgets/bulk_user_edit_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

const _kOpenDialogButton = 'OPEN_BULK_DIALOG';

List<UserModel> _selectedUsers() => [
  UserModel(id: 1, firstName: 'Ιωάννης', lastName: 'Φρυσίρας'),
  UserModel(id: 2, firstName: 'Μαργαρίτα', lastName: 'Ελένη'),
  UserModel(id: 3, firstName: 'Αλέξιος', lastName: 'Καλατζόπουλος'),
];

Future<void> _openBulkDialog(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...callLoggerTestProviderOverrides(),
        enableSpellCheckProvider.overrideWith((ref) async => true),
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
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (ctx) => BulkUserEditDialog(
                    selectedUsers: _selectedUsers(),
                    notifier: ref.read(directoryProvider.notifier),
                  ),
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
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  testWidgets('το πεδίο σημειώσεων έχει ορθογραφικό έλεγχο Λεξικού', (
    tester,
  ) async {
    await _openBulkDialog(tester);
    expect(find.text('Μαζικές ενέργειες — 3 υπάλληλοι'), findsOneWidget);

    await tester.tap(find.text('Σημειώσεις…'));
    await pumpUntilSettled(tester, steps: 20);

    expect(find.text('Σημειώσεις σε 3 υπαλλήλους'), findsOneWidget);
    expect(
      find.byType(LexiconSpellTextFormField),
      findsOneWidget,
      reason:
          'Ο native έλεγχος είναι απενεργοποιημένος στα Windows — το πεδίο '
          'πρέπει να χρησιμοποιεί το πεδίο-συστατικό του Λεξικού',
    );

    await tester.tap(find.text('Ακύρωση'));
    await pumpUntilSettled(tester, steps: 10);
    await flushCallLoggerSqfliteLockTimers(tester);
  });

  testWidgets('το «Συνέχεια» μένει ανενεργό με κενό κείμενο', (tester) async {
    await _openBulkDialog(tester);
    await tester.tap(find.text('Σημειώσεις…'));
    await pumpUntilSettled(tester, steps: 20);

    final continueButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Συνέχεια'),
    );
    expect(
      continueButton.onPressed,
      isNull,
      reason: 'Κενό κείμενο δεν αποθηκεύεται — παραπομπή στον Καθαρισμό',
    );

    await tester.enterText(
      find.byType(LexiconSpellTextFormField),
      'μετακόμιση στο νέο κτίριο',
    );
    await pumpUntilSettled(tester, steps: 15);

    final afterTyping = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Συνέχεια'),
    );
    expect(afterTyping.onPressed, isNotNull);

    await tester.tap(find.text('Ακύρωση'));
    await pumpUntilSettled(tester, steps: 10);
    await flushCallLoggerSqfliteLockTimers(tester);
  });
}
