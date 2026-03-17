/// Μοντέλο τμήματος (πίνακας departments): id, name, building, color, notes, map_*.
class DepartmentModel {
  DepartmentModel({
    this.id,
    required this.name,
    this.building,
    this.color,
    this.notes,
    this.mapFloor,
    this.mapX,
    this.mapY,
    this.mapWidth,
    this.mapHeight,
  });

  final int? id;
  final String name;
  final String? building;
  final String? color;
  final String? notes;
  final String? mapFloor;
  final double? mapX;
  final double? mapY;
  final double? mapWidth;
  final double? mapHeight;

  factory DepartmentModel.fromMap(Map<String, dynamic> map) {
    return DepartmentModel(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      building: map['building'] as String?,
      color: map['color'] as String?,
      notes: map['notes'] as String?,
      mapFloor: map['map_floor'] as String?,
      mapX: (map['map_x'] as num?)?.toDouble(),
      mapY: (map['map_y'] as num?)?.toDouble(),
      mapWidth: (map['map_width'] as num?)?.toDouble(),
      mapHeight: (map['map_height'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      if (building != null) 'building': building,
      if (color != null) 'color': color,
      if (notes != null) 'notes': notes,
      if (mapFloor != null) 'map_floor': mapFloor,
      if (mapX != null) 'map_x': mapX,
      if (mapY != null) 'map_y': mapY,
      if (mapWidth != null) 'map_width': mapWidth,
      if (mapHeight != null) 'map_height': mapHeight,
    };
  }
}
