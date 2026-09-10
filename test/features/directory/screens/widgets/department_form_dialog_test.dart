// Widget test: φόρμα τμήματος — μικτή κατάσταση κοινόχρηστων (σύγκρουση + χωρίς σύγκρουση).
//
// Ολόκληρο αρχείο:
//   flutter test test/features/directory/screens/widgets/department_form_dialog_test.dart
// Σενάριο μικτής σύγκρουσης:
//   flutter test test/features/directory/screens/widgets/department_form_dialog_test.dart --plain-name "μικτή σύγκρουση"

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/settings_repository.dart';
import 'package:call_logger/core/services/lansweeper_department_accounts.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/directory/models/department_kind.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:call_logger/features/directory/providers/building_catalog_provider.dart';
import 'package:call_logger/features/directory/providers/department_directory_provider.dart';
import 'package:call_logger/features/directory/screens/widgets/department_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../test_reporter.dart';
import '../../../../test_setup.dart';

const _kFantasmaDepartmentName = 'Φάντασμα';
const _kMariaFirstName = 'Μαρία';
const _kMariaLastName = 'Άσχημη';
const _kConflictPhone = '333';
const _kNewEquipmentCodes = ['2001', '2002', '2003'];

Finder _sharedEquipmentInputField() {
  return find.byWidgetPredicate(
    (w) =>
        w is TextField &&
        w.decoration?.labelText == 'Προσθήκη εξοπλισμού (με κόμμα)',
  );
}

bool _sameEquipmentCodes(List<String> actual, List<String> expected) {
  if (actual.length != expected.length) return false;
  final a = List<String>.from(actual)..sort();
  final e = List<String>.from(expected)..sort();
  for (var i = 0; i < a.length; i++) {
    if (a[i] != e[i]) return false;
  }
  return true;
}

const _kDepartmentFormTitle = 'Επεξεργασία τμήματος';
const _kNewDepartmentFormTitle = 'Νέο τμήμα';
const _kConflictDialogTitle = 'Εκκρεμή τηλέφωνα / εξοπλισμοί';
const _kUnsavedChangesPrompt = 'Θέλεται να γίνει:';
const _kOpenDepartmentFormButton = 'OPEN_DEPT_FORM';

Finder _fieldByLabel(String label) {
  return find.descendant(
    of: find.byWidgetPredicate(
      (w) => w is InputDecorator && w.decoration.labelText == label,
    ),
    matching: find.byType(EditableText),
  );
}

/// Το «Κτίριο» δεν πληκτρολογείται πια — διαλέγεται από τον κοινό κατάλογο.
Finder _buildingDropdown() => find.byType(DropdownButtonFormField<String?>);

/// Ανοίγει τη λίστα κτιρίων και διαλέγει το [name].
Future<void> _selectBuilding(WidgetTester tester, String name) async {
  await tester.ensureVisible(_buildingDropdown());
  await tester.tap(_buildingDropdown());
  await pumpUntilSettled(tester);
  await tester.tap(find.text(name).last);
  await pumpUntilSettled(tester);
}

/// Ορίζει τον κοινό κατάλογο κτιρίων της βάσης του τεστ.
///
/// Χωρίς δηλωμένο πάροχο `app_settings` ο κατάλογος θα ήταν κενός και το
/// πεδίο δεν θα είχε τίποτα να προσφέρει — όπως ακριβώς και στην εφαρμογή.
Future<void> _seedBuildingCatalog(List<String> buildings) async {
  final db = await DatabaseHelper.instance.database;
  SettingsService.registerAppSettingsProvider(
    (key) => SettingsRepository(db).getSetting(key),
    (key, value) => SettingsRepository(db).saveSetting(key, value),
    (key, change) => SettingsRepository(db).updateSetting(key, change),
  );
  await SettingsService().catalogs.setBuildingCatalog(
    buildings.join(', '),
    expected: null,
  );
}

/// Φορτώνει τον κατάλογο **πριν** χτιστεί η φόρμα.
///
/// Ο πάροχος διαβάζει τη βάση, άρα θέλει πραγματικό I/O: μέσα στο pump του
/// τεστ δεν προχωρά ποτέ, και το πεδίο θα έμενε για πάντα «Φόρτωση κτιρίων…».
Future<void> _warmBuildingCatalog(ProviderContainer container) =>
    container.read(buildingCatalogProvider.future);

Finder _departmentNameField() => _fieldByLabel('Όνομα');

Future<void> _openDepartmentFormInDialog(
  WidgetTester tester,
  ProviderContainer container, {
  DepartmentModel? initialDepartment,
  required DepartmentDirectoryNotifier notifier,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  barrierDismissible: true,
                  builder: (ctx) => DepartmentFormDialog(
                    initialDepartment: initialDepartment,
                    notifier: notifier,
                  ),
                ),
                child: const Text(_kOpenDepartmentFormButton),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text(_kOpenDepartmentFormButton));
  await pumpUntilSettledLong(tester);
}

/// Περιμένει κλείσιμο διαλόγων (σύγκρουσης + κύρια φόρμα) = επιτυχής `_save`.
/// Εναλλάσσει [runAsync] (πραγματικό I/O SQLite) με pump (frames για async UI).
Future<void> _pumpUntilDepartmentSaveCompletes(WidgetTester tester) {
  return pumpUntilDialogCloses(
    tester,
    isOpen: () =>
        find.text(_kDepartmentFormTitle).evaluate().isNotEmpty ||
        find.text(_kConflictDialogTitle).evaluate().isNotEmpty,
    failMessage: 'Η φόρμα τμήματος δεν έκλεισε εγκαίρως μετά την αποθήκευση',
  );
}

/// Έλεγχος βάσης σε [runAsync]· προαιρετικό polling για αποφυγή race με async SQLite.
Future<List<String>> _readSharedEquipmentWhenReady(
  WidgetTester tester,
  int departmentId,
  List<String> expected,
) async {
  // Ίδιο σκεπτικό με την [pumpUntilDialogCloses]: πραγματικός χρόνος, γενναίο
  // όριο. Ένα τεστ που περνά βρίσκει την εγγραφή στην πρώτη προσπάθεια.
  const maxAttempts = 125;
  const pollInterval = Duration(milliseconds: 80);

  final codes = await tester.runAsync(() async {
    List<String> last = const [];
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      last = await _sharedEquipmentCodesInDatabase(departmentId);
      if (_sameEquipmentCodes(last, expected)) return last;
      if (attempt < maxAttempts - 1) {
        await Future<void>.delayed(pollInterval);
      }
    }
    return last;
  });
  await tester.pump();
  return codes ?? const [];
}

/// Τμήμα «Φάντασμα»: κοινόχρηστο 333 + χρήστης «Μαρία Άσχημη» με το ίδιο τηλέφωνο.
Future<int> _seedFantasmaMixedSharedAssetsScenario() async {
  final db = await DatabaseHelper.instance.database;
  await db.delete('user_equipment');
  await db.delete('user_phones');
  await db.delete('department_phones');
  await db.delete('phones');
  await db.delete('equipment');
  await db.delete('users');
  await db.delete('departments');

  final deptId = await db.insert('departments', {
    'name': _kFantasmaDepartmentName,
    'name_key': SearchTextNormalizer.normalizeForSearch(
      _kFantasmaDepartmentName,
    ),
    'color': '#33691F',
    'is_deleted': 0,
  });

  final userId = await db.insert('users', {
    'first_name': _kMariaFirstName,
    'last_name': _kMariaLastName,
    'department_id': deptId,
    'is_deleted': 0,
  });

  final phoneId = await db.insert('phones', {'number': _kConflictPhone});
  await db.insert('user_phones', {'user_id': userId, 'phone_id': phoneId});
  await db.insert('department_phones', {
    'department_id': deptId,
    'phone_id': phoneId,
  });

  LookupService.instance.resetForReload();
  await LookupService.instance.loadFromDatabase();
  return deptId;
}

