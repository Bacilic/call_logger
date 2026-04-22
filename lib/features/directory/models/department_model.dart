// Sentinel για [DepartmentModel.copyWith]: διακρίνει «άσε το παλιό» από «βάλε null»
// σε nullable πεδία. Παράδειγμα: `d.copyWith(mapCustomName: null)` καθαρίζει την
// επωνυμία χάρτη, ενώ χωρίς το `mapCustomName` η τιμή διατηρείται.
class _Unset {
  const _Unset();
}

const Object _unset = _Unset();

/// Μοντέλο τμήματος (πίνακας departments): id, name, building, color, notes, map_*.
///
/// Το πεδίο [color] είναι hex `#RRGGBB` (κεφαλαία)· χρησιμοποιείται στον κατάλογο
/// τμημάτων και ως χρώμα γεμίσματος (fill) της περιοχής στον χάρτη κτιρίου.
/// Αν είναι null/κενό, το χρώμα περιοχής στον χάρτη μπορεί να ανατεθεί αυτόματα
/// κατά την πρώτη αποθήκευση στο φύλλο κατόψης.
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
    this.isHiddenOnMap = false,
  });

  final int? id;
  final String name;
  final String? building;
  /// Hex `#RRGGBB` — κατάλογος τμημάτων και γέμισμα περιοχής στον χάρτη κτιρίου.
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
  /// Απόκρυψη τμήματος από τον χάρτη κτιρίου (διατηρεί τη γεωμετρία). Per-department
  /// — καθώς κάθε τμήμα χαρτογραφείται σε ένα μόνο φύλλο μέσω `mapFloor`.
  final bool isHiddenOnMap;

  String get displayName {
    final custom = mapCustomName?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    return name;
  }

  /// Έχει ήδη αποθηκευμένο ορθογώνιο στο χάρτη (επί κάποιου φύλλου).
  /// Προτεραιότητα: [floorId]· αλλιώς fallback στο `map_floor` (legacy).
  bool get isMapped {
    final w = mapWidth ?? 0;
    final h = mapHeight ?? 0;
    if (w <= 0 || h <= 0) return false;
    if (mapX == null || mapY == null) return false;
    if (floorId != null) {
      final mf = int.tryParse(mapFloor?.trim() ?? '');
      if (mf != null) return mf == floorId;
      return true;
    }
    final mf = mapFloor?.trim();
    if (mf == null || mf.isEmpty) return false;
    return true;
  }

  /// Φιλικό κείμενο για τον όροφο όταν υπάρχει `floor_id`
  /// (λεπτομέρεια φύλλου από `building_map_floors` στο UI όταν διατίθεται λίστα).
  String? get floorDisplay {
    if (floorId == null) return null;
    return 'Όροφος #$floorId';
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
      isHiddenOnMap: (map['map_hidden'] as int?) == 1,
    );
  }

  /// Αντίγραφο με επιλεκτικές αλλαγές. Για nullable πεδία, παράλειψη του παραμέτρου
  /// κρατά την υπάρχουσα τιμή ενώ ρητή τιμή `null` την καθαρίζει. Για non-nullable
  /// πεδία ([name], [mapRotation], [isDeleted], [isHiddenOnMap]), μόνο ρητή τιμή
  /// τα αλλάζει.
  DepartmentModel copyWith({
    Object? id = _unset,
    String? name,
    Object? building = _unset,
    Object? color = _unset,
    Object? notes = _unset,
    Object? mapFloor = _unset,
    Object? mapX = _unset,
    Object? mapY = _unset,
    Object? mapWidth = _unset,
    Object? mapHeight = _unset,
    double? mapRotation,
    Object? mapLabelOffsetX = _unset,
    Object? mapLabelOffsetY = _unset,
    Object? mapAnchorOffsetX = _unset,
    Object? mapAnchorOffsetY = _unset,
    Object? mapCustomName = _unset,
    Object? groupName = _unset,
    Object? floorId = _unset,
    Object? directPhones = _unset,
    bool? isDeleted,
    bool? isHiddenOnMap,
  }) {
    return DepartmentModel(
      id: identical(id, _unset) ? this.id : id as int?,
      name: name ?? this.name,
      building: identical(building, _unset) ? this.building : building as String?,
      color: identical(color, _unset) ? this.color : color as String?,
      notes: identical(notes, _unset) ? this.notes : notes as String?,
      groupName:
          identical(groupName, _unset) ? this.groupName : groupName as String?,
      floorId: identical(floorId, _unset) ? this.floorId : floorId as int?,
      mapFloor:
          identical(mapFloor, _unset) ? this.mapFloor : mapFloor as String?,
      mapX: identical(mapX, _unset) ? this.mapX : (mapX as num?)?.toDouble(),
      mapY: identical(mapY, _unset) ? this.mapY : (mapY as num?)?.toDouble(),
      mapWidth: identical(mapWidth, _unset)
          ? this.mapWidth
          : (mapWidth as num?)?.toDouble(),
      mapHeight: identical(mapHeight, _unset)
          ? this.mapHeight
          : (mapHeight as num?)?.toDouble(),
      mapRotation: mapRotation ?? this.mapRotation,
      mapLabelOffsetX: identical(mapLabelOffsetX, _unset)
          ? this.mapLabelOffsetX
          : (mapLabelOffsetX as num?)?.toDouble(),
      mapLabelOffsetY: identical(mapLabelOffsetY, _unset)
          ? this.mapLabelOffsetY
          : (mapLabelOffsetY as num?)?.toDouble(),
      mapAnchorOffsetX: identical(mapAnchorOffsetX, _unset)
          ? this.mapAnchorOffsetX
          : (mapAnchorOffsetX as num?)?.toDouble(),
      mapAnchorOffsetY: identical(mapAnchorOffsetY, _unset)
          ? this.mapAnchorOffsetY
          : (mapAnchorOffsetY as num?)?.toDouble(),
      mapCustomName: identical(mapCustomName, _unset)
          ? this.mapCustomName
          : mapCustomName as String?,
      directPhones: identical(directPhones, _unset)
          ? this.directPhones
          : directPhones as List<String>?,
      isDeleted: isDeleted ?? this.isDeleted,
      isHiddenOnMap: isHiddenOnMap ?? this.isHiddenOnMap,
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
      'map_hidden': isHiddenOnMap ? 1 : 0,
    };
  }
}
