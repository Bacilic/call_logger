// Επιλογή τμήματος από τη λίστα στον picker μεταφοράς: μόνο γέμισμα πεδίου,
// υποβολή μόνο με το κουμπί «Μεταφορά».
//
//   flutter test test/features/directory/asset_transfer_picker_no_autosubmit_test.dart

import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:call_logger/features/directory/screens/widgets/shared_asset_disconnect_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const targetDeptName = 'Πληροφορική';
  const targetDeptId = 20;

  final departments = [
    DepartmentModel(id: 10, name: 'Προμήθειες'),
    DepartmentModel(id: targetDeptId, name: targetDeptName),
    DepartmentModel(id: 30, name: 'Νοσηλευτική'),
  ];

  testWidgets(
    'επιλογή από λίστα γεμίζει το πεδίο· υποβολή μόνο με «Μεταφορά»',
    (tester) async {
      SharedAssetTransferTarget? result;
      var completed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await showAssetTransferTargetPicker(
                      context: context,
                      headerLabel: 'Μεταφορά δοκιμής',
                      availableDepartments: departments,
                    );
                    completed = true;
                  },
                  child: const Text('Άνοιγμα'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Άνοιγμα'));
      await tester.pumpAndSettle();

      expect(find.text('Μεταφορά κοινόχρηστου'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Πληρ');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(targetDeptName), findsWidgets);
      await tester.tap(
        find.descendant(
          of: find.byType(ListView),
          matching: find.text(targetDeptName),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // (α) Η επιλογή δεν κλείνει τον διάλογο ούτε επιστρέφει αποτέλεσμα.
      expect(completed, isFalse);
      expect(result, isNull);
      expect(find.text('Μεταφορά κοινόχρηστου'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        targetDeptName,
      );

      // (β) Μόνο το κουμπί «Μεταφορά» υποβάλλει.
      await tester.tap(find.widgetWithText(FilledButton, 'Μεταφορά'));
      await tester.pumpAndSettle();

      expect(completed, isTrue);
      expect(result, isNotNull);
      expect(result!.departmentId, targetDeptId);
      expect(result!.newDepartmentName, isNull);
      expect(find.text('Μεταφορά κοινόχρηστου'), findsNothing);
    },
  );
}
