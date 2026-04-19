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
    this.mapRotation = 0.0,
    this.mapLabelOffsetX,
    this.mapLabelOffsetY,
    this.mapAnchorOffsetX,
    this.mapAnchorOffsetY,
    this.mapCustomName,
    this.groupName,
    this.floorId,
    this.directPhones,
    this.isDeleted = false,
  });

  final int? id;
  final String name;
  final String? building;
  final String? color;
  final String? notes;
  /// Ομαδοποίηση στο HUD επιλογής τμήματος στον χάρτη (κατηγορία ομάδας).
  final String? groupName;
  /// Αναφορά σε `building_map_floors.id` για ομαδοποίηση «ανά όροφο» στο HUD.
  final int? floorId;
  final String? mapFloor;
  final double? mapX;
  final double? mapY;
  final double? mapWidth;
  final double? mapHeight;
  final double mapRotation;
  final double? mapLabelOffsetX;
  final double? mapLabelOffsetY;
  final double? mapAnchorOffsetX;
  final double? mapAnchorOffsetY;
  final String? mapCustomName;
  /// “Ορφανά” τηλέφωνα που ανήκουν απευθείας στο τμήμα (δεν είναι των χρηστών).
  /// Δεν αποθηκεύονται μέσα στον πίνακα `departments`· φορτώνονται από `department_phones`.
  final List<String>? directPhones;
  final bool isDeleted;

  String get displayName {
    final custom = mapCustomName?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    return name;
  }

  /// Έχει ήδη αποθηκευμένο ορθογώνιο στο χάρτη (επί κάποιου φύλλου).
  bool get isMapped {
    final mf = mapFloor?.trim();
    if (mf == null || mf.isEmpty) return false;
    final w = mapWidth ?? 0;
    final h = mapHeight ?? 0;
    if (w <= 0 || h <= 0) return false;
    return mapX != null && mapY != null;
  }

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
      mapRotation: (map['map_rotation'] as num?)?.toDouble() ?? 0.0,
      mapLabelOffsetX: (map['map_label_offset_x'] as num?)?.toDouble(),
      mapLabelOffsetY: (map['map_label_offset_y'] as num?)?.toDouble(),
      mapAnchorOffsetX: (map['map_anchor_offset_x'] as num?)?.toDouble(),
      mapAnchorOffsetY: (map['map_anchor_offset_y'] as num?)?.toDouble(),
      mapCustomName: map['map_custom_name'] as String?,
      groupName: map['group_name'] as String?,
      floorId: (map['floor_id'] as num?)?.toInt(),
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
    double? mapRotation,
    double? mapLabelOffsetX,
    double? mapLabelOffsetY,
    double? mapAnchorOffsetX,
    double? mapAnchorOffsetY,
    String? mapCustomName,
    String? groupName,
    int? floorId,
    List<String>? directPhones,
    bool? isDeleted,
  }) {
    return DepartmentModel(
      id: id ?? this.id,
      name: name ?? this.name,
      building: building ?? this.building,
      color: color ?? this.color,
      notes: notes ?? this.notes,
      groupName: groupName ?? this.groupName,
      floorId: floorId ?? this.floorId,
      mapFloor: mapFloor ?? this.mapFloor,
      mapX: mapX ?? this.mapX,
      mapY: mapY ?? this.mapY,
      mapWidth: mapWidth ?? this.mapWidth,
      mapHeight: mapHeight ?? this.mapHeight,
      mapRotation: mapRotation ?? this.mapRotation,
      mapLabelOffsetX: mapLabelOffsetX ?? this.mapLabelOffsetX,
      mapLabelOffsetY: mapLabelOffsetY ?? this.mapLabelOffsetY,
      mapAnchorOffsetX: mapAnchorOffsetX ?? this.mapAnchorOffsetX,
      mapAnchorOffsetY: mapAnchorOffsetY ?? this.mapAnchorOffsetY,
      mapCustomName: mapCustomName ?? this.mapCustomName,
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
      'map_rotation': mapRotation,
      if (mapLabelOffsetX != null) 'map_label_offset_x': mapLabelOffsetX,
      if (mapLabelOffsetY != null) 'map_label_offset_y': mapLabelOffsetY,
      if (mapAnchorOffsetX != null) 'map_anchor_offset_x': mapAnchorOffsetX,
      if (mapAnchorOffsetY != null) 'map_anchor_offset_y': mapAnchorOffsetY,
      if (mapCustomName != null) 'map_custom_name': mapCustomName,
      if (groupName != null) 'group_name': groupName,
      if (floorId != null) 'floor_id': floorId,
      'is_deleted': isDeleted ? 1 : 0,
    };
  }
}
