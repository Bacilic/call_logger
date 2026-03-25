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
    this.directPhones,
    this.isDeleted = false,
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
  /// “Ορφανά” τηλέφωνα που ανήκουν απευθείας στο τμήμα (δεν είναι των χρηστών).
  /// Δεν αποθηκεύονται μέσα στον πίνακα `departments`· φορτώνονται από `department_phones`.
  final List<String>? directPhones;
  final bool isDeleted;

  factory DepartmentModel.fromMap(Map<String, dynamic> map) {
    List<String>? parseDirectPhones(dynamic v) {
      if (v == null) return null;
      if (v is List) {
        final list = v.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
        return list.isEmpty ? null : list;
      }
      if (v is String) {
        final parts = v
            .split(',')
            .map((e) => e.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        return parts.isEmpty ? null : parts;
      }
      return null;
    }
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
      directPhones: parseDirectPhones(map['direct_phones']),
      isDeleted: (map['is_deleted'] as int?) == 1,
    );
  }

  DepartmentModel copyWith({
    int? id,
    String? name,
    String? building,
    String? color,
    String? notes,
    String? mapFloor,
    double? mapX,
    double? mapY,
    double? mapWidth,
    double? mapHeight,
    List<String>? directPhones,
    bool? isDeleted,
  }) {
    return DepartmentModel(
      id: id ?? this.id,
      name: name ?? this.name,
      building: building ?? this.building,
      color: color ?? this.color,
      notes: notes ?? this.notes,
      mapFloor: mapFloor ?? this.mapFloor,
      mapX: mapX ?? this.mapX,
      mapY: mapY ?? this.mapY,
      mapWidth: mapWidth ?? this.mapWidth,
      mapHeight: mapHeight ?? this.mapHeight,
      directPhones: directPhones ?? this.directPhones,
      isDeleted: isDeleted ?? this.isDeleted,
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
      'is_deleted': isDeleted ? 1 : 0,
    };
  }
}
