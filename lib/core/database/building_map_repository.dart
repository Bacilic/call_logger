import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/building_map_floor.dart';
import 'directory_support.dart';
import 'floor_plan_repository.dart';

/// Persistence χάρτη κτιρίου (`building_map_floors` + σχετικές τοποθετήσεις τμημάτων).
class BuildingMapRepository {
  BuildingMapRepository(this.db, [DirectorySupport? support])
    : _support = support ?? DirectorySupport(db);

  final Database db;
  // Κρατιέται για κοινούς βοηθούς σε επόμενες φάσεις (ίδιο συμβόλαιο με CategoryRepository).
  // ignore: unused_field
  final DirectorySupport _support;

  Future<void> Function(int deptId, Map<String, dynamic> fields)?
  _updateDepartment;

  /// Σύνδεση με `DepartmentRepository.updateDepartment` — ορίζεται από orchestrator.
  void bindUpdateDepartment(
    Future<void> Function(int deptId, Map<String, dynamic> fields) fn,
  ) {
    _updateDepartment = fn;
  }

  /// Οι τρέχουσες τιμές των [columns] του τμήματος — για στιγμιότυπο
  /// αναίρεσης πριν από μια ενέργεια χάρτη. Κενό αν το τμήμα δεν υπάρχει.
  Future<Map<String, Object?>> readDepartmentColumns(
    int departmentId,
    Iterable<String> columns,
  ) async {
    final rows = await db.query(
      'departments',
      columns: columns.toList(),
      where: 'id = ?',
      whereArgs: [departmentId],
      limit: 1,
    );
    if (rows.isEmpty) return const {};
    return Map<String, Object?>.from(rows.first);
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

  /// Οι κατόψεις με το **αποτύπωμα** της εικόνας τους — ποτέ τα ίδια τα bytes.
  ///
  /// Οι στήλες γράφονται ρητά: η λίστα διαβάζεται συχνά από το δίκτυο, και ένα
  /// `SELECT *` πάνω στη σύνδεση με τις εικόνες θα κουβαλούσε εκατοντάδες KB σε
  /// κάθε άνοιγμα του χάρτη.
  Future<List<BuildingMapFloor>> listBuildingMapFloors() async {
    final rows = await db.rawQuery('''
      SELECT f.id, f.sort_order, f.label, f.floor_group, f.image_path,
             f.rotation_degrees, i.image_hash, i.previous_image_hash
      FROM building_map_floors f
      LEFT JOIN building_map_floor_images i ON i.floor_id = f.id
      ORDER BY f.sort_order ASC, f.id ASC
    ''');
    return rows.map(BuildingMapFloor.fromMap).toList();
  }

  /// Τα bytes της εικόνας του ορόφου, μαζί με το αποτύπωμά τους· `null` όταν
  /// η κάτοψη δεν έχει ανέβει.
  Future<({Uint8List bytes, String hash})?> readFloorImage(int floorId) async {
    final rows = await db.query(
      'building_map_floor_images',
      columns: ['image_data', 'image_hash'],
      where: 'floor_id = ?',
      whereArgs: [floorId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final data = rows.first['image_data'];
    final hash = rows.first['image_hash'] as String?;
    if (data is! Uint8List || hash == null) return null;
    return (bytes: data, hash: hash);
  }

  /// Αποθηκεύει νέα εικόνα κάτοψης· η τρέχουσα γίνεται «προηγούμενη».
  ///
  /// Επιστρέφει το αποτύπωμα της νέας εικόνας. Αν τα bytes είναι ίδια με την
  /// τρέχουσα, τίποτα δεν αλλάζει — αλλιώς ένα δεύτερο ανέβασμα της ίδιας
  /// εικόνας θα έσβηνε την πραγματική προηγούμενη.
  Future<String> saveFloorImage(int floorId, Uint8List bytes) async {
    final hash = floorImageHash(bytes);
    await db.transaction((txn) async {
      final rows = await txn.query(
        'building_map_floor_images',
        columns: ['image_data', 'image_hash'],
        where: 'floor_id = ?',
        whereArgs: [floorId],
        limit: 1,
      );
      if (rows.isEmpty) {
        await txn.insert('building_map_floor_images', {
          'floor_id': floorId,
          'image_data': bytes,
          'image_hash': hash,
        });
        return;
      }
      if (rows.first['image_hash'] == hash) return;
      await txn.update(
        'building_map_floor_images',
        {
          'previous_image_data': rows.first['image_data'],
          'previous_image_hash': rows.first['image_hash'],
          'image_data': bytes,
          'image_hash': hash,
        },
        where: 'floor_id = ?',
        whereArgs: [floorId],
      );
    });
    return hash;
  }

  /// Ανταλλάσσει τρέχουσα και προηγούμενη εικόνα. Η ίδια ενέργεια ξανά φέρνει
  /// πίσω αυτήν που μόλις αντικαταστάθηκε — η επαναφορά δεν χάνει τίποτα.
  ///
  /// `false` όταν δεν υπάρχει προηγούμενη εικόνα.
  Future<bool> swapFloorImageWithPrevious(int floorId) async {
    final changed = await db.rawUpdate(
      '''
      UPDATE building_map_floor_images
      SET image_data = previous_image_data,
          image_hash = previous_image_hash,
          previous_image_data = image_data,
          previous_image_hash = image_hash
      WHERE floor_id = ? AND previous_image_data IS NOT NULL
      ''',
      [floorId],
    );
    return changed > 0;
  }

  /// Σβήνει την εικόνα κάτοψης του ορόφου — και την προηγούμενη. Ο όροφος
  /// που πέρασε στον νέο χάρτη δεν τη χρειάζεται πια.
  Future<void> deleteFloorImage(int floorId) async {
    await db.delete(
      'building_map_floor_images',
      where: 'floor_id = ?',
      whereArgs: [floorId],
    );
  }

  Future<int> insertBuildingMapFloor({
    required String label,
    String? floorGroup,
    String copiedImagePath = '',
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

  /// Τα τμήματα που έχουν κουτάκι στον παλιό χάρτη του ορόφου.
  Future<List<int>> departmentIdsDrawnOnOldFloor(int floorId) async {
    final rows = await db.query(
      'departments',
      columns: ['id'],
      where: 'map_floor = ?',
      whereArgs: ['$floorId'],
    );
    return [for (final r in rows) r['id'] as int];
  }

  Future<int> countDepartmentsReferencingMapFloor(int floorId) async {
    final idStr = floorId.toString();
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM departments WHERE IFNULL(is_deleted,0)=0 AND map_floor = ?',
      [idStr],
    );
    return (r.first['c'] as int?) ?? 0;
  }

  /// Διαγράφει το φύλλο κάτοψης και μηδενίζει τη θέση στο χάρτη για όλα τα τμήματα
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
    await db.delete(
      'building_map_floor_images',
      where: 'floor_id = ?',
      whereArgs: [id],
    );
    // Ο νέος, σχεδιασμένος χάρτης του ορόφου φεύγει μαζί του — χωρίς δεσμούς
    // ξένου κλειδιού, κανείς άλλος δεν θα τον έσβηνε.
    await FloorPlanRepository(db).deleteFloorPlan(db, id);
    await db.delete('building_map_floors', where: 'id = ?', whereArgs: [id]);
  }
}

/// Το αποτύπωμα των bytes μιας εικόνας κάτοψης — ίδια bytes, ίδιο αποτύπωμα σε
/// κάθε σταθμό. Με αυτό ονομάζεται και το τοπικό αντίγραφο κάθε σταθμού.
String floorImageHash(Uint8List bytes) => sha1.convert(bytes).toString();
