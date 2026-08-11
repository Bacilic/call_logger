// Widget test: φόρμα χρήστη — δημιουργία, επεξεργασία, προστασία μη αποθηκευμένων.
//
// Ολόκληρο αρχείο:
//   flutter test test/features/directory/screens/widgets/user_form_dialog_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/utils/phone_list_parser.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/directory/providers/catalog_validation_provider.dart';
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
    final formOpen =
        find.text(_kNewUserTitle).evaluate().isNotEmpty ||
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
    where: 'first_name = ? AND last_name = ? AND COALESCE(is_deleted, 0) = 0',
    whereArgs: [firstName, lastName],
    limit: 1,
  );
  return rows.isNotEmpty;
}

UserModel _findSeededTestUser(DirectoryNotifier notifier) {
  return notifier.allUsersForUi.firstWhere(
    (u) => u.firstName == kTestUserFirstName && u.lastName == kTestUserLastName,
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

    testWidgets('δημιουργία: επιτυχής αποθήκευση νέου χρήστη στη βάση', (
      tester,
    ) async {
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

      // Νέος υπάλληλος χωρίς τμήμα: ο φρουρός ρωτά πριν την αποθήκευση.
      expect(
        find.text('Συνέχεια χωρίς τμήμα'),
        findsOneWidget,
        reason: greekExpectMsg(
          'Ο υπάλληλος αποθηκεύεται χωρίς τμήμα μόνο μετά από ρητή επιλογή',
        ),
      );
      await tester.tap(find.text('Συνέχεια χωρίς τμήμα'));
      await pumpUntilSettled(tester);

      await _pumpUntilUserSaveCompletes(tester);

      final exists = await tester.runAsync(
        () => _userExistsByName(
          _kCharSplitUserFirstName,
          _kCharSplitUserLastName,
        ),
      );
      expect(exists, isTrue);
    });

    testWidgets(
      'δημιουργία: το αναγνωριστικό Lansweeper που πληκτρολογήθηκε γράφεται στη βάση',
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

        await tester.enterText(_lastNameField(), 'LsIdUserLn');
        await tester.enterText(_firstNameField(), 'LsIdUserFn');
        await tester.enterText(
          _fieldByLabel('Αναγνωριστικό Lansweeper'),
          r'gnk\ls.user',
        );
        await pumpUntilSettled(tester);

        await tester.tap(find.widgetWithText(FilledButton, 'Προσθήκη'));
        await pumpUntilSettled(tester);

        // Νέος υπάλληλος χωρίς τμήμα: ο φρουρός ρωτά πριν την αποθήκευση.
        await tester.tap(find.text('Συνέχεια χωρίς τμήμα'));
        await pumpUntilSettled(tester);
        await _pumpUntilUserSaveCompletes(tester);

        final stored = await tester.runAsync(() async {
          final db = await DatabaseHelper.instance.database;
          final rows = await db.query(
            'users',
            columns: ['lansweeper_username'],
            where: 'first_name = ? AND last_name = ?',
            whereArgs: ['LsIdUserFn', 'LsIdUserLn'],
            limit: 1,
          );
          return rows.isEmpty
              ? null
              : rows.first['lansweeper_username'] as String?;
        });
        expect(stored, r'gnk\ls.user');
      },
    );

    testWidgets(
      'επεξεργασία: το άδειασμα Σημειώσεων και Τοποθεσίας γράφεται στη βάση',
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
          final seeded = _findSeededTestUser(notifier);
          // Ο χρήστης αποκτά σημειώσεις και τοποθεσία, ώστε το άδειασμα
          // να έχει κάτι να καθαρίσει.
          final db = await DatabaseHelper.instance.database;
          await db.update(
            'users',
            {'notes': 'Προϊσταμένη', 'location': 'δίπλα στο ερμάριο'},
            where: 'id = ?',
            whereArgs: [seeded.id],
          );
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

        await tester.enterText(_notesField(), '');
        await tester.enterText(_fieldByLabel('Τοποθεσία'), '');
        await pumpUntilSettled(tester);

        await tester.tap(find.widgetWithText(FilledButton, 'Αποθήκευση'));
        await pumpUntilSettled(tester);
        await _pumpUntilUserSaveCompletes(tester);

        final row = await tester.runAsync(() async {
          final db = await DatabaseHelper.instance.database;
          final rows = await db.query(
            'users',
            columns: ['notes', 'location'],
            where: 'id = ?',
            whereArgs: [initial.id],
            limit: 1,
          );
          return rows.first;
        });
        expect(
          (row!['notes'] as String?) ?? '',
          isEmpty,
          reason: greekExpectMsg(
            'Το άδειασμα των Σημειώσεων γράφεται στη βάση',
          ),
        );
        expect(
          (row['location'] as String?) ?? '',
          isEmpty,
          reason: greekExpectMsg('Το άδειασμα της Τοποθεσίας γράφεται στη βάση'),
        );
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

        await tester.enterText(
          _notesField(),
          'Νέα σημείωση δοκιμής χαρακτηρισμού',
        );
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

    testWidgets(
      'κανόνες επικύρωσης: λάθος πρόθεμα τηλεφώνου και επώνυμο-αριθμός εμφανίζουν υπόδειξη χωρίς να μπλοκάρουν',
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
          // Προφόρτωση των κανόνων ΜΕΣΑ σε runAsync: το sqflite FFI δεν
          // προωθείται από τον fake χρόνο του testWidgets.
          await container.read(catalogValidationServiceProvider.future);
          notifier = container.read(directoryProvider.notifier);
          await notifier.loadUsers();
          await _openUserFormInDialog(tester, container, notifier: notifier);
        });

        // Τηλέφωνο 4ψήφιο με πρόθεμα εκτός 22–29 → υπόδειξη προθέματος.
        await tester.enterText(_fieldByLabel('Τηλέφωνο'), '3122');
        await pumpUntilSettled(tester);
        expect(
          find.text('Το 3122 δεν ξεκινά από 22–29'),
          findsOneWidget,
          reason: greekExpectMsg(
            'Το λάθος πρόθεμα εσωτερικού εμφανίζει υπόδειξη κάτω από το πεδίο',
          ),
        );

        // Διόρθωση σε έγκυρο εσωτερικό → η υπόδειξη φεύγει.
        await tester.enterText(_fieldByLabel('Τηλέφωνο'), '2534');
        await pumpUntilSettled(tester);
        expect(find.text('Το 3122 δεν ξεκινά από 22–29'), findsNothing);

        // Επώνυμο που ξεκινά από ψηφίο (εταιρεία «3π») → υπόδειξη, ΟΧΙ σφάλμα.
        await tester.enterText(_lastNameField(), '3π');
        await pumpUntilSettled(tester);
        expect(
          find.text(
            'Ξεκινά από ψηφίο ή σύμβολο — σωστό μόνο αν πρόκειται για εταιρεία',
          ),
          findsOneWidget,
          reason: greekExpectMsg(
            'Το επώνυμο-αριθμός εμφανίζει υπόδειξη εταιρείας',
          ),
        );

        // Η υπόδειξη είναι προειδοποίηση: η φόρμα δεν δείχνει κόκκινο
        // «Υποχρεωτικό» και το κουμπί προσθήκης παραμένει ενεργό.
        expect(find.text('Υποχρεωτικό'), findsNothing);
        final addButton = find.widgetWithText(FilledButton, 'Προσθήκη');
        expect(
          tester.widget<FilledButton>(addButton).onPressed,
          isNotNull,
          reason: greekExpectMsg(
            'Οι υποδείξεις δεν απενεργοποιούν την αποθήκευση',
          ),
        );
      },
    );

    testWidgets(
      'λίστα προτάσεων τηλεφώνου δείχνει τμήμα-υπάλληλο και η επιλογή γράφει μόνο τον αριθμό',
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

        final phoneField = _fieldByLabel('Τηλέφωνο');
        await tester.tap(phoneField);
        await pumpUntilSettled(tester);
        // Ελάχιστο μήκος query autocomplete = 2.
        await tester.enterText(phoneField, kTestPhoneDigits.substring(0, 2));
        await pumpUntilSettledLong(tester);

        final labeledOption = find.textContaining(
          '($kTestDepartmentName - $kTestUserFirstName $kTestUserLastName)',
        );
        expect(
          labeledOption,
          findsWidgets,
          reason: greekExpectMsg(
            'Η πρόταση τηλεφώνου πρέπει να δείχνει (Τμήμα - Υπάλληλος)',
          ),
        );

        await tester.tap(labeledOption.first);
        await pumpUntilSettled(tester);

        final phoneEditable = tester.widget<EditableText>(
          find.descendant(
            of: find.byWidgetPredicate(
              (w) =>
                  w is InputDecorator && w.decoration.labelText == 'Τηλέφωνο',
            ),
            matching: find.byType(EditableText),
          ),
        );
        final fieldText = phoneEditable.controller.text.trim();
        final writtenPhones = PhoneListParser.splitPhones(fieldText);
        expect(
          writtenPhones,
          [kTestPhoneDigits],
          reason: greekExpectMsg(
            'Μετά την επιλογή στο πεδίο μένει μόνο ο αριθμός',
          ),
        );
        expect(
          fieldText.contains('('),
          isFalse,
          reason: greekExpectMsg(
            'Η πληροφορία τμήματος-κατόχου δεν γράφεται στο πεδίο',
          ),
        );
      },
    );
  });
}
