// Μαζική διαγραφή τμημάτων: τι ονομάζει το μήνυμα και τι μένει επιλεγμένο.
//
// Ολόκληρο αρχείο:
//   flutter test test/features/directory/screens/widgets/departments_tab_bulk_deletion_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/models/building_map_floor.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/directory/building_map/providers/building_map_providers.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:call_logger/features/directory/providers/department_directory_provider.dart';
import 'package:call_logger/features/directory/providers/directory_provider.dart';
import 'package:call_logger/features/directory/screens/widgets/departments_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../test_setup.dart';

class _FakeDepartmentDirectoryNotifier extends DepartmentDirectoryNotifier {
  _FakeDepartmentDirectoryNotifier(this._initialState);

  final DepartmentDirectoryState _initialState;

  @override
  DepartmentDirectoryState build() => _initialState;

  @override
  Future<void> loadDepartments() async {}
}

/// Περιμένει συνθήκη που εξαρτάται από πραγματικές αναγνώσεις/εγγραφές βάσης.
///
/// Το `pumpAndSettle` δεν προωθεί πραγματικό I/O — χρειάζεται `runAsync`.
Future<void> _pumpUntilTrue(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 80 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) =>
    _pumpUntilTrue(tester, () => finder.evaluate().isNotEmpty);

/// Στήνει δύο τμήματα, με κοινόχρηστο τηλέφωνο μόνο σε αυτό που ζητείται.
///
/// Το τμήμα με κοινόχρηστο γίνεται **κάρτα** στην προεπισκόπηση (και ζητά
/// απόφαση στη σειριακή ροή)· το άλλο πέφτει στη συμπτυγμένη γραμμή των άδειων.
Future<(int, int)> _seedTwoDepartments(
  WidgetTester tester, {
  required String firstName,
  required String secondName,
  required bool sharedPhoneOnSecond,
}) async {
  late int firstId;
  late int secondId;
  await tester.runAsync(() async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('department_phones');
    await db.delete('phones');
    await db.delete('departments');

    firstId = await db.insert('departments', {
      'name': firstName,
      'name_key': SearchTextNormalizer.normalizeForSearch(firstName),
      'is_deleted': 0,
    });
    secondId = await db.insert('departments', {
      'name': secondName,
      'name_key': SearchTextNormalizer.normalizeForSearch(secondName),
      'is_deleted': 0,
    });
    final phoneId = await db.insert('phones', {
      'number': '2900',
      'is_deleted': 0,
    });
    await db.insert('department_phones', {
      'department_id': sharedPhoneOnSecond ? secondId : firstId,
      'phone_id': phoneId,
    });
  });
  return (firstId, secondId);
}

