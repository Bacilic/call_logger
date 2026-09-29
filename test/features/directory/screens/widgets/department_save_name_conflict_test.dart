// Δίχτυ συμπεριφοράς για το ΤΕΛΟΣ της αποθήκευσης τμήματος: τι γίνεται όταν το
// όνομα υπάρχει ήδη — ζωντανό ή διαγραμμένο.
//
//   flutter test test/features/directory/screens/widgets/department_save_name_conflict_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/directory/providers/department_directory_provider.dart';
import 'package:call_logger/features/directory/screens/widgets/department_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../test_setup.dart';

const _kExistingName = 'Μαγειρείο';
const _kFormTitle = 'Νέο τμήμα';

Finder _fieldByLabel(String label) => find.descendant(
  of: find.byWidgetPredicate(
    (w) => w is InputDecorator && w.decoration.labelText == label,
  ),
  matching: find.byType(EditableText),
);

/// Καθαρή αφετηρία με **ένα** τμήμα, ζωντανό ή διαγραμμένο.
Future<int> _seedDepartment({required bool deleted}) async {
  final db = await DatabaseHelper.instance.database;
  await db.delete('department_phones');
  await db.delete('departments');
  final id = await db.insert('departments', {
    'name': _kExistingName,
    'name_key': SearchTextNormalizer.normalizeForSearch(_kExistingName),
    'color': '#1976D2',
    'building': 'Κτίριο Α',
    'notes': 'Παλιές σημειώσεις',
    'is_deleted': deleted ? 1 : 0,
  });
  LookupService.instance.resetForReload();
  await LookupService.instance.loadFromDatabase();
  return id;
}

Future<Map<String, Object?>> _readDepartment(int id) async {
  final db = await DatabaseHelper.instance.database;
  final rows = await db.query('departments', where: 'id = ?', whereArgs: [id]);
  return rows.single;
}

