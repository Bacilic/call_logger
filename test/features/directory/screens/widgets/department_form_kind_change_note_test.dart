// Η φόρμα τμήματος λέει τι αλλάζει τη στιγμή που γυρίζει το Είδος.
//
// Η κρίση ελέγχεται χωριστά ως καθαρή συνάρτηση
// (test/features/directory/kind_change_consequences_test.dart)· εδώ φυλάγεται
// η ΣΥΝΔΕΣΗ: ότι η φόρμα τη ρωτά με τα δικά της δεδομένα και δείχνει το
// αποτέλεσμα κάτω από το πεδίο.
//
//   flutter test test/features/directory/screens/widgets/department_form_kind_change_note_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/directory/models/department_kind.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:call_logger/features/directory/providers/department_directory_provider.dart';
import 'package:call_logger/features/directory/screens/widgets/department_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../test_setup.dart';

const _kDepartmentName = 'Ακτινολογικό';

/// Ένα τμήμα με δύο υπαλλήλους, ο ένας με αναγνωριστικό Lansweeper.
Future<int> _seedDepartmentWithEmployees() async {
  final db = await DatabaseHelper.instance.database;
  await db.delete('user_equipment');
  await db.delete('user_phones');
  await db.delete('department_phones');
  await db.delete('phones');
  await db.delete('equipment');
  await db.delete('users');
  await db.delete('departments');

  final deptId = await db.insert('departments', {
    'name': _kDepartmentName,
    'name_key': SearchTextNormalizer.normalizeForSearch(_kDepartmentName),
    'color': '#33691F',
    'kind': DepartmentKind.hospital.dbValue,
    'is_deleted': 0,
  });
  await db.insert('users', {
    'first_name': 'Μαρία',
    'last_name': 'Δαμανάκη',
    'department_id': deptId,
    'lansweeper_username': r'nosokomeio\mdamanaki',
    'is_deleted': 0,
  });
  await db.insert('users', {
    'first_name': 'Αντώνης',
    'last_name': 'Δαμωράκης',
    'department_id': deptId,
    'is_deleted': 0,
  });
  return deptId;
}

Finder _kindDropdown() => find.ancestor(
  of: find.text('Είδος'),
  matching: find.byType(DropdownButtonFormField<DepartmentKind>),
);

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  late int deptId;

  setUp(() async {
    await seedIsolatedTestDatabase();
    deptId = await _seedDepartmentWithEmployees();
  });

  /// Η φόρμα στήνεται **μέσα σε `runAsync`**, όπως κάθε τεστ της: το άνοιγμά
  /// της διαβάζει ρυθμίσεις από πραγματικό SQLite, και ο πλαστός χρόνος του
  /// `pumpAndSettle` αφήνει τα χρονόμετρα του sqflite εκκρεμή.
  Future<void> openForm(
    WidgetTester tester, {
    required DepartmentKind kind,
  }) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final container = ProviderContainer(
      overrides: callLoggerTestProviderOverrides(),
    );
    addTearDown(container.dispose);

    await tester.runAsync(() async {
      await container.read(lookupServiceProvider.future);
      final notifier = container.read(departmentDirectoryProvider.notifier);
      await notifier.loadDepartments();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: DepartmentFormDialog(
                initialDepartment: DepartmentModel(
                  id: deptId,
                  name: _kDepartmentName,
                  color: '#33691F',
                  kind: kind,
                ),
                notifier: notifier,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await pumpUntilSettledLong(tester);
    });
  }

  Future<void> chooseKind(WidgetTester tester, DepartmentKind kind) async {
    await tester.runAsync(() async {
      await tester.tap(_kindDropdown());
      await pumpUntilSettledLong(tester);
      await tester.tap(find.text(kind.label).last);
      await pumpUntilSettledLong(tester);
    });
  }

  testWidgets('τμήμα → εταιρεία: η γραμμή μετρά υπαλλήλους και αναγνωριστικά', (
    tester,
  ) async {
    await openForm(tester, kind: DepartmentKind.hospital);
    expect(find.textContaining('υπάλληλοι μένουν'), findsNothing);

    await chooseKind(tester, DepartmentKind.company);

    expect(
      find.textContaining(
        '2 υπάλληλοι μένουν στην εταιρεία και το δικό του αναγνωριστικό',
      ),
      findsOneWidget,
      reason:
          'Η φόρμα μετρά τους ΔΙΚΟΥΣ της υπαλλήλους — δύο, ο ένας με '
          'αναγνωριστικό.',
    );
  });

  testWidgets('επιστροφή σε τμήμα χωρίς κτίριο: το λέει', (tester) async {
    await openForm(tester, kind: DepartmentKind.company);

    await chooseKind(tester, DepartmentKind.hospital);

    expect(find.textContaining('η καρτέλα ζητά κτίριο'), findsOneWidget);
  });

  testWidgets('χωρίς αλλαγή Είδους η γραμμή σιωπά', (tester) async {
    await openForm(tester, kind: DepartmentKind.hospital);

    expect(find.textContaining('παύουν να ισχύουν'), findsNothing);
    expect(find.textContaining('ζητά κτίριο'), findsNothing);
  });
}
