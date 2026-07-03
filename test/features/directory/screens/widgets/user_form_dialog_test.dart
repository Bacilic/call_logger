// Widget test: φόρμα χρήστη — δημιουργία, επεξεργασία, προστασία μη αποθηκευμένων.
//
// Ολόκληρο αρχείο:
//   flutter test test/features/directory/screens/widgets/user_form_dialog_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/directory/providers/directory_provider.dart';
import 'package:call_logger/features/directory/screens/widgets/user_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../test_reporter.dart';
import '../../../../test_setup.dart';

const _kOpenUserFormButton = 'OPEN_USER_FORM';
const _kNewUserTitle = 'Νέος Υπάλληλος';
const _kEditUserTitle = 'Επεξεργασία Υπαλλήλου';
const _kUnsavedChangesPrompt = 'Θέλεται να γίνει:';
const _kCharSplitUserFirstName = 'CharSplitUserFn';
const _kCharSplitUserLastName = 'CharSplitUserLn';

Finder _fieldByLabel(String label) {
  return find.descendant(
    of: find.byWidgetPredicate(
      (w) => w is InputDecorator && w.decoration.labelText == label,
    ),
    matching: find.byType(EditableText),
  );
}

Finder _lastNameField() => _fieldByLabel('Επώνυμο');

Finder _firstNameField() => _fieldByLabel('Όνομα');

Finder _notesField() => _fieldByLabel('Σημειώσεις');

Future<void> _openUserFormInDialog(
  WidgetTester tester,
  ProviderContainer container, {
  UserModel? initialUser,
  required DirectoryNotifier notifier,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  barrierDismissible: true,
                  builder: (ctx) => UserFormDialog(
                    initialUser: initialUser,
                    notifier: notifier,
                  ),
                ),
                child: const Text(_kOpenUserFormButton),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text(_kOpenUserFormButton));
  await pumpUntilSettledLong(tester);
}

Future<void> _pumpUntilUserSaveCompletes(WidgetTester tester) async {
  const maxAttempts = 40;
  for (var i = 0; i < maxAttempts; i++) {
    final formOpen = find.text(_kNewUserTitle).evaluate().isNotEmpty ||
        find.text(_kEditUserTitle).evaluate().isNotEmpty;
    if (!formOpen) return;
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump(const Duration(milliseconds: 50));
  }
  fail(
    greekExpectMsg('Η φόρμα χρήστη δεν έκλεισε εγκαίρως μετά την αποθήκευση'),
  );
}

Future<bool> _userExistsByName(String firstName, String lastName) async {
  final db = await DatabaseHelper.instance.database;
  final rows = await db.query(
    'users',
    where:
        'first_name = ? AND last_name = ? AND COALESCE(is_deleted, 0) = 0',
    whereArgs: [firstName, lastName],
    limit: 1,
  );
  return rows.isNotEmpty;
}

