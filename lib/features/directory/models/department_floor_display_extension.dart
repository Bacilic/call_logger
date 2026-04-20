import '../../../core/models/building_map_floor.dart';

import 'department_model.dart';

String _buildingMapFloorLabel(BuildingMapFloor f) {
  final g = f.floorGroup?.trim();
  return (g != null && g.isNotEmpty) ? '$g · ${f.label}' : f.label;
}

extension DepartmentFloorCatalogDisplay on DepartmentModel {
  /// Εμφάνιση ορόφου με ετικέτα από `building_map_floors` όταν υπάρχει στο [floorById].
  String? floorDisplayWithCatalog(Map<int, BuildingMapFloor> floorById) {
    final id = floorId ?? int.tryParse(mapFloor?.trim() ?? '');
    if (id == null) return null;
    final f = floorById[id];
    if (f != null) return _buildingMapFloorLabel(f);
    return floorDisplay;
  }
}
