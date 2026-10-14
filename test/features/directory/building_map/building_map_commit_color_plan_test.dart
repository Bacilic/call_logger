// Χρώμα τμήματος στην Επιβεβαίωση (✓) του χάρτη: κρατιέται, αλλάζει ή ρωτά.
// Τιμές από εκτέλεση του σημερινού κώδικα.
//
//   flutter test test/features/directory/building_map/building_map_commit_color_plan_test.dart

import 'package:call_logger/features/directory/building_map/services/building_map_commit_color_plan.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:call_logger/features/directory/screens/widgets/department_color_palette.dart';
import 'package:flutter_test/flutter_test.dart';

DepartmentModel _dept({String? mapFloor, bool placed = true, String? color}) =>
    DepartmentModel(
      id: 9,
      name: 'Ακτινολογικό',
      mapFloor: mapFloor,
      mapX: placed ? 0.1 : null,
      mapY: placed ? 0.2 : null,
      mapWidth: placed ? 0.3 : null,
      mapHeight: placed ? 0.3 : null,
      color: color,
    );

void main() {
  final blue = tryParseDepartmentHex('#1976D2');

  test('θέση στο ίδιο φύλλο με χρώμα: το χρώμα μένει, χωρίς ερώτηση', () {
    final plan = resolveBuildingMapCommitColorPlan(
      dept: _dept(mapFloor: '2', color: '#1976D2'),
      sheetStr: '2',
    );

    expect(plan.action, BuildingMapCommitColorAction.keepCurrent);
    expect(plan.currentColor, blue);
    expect(plan.releaseFromFloorId, isNull);
  });

  test(
    'μετακόμιση από άλλο φύλλο με χρώμα: ερώτηση, το παλιό φύλλο ελευθερώνεται',
    () {
      final plan = resolveBuildingMapCommitColorPlan(
        dept: _dept(mapFloor: '1', color: '#1976D2'),
        sheetStr: '2',
      );

      expect(plan.action, BuildingMapCommitColorAction.askUser);
      expect(plan.currentColor, blue);
      expect(plan.releaseFromFloorId, 1);
    },
  );

  test('χωρίς χρώμα: δίνεται καινούργιο', () {
    final plan = resolveBuildingMapCommitColorPlan(
      dept: _dept(mapFloor: '1'),
      sheetStr: '2',
    );

    expect(plan.action, BuildingMapCommitColorAction.assignNew);
    expect(plan.releaseFromFloorId, 1);
  });

  test('πρώτη σχεδίαση με χρώμα από τη φόρμα: ερώτηση', () {
    final plan = resolveBuildingMapCommitColorPlan(
      dept: _dept(placed: false, color: '#FF0000'),
      sheetStr: '2',
    );

    expect(plan.action, BuildingMapCommitColorAction.askUser);
    expect(plan.releaseFromFloorId, isNull);
  });

  test('μη αναγνώσιμο χρώμα: στο ίδιο φύλλο μένει, αλλού αντικαθίσταται', () {
    expect(
      resolveBuildingMapCommitColorPlan(
        dept: _dept(mapFloor: '2', color: 'κόκκινο'),
        sheetStr: '2',
      ).action,
      BuildingMapCommitColorAction.keepCurrent,
    );
    expect(
      resolveBuildingMapCommitColorPlan(
        dept: _dept(mapFloor: '1', color: 'κόκκινο'),
        sheetStr: '2',
      ).action,
      BuildingMapCommitColorAction.assignNew,
    );
  });
}
