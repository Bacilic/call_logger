// Το παράθυρο «Επεξεργασία …» της Λάμπας: κόστος σε ελληνική γραφή, όροφος
// ακέραιος — λάθος γραφή = μήνυμα, ποτέ σιωπηλή αλλοίωση.
//
//   flutter test test/features/lamp/widgets/lamp_edit_section_dialog_test.dart

import 'package:call_logger/features/lamp/models/lamp_equipment_view_model.dart';
import 'package:call_logger/features/lamp/models/lamp_field_input.dart';
import 'package:call_logger/features/lamp/widgets/lamp_edit_section_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('el'));

  late List<Map<String, Object?>> saved;

  Future<void> open(WidgetTester tester, InfoSectionData section) async {
    saved = [];
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditSectionDialog<void>(
            section: section,
            onSave: (fields) async {
              saved.add(fields);
              return const EquipmentSectionSaveResult(success: true);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  InfoSectionData costSection() => InfoSectionData(
    type: InfoSectionType.equipment,
    recordId: 1,
    items: const [],
    editableFields: [
      EditableInfoField(
        label: 'Κόστος',
        fieldKey: 'cost',
        value: LampFieldInput.moneyForEdit('1537.5000'),
        type: EditableFieldType.money,
      ),
    ],
  );

  const floorSection = InfoSectionData(
    type: InfoSectionType.department,
    recordId: 1,
    items: [],
    editableFields: [
      EditableInfoField(
        label: 'Όροφος',
        fieldKey: 'level',
        value: '2',
        type: EditableFieldType.number,
      ),
    ],
  );

  testWidgets('«1.537» αποθηκεύεται 1.537 €, όχι 1,54 €', (tester) async {
    await open(tester, costSection());

    await tester.enterText(find.byType(TextFormField), '1.537');
    // Το κουμπί ενεργοποιείται στο επόμενο καρέ μετά την πληκτρολόγηση.
    await tester.pump();
    await tester.tap(find.text('Αποθήκευση'));
    await tester.pumpAndSettle();

    expect(saved.single['cost'], '1537.0000');
  });

  testWidgets('«1537.50» δεν αποθηκεύεται — μήνυμα αντί για μαντεψιά', (
    tester,
  ) async {
    await open(tester, costSection());

    await tester.enterText(find.byType(TextFormField), '1537.50');
    // Το κουμπί ενεργοποιείται στο επόμενο καρέ μετά την πληκτρολόγηση.
    await tester.pump();
    await tester.tap(find.text('Αποθήκευση'));
    await tester.pumpAndSettle();

    expect(saved, isEmpty);
    expect(find.text(LampFieldInput.moneyFormatError), findsOneWidget);
  });

  testWidgets('όροφος «1,5» δεν σβήνεται σιωπηλά — μήνυμα', (tester) async {
    await open(tester, floorSection);

    await tester.enterText(find.byType(TextFormField), '1,5');
    // Το κουμπί ενεργοποιείται στο επόμενο καρέ μετά την πληκτρολόγηση.
    await tester.pump();
    await tester.tap(find.text('Αποθήκευση'));
    await tester.pumpAndSettle();

    expect(saved, isEmpty, reason: 'Πριν: ο όροφος γινόταν σιωπηλά κενός.');
    expect(find.text(LampFieldInput.floorFormatError), findsOneWidget);
  });
}
