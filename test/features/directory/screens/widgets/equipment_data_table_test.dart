import 'package:call_logger/features/calls/models/equipment_model.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/directory/models/equipment_column.dart';
import 'package:call_logger/features/directory/screens/widgets/equipment_data_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('EquipmentDataTable εμφανίζει δυναμικές στήλες και τιμές γραμμών', (tester) async {
    final items = [
      (
        EquipmentModel(
          id: 1,
          code: 'PC-01',
          type: 'Desktop',
          customIp: '10.0.0.1',
          defaultRemoteTool: 'AnyDesk',
          userId: 100,
        ),
        UserModel(
          id: 100,
          firstName: 'Γιάννης',
          lastName: 'Ιωάννου',
          phone: '2101234567',
          location: 'Κτίριο Α',
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

  testWidgets('EquipmentDataTable εμφανίζει παύλα όταν owner ή πεδία λείπουν', (tester) async {
    final items = [
      (
        EquipmentModel(
            id: 2, code: 'PC-02', type: 'Laptop', notes: null, userId: null),
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
