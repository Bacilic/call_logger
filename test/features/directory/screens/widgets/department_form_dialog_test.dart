// Widget test: φόρμα τμήματος — μικτή κατάσταση κοινόχρηστων (σύγκρουση + χωρίς σύγκρουση).
//
// Ολόκληρο αρχείο:
//   flutter test test/features/directory/screens/widgets/department_form_dialog_test.dart
// Σενάριο μικτής σύγκρουσης:
//   flutter test test/features/directory/screens/widgets/department_form_dialog_test.dart --plain-name "μικτή σύγκρουση"

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
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

Finder _buildingField() => _fieldByLabel('Κτίριο');

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
Future<void> _pumpUntilDepartmentSaveCompletes(WidgetTester tester) async {
  const maxAttempts = 40;
  for (var i = 0; i < maxAttempts; i++) {
    final formOpen = find.text(_kDepartmentFormTitle).evaluate().isNotEmpty;
    final conflictOpen =
        find.text(_kConflictDialogTitle).evaluate().isNotEmpty;
    if (!formOpen && !conflictOpen) {
      return;
    }
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump(const Duration(milliseconds: 50));
  }
  fail(
    greekExpectMsg(
      'Η φόρμα τμήματος δεν έκλεισε εγκαίρως μετά την αποθήκευση',
    ),
  );
}

/// Έλεγχος βάσης σε [runAsync]· προαιρετικό polling για αποφυγή race με async SQLite.
Future<List<String>> _readSharedEquipmentWhenReady(
  WidgetTester tester,
  int departmentId,
  List<String> expected,
) async {
  const maxAttempts = 25;
  const pollInterval = Duration(milliseconds: 80);

  final codes = await tester.runAsync(() async {
    List<String> last = const [];
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      last = await _sharedEquipmentCodesInDatabase(departmentId);
      if (_sameEquipmentCodes(last, expected)) {
        return last;
      }
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
  await db.insert('user_phones', {
    'user_id': userId,
    'phone_id': phoneId,
  });
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
        reporter.logStepDone('Διάλογος ανοιχτός — κοινόχρηστο 333 ήδη στη φόρμα');

        reporter.logProgress('Προσθήκη μόνο κοινόχρηστου εξοπλισμού 2001, 2002, 2003');

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

        reporter.logProgress('Αποθήκευση — αναμένεται διάλογος σύγκρουσης μόνο για το 333');

        final saveButton = find.widgetWithText(FilledButton, 'Αποθήκευση');
        await tester.ensureVisible(saveButton);
        expect(
          tester.widget<FilledButton>(saveButton).onPressed,
          isNotNull,
          reason: greekExpectMsg('Κουμπί αποθήκευσης ενεργό μετά την προσθήκη εξοπλισμού'),
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
          reason: greekExpectMsg('Εμφάνιση ιδιοκτήτριας Μαρία Άσχημη στον διάλογο σύγκρουσης'),
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
        reporter.logStepDone('Διάλογος σύγκρουσης μόνο για το 333 (Μαρία Άσχημη)');

        reporter.logProgress('Επιλογή διατήρησης 333 ως κοινόχρηστου τμήματος και επιβεβαίωση');

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

        reporter.logProgress('Έλεγχος βάσης — κοινόχρηστος εξοπλισμός 2001, 2002, 2003');

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

        reporter.logStepDone(
          'Εξοπλισμός στη βάση: ${codes.join(', ')}',
        );
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

        await tester.enterText(_buildingField(), 'Νέο κτίριο');
        await pumpUntilSettled(tester);
        await tester.tap(find.widgetWithText(TextButton, 'Ακύρωση'));
        await pumpUntilSettled(tester);

        expect(find.text(_kDepartmentFormTitle), findsNothing);
        expect(find.textContaining(_kUnsavedChangesPrompt), findsNothing);
      },
    );

    testWidgets(
      'επεξεργασία με αλλαγή: «Επεξεργασία» επιστρέφει στη φόρμα',
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

        await tester.enterText(_buildingField(), 'Νέο κτίριο');
        await pumpUntilSettled(tester);
        await tester.tapAt(const Offset(8, 8));
        await pumpUntilSettled(tester);
        await tester.tap(find.widgetWithText(TextButton, 'Επεξεργασία').last);
        await pumpUntilSettled(tester);

        expect(find.text(_kUnsavedChangesPrompt), findsNothing);
        expect(find.text(_kDepartmentFormTitle), findsOneWidget);
        expect(find.textContaining('Νέο κτίριο'), findsOneWidget);
      },
    );

    testWidgets(
      'επεξεργασία με αλλαγή: «Ακύρωση Αλλαγών» κλείνει τη φόρμα',
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

        await tester.enterText(_buildingField(), 'Νέο κτίριο');
        await pumpUntilSettled(tester);
        await tester.tapAt(const Offset(8, 8));
        await pumpUntilSettled(tester);
        await tester.tap(find.widgetWithText(FilledButton, 'Ακύρωση Αλλαγών'));
        await pumpUntilSettled(tester);

        expect(find.text(_kDepartmentFormTitle), findsNothing);
      },
    );

    testWidgets(
      'νέο τμήμα χωρίς όνομα: ακύρωση κλείνει χωρίς επιβεβαίωση',
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
      },
    );

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

    testWidgets(
      'νέο τμήμα με όνομα: κλικ εκτός εμφανίζει προειδοποίηση',
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
      },
    );

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

        await tester.enterText(_buildingField(), 'Barrier test');
        await pumpUntilSettled(tester);
        await tester.tapAt(const Offset(8, 8));
        await pumpUntilSettled(tester);

        expect(find.textContaining('- Κτίριο'), findsOneWidget);
        expect(find.text(_kDepartmentFormTitle), findsOneWidget);
      },
    );
  });
}
