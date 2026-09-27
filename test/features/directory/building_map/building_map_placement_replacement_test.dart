import 'package:call_logger/features/directory/building_map/services/building_map_placement_replacement.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:flutter_test/flutter_test.dart';

DepartmentModel _department({String? mapFloor, bool placed = true}) {
  return DepartmentModel(
    id: 7,
    name: 'Μαγειρείο',
    mapFloor: mapFloor,
    mapX: placed ? 10 : null,
    mapY: placed ? 20 : null,
    mapWidth: placed ? 30 : null,
    mapHeight: placed ? 40 : null,
  );
}

void main() {
  group('Τι αντικαθιστά η Επιβεβαίωση', () {
    test('πρώτη σχεδίαση δεν αντικαθιστά τίποτα', () {
      final r = resolveBuildingMapPlacementReplacement(
        department: _department(placed: false),
        targetSheetId: 1,
      );
      expect(r.isFirstPlacement, isTrue);
      expect(r.movesFromAnotherSheet, isFalse);
    });

    test('θέση στο ίδιο φύλλο αντικαθίσταται χωρίς μετακόμιση', () {
      final r = resolveBuildingMapPlacementReplacement(
        department: _department(mapFloor: '1'),
        targetSheetId: 1,
      );
      expect(r.replacesPlacementOnThisSheet, isTrue);
      expect(r.movesFromAnotherSheet, isFalse);
      expect(r.isFirstPlacement, isFalse);
    });

    test('θέση σε άλλο φύλλο είναι μετακόμιση, με το φύλλο προέλευσης', () {
      final r = resolveBuildingMapPlacementReplacement(
        department: _department(mapFloor: '2'),
        targetSheetId: 1,
      );
      expect(r.movesFromAnotherSheet, isTrue);
      expect(r.previousFloorId, 2);
      expect(r.replacesPlacementOnThisSheet, isFalse);
    });

    test('τμήμα με γεωμετρία αλλά χωρίς φύλλο δεν θεωρείται αντικατάσταση', () {
      final r = resolveBuildingMapPlacementReplacement(
        department: _department(mapFloor: ''),
        targetSheetId: 1,
      );
      expect(r.isFirstPlacement, isTrue);
    });
  });
}
