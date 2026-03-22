// Widget tests: EquipmentDataTable — δυναμικές στήλες, τιμές γραμμών, ελλείψεις (παύλες).
//
// Ολόκληρο αρχείο:
//   flutter test test/features/directory/screens/widgets/equipment_data_table_test.dart

import 'package:call_logger/features/calls/models/equipment_model.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/directory/models/equipment_column.dart';
import 'package:call_logger/features/directory/screens/widgets/equipment_data_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Έλεγχος επικεφαλίδων και κελιών (κωδικός, κάτοχος, IP, εργαλείο απομακρυσμένης).
  //   flutter test test/features/directory/screens/widgets/equipment_data_table_test.dart --plain-name "EquipmentDataTable εμφανίζει δυναμικές στήλες και τιμές γραμμών"
  testWidgets('EquipmentDataTable εμφανίζει δυναμικές στήλες και τιμές γραμμών', (tester) async {
    final items = [
      (
        EquipmentModel(
          id: 1,
          code: 'PC-01',
          type: 'Desktop',
          customIp: '10.0.0.1',
          defaultRemoteTool: 'AnyDesk',
        ),
        UserModel(
          id: 100,
          firstName: 'Γιάννης',
          lastName: 'Ιωάννου',
          phones: const ['2101234567'],
        ),
      ),
    ];
    final visibleColumns = [
      EquipmentColumn.code,
      EquipmentColumn.owner,
      EquipmentColumn.customIp,
      EquipmentColumn.defaultRemote,
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 500,
            child: EquipmentDataTable(
              items: items,
              selectedIds: {},
              sortColumn: null,
              sortAscending: true,
              visibleColumns: visibleColumns,
              onToggleSelection: (_) {},
              onSetSort: (_, _) {},
              onEditEquipment: (_, {focusedField}) {},
              continuousScroll: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Κωδικός'), findsOneWidget);
    expect(find.text('Κάτοχος'), findsOneWidget);
    expect(find.text('Προσαρμοσμένη IP'), findsOneWidget);
    expect(find.text('Εργαλείο Απομακρυσμένης'), findsOneWidget);

    expect(find.text('PC-01'), findsOneWidget);
    expect(find.text('Γιάννης Ιωάννου'), findsOneWidget);
    expect(find.text('10.0.0.1'), findsOneWidget);
    expect(find.text('AnyDesk'), findsOneWidget);
  });

  // Χωρίς κάτοχο/κενά πεδία: «Χωρίς κάτοχο» και em dash στα κενά.
  //   flutter test test/features/directory/screens/widgets/equipment_data_table_test.dart --plain-name "EquipmentDataTable εμφανίζει παύλα όταν owner ή πεδία λείπουν"
  testWidgets('EquipmentDataTable εμφανίζει παύλα όταν owner ή πεδία λείπουν', (tester) async {
    final items = [
      (
        EquipmentModel(
          id: 2,
          code: 'PC-02',
          type: 'Laptop',
          notes: null,
        ),
        null,
      ),
    ];
    final visibleColumns = [
      EquipmentColumn.owner,
      EquipmentColumn.phone,
      EquipmentColumn.notes,
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 500,
            child: EquipmentDataTable(
              items: items,
              selectedIds: {},
              sortColumn: null,
              sortAscending: true,
              visibleColumns: visibleColumns,
              onToggleSelection: (_) {},
              onSetSort: (_, _) {},
              onEditEquipment: (_, {focusedField}) {},
              continuousScroll: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Χωρίς κάτοχο'), findsOneWidget);
    expect(find.text('–'), findsNWidgets(2));
  });
}
