import 'package:call_logger/core/models/building_map_floor.dart';
import 'package:call_logger/features/directory/building_map/services/building_map_department_pick_outcome.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:flutter_test/flutter_test.dart';

BuildingMapFloor _floor(int id, String label, {String? group}) =>
    BuildingMapFloor(
      id: id,
      label: label,
      floorGroup: group,
      imagePath: '',
      rotationDegrees: 0,
      sortOrder: id,
    );

DepartmentModel _department({
  int id = 7,
  String? mapFloor,
  bool placed = true,
}) {
  return DepartmentModel(
    id: id,
    name: 'Μαγειρείο',
    mapFloor: mapFloor,
    mapX: placed ? 10 : null,
    mapY: placed ? 20 : null,
    mapWidth: placed ? 30 : null,
    mapHeight: placed ? 40 : null,
  );
}

void main() {
  final floors = [_floor(1, 'Ισόγειο'), _floor(2, '1ος', group: 'Κτίριο Α')];

  group('Επιλογή τμήματος από τη λίστα', () {
    test('τμήμα χωρίς θέση → σχεδίαση στο τρέχον φύλλο', () {
      final pick = resolveBuildingMapDepartmentPick(
        department: _department(placed: false),
        currentSheetId: 1,
        floors: floors,
      );
      expect(pick.action, BuildingMapDepartmentPickAction.drawHere);
    });

    test('τμήμα με θέση στο τρέχον φύλλο → επεξεργασία, χωρίς ερώτηση', () {
      final pick = resolveBuildingMapDepartmentPick(
        department: _department(mapFloor: '1'),
        currentSheetId: 1,
        floors: floors,
      );
      expect(pick.action, BuildingMapDepartmentPickAction.editHere);
    });

    test(
      'τμήμα με θέση σε άλλο υπαρκτό φύλλο → ερώτηση, με ετικέτα ορόφου',
      () {
        final pick = resolveBuildingMapDepartmentPick(
          department: _department(mapFloor: '2'),
          currentSheetId: 1,
          floors: floors,
        );
        expect(pick.action, BuildingMapDepartmentPickAction.askFloorChoice);
        expect(pick.otherFloorId, 2);
        expect(pick.otherFloorLabel, 'Κτίριο Α · 1ος');
      },
    );

    test('τμήμα που δείχνει σε φύλλο που δεν υπάρχει → σχεδίαση εδώ', () {
      final pick = resolveBuildingMapDepartmentPick(
        department: _department(mapFloor: '99'),
        currentSheetId: 1,
        floors: floors,
      );
      expect(pick.action, BuildingMapDepartmentPickAction.orphanedPlacement);
    });
  });

  group('Ετικέτα ορόφου όπου είναι σχεδιασμένο', () {
    final floorById = {for (final f in floors) f.id: f};

    test('τμήμα χωρίς θέση δεν έχει ετικέτα', () {
      expect(
        buildingMapPlacementFloorLabel(
          department: _department(placed: false),
          floorById: floorById,
        ),
        isNull,
      );
    });

    test('τμήμα με θέση δίνει την ετικέτα του φύλλου του', () {
      expect(
        buildingMapPlacementFloorLabel(
          department: _department(mapFloor: '1'),
          floorById: floorById,
        ),
        'Ισόγειο',
      );
    });

    test('φύλλο που δεν υπάρχει πια δεν δίνει ετικέτα', () {
      expect(
        buildingMapPlacementFloorLabel(
          department: _department(mapFloor: '99'),
          floorById: floorById,
        ),
        isNull,
      );
    });
  });
}