Widget _hostWith(DepartmentDirectoryState initial) {
  return ProviderScope(
    overrides: [
      ...callLoggerTestProviderOverrides(),
      departmentDirectoryProvider.overrideWith(
        () => _FakeDepartmentDirectoryNotifier(initial),
      ),
      catalogDepartmentsContinuousScrollProvider.overrideWith(
        (ref) async => true,
      ),
      buildingMapFloorsCatalogProvider.overrideWith(
        (ref) async => const <BuildingMapFloor>[],
      ),
    ],
    child: const MaterialApp(home: Scaffold(body: DepartmentsTab())),
  );
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  testWidgets(
    'το μήνυμα ονομάζει μόνο όσα διαγράφηκαν, και τα αφαιρεμένα μένουν '
    'επιλεγμένα',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Κοινόχρηστο τηλέφωνο ΜΟΝΟ στο πρώτο: γίνεται κάρτα με «✕», ενώ το
      // δεύτερο πέφτει στη συμπτυγμένη γραμμή των άδειων.
      final (keptId, deletedId) = await _seedTwoDepartments(
        tester,
        firstName: 'Μένει Επιλεγμένο',
        secondName: 'Φεύγει Τώρα',
        sharedPhoneOnSecond: false,
      );

      final kept = DepartmentModel(id: keptId, name: 'Μένει Επιλεγμένο');
      final deleted = DepartmentModel(id: deletedId, name: 'Φεύγει Τώρα');

      await tester.pumpWidget(
        _hostWith(
          DepartmentDirectoryState(
            allDepartments: [kept, deleted],
            filteredDepartments: [kept, deleted],
            selectedIds: {keptId, deletedId},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Ο provider του lookup μηδενίζει σύγχρονα και φορτώνει ασύγχρονα· χωρίς
      // αναμονή ο διάλογος θα χτιζόταν πάνω σε άδειο ευρετήριο.
      await _pumpUntilTrue(
        tester,
        () => LookupService.instance
            .getDirectPhonesByDepartment(keptId)
            .isNotEmpty,
      );

      await tester.tap(find.text('Διαγραφή'));
      await _pumpUntil(tester, find.byType(AlertDialog));

      // Μόνο η κάρτα του πρώτου έχει «✕» — τα άδεια είναι σε πτυσσόμενη γραμμή.
      final removeButton = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byIcon(Icons.close),
      );
      expect(removeButton, findsOneWidget);
      await tester.tap(removeButton);
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Διαγραφή'),
        ),
      );
      await _pumpUntil(tester, find.byType(SnackBar));

      final snackBar = find.byType(SnackBar);
      expect(snackBar, findsOneWidget);
      expect(
        find.descendant(
          of: snackBar,
          matching: find.textContaining('Φεύγει Τώρα'),
        ),
        findsOneWidget,
      );
      // Το τμήμα που αφαιρέθηκε ΔΕΝ διαγράφηκε — δεν επιτρέπεται να ονομάζεται.
      expect(
        find.descendant(
          of: snackBar,
          matching: find.textContaining('Μένει Επιλεγμένο'),
        ),
        findsNothing,
      );

      // Το «✕» σημαίνει «αυτό αργότερα», όχι «αυτό ποτέ».
      final container = ProviderScope.containerOf(
        tester.element(find.byType(DepartmentsTab)),
      );
      expect(container.read(departmentDirectoryProvider).selectedIds, {keptId});

      await flushCallLoggerSqfliteLockTimers(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'με τη διέξοδο της διακοπής, το μήνυμα ονομάζει μόνο όσα ολοκληρώθηκαν',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Το πρώτο είναι άδειο (ολοκληρώνεται σιωπηλά), το δεύτερο έχει
      // κοινόχρηστο τηλέφωνο και ρωτά — εκεί διακόπτει ο χρήστης.
      final (doneId, abortedId) = await _seedTwoDepartments(
        tester,
        firstName: 'Ολοκληρώθηκε',
        secondName: 'Διακόπηκε',
        sharedPhoneOnSecond: true,
      );

      final done = DepartmentModel(id: doneId, name: 'Ολοκληρώθηκε');
      final aborted = DepartmentModel(id: abortedId, name: 'Διακόπηκε');

      await tester.pumpWidget(
        _hostWith(
          DepartmentDirectoryState(
            allDepartments: [done, aborted],
            filteredDepartments: [done, aborted],
            selectedIds: {doneId, abortedId},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _pumpUntilTrue(
        tester,
        () => LookupService.instance
            .getDirectPhonesByDepartment(abortedId)
            .isNotEmpty,
      );

      await tester.tap(find.text('Διαγραφή'));
      await _pumpUntil(tester, find.byType(AlertDialog));

      await tester.tap(find.text('Αναλυτικά (ανά οντότητα)'));
      await _pumpUntil(tester, find.text('Ακύρωση'));

      // Διακοπή στο δεύτερο τμήμα: το πρώτο έχει ήδη ολοκληρωθεί σιωπηλά.
      await tester.tap(find.text('Ακύρωση'));
      await _pumpUntil(tester, find.text('Διακοπή διαδικασίας;'));

      expect(
        find.textContaining('Ολοκληρώσατε 1 τμήμα από τα 2.'),
        findsOneWidget,
      );
      expect(find.textContaining('θα χαθ'), findsNothing);
      // Η εξήγηση του κουμπιού ανήκει στην υπόδειξή του, όχι στο σώμα.
      expect(find.textContaining('Κλείνει ο οδηγός'), findsNothing);

      await tester.tap(find.text('Εφαρμογή απαντήσεων'));
      await _pumpUntil(tester, find.byType(SnackBar));

      final snackBar = find.byType(SnackBar);
      expect(snackBar, findsOneWidget);
      expect(
        find.descendant(
          of: snackBar,
          matching: find.textContaining('Ολοκληρώθηκε'),
        ),
        findsOneWidget,
      );
      // Το τμήμα όπου διακόπηκε η ροή ΔΕΝ διαγράφηκε — δεν επιτρέπεται να
      // ονομάζεται ως διαγραμμένο.
      expect(
        find.descendant(
          of: snackBar,
          matching: find.textContaining('Διακόπηκε'),
        ),
        findsNothing,
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(DepartmentsTab)),
      );
      expect(container.read(departmentDirectoryProvider).selectedIds, {
        abortedId,
      });

      await flushCallLoggerSqfliteLockTimers(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
