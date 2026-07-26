// Ετικέτες κουμπιών στον διάλογο αποδέσμευσης κοινόχρηστου στοιχείου.
//
//   flutter test test/features/directory/shared_asset_disconnect_label_test.dart

import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:call_logger/features/directory/screens/widgets/shared_asset_disconnect_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('κουμπιά: Ακύρωση + Παραμονή στο [όνομα τμήματος]', (
    tester,
  ) async {
    const deptName = 'Προμήθειες';
    final departments = <DepartmentModel>[
      DepartmentModel(id: 1, name: deptName),
      DepartmentModel(id: 2, name: 'Άλλο Τμήμα'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () {
                showSharedAssetDisconnectFlow(
                  context: context,
                  sourceDepartmentId: 1,
                  sourceDepartmentName: deptName,
                  phones: const ['2310123456'],
                  availableDepartments: departments,
                  mode: SharedAssetDisconnectMode.sharedAsset,
                  allowKeepInDepartment: true,
                );
              },
              child: const Text('OPEN'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();

    expect(find.text('Ακύρωση'), findsOneWidget);
    expect(find.text('Άκυρο'), findsNothing);
    expect(find.text('Παραμονή στο $deptName'), findsOneWidget);
    expect(find.text('Παραμονή στο ίδιο τμήμα'), findsNothing);
  });

  testWidgets('personalPhone: Παραμονή στο [όνομα τμήματος]', (tester) async {
    const deptName = 'Γραμματεία';
    final departments = <DepartmentModel>[
      DepartmentModel(id: 10, name: deptName),
      DepartmentModel(id: 11, name: 'Άλλο'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () {
                showSharedAssetDisconnectFlow(
                  context: context,
                  sourceDepartmentId: 10,
                  sourceDepartmentName: deptName,
                  phones: const ['2345000001'],
                  availableDepartments: departments,
                  mode: SharedAssetDisconnectMode.personalPhone,
                  personalPhoneUserDisplayName: 'Μαρία Παπα',
                  allowKeepInDepartment: true,
                );
              },
              child: const Text('OPEN'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();

    expect(find.text('Ακύρωση'), findsOneWidget);
    expect(find.text('Παραμονή στο $deptName'), findsOneWidget);
    expect(find.text('Παραμονή στο τμήμα του υπαλλήλου'), findsNothing);
  });
}
