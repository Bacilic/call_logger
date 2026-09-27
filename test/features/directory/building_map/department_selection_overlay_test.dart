// Widget tests: το πλέγμα «Επιλογή τμήματος» του χάρτη κτιρίου.
//
//   flutter test test/features/directory/building_map/department_selection_overlay_test.dart

import 'package:call_logger/core/models/building_map_floor.dart';
import 'package:call_logger/features/directory/building_map/widgets/department_selection_card.dart';
import 'package:call_logger/features/directory/building_map/widgets/department_selection_overlay.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

BuildingMapFloor _floor(int id, String label) => BuildingMapFloor(
  id: id,
  label: label,
  imagePath: '',
  rotationDegrees: 0,
  sortOrder: id,
);

DepartmentModel _mapped(int id, String name, String mapFloor) =>
    DepartmentModel(
      id: id,
      name: name,
      mapFloor: mapFloor,
      floorId: int.tryParse(mapFloor),
      color: '#1976D2',
      mapX: 10,
      mapY: 20,
      mapWidth: 30,
      mapHeight: 40,
    );

DepartmentModel _unmapped(int id, String name) =>
    DepartmentModel(id: id, name: name);

/// Πραγματικό μέγεθος παραθύρου — το προεπιλεγμένο 800x600 είναι κάτω από το
/// ελάχιστο της εφαρμογής και στριμώχνει το πλέγμα.
void _useRealWindowSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<DepartmentModel?> _pumpOverlay(
  WidgetTester tester, {
  required List<DepartmentModel> departments,
}) async {
  _useRealWindowSize(tester);
  DepartmentModel? picked;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DepartmentSelectionOverlay(
          activeDepartments: departments,
          floors: [_floor(1, 'Ισόγειο'), _floor(2, '1ος')],
          onClose: () {},
          onSelectDepartment: (d) => picked = d,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return picked;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'τα σχεδιασμένα δείχνουν τον όροφό τους, τα υπόλοιπα «Χωρίς θέση»',
    (tester) async {
      await _pumpOverlay(
        tester,
        departments: [_mapped(1, 'Μαγειρείο', '2'), _unmapped(2, 'Κουζίνα')],
      );

      final mapped = tester.widget<DepartmentSelectionCard>(
        find.widgetWithText(DepartmentSelectionCard, 'Μαγειρείο'),
      );
      expect(mapped.placementFloorLabel, '1ος');
      expect(
        find.descendant(
          of: find.widgetWithText(DepartmentSelectionCard, 'Μαγειρείο'),
          matching: find.text('1ος'),
        ),
        findsOneWidget,
      );

      final unmapped = tester.widget<DepartmentSelectionCard>(
        find.widgetWithText(DepartmentSelectionCard, 'Κουζίνα'),
      );
      expect(unmapped.placementFloorLabel, isNull);
      expect(find.text('Χωρίς θέση'), findsOneWidget);
    },
  );

  testWidgets(
    'η κάρτα σχεδιασμένου τμήματος πατιέται και επιστρέφει το τμήμα',
    (tester) async {
      _useRealWindowSize(tester);
      DepartmentModel? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DepartmentSelectionOverlay(
              activeDepartments: [_mapped(1, 'Μαγειρείο', '2')],
              floors: [_floor(1, 'Ισόγειο'), _floor(2, '1ος')],
              onClose: () {},
              onSelectDepartment: (d) => picked = d,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Μαγειρείο'));
      await tester.pumpAndSettle();

      expect(picked?.id, 1);
    },
  );

  testWidgets('η αναζήτηση φιλτράρει χωρίς να χάνει τις ενδείξεις θέσης', (
    tester,
  ) async {
    await _pumpOverlay(
      tester,
      departments: [_mapped(1, 'Μαγειρείο', '2'), _unmapped(2, 'Κουζίνα')],
    );

    await tester.enterText(find.byType(TextField), 'κουζ');
    await tester.pumpAndSettle();

    expect(find.text('Μαγειρείο'), findsNothing);
    expect(find.text('Κουζίνα'), findsOneWidget);
    expect(find.text('Χωρίς θέση'), findsOneWidget);
  });
}
