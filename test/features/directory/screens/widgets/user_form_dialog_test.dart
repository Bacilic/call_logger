// Widget test: φόρμα χρήστη — δημιουργία, επεξεργασία, προστασία μη αποθηκευμένων.
//
// Ολόκληρο αρχείο:
//   flutter test test/features/directory/screens/widgets/user_form_dialog_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/phone_repository.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/utils/phone_list_parser.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
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

Future<void> _pumpUntilUserSaveCompletes(WidgetTester tester) {
  return pumpUntilDialogCloses(
    tester,
    isOpen: () =>
        find.text(_kNewUserTitle).evaluate().isNotEmpty ||
        find.text(_kEditUserTitle).evaluate().isNotEmpty,
    failMessage: 'Η φόρμα χρήστη δεν έκλεισε εγκαίρως μετά την αποθήκευση',
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
          reason: greekExpectMsg(
            'Το άδειασμα της Τοποθεσίας γράφεται στη βάση',
          ),
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

        // Επώνυμο που ξεκινά από ψηφίο → υπόδειξη, ΟΧΙ σφάλμα. Το κείμενο
        // στέλνει στα Τμήματα: από το v58 η εταιρεία είναι τμήμα με Είδος
        // «Εταιρεία», όχι υπάλληλος.
        await tester.enterText(_lastNameField(), '3π');
        await pumpUntilSettled(tester);
        expect(
          find.text(
            'Ξεκινά από ψηφίο ή σύμβολο — οι εταιρείες καταχωρούνται '
            'στα Τμήματα, με Είδος «Εταιρεία»',
          ),
          findsOneWidget,
          reason: greekExpectMsg(
            'Το επώνυμο-αριθμός στέλνει τον χρήστη στα Τμήματα',
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

    // Κοινό μηχάνημα: ο υπάλληλος μεταφέρεται, και ρωτιέται η τύχη του
    // ΜΗΧΑΝΗΜΑΤΟΣ — απόφαση Διευθυντή 03/10 (σενάριο 3140).
    //   flutter test test/features/directory/screens/widgets/user_form_dialog_test.dart --plain-name "κοινό μηχάνημα"
    Future<({int user, int coOwner, int eq, int oldDept, int leaves})>
    moveOwnerOfSharedMachine(
      WidgetTester tester, {
      required String answer,
      required String tag,
    }) async {
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

      // Δικά του δεδομένα σε κάθε τεστ — η βάση αυτού του αρχείου δεν
      // καθαρίζει ανάμεσα στα τεστ.
      late DirectoryNotifier notifier;
      late UserModel initial;
      late ({int user, int coOwner, int eq, int oldDept, int leaves}) ids;
      await tester.runAsync(() async {
        final db = await DatabaseHelper.instance.database;
        Future<int> department(String name) => db.insert('departments', {
          'name': name,
          'name_key': SearchTextNormalizer.normalizeForSearch(name),
          'is_deleted': 0,
        });
        final secretariat = await department('Γραμματεία $tag');
        final leaves = await department('Άδειες $tag');
        Future<int> person(String first, String last) => db.insert('users', {
          'first_name': first,
          'last_name': last,
          'department_id': secretariat,
          'is_deleted': 0,
        });
        final user = await person('Μαρία', 'Νακαστσή $tag');
        final coOwner = await person('Ελένη', 'Διακομοπούλου $tag');
        final eq = await db.insert('equipment', {
          'code_equipment': '3140-$tag',
          'department_id': secretariat,
          'is_deleted': 0,
        });
        for (final owner in [user, coOwner]) {
          await db.insert('user_equipment', {
            'user_id': owner,
            'equipment_id': eq,
          });
        }
        ids = (
          user: user,
          coOwner: coOwner,
          eq: eq,
          oldDept: secretariat,
          leaves: leaves,
        );
        await container.read(lookupServiceProvider.future);
        container.invalidate(lookupServiceProvider);
        await container.read(lookupServiceProvider.future);
        notifier = container.read(directoryProvider.notifier);
        await notifier.loadUsers();
        initial = notifier.allUsersForUi.firstWhere((u) => u.id == user);
        await _openUserFormInDialog(
          tester,
          container,
          initialUser: initial,
          notifier: notifier,
        );
      });

      Future<void> waitFor(Finder finder) => tester.runAsync(() async {
        for (var i = 0; i < 60; i++) {
          if (finder.evaluate().isNotEmpty) return;
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump(const Duration(milliseconds: 50));
        }
      });

      await tester.enterText(_fieldByLabel('Τμήμα'), 'Άδειες $tag');
      await pumpUntilSettled(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Αποθήκευση'));
      await waitFor(find.text('Μεταφορά'));
      await tester.tap(find.byType(Checkbox).last);
      await pumpUntilSettled(tester);
      await tester.tap(find.text('Μεταφορά'));
      // Το κοινό μηχάνημα: η ερώτηση του σκαριφήματος.
      await waitFor(find.text('Κοινός εξοπλισμός'));
      expect(find.text('Κοινός εξοπλισμός'), findsOneWidget);
      expect(
        find.textContaining('Ο εξοπλισμός 3140-$tag μοιράζεται με:'),
        findsOneWidget,
      );
      await tester.tap(find.textContaining(answer));
      await _pumpUntilUserSaveCompletes(tester);
      await flushCallLoggerSqfliteLockTimers(tester);
      return ids;
    }

    Future<({List<Object?> owners, Object? department})> machine3140(
      WidgetTester tester,
      int eq,
    ) async => (await tester.runAsync(() async {
      final db = await DatabaseHelper.instance.database;
      final owners = (await db.query(
        'user_equipment',
        where: 'equipment_id = ?',
        whereArgs: [eq],
      )).map((r) => r['user_id']).toList();
      final department = (await db.query(
        'equipment',
        where: 'id = ?',
        whereArgs: [eq],
      )).single['department_id'];
      return (owners: owners, department: department);
    }))!;

    // Κοινό τηλέφωνο (το κρατά και συνάδελφος): ρωτιέται ΜΙΑ φορά, στο
    // «Κοινό τηλέφωνο» — ούτε στα «Τηλέφωνα του υπαλλήλου» ούτε στη
    // «Σύγκρουση τοποθεσίας τηλεφώνου» (αποφάσεις Διευθυντή 04/10). Σενάριο
    // 2534: κοινόχρηστο της Γραμματείας και προσωπικό δύο υπαλλήλων της.
    //   flutter test test/features/directory/screens/widgets/user_form_dialog_test.dart --plain-name "κοινό τηλέφωνο"
    Future<({int mover, int colleague, int oldDept, int leaves})>
    moveHolderOfSharedPhone(
      WidgetTester tester, {
      required String answer,
      required String tag,
      required String number,
    }) async {
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

      late ({int mover, int colleague, int oldDept, int leaves}) ids;
      await tester.runAsync(() async {
        final db = await DatabaseHelper.instance.database;
        Future<int> department(String name) => db.insert('departments', {
          'name': name,
          'name_key': SearchTextNormalizer.normalizeForSearch(name),
          'is_deleted': 0,
        });
        final secretariat = await department('Γραμματεία $tag');
        final leaves = await department('Άδειες $tag');
        Future<int> person(String last) => db.insert('users', {
          'first_name': 'Βαρβάρα',
          'last_name': last,
          'department_id': secretariat,
          'is_deleted': 0,
        });
        final mover = await person('Νακαστσή $tag');
        final colleague = await person('Διακομοπούλου $tag');
        final phone = await db.insert('phones', {
          'number': number,
          'department_id': secretariat,
        });
        await db.insert('department_phones', {
          'department_id': secretariat,
          'phone_id': phone,
        });
        for (final owner in [mover, colleague]) {
          await db.insert('user_phones', {'user_id': owner, 'phone_id': phone});
        }
        ids = (
          mover: mover,
          colleague: colleague,
          oldDept: secretariat,
          leaves: leaves,
        );
        await container.read(lookupServiceProvider.future);
        container.invalidate(lookupServiceProvider);
        await container.read(lookupServiceProvider.future);
        final notifier = container.read(directoryProvider.notifier);
        await notifier.loadUsers();
        await _openUserFormInDialog(
          tester,
          container,
          initialUser: notifier.allUsersForUi.firstWhere((u) => u.id == mover),
          notifier: notifier,
        );
      });

      Future<void> waitFor(Finder finder) => tester.runAsync(() async {
        for (var i = 0; i < 60; i++) {
          if (finder.evaluate().isNotEmpty) return;
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump(const Duration(milliseconds: 50));
        }
      });

      await tester.enterText(_fieldByLabel('Τμήμα'), 'Άδειες $tag');
      await pumpUntilSettled(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Αποθήκευση'));
      await waitFor(find.text('Μεταφορά'));
      await tester.tap(find.byType(Checkbox).last);
      await pumpUntilSettled(tester);
      await tester.tap(find.text('Μεταφορά'));
      await waitFor(find.text('Κοινό τηλέφωνο'));

      expect(
        find.text('Τηλέφωνα του υπαλλήλου'),
        findsNothing,
        reason: greekExpectMsg(
          'Το κοινό τηλέφωνο δεν ρωτιέται στην ερώτηση «μένει ή ακολουθεί»',
        ),
      );
      expect(find.text('Κοινό τηλέφωνο'), findsOneWidget);
      expect(
        find.textContaining('Το τηλέφωνο $number μοιράζεται με:'),
        findsOneWidget,
      );
      await tester.tap(find.textContaining(answer));
      await _pumpUntilUserSaveCompletes(tester);
      await flushCallLoggerSqfliteLockTimers(tester);
      expect(
        find.text('Σύγκρουση τοποθεσίας τηλεφώνου'),
        findsNothing,
        reason: greekExpectMsg('Δεύτερη ερώτηση για τον ίδιο αριθμό'),
      );
      return ids;
    }

    Future<({List<Object?> holders, Set<int> departments})> sharedPhone(
      WidgetTester tester,
      String number,
    ) async => (await tester.runAsync(() async {
      final db = await DatabaseHelper.instance.database;
      final repo = PhoneRepository(db);
      return (
        holders: (await repo.holderUserIds(number)).cast<Object?>()
          ..sort((a, b) => (a as int).compareTo(b as int)),
        departments: await repo.sharedDepartmentIds(number),
      );
    }))!;

    testWidgets(
      'κοινό τηλέφωνο «Παραμένει»: φεύγει μόνο από τον μεταφερόμενο',
      (tester) async {
        final ids = await moveHolderOfSharedPhone(
          tester,
          answer: 'Παραμένει',
          tag: 'Τ1',
          number: '2734',
        );
        final phone = await sharedPhone(tester, '2734');
        expect(phone.holders, [ids.colleague]);
        expect(phone.departments, {ids.oldDept});
      },
    );

    testWidgets(
      'κοινό τηλέφωνο «Μεταφέρεται»: φεύγει από τη συνάδελφο, γίνεται '
      'κοινόχρηστο του νέου τμήματος',
      (tester) async {
        final ids = await moveHolderOfSharedPhone(
          tester,
          answer: 'Μεταφέρεται',
          tag: 'Τ2',
          number: '2735',
        );
        final phone = await sharedPhone(tester, '2735');
        expect(phone.holders, [ids.mover]);
        expect(phone.departments, {ids.leaves});
      },
    );

    testWidgets(
      'κοινό μηχάνημα «Παραμένει»: φεύγει μόνο από τον μεταφερόμενο',
      (tester) async {
        final ids = await moveOwnerOfSharedMachine(
          tester,
          answer: 'Παραμένει',
          tag: 'Α',
        );
        final m = await machine3140(tester, ids.eq);
        expect(m.owners, [ids.coOwner]);
        expect(m.department, ids.oldDept);
      },
    );

    testWidgets(
      'κοινό μηχάνημα «Μεταφέρεται»: ακολουθεί, φεύγει από τη συν-κάτοχο',
      (tester) async {
        final ids = await moveOwnerOfSharedMachine(
          tester,
          answer: 'Μεταφέρεται',
          tag: 'Β',
        );
        final m = await machine3140(tester, ids.eq);
        expect(m.owners, [ids.user]);
        expect(m.department, ids.leaves);
      },
    );

    // Ο έλεγχος διπλότυπου τρέχει πλέον ΠΡΙΝ φύγουν τα μηχανήματα που
    // «μένουν πίσω» — οπότε τα αφαιρεί ο ίδιος, για να κρίνει την καρτέλα
    // όπως θα είναι μετά την αποθήκευση.
    //   flutter test test/features/directory/screens/widgets/user_form_dialog_test.dart --plain-name "μένουν πίσω δεν μετρούν"
    test('διπλότυπο: τα μηχανήματα που μένουν πίσω δεν μετρούν', () async {
      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      addTearDown(container.dispose);
      final db = await DatabaseHelper.instance.database;
      final withEquipment = await db.insert('users', {
        'first_name': 'Ίδιος',
        'last_name': 'Συνώνυμος',
        'is_deleted': 0,
      });
      await db.insert('users', {
        'first_name': 'Ίδιος',
        'last_name': 'Συνώνυμος',
        'is_deleted': 0,
      });
      final equipmentId = await db.insert('equipment', {
        'code_equipment': 'PC-LEAVES',
        'is_deleted': 0,
      });
      await db.insert('user_equipment', {
        'user_id': withEquipment,
        'equipment_id': equipmentId,
      });
      await container.read(lookupServiceProvider.future);
      final notifier = container.read(directoryProvider.notifier);
      await notifier.loadUsers();
      final candidate = UserModel(
        id: withEquipment,
        firstName: 'Ίδιος',
        lastName: 'Συνώνυμος',
      );
      final leaving = LookupService.instance.findEquipmentsForUser(
        withEquipment,
      );

      expect(
        await notifier.hasDuplicateUserFresh(
          candidate,
          excludeId: withEquipment,
        ),
        isFalse,
        reason: 'με το μηχάνημά του ο υπάλληλος διαφέρει από τον συνώνυμο',
      );
      expect(
        await notifier.hasDuplicateUserFresh(
          candidate,
          excludeId: withEquipment,
          equipmentLeaving: leaving,
        ),
        isTrue,
        reason: 'χωρίς το μηχάνημα που μένει πίσω, θα είναι ίδιος',
      );
    });

    // Η απόρριψη διπλότυπου γίνεται πριν από κάθε εγγραφή: το νέο τμήμα που
    // γράφτηκε στη φόρμα δεν δημιουργείται για αποθήκευση που απορρίπτεται.
    //   flutter test test/features/directory/screens/widgets/user_form_dialog_test.dart --plain-name "διπλότυπο"
    testWidgets('διπλότυπο: η απόρριψη δεν αφήνει πίσω νέο τμήμα', (
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
        final db = await DatabaseHelper.instance.database;
        // Υπάρχων υπάλληλος χωρίς τηλέφωνα και μηχανήματα.
        await db.insert('users', {
          'first_name': 'Ίδιος',
          'last_name': 'Υπάλληλος',
          'is_deleted': 0,
        });
        await container.read(lookupServiceProvider.future);
        notifier = container.read(directoryProvider.notifier);
        await notifier.loadUsers();
        await _openUserFormInDialog(tester, container, notifier: notifier);
      });

      await tester.enterText(_lastNameField(), 'Υπάλληλος');
      await tester.enterText(_firstNameField(), 'Ίδιος');
      await tester.enterText(_fieldByLabel('Τμήμα'), 'Ακτινολογικό');
      await pumpUntilSettled(tester);

      Future<void> waitFor(Finder finder) => tester.runAsync(() async {
        for (var i = 0; i < 60; i++) {
          if (finder.evaluate().isNotEmpty) return;
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump(const Duration(milliseconds: 50));
        }
      });

      await tester.tap(find.widgetWithText(FilledButton, 'Προσθήκη'));
      // Συνωνυμία: «συνέχεια ως νέος».
      await waitFor(find.text('Συνέχεια ως Συνωνυμία'));
      await tester.tap(find.text('Συνέχεια ως Συνωνυμία'));
      // Τμήμα που δεν υπάρχει: επιβεβαίωση με σημάδι.
      await waitFor(find.text('Προσθήκη + Δημιουργία'));
      await tester.tap(find.byType(Checkbox).last);
      await pumpUntilSettled(tester);
      await tester.tap(find.text('Προσθήκη + Δημιουργία'));
      await tester.runAsync(() async {
        for (var i = 0; i < 40; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump(const Duration(milliseconds: 50));
        }
      });
      await flushCallLoggerSqfliteLockTimers(tester);

      expect(
        find.text(_kNewUserTitle),
        findsOneWidget,
        reason: greekExpectMsg('Η αποθήκευση απορρίφθηκε — η φόρμα μένει'),
      );
      final stored = await tester.runAsync(() async {
        final db = await DatabaseHelper.instance.database;
        final users = await db.query(
          'users',
          where: "first_name = 'Ίδιος' AND last_name = 'Υπάλληλος'",
        );
        final newDepartment = await db.query(
          'departments',
          where: "name = 'Ακτινολογικό'",
        );
        return (users: users, newDepartment: newDepartment);
      });
      expect(stored!.users, hasLength(1), reason: 'το διπλότυπο απορρίφθηκε');
      expect(
        stored.newDepartment,
        isEmpty,
        reason: greekExpectMsg(
          'Αποθήκευση που απορρίπτεται δεν αφήνει πίσω νέο τμήμα',
        ),
      );

      await flushCallLoggerSqfliteLockTimers(tester);
    });

    // Δύο σταθμοί: ο συνάδελφος άλλαξε την καρτέλα στο μεταξύ. «Ακύρωσε την
    // αλλαγή μου» σημαίνει ότι ΤΙΠΟΤΑ δεν γράφεται — ούτε το νέο τμήμα, ούτε
    // το τηλέφωνο που απαντήθηκε ότι μένει στο παλιό τμήμα.
    //   flutter test test/features/directory/screens/widgets/user_form_dialog_test.dart --plain-name "διένεξη με συνάδελφο"
    testWidgets(
      'διένεξη με συνάδελφο: «Ακύρωσε την αλλαγή μου» δεν γράφει τίποτα',
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

        await tester.enterText(_fieldByLabel('Τμήμα'), 'Ακτινολογικό');
        await pumpUntilSettled(tester);

        // Ο συνάδελφος, από άλλο σταθμό, αλλάζει τις σημειώσεις.
        await tester.runAsync(() async {
          final db = await DatabaseHelper.instance.database;
          await db.update(
            'users',
            {'notes': 'Αλλαγή συναδέλφου'},
            where: 'id = ?',
            whereArgs: [initial.id],
          );
        });

        Future<void> waitFor(Finder finder) => tester.runAsync(() async {
          for (var i = 0; i < 60; i++) {
            if (finder.evaluate().isNotEmpty) return;
            await Future<void>.delayed(const Duration(milliseconds: 50));
            await tester.pump(const Duration(milliseconds: 50));
          }
        });

        await tester.tap(find.widgetWithText(FilledButton, 'Αποθήκευση'));
        // Μεταφορά σε τμήμα που δεν υπάρχει: επιβεβαίωση με σημάδι.
        await waitFor(find.text('Μεταφορά + Δημιουργία'));
        await tester.tap(find.byType(Checkbox).last);
        await pumpUntilSettled(tester);
        await tester.tap(find.text('Μεταφορά + Δημιουργία'));
        // Το τηλέφωνο του υπαλλήλου μένει στο παλιό τμήμα.
        await waitFor(find.textContaining('Μένει στο'));
        await tester.tap(find.textContaining('Μένει στο').first);
        // …και το μηχάνημά του επίσης.
        await waitFor(find.text('Μένει στο παλιό τμήμα'));
        await tester.tap(find.text('Μένει στο παλιό τμήμα'));

        await waitFor(find.text('Ακύρωσε την αλλαγή μου'));
        expect(
          find.text('Ακύρωσε την αλλαγή μου'),
          findsOneWidget,
          reason: greekExpectMsg('Η διένεξη ρωτιέται'),
        );
        await tester.tap(find.text('Ακύρωσε την αλλαγή μου'));
        await tester.runAsync(() async {
          for (var i = 0; i < 20; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
            await tester.pump(const Duration(milliseconds: 50));
          }
        });
        await flushCallLoggerSqfliteLockTimers(tester);

        final stored = await tester.runAsync(() async {
          final db = await DatabaseHelper.instance.database;
          final user = (await db.query(
            'users',
            where: 'id = ?',
            whereArgs: [initial.id],
          )).single;
          final newDepartment = await db.query(
            'departments',
            where: "name = 'Ακτινολογικό'",
          );
          final linked = await db.rawQuery(
            'SELECT 1 FROM user_phones up JOIN phones p ON p.id = up.phone_id '
            'WHERE up.user_id = ? AND p.number = ?',
            [initial.id, kTestPhoneDigits],
          );
          final equipment = await db.rawQuery(
            'SELECT 1 FROM user_equipment WHERE user_id = ?',
            [initial.id],
          );
          return (
            user: user,
            newDepartment: newDepartment,
            linked: linked,
            equipment: equipment,
          );
        });
        expect(stored!.user['notes'], 'Αλλαγή συναδέλφου');
        expect(stored.user['department_id'], initial.departmentId);
        expect(
          stored.newDepartment,
          isEmpty,
          reason: greekExpectMsg(
            '«Η αποθήκευση ακυρώθηκε» σημαίνει ότι ούτε το νέο τμήμα γράφτηκε',
          ),
        );
        expect(
          stored.linked,
          hasLength(1),
          reason: greekExpectMsg(
            'Το τηλέφωνο μένει στον υπάλληλο — η απάντηση «μένει πίσω» δεν '
            'εφαρμόζεται σε αποθήκευση που ακυρώθηκε',
          ),
        );
        expect(
          stored.equipment,
          hasLength(1),
          reason: greekExpectMsg('Το ίδιο και για το μηχάνημα του υπαλλήλου'),
        );

        await flushCallLoggerSqfliteLockTimers(tester);
      },
    );
  });
}
