import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/building_map_floor.dart';
import 'directory_support.dart';

/// Persistence χάρτη κτιρίου (`building_map_floors` + σχετικές τοποθετήσεις τμημάτων).
class BuildingMapRepository {
  BuildingMapRepository(this.db, this._support);

  final Database db;
  // Κρατιέται για κοινούς βοηθούς σε επόμενες φάσεις (ίδιο συμβόλαιο με CategoryRepository).
  // ignore: unused_field
  final DirectorySupport _support;

  Future<void> Function(int deptId, Map<String, dynamic> fields)?
      _updateDepartment;

  /// Σύνδεση με [DirectoryRepository.updateDepartment] — ορίζεται από orchestrator.
  void bindUpdateDepartment(
    Future<void> Function(int deptId, Map<String, dynamic> fields) fn,
  ) {
    _updateDepartment = fn;
  }

  /// Πυρήνας «τοποθέτησης χάρτη» (χωρίς `floor_id`, `color`): οι στήλες
  /// με τις προεπιλογές τους όταν αφαιρείται εντελώς το τμήμα από τον χάρτη.
  static const Map<String, dynamic> _kBuildingMapPlacementClearedDefaults =
      <String, dynamic>{
    'map_floor': null,
    'map_x': 0.0,
    'map_y': 0.0,
    'map_width': 0.0,
    'map_height': 0.0,
    'map_rotation': 0.0,
    'map_label_offset_x': null,
    'map_label_offset_y': null,
    'map_anchor_offset_x': null,
    'map_anchor_offset_y': null,
    'map_custom_name': null,
    'map_label_font_scale': null,
    'map_label_width': null,
    'map_label_height': null,
    'map_hidden': 0,
  };

  /// Ονόματα στηλών που επηρεάζονται από [clearedBuildingMapPlacementColumns].
  static Iterable<String> get buildingMapPlacementColumnNames =>
      _kBuildingMapPlacementClearedDefaults.keys;

  /// Στήλες που μηδενίζουν την τοποθέτηση τμήματος στον χάρτη κτιρίου (`map_*`,
  /// προαιρετικά `floor_id`, `color`).
  static Map<String, dynamic> clearedBuildingMapPlacementColumns({
    bool clearFloorId = false,
    bool clearDepartmentHex = false,
  }) {
    final map = Map<String, dynamic>.from(
      _kBuildingMapPlacementClearedDefaults,
    );
    if (clearFloorId) {
      map['floor_id'] = null;
    }
    if (clearDepartmentHex) {
      map['color'] = null;
    }
    return map;
  }

  Future<List<BuildingMapFloor>> listBuildingMapFloors() async {
    final rows = await db.query(
      'building_map_floors',
      orderBy: 'sort_order ASC, id ASC',
    );
    return rows.map(BuildingMapFloor.fromMap).toList();
  }

  Future<int> insertBuildingMapFloor({
    required String label,
    String? floorGroup,
    required String copiedImagePath,
    required double rotationDegrees,
  }) async {
    final res = await db.rawQuery(
      'SELECT COALESCE(MAX(sort_order), -1) + 1 AS n FROM building_map_floors',
    );
    final sortOrder = (res.first['n'] as num?)?.toInt() ?? 0;
    return db.insert('building_map_floors', {
      'sort_order': sortOrder,
      'label': label,
      'floor_group': floorGroup,
      'image_path': copiedImagePath,
      'rotation_degrees': rotationDegrees,
    });
  }

  Future<void> updateBuildingMapFloor(
    int id, {
    double? rotationDegrees,
    String? label,
    String? floorGroup,
    String? imagePath,
  }) async {
    final m = <String, dynamic>{};
    if (rotationDegrees != null) {
      m['rotation_degrees'] = rotationDegrees;
    }
    if (label != null) {
      m['label'] = label;
    }
    if (floorGroup != null) {
      final t = floorGroup.trim();
      m['floor_group'] = t.isEmpty ? null : t;
    }
    if (imagePath != null) {
      m['image_path'] = imagePath;
    }
    if (m.isEmpty) return;
    await db.update('building_map_floors', m, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> countDepartmentsReferencingMapFloor(int floorId) async {
    final idStr = floorId.toString();
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM departments WHERE IFNULL(is_deleted,0)=0 AND map_floor = ?',
      [idStr],
    );
    return (r.first['c'] as int?) ?? 0;
  }

  /// Διαγράφει το φύλλο κατόψης και μηδενίζει τη θέση στο χάρτη για όλα τα τμήματα
  /// που δένονταν σε αυτό (`map_floor` = id ως string).
  Future<void> deleteBuildingMapFloorClearingDepartmentMaps(int id) async {
    final updateDepartment = _updateDepartment;
    if (updateDepartment == null) {
      throw StateError(
        'BuildingMapRepository: bindUpdateDepartment δεν έχει οριστεί.',
      );
    }
    final idStr = id.toString();
    final deptRows = await db.query(
      'departments',
      columns: ['id'],
      where: 'map_floor = ?',
      whereArgs: [idStr],
    );
    final cleared = <String, dynamic>{
      'map_floor': null,
      'floor_id': null,
      'map_x': 0.0,
      'map_y': 0.0,
      'map_width': 0.0,
      'map_height': 0.0,
      'map_rotation': 0.0,
      'map_label_offset_x': null,
      'map_label_offset_y': null,
      'map_anchor_offset_x': null,
      'map_anchor_offset_y': null,
      'map_custom_name': null,
      'map_label_font_scale': null,
      'map_label_width': null,
      'map_label_height': null,
    };
    for (final r in deptRows) {
      final deptId = r['id'] as int?;
      if (deptId == null) continue;
      await updateDepartment(deptId, cleared);
    }
    await db.delete('building_map_floors', where: 'id = ?', whereArgs: [id]);
  }
}