Future<int> _countDepartments() async {
  final db = await DatabaseHelper.instance.database;
  return (await db.query('departments')).length;
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  /// Ανοίγει τη φόρμα **νέου** τμήματος και γράφει το όνομα που συγκρούεται.
  Future<void> openNewFormWithConflictingName(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    late DepartmentDirectoryNotifier notifier;
    await tester.runAsync(() async {
      await container.read(lookupServiceProvider.future);
      notifier = container.read(departmentDirectoryProvider.notifier);
      await notifier.loadDepartments();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(body: DepartmentFormDialog(notifier: notifier)),
          ),
        ),
      );
      await tester.pump();
    });
    await pumpUntilSettledLong(tester);

    await tester.enterText(_fieldByLabel('Όνομα'), _kExistingName);
    await pumpUntilSettledLong(tester);
  }

  /// Περιμένει να **εμφανιστεί** κάτι, με πραγματικό χρόνο.
  ///
  /// Η αποθήκευση γράφει σε αληθινή βάση SQLite: το σκέτο pump δουλεύει με
  /// εικονικό ρολόι και επιστρέφει πριν προλάβει το I/O. Ο υπάρχων βοηθός
  /// περιμένει να ΚΛΕΙΣΕΙ διάλογος — εδώ χρησιμοποιείται αντίστροφα:
  /// «όσο δεν έχει φανεί, συνέχισε να περιμένεις».
  Future<void> pumpUntilAppears(
    WidgetTester tester,
    Finder finder,
    String what,
  ) {
    return pumpUntilDialogCloses(
      tester,
      isOpen: () => finder.evaluate().isEmpty,
      failMessage: 'Δεν εμφανίστηκε: $what',
    );
  }

  /// Στη φόρμα **νέου** τμήματος το κουμπί λέει «Προσθήκη» — το «Αποθήκευση»
  /// υπάρχει μόνο στην επεξεργασία.
  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Προσθήκη'));
    await pumpUntilSettledLong(tester);
  }

  group('Αποθήκευση τμήματος — το όνομα υπάρχει ΖΩΝΤΑΝΟ', () {
    setUp(() => _seedDepartment(deleted: false));

    testWidgets('ο χρήστης ειδοποιείται αντί να γίνει σιωπηλά τίποτα', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      addTearDown(container.dispose);

      await openNewFormWithConflictingName(tester, container);
      await tapSave(tester);
      await pumpUntilAppears(
        tester,
        find.text('Όνομα σε χρήση'),
        'ο διάλογος «Όνομα σε χρήση»',
      );

      expect(find.text('Όνομα σε χρήση'), findsOneWidget);
    });

    testWidgets('δεν δημιουργείται δεύτερη καρτέλα με το ίδιο όνομα', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      addTearDown(container.dispose);

      await openNewFormWithConflictingName(tester, container);
      await tapSave(tester);
      await pumpUntilAppears(tester, find.text('Όνομα σε χρήση'), 'ο διάλογος');

      final count = await tester.runAsync(_countDepartments);
      expect(count, 1, reason: 'η σύγκρουση ονόματος δεν γράφει τίποτα');

      // Το κλείδωμα του sqflite αφήνει χρονόμετρο ~10΄΄ στο εικονικό ρολόι· χωρίς
      // ξεπέρασμα, ο έλεγχος κοκκινίζει για λόγο άσχετο με τη συμπεριφορά.
      await tester.tap(find.widgetWithText(TextButton, 'OK'));
      await pumpUntilSettledLong(tester);
      await flushCallLoggerSqfliteLockTimers(tester);
    });

    testWidgets('η φόρμα ΜΕΝΕΙ ανοιχτή ώστε να διορθωθεί το όνομα', (
      tester,
    ) async {
      // Αν έκλεινε, ο χρήστης θα έχανε ό,τι πληκτρολόγησε για ένα λάθος που
      // διορθώνεται με μία λέξη.
      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      addTearDown(container.dispose);

      await openNewFormWithConflictingName(tester, container);
      await tapSave(tester);
      await pumpUntilAppears(tester, find.text('Όνομα σε χρήση'), 'ο διάλογος');
      await tester.tap(find.widgetWithText(TextButton, 'OK'));
      await pumpUntilSettledLong(tester);

      expect(find.text(_kFormTitle), findsOneWidget);
    });
  });

  group('Αποθήκευση τμήματος — το όνομα υπάρχει ΔΙΑΓΡΑΜΜΕΝΟ', () {
    late int deptId;
    setUp(() async {
      deptId = await _seedDepartment(deleted: true);
    });

    testWidgets('προσφέρεται επαναφορά αντί για σφάλμα', (tester) async {
      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      addTearDown(container.dispose);

      await openNewFormWithConflictingName(tester, container);
      await tapSave(tester);
      await pumpUntilAppears(
        tester,
        find.text('Επαναφορά'),
        'η προσφορά επαναφοράς',
      );

      expect(find.text('Επαναφορά'), findsOneWidget);
    });

    testWidgets('«Άκυρο» αφήνει την καρτέλα διαγραμμένη', (tester) async {
      // **Το κρίσιμο αναλλοίωτο:** μια ακύρωση δεν αλλάζει τίποτα στη βάση.
      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      addTearDown(container.dispose);

      await openNewFormWithConflictingName(tester, container);
      await tapSave(tester);
      await pumpUntilAppears(tester, find.text('Επαναφορά'), 'η προσφορά');
      await tester.tap(find.widgetWithText(TextButton, 'Άκυρο'));
      await pumpUntilSettledLong(tester);

      final row = await tester.runAsync(() => _readDepartment(deptId));
      expect(row!['is_deleted'], 1);
      expect(
        row['notes'],
        'Παλιές σημειώσεις',
        reason: 'η ακύρωση δεν αγγίζει ούτε τα πεδία',
      );
    });

    testWidgets('«Επαναφορά» ξαναζωντανεύει την ΙΔΙΑ καρτέλα', (tester) async {
      // Ίδιο id: η επαναφορά δεν φτιάχνει δεύτερη εγγραφή, ξυπνά την παλιά —
      // αλλιώς θα χάνονταν όσα κρέμονται πάνω της.
      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      addTearDown(container.dispose);

      await openNewFormWithConflictingName(tester, container);
      await tapSave(tester);
      await pumpUntilAppears(tester, find.text('Επαναφορά'), 'η προσφορά');
      await tester.tap(find.widgetWithText(FilledButton, 'Επαναφορά'));
      await pumpUntilSettledLong(tester);

      final count = await tester.runAsync(_countDepartments);
      expect(count, 1, reason: 'δεν δημιουργήθηκε δεύτερη καρτέλα');

      final row = await tester.runAsync(() => _readDepartment(deptId));
      expect(row!['is_deleted'], 0);
    });
  });
}