Future<List<String>> _sharedEquipmentCodesInDatabase(int departmentId) async {
  final db = await DatabaseHelper.instance.database;
  final rows = await db.query(
    'equipment',
    columns: ['code_equipment'],
    where: 'department_id = ? AND COALESCE(is_deleted, 0) = 0',
    whereArgs: [departmentId],
    orderBy: 'code_equipment ASC',
  );
  return rows
      .map((r) => (r['code_equipment'] as String?)?.trim() ?? '')
      .where((c) => c.isNotEmpty)
      .toList();
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('Φόρμα τμήματος — κοινόχρηστα στοιχεία (widget)', () {
    late int deptId;

    setUp(() async {
      deptId = await _seedFantasmaMixedSharedAssetsScenario();
    });

    // Μικτή σύγκρουση: κοινόχρηστο 333 (και ιδιοκτησία χρήστη) + νέοι κωδικοί εξοπλισμού χωρίς σύγκρουση.
    //   flutter test test/features/directory/screens/widgets/department_form_dialog_test.dart --plain-name "μικτή σύγκρουση"
    testWidgets(
      'μικτή σύγκρουση: εξοπλισμός χωρίς σύγκρουση καταχωρείται μετά την επιβεβαίωση',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final reporter = GreekTestReportCollector();
        addTearDown(
          () => reporter.printFinalSummary(
            title: 'Φόρμα τμήματος — μικτή σύγκρουση κοινόχρηστων',
          ),
        );

        final container = ProviderContainer(
          overrides: callLoggerTestProviderOverrides(),
        );
        addTearDown(container.dispose);

        final initialDepartment = DepartmentModel(
          id: deptId,
          name: _kFantasmaDepartmentName,
          color: '#33691F',
        );

        reporter.logProgress(
          'Άνοιγμα διαλόγου «Φάντασμα» — το 333 είναι ήδη κοινόχρηστο τμήματος',
        );

        late DepartmentDirectoryNotifier notifier;
        await tester.runAsync(() async {
          await container.read(lookupServiceProvider.future);
          notifier = container.read(departmentDirectoryProvider.notifier);
          await notifier.loadDepartments();

          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                home: Scaffold(
                  body: DepartmentFormDialog(
                    initialDepartment: initialDepartment,
                    notifier: notifier,
                    focusedField: 'equipment',
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          await pumpUntilSettledLong(tester);
        });

        expect(
          find.text(_kDepartmentFormTitle),
          findsOneWidget,
          reason: greekExpectMsg('Διάλογος επεξεργασίας τμήματος'),
        );
        expect(
          find.widgetWithText(InputChip, _kConflictPhone),
          findsOneWidget,
          reason: greekExpectMsg(
            'Το 333 εμφανίζεται ήδη ως κοινόχρηστο τηλέφωνο του τμήματος',
          ),
        );
        reporter.logStepDone(
          'Διάλογος ανοιχτός — κοινόχρηστο 333 ήδη στη φόρμα',
        );

        reporter.logProgress(
          'Προσθήκη μόνο κοινόχρηστου εξοπλισμού 2001, 2002, 2003',
        );

        await tester.tap(_sharedEquipmentInputField());
        await pumpUntilSettled(tester);
        await tester.enterText(
          _sharedEquipmentInputField(),
          _kNewEquipmentCodes.join(','),
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await pumpUntilSettled(tester);

        for (final code in _kNewEquipmentCodes) {
          expect(
            find.widgetWithText(InputChip, code),
            findsOneWidget,
            reason: greekExpectMsg(
              'Chip εξοπλισμού $code στη φόρμα πριν την αποθήκευση',
            ),
          );
        }
        reporter.logStepDone('Chips εξοπλισμού 2001, 2002, 2003 στη φόρμα');

        reporter.logProgress(
          'Αποθήκευση — αναμένεται διάλογος σύγκρουσης μόνο για το 333',
        );

        final saveButton = find.widgetWithText(FilledButton, 'Αποθήκευση');
        await tester.ensureVisible(saveButton);
        expect(
          tester.widget<FilledButton>(saveButton).onPressed,
          isNotNull,
          reason: greekExpectMsg(
            'Κουμπί αποθήκευσης ενεργό μετά την προσθήκη εξοπλισμού',
          ),
        );
        await tester.tap(saveButton);
        await pumpUntilSettled(tester);

        expect(
          find.text(_kConflictDialogTitle),
          findsOneWidget,
          reason: greekExpectMsg('Διάλογος επίλυσης συγκρούσεων κοινόχρηστων'),
        );
        expect(
          find.textContaining('Τηλέφωνο: $_kConflictPhone'),
          findsOneWidget,
          reason: greekExpectMsg('Σύγκρουση για το κοινόχρηστο τηλέφωνο 333'),
        );
        expect(
          find.textContaining('$_kMariaFirstName $_kMariaLastName'),
          findsWidgets,
          reason: greekExpectMsg(
            'Εμφάνιση ιδιοκτήτριας Μαρία Άσχημη στον διάλογο σύγκρουσης',
          ),
        );
        for (final code in _kNewEquipmentCodes) {
          expect(
            find.textContaining('Εξοπλισμός: $code'),
            findsNothing,
            reason: greekExpectMsg(
              'Ο εξοπλισμός $code δεν έχει σύγκρουση — δεν εμφανίζεται στον διάλογο',
            ),
          );
        }
        reporter.logStepDone(
          'Διάλογος σύγκρουσης μόνο για το 333 (Μαρία Άσχημη)',
        );

        reporter.logProgress(
          'Επιλογή διατήρησης 333 ως κοινόχρηστου τμήματος και επιβεβαίωση',
        );

        await tester.tap(find.textContaining('Κάνε το κοινόχρηστο').last);
        await pumpUntilSettled(tester);

        final confirmButton = find.widgetWithText(FilledButton, 'Επιβεβαίωση');
        expect(
          tester.widget<FilledButton>(confirmButton).onPressed,
          isNotNull,
          reason: greekExpectMsg('Κουμπί επιβεβαίωσης ενεργό μετά την επιλογή'),
        );
        await tester.tap(confirmButton);
        await pumpUntilSettled(tester);
        await _pumpUntilDepartmentSaveCompletes(tester);

        expect(
          find.text(_kConflictDialogTitle),
          findsNothing,
          reason: greekExpectMsg(
            'Ο διάλογος σύγκρουσης κλείνει μετά την επιβεβαίωση',
          ),
        );
        expect(
          find.text(_kDepartmentFormTitle),
          findsNothing,
          reason: greekExpectMsg(
            'Η φόρμα τμήματος κλείνει μετά επιτυχημένη αποθήκευση',
          ),
        );
        reporter.logStepDone(
          'Επιβεβαίωση — διάλογοι έκλεισαν (αποθήκευση ολοκληρώθηκε)',
        );

        reporter.logProgress(
          'Έλεγχος βάσης — κοινόχρηστος εξοπλισμός 2001, 2002, 2003',
        );

        final codes = await _readSharedEquipmentWhenReady(
          tester,
          deptId,
          _kNewEquipmentCodes,
        );
        if (!_sameEquipmentCodes(codes, _kNewEquipmentCodes)) {
          final actualLabel = codes.isEmpty ? '[]' : codes.join(', ');
          final expectedLabel = _kNewEquipmentCodes.join(', ');
          reporter.failGreek(
            'Αποθήκευση κοινόχρηστου εξοπλισμού',
            'Αναμενόμενοι κωδικοί: [$expectedLabel] · Πραγματικοί στη βάση: [$actualLabel]',
          );
        }

        reporter.logStepDone('Εξοπλισμός στη βάση: ${codes.join(', ')}');
        reporter.recordPass(
          'Μικτή σύγκρουση — κοινόχρηστος εξοπλισμός χωρίς σύγκρουση στη βάση',
        );
      },
      semanticsEnabled: false,
    );
  });

  group('Φόρμα τμήματος — προστασία μη αποθηκευμένων αλλαγών', () {
    late int deptId;

    setUp(() async {
      deptId = await _seedFantasmaMixedSharedAssetsScenario();
      // Η «αλλαγή κτιρίου» είναι πια επιλογή από τον κατάλογο, όχι κείμενο:
      // χωρίς κατάλογο δεν υπάρχει τίποτα να διαλέξει ο χρήστης.
      await _seedBuildingCatalog(['Καινούριο', 'Παλιό']);
    });

    testWidgets(
      'επεξεργασία χωρίς αλλαγές: ακύρωση κλείνει χωρίς επιβεβαίωση',
      (tester) async {
        final container = ProviderContainer(
          overrides: callLoggerTestProviderOverrides(),
        );
        addTearDown(container.dispose);

        late DepartmentDirectoryNotifier notifier;
        await tester.runAsync(() async {
          await container.read(lookupServiceProvider.future);
          notifier = container.read(departmentDirectoryProvider.notifier);
          await notifier.loadDepartments();
          await _warmBuildingCatalog(container);
          await _warmBuildingCatalog(container);
          await _openDepartmentFormInDialog(
            tester,
            container,
            initialDepartment: DepartmentModel(
              id: deptId,
              name: _kFantasmaDepartmentName,
              color: '#33691F',
            ),
            notifier: notifier,
          );
        });

        await tester.tap(find.widgetWithText(TextButton, 'Ακύρωση'));
        await pumpUntilSettled(tester);

        expect(find.text(_kDepartmentFormTitle), findsNothing);
        expect(find.text(_kUnsavedChangesPrompt), findsNothing);
      },
    );

    testWidgets(
      'επεξεργασία με αλλαγή κτιρίου: κουμπί ακύρωσης κλείνει χωρίς επιβεβαίωση',
      (tester) async {
        final container = ProviderContainer(
          overrides: callLoggerTestProviderOverrides(),
        );
        addTearDown(container.dispose);

        late DepartmentDirectoryNotifier notifier;
        await tester.runAsync(() async {
          await container.read(lookupServiceProvider.future);
          notifier = container.read(departmentDirectoryProvider.notifier);
          await notifier.loadDepartments();
          await _warmBuildingCatalog(container);
          await _warmBuildingCatalog(container);
          await _openDepartmentFormInDialog(
            tester,
            container,
            initialDepartment: DepartmentModel(
              id: deptId,
              name: _kFantasmaDepartmentName,
              color: '#33691F',
            ),
            notifier: notifier,
          );
        });

        await _selectBuilding(tester, 'Καινούριο');
        await tester.tap(find.widgetWithText(TextButton, 'Ακύρωση'));
        await pumpUntilSettled(tester);

        expect(find.text(_kDepartmentFormTitle), findsNothing);
        expect(find.textContaining(_kUnsavedChangesPrompt), findsNothing);
      },
    );

    testWidgets('επεξεργασία με αλλαγή: «Επεξεργασία» επιστρέφει στη φόρμα', (
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

      late DepartmentDirectoryNotifier notifier;
      await tester.runAsync(() async {
        await container.read(lookupServiceProvider.future);
        notifier = container.read(departmentDirectoryProvider.notifier);
        await notifier.loadDepartments();
        await _warmBuildingCatalog(container);
        await _warmBuildingCatalog(container);
        await _openDepartmentFormInDialog(
          tester,
          container,
          initialDepartment: DepartmentModel(
            id: deptId,
            name: _kFantasmaDepartmentName,
            color: '#33691F',
          ),
          notifier: notifier,
        );
      });

      await _selectBuilding(tester, 'Καινούριο');
      await tester.tapAt(const Offset(8, 8));
      await pumpUntilSettled(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Επεξεργασία').last);
      await pumpUntilSettled(tester);

      expect(find.text(_kUnsavedChangesPrompt), findsNothing);
      expect(find.text(_kDepartmentFormTitle), findsOneWidget);
      expect(find.text('Καινούριο'), findsWidgets);
    });

    testWidgets('επεξεργασία με αλλαγή: «Ακύρωση Αλλαγών» κλείνει τη φόρμα', (
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

      late DepartmentDirectoryNotifier notifier;
      await tester.runAsync(() async {
        await container.read(lookupServiceProvider.future);
        notifier = container.read(departmentDirectoryProvider.notifier);
        await notifier.loadDepartments();
        await _warmBuildingCatalog(container);
        await _warmBuildingCatalog(container);
        await _openDepartmentFormInDialog(
          tester,
          container,
          initialDepartment: DepartmentModel(
            id: deptId,
            name: _kFantasmaDepartmentName,
            color: '#33691F',
          ),
          notifier: notifier,
        );
      });

      await _selectBuilding(tester, 'Καινούριο');
      await tester.tapAt(const Offset(8, 8));
      await pumpUntilSettled(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Ακύρωση Αλλαγών'));
      await pumpUntilSettled(tester);

      expect(find.text(_kDepartmentFormTitle), findsNothing);
    });

    testWidgets('νέο τμήμα χωρίς όνομα: ακύρωση κλείνει χωρίς επιβεβαίωση', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      addTearDown(container.dispose);

      late DepartmentDirectoryNotifier notifier;
      await tester.runAsync(() async {
        await container.read(lookupServiceProvider.future);
        notifier = container.read(departmentDirectoryProvider.notifier);
        await notifier.loadDepartments();
        await _warmBuildingCatalog(container);
        await _warmBuildingCatalog(container);
        await _openDepartmentFormInDialog(
          tester,
          container,
          notifier: notifier,
        );
      });

      expect(find.text(_kNewDepartmentFormTitle), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Ακύρωση'));
      await pumpUntilSettled(tester);

      expect(find.text(_kNewDepartmentFormTitle), findsNothing);
      expect(find.text(_kUnsavedChangesPrompt), findsNothing);
    });

    testWidgets(
      'νέο τμήμα με όνομα: κουμπί ακύρωσης κλείνει χωρίς επιβεβαίωση',
      (tester) async {
        final container = ProviderContainer(
          overrides: callLoggerTestProviderOverrides(),
        );
        addTearDown(container.dispose);

        late DepartmentDirectoryNotifier notifier;
        await tester.runAsync(() async {
          await container.read(lookupServiceProvider.future);
          notifier = container.read(departmentDirectoryProvider.notifier);
          await notifier.loadDepartments();
          await _warmBuildingCatalog(container);
          await _warmBuildingCatalog(container);
          await _openDepartmentFormInDialog(
            tester,
            container,
            notifier: notifier,
          );
        });

        await tester.enterText(_departmentNameField(), 'Πειραματικό');
        await pumpUntilSettled(tester);
        await tester.tap(find.widgetWithText(TextButton, 'Ακύρωση'));
        await pumpUntilSettled(tester);

        expect(find.text(_kNewDepartmentFormTitle), findsNothing);
        expect(find.textContaining(_kUnsavedChangesPrompt), findsNothing);
      },
    );

    testWidgets('νέο τμήμα με όνομα: κλικ εκτός εμφανίζει προειδοποίηση', (
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

      late DepartmentDirectoryNotifier notifier;
      await tester.runAsync(() async {
        await container.read(lookupServiceProvider.future);
        notifier = container.read(departmentDirectoryProvider.notifier);
        await notifier.loadDepartments();
        await _warmBuildingCatalog(container);
        await _warmBuildingCatalog(container);
        await _openDepartmentFormInDialog(
          tester,
          container,
          notifier: notifier,
        );
      });

      await tester.enterText(_departmentNameField(), 'Πειραματικό');
      await pumpUntilSettled(tester);
      await tester.tapAt(const Offset(8, 8));
      await pumpUntilSettled(tester);

      expect(
        find.textContaining('Το τμήμα δεν έχει αποθηκευτεί.'),
        findsOneWidget,
      );
      expect(find.textContaining(_kUnsavedChangesPrompt), findsOneWidget);
      expect(find.text(_kNewDepartmentFormTitle), findsOneWidget);
    });

    testWidgets(
      'επεξεργασία με αλλαγή: κλικ εκτός (barrier) εμφανίζει επιβεβαίωση',
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

        late DepartmentDirectoryNotifier notifier;
        await tester.runAsync(() async {
          await container.read(lookupServiceProvider.future);
          notifier = container.read(departmentDirectoryProvider.notifier);
          await notifier.loadDepartments();
          await _warmBuildingCatalog(container);
          await _warmBuildingCatalog(container);
          await _openDepartmentFormInDialog(
            tester,
            container,
            initialDepartment: DepartmentModel(
              id: deptId,
              name: _kFantasmaDepartmentName,
              color: '#33691F',
            ),
            notifier: notifier,
          );
        });

        await _selectBuilding(tester, 'Καινούριο');
        await tester.tapAt(const Offset(8, 8));
        await pumpUntilSettled(tester);

        expect(find.textContaining('- Κτίριο'), findsOneWidget);
        expect(find.text(_kDepartmentFormTitle), findsOneWidget);
      },
    );
  });

  group('Φόρμα τμήματος — το Κτίριο διαλέγεται από τον κατάλογο', () {
    //   flutter test test/features/directory/screens/widgets/department_form_dialog_test.dart --plain-name "Κτίριο"
    testWidgets('προσφέρει τα κτίρια του καταλόγου και τίποτα άλλο', (
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

      late DepartmentDirectoryNotifier notifier;
      await tester.runAsync(() async {
        await seedIsolatedTestDatabase();
        await _seedBuildingCatalog(['Καινούριο', 'Παλιό']);
        await container.read(lookupServiceProvider.future);
        notifier = container.read(departmentDirectoryProvider.notifier);
        await notifier.loadDepartments();
        await _warmBuildingCatalog(container);
        await _warmBuildingCatalog(container);
        await _openDepartmentFormInDialog(
          tester,
          container,
          notifier: notifier,
        );
      });
      await pumpUntilSettled(tester);

      await tester.ensureVisible(_buildingDropdown());
      await tester.tap(_buildingDropdown());
      await pumpUntilSettled(tester);

      expect(find.text('Καινούριο'), findsWidgets);
      expect(find.text('Παλιό'), findsWidgets);
      expect(
        find.byWidgetPredicate(
          (w) => w is DropdownMenuItem<String?> && w.value == null,
        ),
        findsNothing,
        reason:
            'Κλειστή λίστα: το κενό δεν επιλέγεται από τη φόρμα — τα τμήματα '
            'χωρίς κτίριο τα βγάζει ο «Έλεγχος δεδομένων»',
      );

      await flushCallLoggerSqfliteLockTimers(tester);
    });

    testWidgets('η επιλογή γράφεται στη βάση', (tester) async {
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

      const deptName = 'BuildingChoiceDept';
      late int deptId;
      late DepartmentDirectoryNotifier notifier;
      await tester.runAsync(() async {
        await seedIsolatedTestDatabase();
        await _seedBuildingCatalog(['Καινούριο', 'Παλιό']);
        final db = await DatabaseHelper.instance.database;
        deptId = await db.insert('departments', {
          'name': deptName,
          'name_key': SearchTextNormalizer.normalizeForSearch(deptName),
          'color': '#1976D2',
          'is_deleted': 0,
        });
        LookupService.instance.resetForReload();
        await LookupService.instance.loadFromDatabase();
        await container.read(lookupServiceProvider.future);
        notifier = container.read(departmentDirectoryProvider.notifier);
        await notifier.loadDepartments();
        await _warmBuildingCatalog(container);
        await _warmBuildingCatalog(container);
        await _openDepartmentFormInDialog(
          tester,
          container,
          initialDepartment: DepartmentModel(
            id: deptId,
            name: deptName,
            color: '#1976D2',
          ),
          notifier: notifier,
        );
      });
      await pumpUntilSettled(tester);

      await _selectBuilding(tester, 'Παλιό');

      final saveButton = find.widgetWithText(FilledButton, 'Αποθήκευση');
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await pumpUntilSettled(tester);
      await _pumpUntilDepartmentSaveCompletes(tester);

      final building = await tester.runAsync(() async {
        final db = await DatabaseHelper.instance.database;
        final rows = await db.query(
          'departments',
          columns: ['building'],
          where: 'id = ?',
          whereArgs: [deptId],
          limit: 1,
        );
        return rows.single['building'] as String?;
      });
      expect(
        building,
        'Παλιό',
        reason: greekExpectMsg('Η επιλογή κτιρίου γράφεται στη βάση'),
      );

      await flushCallLoggerSqfliteLockTimers(tester);
    });

    testWidgets('κτίριο εκτός καταλόγου δεν εξαφανίζεται από τη φόρμα', (
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

      late DepartmentDirectoryNotifier notifier;
      await tester.runAsync(() async {
        await seedIsolatedTestDatabase();
        await _seedBuildingCatalog(['Καινούριο']);
        await container.read(lookupServiceProvider.future);
        notifier = container.read(departmentDirectoryProvider.notifier);
        await notifier.loadDepartments();
        await _warmBuildingCatalog(container);
        await _warmBuildingCatalog(container);
        await _openDepartmentFormInDialog(
          tester,
          container,
          initialDepartment: DepartmentModel(
            id: 4242,
            name: 'OutOfCatalogDept',
            color: '#1976D2',
            building: 'Πτέρυγα Γ',
          ),
          notifier: notifier,
        );
      });
      await pumpUntilSettled(tester);

      expect(
        find.text('Πτέρυγα Γ'),
        findsWidgets,
        reason:
            'Τιμή που λείπει από τον κατάλογο μένει ορατή — αλλιώς ένα '
            'άνοιγμα-και-αποθήκευση θα την έσβηνε σιωπηλά',
      );

      await flushCallLoggerSqfliteLockTimers(tester);
    });
  });

  group('Φόρμα τμήματος — χαρακτηρισμός split', () {
    const kCharSplitDeptName = 'CharSplitDeptMarker';
    const kCharSplitFloorLabel = 'CharSplitFloorMarker';

    Future<int> seedCharacterizationFloor() async {
      final db = await DatabaseHelper.instance.database;
      return db.insert('building_map_floors', {
        'sort_order': 0,
        'label': kCharSplitFloorLabel,
        'image_path': 'char_split_test.png',
        'rotation_degrees': 0.0,
      });
    }

    Finder floorDropdown() {
      return find.byWidgetPredicate((w) => w is DropdownButtonFormField<int?>);
    }

    testWidgets(
      'δημιουργία νέου τμήματος με όνομα και όροφο αποθηκεύεται στη βάση',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        late int floorId;
        final container = ProviderContainer(
          overrides: callLoggerTestProviderOverrides(),
        );
        addTearDown(container.dispose);

        late DepartmentDirectoryNotifier notifier;
        await tester.runAsync(() async {
          await seedIsolatedTestDatabase();
          floorId = await seedCharacterizationFloor();
          await container.read(lookupServiceProvider.future);
          notifier = container.read(departmentDirectoryProvider.notifier);
          await notifier.loadDepartments();
          await _warmBuildingCatalog(container);
          await _warmBuildingCatalog(container);
          await _openDepartmentFormInDialog(
            tester,
            container,
            notifier: notifier,
          );
        });

        expect(find.text(_kNewDepartmentFormTitle), findsOneWidget);
        await tester.runAsync(() async {
          for (var i = 0; i < 30; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
            await tester.pump(const Duration(milliseconds: 50));
          }
        });
        await pumpUntilSettledLong(tester);

        await tester.enterText(_departmentNameField(), kCharSplitDeptName);
        await pumpUntilSettled(tester);

        final floorDropdownFinder = floorDropdown();
        await tester.ensureVisible(floorDropdownFinder);
        await pumpUntilSettled(tester);
        await tester.tap(floorDropdownFinder);
        await pumpUntilSettled(tester);
        await tester.tap(find.text(kCharSplitFloorLabel));
        await pumpUntilSettled(tester);
        await tester.tap(find.widgetWithText(FilledButton, 'Προσθήκη'));
        await tester.runAsync(() async {
          for (var i = 0; i < 40; i++) {
            if (find.text(_kNewDepartmentFormTitle).evaluate().isEmpty) {
              return;
            }
            await Future<void>.delayed(const Duration(milliseconds: 50));
            await tester.pump(const Duration(milliseconds: 50));
          }
        });

        expect(find.text(_kNewDepartmentFormTitle), findsNothing);

        final row = await tester.runAsync(() async {
          final db = await DatabaseHelper.instance.database;
          final rows = await db.query(
            'departments',
            where: 'name = ?',
            whereArgs: [kCharSplitDeptName],
            limit: 1,
          );
          return rows.isEmpty ? null : rows.first;
        });
        expect(row?['name'], kCharSplitDeptName);
        expect(row?['floor_id'], floorId);
        expect(row?['is_deleted'], 0);
      },
    );
  });

  group('Φόρμα τμήματος — άδειασμα πεδίων', () {
    late int deptId;
    const deptName = 'Παθολογική';

    setUp(() async {
      final db = await DatabaseHelper.instance.database;
      await db.delete('user_equipment');
      await db.delete('user_phones');
      await db.delete('department_phones');
      await db.delete('phones');
      await db.delete('equipment');
      await db.delete('users');
      await db.delete('departments');

      // Το τμήμα ξεκινά με κτίριο και σημειώσεις, ώστε το άδειασμα να έχει
      // κάτι να καθαρίσει.
      deptId = await db.insert('departments', {
        'name': deptName,
        'name_key': SearchTextNormalizer.normalizeForSearch(deptName),
        'color': '#1976D2',
        'building': 'Κτίριο Α',
        'notes': 'Παλιές σημειώσεις',
        'is_deleted': 0,
      });
      LookupService.instance.resetForReload();
      await LookupService.instance.loadFromDatabase();
    });

    // Το Κτίριο δεν αδειάζει πια από τη φόρμα: είναι κλειστή λίστα χωρίς
    // «κανένα». Το άδειασμα γίνεται ρητά, από τη διαγραφή του κτιρίου στον
    // κατάλογο (Διάφορα → Τμήματα) — και το φυλάει το
    // test/features/directory/building_catalog_test.dart.
    testWidgets('επεξεργασία: το άδειασμα Σημειώσεων γράφεται στη βάση', (
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

      late DepartmentDirectoryNotifier notifier;
      await tester.runAsync(() async {
        await container.read(lookupServiceProvider.future);
        notifier = container.read(departmentDirectoryProvider.notifier);
        await notifier.loadDepartments();
        await _warmBuildingCatalog(container);
        await _warmBuildingCatalog(container);
        await _openDepartmentFormInDialog(
          tester,
          container,
          initialDepartment: DepartmentModel(
            id: deptId,
            name: deptName,
            color: '#1976D2',
            building: 'Κτίριο Α',
            notes: 'Παλιές σημειώσεις',
          ),
          notifier: notifier,
        );
      });

      expect(find.text(_kDepartmentFormTitle), findsOneWidget);

      await tester.enterText(_fieldByLabel('Σημειώσεις'), '');
      await pumpUntilSettled(tester);

      final saveButton = find.widgetWithText(FilledButton, 'Αποθήκευση');
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await pumpUntilSettled(tester);
      await _pumpUntilDepartmentSaveCompletes(tester);

      final row = await tester.runAsync(() async {
        final db = await DatabaseHelper.instance.database;
        final rows = await db.query(
          'departments',
          columns: ['building', 'notes'],
          where: 'id = ?',
          whereArgs: [deptId],
          limit: 1,
        );
        return rows.single;
      });
      expect(
        (row!['building'] as String?) ?? '',
        'Κτίριο Α',
        reason: greekExpectMsg(
          'Το Κτίριο μένει ως έχει — η φόρμα δεν το αδειάζει',
        ),
      );
      expect(
        (row['notes'] as String?) ?? '',
        isEmpty,
        reason: greekExpectMsg('Το άδειασμα των Σημειώσεων γράφεται στη βάση'),
      );
    });
  });

  group('Φόρμα τμήματος — αναγνωριστικά Lansweeper', () {
    late int deptId;
    const deptName = 'Βιοχημικό';

    setUp(() async {
      final db = await DatabaseHelper.instance.database;
      await db.delete('user_equipment');
      await db.delete('user_phones');
      await db.delete('department_phones');
      await db.delete('phones');
      await db.delete('equipment');
      await db.delete('users');
      await db.delete('departments');

      deptId = await db.insert('departments', {
        'name': deptName,
        'name_key': SearchTextNormalizer.normalizeForSearch(deptName),
        'color': '#1976D2',
        'is_deleted': 0,
      });
      LookupService.instance.resetForReload();
      await LookupService.instance.loadFromDatabase();
    });

    Future<String?> storedAccounts() async {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query(
        'departments',
        columns: ['lansweeper_usernames'],
        where: 'id = ?',
        whereArgs: [deptId],
        limit: 1,
      );
      return rows.single['lansweeper_usernames'] as String?;
    }

    testWidgets(
      'δύο λογαριασμοί με ονομασία γράφονται στη βάση και ξαναδιαβάζονται',
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

        late DepartmentDirectoryNotifier notifier;
        await tester.runAsync(() async {
          await container.read(lookupServiceProvider.future);
          notifier = container.read(departmentDirectoryProvider.notifier);
          await notifier.loadDepartments();
          await _warmBuildingCatalog(container);
          await _warmBuildingCatalog(container);
          await _openDepartmentFormInDialog(
            tester,
            container,
            initialDepartment: DepartmentModel(
              id: deptId,
              name: deptName,
              color: '#1976D2',
            ),
            notifier: notifier,
          );
        });

        final accountsField = _fieldByLabel(
          'Αναγνωριστικά Lansweeper (με κόμμα)',
        );
        await tester.ensureVisible(accountsField);
        await pumpUntilSettled(tester);
        await tester.enterText(
          accountsField,
          r'Υπάλληλος #1 = gnk\bio1, Υπάλληλος #2 = gnk\bio2',
        );
        await pumpUntilSettled(tester);

        final saveButton = find.widgetWithText(FilledButton, 'Αποθήκευση');
        await tester.ensureVisible(saveButton);
        await tester.tap(saveButton);
        await pumpUntilSettled(tester);
        await _pumpUntilDepartmentSaveCompletes(tester);

        final stored = await tester.runAsync(storedAccounts);
        final accounts = decodeLansweeperAccounts(stored);
        expect(
          accounts.map((a) => a.username),
          [r'gnk\bio1', r'gnk\bio2'],
          reason: greekExpectMsg(
            'Στο Lansweeper φεύγουν τα αναγνωριστικά, όχι οι ονομασίες',
          ),
        );
        expect(accounts.map((a) => a.label), [
          'Υπάλληλος #1',
          'Υπάλληλος #2',
        ], reason: greekExpectMsg('Οι ονομασίες μένουν για τον επιλογέα'));
      },
    );

    testWidgets(
      'κλικ στο chip: ο λογαριασμός επιστρέφει στο πεδίο για επεξεργασία '
      'και ό,τι μισογραμμένο κατοχυρώνεται πρώτα',
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

        late DepartmentDirectoryNotifier notifier;
        await tester.runAsync(() async {
          await container.read(lookupServiceProvider.future);
          notifier = container.read(departmentDirectoryProvider.notifier);
          await notifier.loadDepartments();
          await _warmBuildingCatalog(container);
          await _warmBuildingCatalog(container);
          await _openDepartmentFormInDialog(
            tester,
            container,
            initialDepartment: DepartmentModel(
              id: deptId,
              name: deptName,
              color: '#1976D2',
              lansweeperUsernames: r'Γραφείο Λοιμώξεων = gnk\loimokseis1',
            ),
            notifier: notifier,
          );
        });

        final chip = find.byKey(
          const ValueKey(r'lansweeper_account_gnk\loimokseis1'),
        );
        expect(chip, findsOneWidget);

        // Μισογραμμένος δεύτερος λογαριασμός στο πεδίο — δεν πρέπει να χαθεί.
        final accountsField = _fieldByLabel(
          'Αναγνωριστικά Lansweeper (με κόμμα)',
        );
        await tester.ensureVisible(accountsField);
        await pumpUntilSettled(tester);
        await tester.enterText(accountsField, r'gnk\extra1');

        await tester.ensureVisible(chip);
        await pumpUntilSettled(tester);
        await tester.tap(chip);
        await pumpUntilSettled(tester);

        // Το chip του λογαριασμού έφυγε και το κείμενό του γύρισε στο πεδίο.
        expect(chip, findsNothing);
        final field = tester.widget<EditableText>(accountsField);
        expect(
          field.controller.text,
          r'Γραφείο Λοιμώξεων = gnk\loimokseis1',
          reason: greekExpectMsg(
            'Η επεξεργασία δεν ξεκινά από το μηδέν — το πλήρες κείμενο '
            'επιστρέφει στο πεδίο',
          ),
        );
        // Ο μισογραμμένος έγινε chip πριν την επεξεργασία — δεν σβήστηκε.
        expect(
          find.byKey(const ValueKey(r'lansweeper_account_gnk\extra1')),
          findsOneWidget,
          reason: greekExpectMsg(
            'Ό,τι υπήρχε στο πεδίο κατοχυρώνεται ως λογαριασμός πριν '
            'αντικατασταθεί από το κείμενο του chip',
          ),
        );
      },
    );

    testWidgets(
      'ξεχασμένο «=»: το αναγνωριστικό ξεχωρίζει μόνο του από την ονομασία',
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

        late DepartmentDirectoryNotifier notifier;
        await tester.runAsync(() async {
          await container.read(lookupServiceProvider.future);
          notifier = container.read(departmentDirectoryProvider.notifier);
          await notifier.loadDepartments();
          await _warmBuildingCatalog(container);
          await _warmBuildingCatalog(container);
          await _openDepartmentFormInDialog(
            tester,
            container,
            initialDepartment: DepartmentModel(
              id: deptId,
              name: deptName,
              color: '#1976D2',
            ),
            notifier: notifier,
          );
        });

        final accountsField = _fieldByLabel(
          'Αναγνωριστικά Lansweeper (με κόμμα)',
        );
        await tester.ensureVisible(accountsField);
        await pumpUntilSettled(tester);
        await tester.enterText(
          accountsField,
          r'Γραφείο Λοιμώξεων gnk\loimokseis1',
        );
        await pumpUntilSettled(tester);

        final saveButton = find.widgetWithText(FilledButton, 'Αποθήκευση');
        await tester.ensureVisible(saveButton);
        await tester.tap(saveButton);
        await pumpUntilSettled(tester);
        await _pumpUntilDepartmentSaveCompletes(tester);

        final stored = await tester.runAsync(storedAccounts);
        final accounts = decodeLansweeperAccounts(stored);
        expect(
          accounts.single.username,
          r'gnk\loimokseis1',
          reason: greekExpectMsg(
            'Στο Lansweeper φεύγει μόνο ο λογαριασμός, χωρίς την ονομασία',
          ),
        );
        expect(accounts.single.label, 'Γραφείο Λοιμώξεων');
      },
    );

    testWidgets('αναγνωριστικό που δεν στέκει: εμφανίζεται προειδοποίηση', (
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

      late DepartmentDirectoryNotifier notifier;
      await tester.runAsync(() async {
        await container.read(lookupServiceProvider.future);
        notifier = container.read(departmentDirectoryProvider.notifier);
        await notifier.loadDepartments();
        await _warmBuildingCatalog(container);
        await _warmBuildingCatalog(container);
        await _openDepartmentFormInDialog(
          tester,
          container,
          initialDepartment: DepartmentModel(
            id: deptId,
            name: deptName,
            color: '#1976D2',
          ),
          notifier: notifier,
        );
      });

      final accountsField = _fieldByLabel(
        'Αναγνωριστικά Lansweeper (με κόμμα)',
      );
      await tester.ensureVisible(accountsField);
      await pumpUntilSettled(tester);
      await tester.enterText(accountsField, 'Γραφείο Λοιμώξεων,');
      await pumpUntilSettled(tester);

      // Η προειδοποίηση ζει πλέον ΠΑΝΩ στο chip: το στοχευμένο λάθος
      // βρίσκεται στο tooltip του, όχι σε συγκεντρωτικό κείμενο από κάτω.
      final chip = find.byKey(
        const ValueKey('lansweeper_account_Γραφείο Λοιμώξεων'),
      );
      expect(chip, findsOneWidget);
      final tooltip = tester.widget<Tooltip>(
        find.descendant(of: chip, matching: find.byType(Tooltip)).first,
      );
      expect(
        tooltip.message,
        contains('Δεν μοιάζει ούτε με'),
        reason: greekExpectMsg(
          'Ονομασία χωρίς αναγνωριστικό προειδοποιεί πριν την αποθήκευση — '
          'με το στοχευμένο λάθος στο tooltip του chip',
        ),
      );
    });

    testWidgets('το σβήσιμο όλων των λογαριασμών γράφεται στη βάση', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.runAsync(() async {
        final db = await DatabaseHelper.instance.database;
        await db.update(
          'departments',
          {'lansweeper_usernames': r'[{"username":"gnk\\bio1"}]'},
          where: 'id = ?',
          whereArgs: [deptId],
        );
        LookupService.instance.resetForReload();
        await LookupService.instance.loadFromDatabase();
      });

      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      addTearDown(container.dispose);

      late DepartmentDirectoryNotifier notifier;
      await tester.runAsync(() async {
        await container.read(lookupServiceProvider.future);
        notifier = container.read(departmentDirectoryProvider.notifier);
        await notifier.loadDepartments();
        await _warmBuildingCatalog(container);
        await _warmBuildingCatalog(container);
        await _openDepartmentFormInDialog(
          tester,
          container,
          initialDepartment: DepartmentModel(
            id: deptId,
            name: deptName,
            color: '#1976D2',
            lansweeperUsernames: r'[{"username":"gnk\\bio1"}]',
          ),
          notifier: notifier,
        );
      });

      final removeChip = find.byIcon(Icons.cancel).first;
      await tester.ensureVisible(removeChip);
      await pumpUntilSettled(tester);
      await tester.tap(removeChip);
      await pumpUntilSettled(tester);

      final saveButton = find.widgetWithText(FilledButton, 'Αποθήκευση');
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await pumpUntilSettled(tester);
      await _pumpUntilDepartmentSaveCompletes(tester);

      final stored = await tester.runAsync(storedAccounts);
      expect(
        decodeLansweeperAccounts(stored),
        isEmpty,
        reason: greekExpectMsg('Το άδειασμα φτάνει στη βάση'),
      );
    });
  });

  group('Φόρμα τμήματος — map_hidden', () {
    late int deptId;

    setUp(() async {
      final db = await DatabaseHelper.instance.database;
      await db.delete('user_equipment');
      await db.delete('user_phones');
      await db.delete('department_phones');
      await db.delete('phones');
      await db.delete('equipment');
      await db.delete('users');
      await db.delete('departments');

      const deptName = 'Κρυφό Τμήμα';
      deptId = await db.insert('departments', {
        'name': deptName,
        'name_key': SearchTextNormalizer.normalizeForSearch(deptName),
        'color': '#1976D2',
        'is_deleted': 0,
        'map_hidden': 1,
      });
      await _seedBuildingCatalog(['Καινούριο']);
      LookupService.instance.resetForReload();
      await LookupService.instance.loadFromDatabase();
    });

    //   flutter test test/features/directory/screens/widgets/department_form_dialog_test.dart --plain-name "map_hidden"
    testWidgets(
      'αποθήκευση διατηρεί map_hidden=1 όταν το τμήμα είναι κρυφό στον χάρτη',
      (tester) async {
        const deptName = 'Κρυφό Τμήμα';
        final container = ProviderContainer(
          overrides: callLoggerTestProviderOverrides(),
        );
        addTearDown(container.dispose);

        late DepartmentDirectoryNotifier notifier;
        await tester.runAsync(() async {
          await container.read(lookupServiceProvider.future);
          notifier = container.read(departmentDirectoryProvider.notifier);
          await notifier.loadDepartments();
          await _warmBuildingCatalog(container);
          await _warmBuildingCatalog(container);
          await _openDepartmentFormInDialog(
            tester,
            container,
            initialDepartment: DepartmentModel(
              id: deptId,
              name: deptName,
              color: '#1976D2',
              isHiddenOnMap: true,
            ),
            notifier: notifier,
          );
        });

        await _selectBuilding(tester, 'Καινούριο');

        final saveButton = find.widgetWithText(FilledButton, 'Αποθήκευση');
        await tester.ensureVisible(saveButton);
        expect(
          tester.widget<FilledButton>(saveButton).onPressed,
          isNotNull,
          reason: greekExpectMsg(
            'Το κουμπί αποθήκευσης πρέπει να είναι ενεργό',
          ),
        );
        await tester.tap(saveButton);
        await pumpUntilSettled(tester);
        await _pumpUntilDepartmentSaveCompletes(tester);

        final mapHidden = await tester.runAsync(() async {
          final db = await DatabaseHelper.instance.database;
          final rows = await db.query(
            'departments',
            columns: ['map_hidden'],
            where: 'id = ?',
            whereArgs: [deptId],
            limit: 1,
          );
          return rows.single['map_hidden'];
        });
        expect(
          mapHidden,
          1,
          reason: greekExpectMsg(
            'Η αποθήκευση φόρμας δεν πρέπει να μηδενίζει το map_hidden',
          ),
        );
      },
    );
  });

  group('Φόρμα τμήματος — είδος', () {
    setUp(() async {
      final db = await DatabaseHelper.instance.database;
      await db.delete('user_equipment');
      await db.delete('user_phones');
      await db.delete('department_phones');
      await db.delete('phones');
      await db.delete('equipment');
      await db.delete('users');
      await db.delete('departments');
      await _seedBuildingCatalog(['Καινούριο']);
      LookupService.instance.resetForReload();
      await LookupService.instance.loadFromDatabase();
    });

    Future<Object?> storedKind(WidgetTester tester, String name) {
      return tester.runAsync<Object?>(() async {
        final db = await DatabaseHelper.instance.database;
        final rows = await db.query(
          'departments',
          columns: ['kind'],
          where: 'name = ?',
          whereArgs: [name],
          limit: 1,
        );
        return rows.isEmpty ? null : rows.first['kind'];
      });
    }

    // Ο τίτλος της φόρμας ακολουθεί το είδος («Νέο τμήμα» / «Νέα εταιρεία»),
    // οπότε η αναμονή πρέπει να κοιτά τον τίτλο που ΟΝΤΩΣ δείχνει η οθόνη —
    // αλλιώς θα «τελείωνε» πριν καν ξεκινήσει η αποθήκευση.
    Future<void> submitNewDepartment(
      WidgetTester tester, {
      String formTitle = _kNewDepartmentFormTitle,
    }) async {
      expect(find.text(formTitle), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Προσθήκη'));
      await tester.runAsync(() async {
        for (var i = 0; i < 40; i++) {
          if (find.text(formTitle).evaluate().isEmpty) return;
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump(const Duration(milliseconds: 50));
        }
      });
      expect(find.text(formTitle), findsNothing);
    }

    Future<void> openNewForm(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      late DepartmentDirectoryNotifier notifier;
      await tester.runAsync(() async {
        await container.read(lookupServiceProvider.future);
        notifier = container.read(departmentDirectoryProvider.notifier);
        await notifier.loadDepartments();
        await _warmBuildingCatalog(container);
        await _warmBuildingCatalog(container);
        await _openDepartmentFormInDialog(
          tester,
          container,
          notifier: notifier,
        );
      });
      await tester.runAsync(() async {
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump(const Duration(milliseconds: 50));
        }
      });
      await pumpUntilSettledLong(tester);
    }

    //   flutter test test/features/directory/screens/widgets/department_form_dialog_test.dart --plain-name "είδος"
    testWidgets('νέο τμήμα αποθηκεύεται ως Νοσοκομείο χωρίς καμία επιλογή', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      addTearDown(container.dispose);
      await openNewForm(tester, container);

      await tester.enterText(_departmentNameField(), 'Ακτινολογικό');
      await pumpUntilSettled(tester);
      await submitNewDepartment(tester);

      expect(
        await storedKind(tester, 'Ακτινολογικό'),
        'hospital',
        reason: greekExpectMsg(
          'Η προεπιλογή κρατά γρήγορη την καταχώρηση τμήματος νοσοκομείου',
        ),
      );
    });

    // Η ενότητα «Κοινόχρηστος εξοπλισμός» φεύγει από την οθόνη όταν το Είδος
    // δεν επιτρέπει κατοχή — αλλά η λίστα γραφόταν στη βάση όπως ήταν, και η
    // εταιρεία έμενε σιωπηλά χρεωμένη με μηχανήματα που κανείς δεν έβλεπε.
    //   flutter test test/features/directory/screens/widgets/department_form_dialog_test.dart --plain-name "είδος"
    testWidgets(
      'αλλαγή σε «Εταιρεία» ρωτά πού πάει ο κοινόχρηστος εξοπλισμός',
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

        late int deptId;
        await tester.runAsync(() async {
          final db = await DatabaseHelper.instance.database;
          deptId = await db.insert('departments', {
            'name': 'Ακτινολογικό',
            'name_key': SearchTextNormalizer.normalizeForSearch('Ακτινολογικό'),
            'color': '#33691F',
            'is_deleted': 0,
          });
          // Μηχάνημα του τμήματος, χωρίς κανέναν κάτοχο: αν φύγει από εδώ και
          // δεν ρωτηθεί κανείς, μένει ορφανό.
          await db.insert('equipment', {
            'code_equipment': '25067',
            'department_id': deptId,
            'is_deleted': 0,
          });
          LookupService.instance.resetForReload();
          await LookupService.instance.loadFromDatabase();
        });

        late DepartmentDirectoryNotifier notifier;
        await tester.runAsync(() async {
          await container.read(lookupServiceProvider.future);
          notifier = container.read(departmentDirectoryProvider.notifier);
          await notifier.loadDepartments();
          await _openDepartmentFormInDialog(
            tester,
            container,
            initialDepartment: DepartmentModel(
              id: deptId,
              name: 'Ακτινολογικό',
              color: '#33691F',
            ),
            notifier: notifier,
          );
        });
        await pumpUntilSettledLong(tester);

        expect(
          find.widgetWithText(InputChip, '25067'),
          findsOneWidget,
          reason: greekExpectMsg(
            'Το τμήμα ξεκινά με το μηχάνημα ως κοινόχρηστο',
          ),
        );

        final kindField = find.byType(DropdownButtonFormField<DepartmentKind>);
        await tester.ensureVisible(kindField);
        await pumpUntilSettled(tester);
        await tester.tap(kindField);
        await pumpUntilSettledLong(tester);
        await tester.tap(find.text('Εταιρεία').last);
        await pumpUntilSettledLong(tester);

        expect(
          find.widgetWithText(InputChip, '25067'),
          findsNothing,
          reason: greekExpectMsg(
            'Η ενότητα κοινόχρηστου εξοπλισμού φεύγει από την οθόνη',
          ),
        );

        final saveButton = find.widgetWithText(FilledButton, 'Αποθήκευση');
        await tester.ensureVisible(saveButton);
        await tester.tap(saveButton);
        // Πραγματικός χρόνος: η αποθήκευση αγγίζει τη βάση. Σταματά μόλις
        // εμφανιστεί η ερώτηση — ή μόλις κλείσει η φόρμα (ο τίτλος της
        // ακολουθεί το Είδος), που σημαίνει ότι γράφτηκε σιωπηλά.
        await tester.runAsync(() async {
          for (var i = 0; i < 60; i++) {
            final asked = find
                .text('Αποδέσμευση κοινόχρηστου εξοπλισμού')
                .evaluate()
                .isNotEmpty;
            final formOpen =
                find.text(_kDepartmentFormTitle).evaluate().isNotEmpty ||
                find.text('Επεξεργασία εταιρείας').evaluate().isNotEmpty;
            if (asked || !formOpen) return;
            await Future<void>.delayed(const Duration(milliseconds: 50));
            await tester.pump(const Duration(milliseconds: 50));
          }
        });
        await tester.pump();
        // Πριν από τον έλεγχο: μια αποτυχία δεν πρέπει να αφήσει εκκρεμείς
        // χρονιστές του sqflite και να κρεμάσει τη σουίτα αντί να κοκκινίσει.
        await flushCallLoggerSqfliteLockTimers(tester);

        expect(
          find.text('Αποδέσμευση κοινόχρηστου εξοπλισμού'),
          findsOneWidget,
          reason: greekExpectMsg(
            'Ό,τι κρύβει το Είδος δεν αποθηκεύεται σιωπηλά: ο χρήστης ρωτιέται '
            'πού πάει το μηχάνημα, από την ίδια πύλη με κάθε άλλη αφαίρεση',
          ),
        );

        await flushCallLoggerSqfliteLockTimers(tester);
      },
    );

    // Ο εξοπλισμός μπορεί να μην είναι κοινόχρηστος του τμήματος αλλά χρεωμένος
    // σε ΥΠΑΛΛΗΛΟ του. Η μετατροπή σε εταιρεία τον άφηνε χρεωμένο σε πρόσωπο
    // που πλέον δηλώνεται εξωτερικός συνεργάτης.
    //   flutter test test/features/directory/screens/widgets/department_form_dialog_test.dart --plain-name "είδος"
    testWidgets(
      'αλλαγή σε «Εταιρεία» ρωτά και για τον εξοπλισμό των υπαλλήλων',
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

        late int deptId;
        await tester.runAsync(() async {
          final db = await DatabaseHelper.instance.database;
          deptId = await db.insert('departments', {
            'name': 'Αναισθησιολογικό',
            'name_key': SearchTextNormalizer.normalizeForSearch(
              'Αναισθησιολογικό',
            ),
            'color': '#33691F',
            'is_deleted': 0,
          });
          final userId = await db.insert('users', {
            'first_name': 'Μαρία',
            'last_name': 'Ορφανού',
            'department_id': deptId,
            'is_deleted': 0,
          });
          // Χρεωμένο στο πρόσωπο, χωρίς τμήμα δικό του: το τμήμα δεν το
          // «κατέχει», ο υπάλληλός του το κρατά.
          final equipmentId = await db.insert('equipment', {
            'code_equipment': '3731',
            'is_deleted': 0,
          });
          await db.insert('user_equipment', {
            'user_id': userId,
            'equipment_id': equipmentId,
          });
          LookupService.instance.resetForReload();
          await LookupService.instance.loadFromDatabase();
        });

        late DepartmentDirectoryNotifier notifier;
        await tester.runAsync(() async {
          await container.read(lookupServiceProvider.future);
          notifier = container.read(departmentDirectoryProvider.notifier);
          await notifier.loadDepartments();
          await _openDepartmentFormInDialog(
            tester,
            container,
            initialDepartment: DepartmentModel(
              id: deptId,
              name: 'Αναισθησιολογικό',
              color: '#33691F',
            ),
            notifier: notifier,
          );
        });
        await pumpUntilSettledLong(tester);

        final kindField = find.byType(DropdownButtonFormField<DepartmentKind>);
        await tester.ensureVisible(kindField);
        await pumpUntilSettled(tester);
        await tester.tap(kindField);
        await pumpUntilSettledLong(tester);
        await tester.tap(find.text('Εταιρεία').last);
        await pumpUntilSettledLong(tester);

        final saveButton = find.widgetWithText(FilledButton, 'Αποθήκευση');
        await tester.ensureVisible(saveButton);
        await tester.tap(saveButton);
        await tester.runAsync(() async {
          for (var i = 0; i < 60; i++) {
            final asked = find
                .text('Αποδέσμευση προσωπικού εξοπλισμού')
                .evaluate()
                .isNotEmpty;
            final formOpen =
                find.text(_kDepartmentFormTitle).evaluate().isNotEmpty ||
                find.text('Επεξεργασία εταιρείας').evaluate().isNotEmpty;
            if (asked || !formOpen) return;
            await Future<void>.delayed(const Duration(milliseconds: 50));
            await tester.pump(const Duration(milliseconds: 50));
          }
        });
        await tester.pump();
        await flushCallLoggerSqfliteLockTimers(tester);

        expect(
          find.text('Αποδέσμευση προσωπικού εξοπλισμού'),
          findsOneWidget,
          reason: greekExpectMsg(
            'Ο εξοπλισμός του υπαλλήλου δεν μένει σιωπηλά χρεωμένος σε '
            'πρόσωπο εταιρείας — ο χρήστης ρωτιέται πού πάει',
          ),
        );

        await flushCallLoggerSqfliteLockTimers(tester);
      },
    );

    //   flutter test test/features/directory/screens/widgets/department_form_dialog_test.dart --plain-name "είδος"
    testWidgets('επιλογή «Εταιρεία» φτάνει στη βάση', (tester) async {
      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      addTearDown(container.dispose);
      await openNewForm(tester, container);

      await tester.enterText(_departmentNameField(), 'DataMed');
      await pumpUntilSettled(tester);

      final kindField = find.byType(DropdownButtonFormField<DepartmentKind>);
      expect(kindField, findsOneWidget);
      await tester.ensureVisible(kindField);
      await pumpUntilSettled(tester);
      await tester.tap(kindField);
      await pumpUntilSettledLong(tester);
      await tester.tap(find.text('Εταιρεία').last);
      await pumpUntilSettledLong(tester);

      expect(
        _buildingDropdown(),
        findsNothing,
        reason: greekExpectMsg(
          'Η εταιρεία δεν βρίσκεται σε κτίριο του νοσοκομείου',
        ),
      );

      await submitNewDepartment(tester, formTitle: 'Νέα εταιρεία');

      expect(
        await storedKind(tester, 'DataMed'),
        'company',
        reason: greekExpectMsg('Η εταιρεία πρέπει να αποθηκεύεται ως εταιρεία'),
      );
    });

    // Η δημιουργία τμήματος ξανάχτιζε το μοντέλο πεδίο-πεδίο και ξεχνούσε ό,τι
    // δεν ήταν στη λίστα — τα αναγνωριστικά Lansweeper χάνονταν σιωπηλά.
    //   flutter test test/features/directory/screens/widgets/department_form_dialog_test.dart --plain-name "είδος"
    testWidgets('νέο τμήμα κρατά τα αναγνωριστικά Lansweeper του', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      addTearDown(container.dispose);
      await openNewForm(tester, container);

      await tester.enterText(_departmentNameField(), 'Παθολογική');
      await pumpUntilSettled(tester);
      final accountsField = _fieldByLabel(
        'Αναγνωριστικά Lansweeper (με κόμμα)',
      );
      await tester.ensureVisible(accountsField);
      await tester.enterText(accountsField, r'gnk\docpath1');
      await pumpUntilSettled(tester);

      await submitNewDepartment(tester);

      final stored = await tester.runAsync<Object?>(() async {
        final db = await DatabaseHelper.instance.database;
        final rows = await db.query(
          'departments',
          columns: ['lansweeper_usernames'],
          where: 'name = ?',
          whereArgs: ['Παθολογική'],
          limit: 1,
        );
        return rows.isEmpty ? null : rows.first['lansweeper_usernames'];
      });
      expect(
        decodeLansweeperAccounts(stored as String?).map((a) => a.username),
        [r'gnk\docpath1'],
        reason: greekExpectMsg(
          'Ό,τι γράφτηκε στη φόρμα πρέπει να φτάνει στη βάση και στο νέο τμήμα',
        ),
      );
    });
  });
}
