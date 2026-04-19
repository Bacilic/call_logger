/// Φύλλο κατόψης για τον χάρτη κτιρίου (`building_map_floors`).
class BuildingMapFloor {
  BuildingMapFloor({
    required this.id,
    required this.sortOrder,
    required this.label,
    this.floorGroup,
    required this.imagePath,
    required this.rotationDegrees,
  });

  final int id;
  final int sortOrder;
  final String label;
  final String? floorGroup;
  final String imagePath;
  final double rotationDegrees;

  factory BuildingMapFloor.fromMap(Map<String, dynamic> row) {
    return BuildingMapFloor(
      id: row['id'] as int,
      sortOrder: (row['sort_order'] as num?)?.toInt() ?? 0,
      label: (row['label'] as String?) ?? '',
      floorGroup: row['floor_group'] as String?,
      imagePath: (row['image_path'] as String?) ?? '',
      rotationDegrees: (row['rotation_degrees'] as num?)?.toDouble() ?? 0,
    );
  }
}