UserModel _findSeededTestUser(DirectoryNotifier notifier) {
  return notifier.allUsersForUi.firstWhere(
    (u) =>
        u.firstName == kTestUserFirstName && u.lastName == kTestUserLastName,
  );
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('Φόρμα χρήστη — χαρακτηρισμός (widget)', () {
    testWidgets(
      'δημιουργία: διάλογος αποδίδεται και η αποθήκευση μπλοκάρεται χωρίς υποχρεωτικά ονόματα',
      (tester) async {
        final container = ProviderContainer(
          overrides: callLoggerTestProviderOverrides(),
        );
        addTearDown(container.dispose);

        late DirectoryNotifier notifier;
        await tester.runAsync(() async {
          await container.read(lookupServiceProvider.future);
          notifier = container.read(directoryProvider.notifier);
          await notifier.loadUsers();
          await _openUserFormInDialog(tester, container, notifier: notifier);
        });

        expect(find.text(_kNewUserTitle), findsOneWidget);

        final addButton = find.widgetWithText(FilledButton, 'Προσθήκη');
        expect(addButton, findsOneWidget);
        expect(
          tester.widget<FilledButton>(addButton).onPressed,
          isNull,
          reason: greekExpectMsg(
            'Η προσθήκη απενεργοποιείται όταν η φόρμα δεν έχει αλλαγές',
          ),
        );

        await tester.enterText(_fieldByLabel('Τηλέφωνο'), '9999');
        await pumpUntilSettled(tester);

        expect(
          tester.widget<FilledButton>(addButton).onPressed,
          isNotNull,
          reason: greekExpectMsg(
            'Με αλλαγή στο τηλέφωνο η προσθήκη ενεργοποιείται για έλεγχο επικύρωσης',
          ),
        );

        await tester.tap(addButton);
        await pumpUntilSettled(tester);

        expect(find.text(_kNewUserTitle), findsOneWidget);
        expect(find.text('Υποχρεωτικό'), findsWidgets);
      },
    );

    testWidgets(
      'δημιουργία: επιτυχής αποθήκευση νέου χρήστη στη βάση',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final container = ProviderContainer(
          overrides: callLoggerTestProviderOverrides(),
        );
        addTearDown(container.dispose);

        late DirectoryNotifier notifier;
        await tester.runAsync(() async {
          await container.read(lookupServiceProvider.future);
          notifier = container.read(directoryProvider.notifier);
          await notifier.loadUsers();
          await _openUserFormInDialog(tester, container, notifier: notifier);
        });

        await tester.enterText(_lastNameField(), _kCharSplitUserLastName);
        await tester.enterText(_firstNameField(), _kCharSplitUserFirstName);
        await pumpUntilSettled(tester);

        final addButton = find.widgetWithText(FilledButton, 'Προσθήκη');
        expect(
          tester.widget<FilledButton>(addButton).onPressed,
          isNotNull,
          reason: greekExpectMsg(
            'Η προσθήκη ενεργοποιείται με συμπληρωμένα υποχρεωτικά ονόματα',
          ),
        );

        await tester.tap(addButton);
        await pumpUntilSettled(tester);
        await _pumpUntilUserSaveCompletes(tester);

        final exists = await tester.runAsync(
          () => _userExistsByName(
            _kCharSplitUserFirstName,
            _kCharSplitUserLastName,
          ),
        );
        expect(exists, isTrue);
      },
    );

    testWidgets(
      'επεξεργασία: αλλαγή εμφανίζει διάλογο επιβεβαίωσης, χωρίς αλλαγές όχι',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final container = ProviderContainer(
          overrides: callLoggerTestProviderOverrides(),
        );
        addTearDown(container.dispose);

        late DirectoryNotifier notifier;
        late UserModel initial;
        await tester.runAsync(() async {
          await container.read(lookupServiceProvider.future);
          notifier = container.read(directoryProvider.notifier);
          await notifier.loadUsers();
          initial = _findSeededTestUser(notifier);
          await _openUserFormInDialog(
            tester,
            container,
            initialUser: initial,
            notifier: notifier,
          );
        });

        expect(find.text(_kEditUserTitle), findsOneWidget);

        await tester.tapAt(const Offset(8, 8));
        await pumpUntilSettled(tester);
        expect(find.textContaining(_kUnsavedChangesPrompt), findsNothing);
        expect(find.text(_kEditUserTitle), findsNothing);

        await tester.runAsync(() async {
          await container.read(lookupServiceProvider.future);
          await notifier.loadUsers();
          initial = _findSeededTestUser(notifier);
          await _openUserFormInDialog(
            tester,
            container,
            initialUser: initial,
            notifier: notifier,
          );
        });

        await tester.enterText(_notesField(), 'Νέα σημείωση δοκιμής χαρακτηρισμού');
        await pumpUntilSettled(tester);
        await tester.tapAt(const Offset(8, 8));
        await pumpUntilSettled(tester);

        expect(find.text('Μη αποθηκευμένες αλλαγές'), findsOneWidget);
        expect(find.textContaining(_kUnsavedChangesPrompt), findsOneWidget);
        expect(find.text('Διατήρηση'), findsOneWidget);
        expect(find.text('Ακύρωση Αλλαγών'), findsOneWidget);
        expect(find.text('Επεξεργασία'), findsOneWidget);
        expect(find.text(_kEditUserTitle), findsOneWidget);
      },
    );
  });
}
