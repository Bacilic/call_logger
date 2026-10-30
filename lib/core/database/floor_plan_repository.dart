import 'dart:typed_data';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/floor_plan_element.dart';
import '../models/floor_plan_state.dart';
import 'building_map_repository.dart' show floorImageHash;

/// Persistence του **νέου, σχεδιασμένου** χάρτη: τα στοιχεία του σχεδίου
/// (`building_map_plan_elements`) και η κατάσταση κάθε ορόφου
/// (`building_map_floor_state`).
///
/// Κάθε εγγραφή ενημερώνει και το «πότε άλλαξε» του ορόφου, ώστε οι άλλοι
/// σταθμοί να ξέρουν πότε έχει νόημα να ξαναδιαβάσουν.
class FloorPlanRepository {
  FloorPlanRepository(this.db);

  final Database db;

  static const String _elements = 'building_map_plan_elements';
  static const String _state = 'building_map_floor_state';

  Future<List<FloorPlanElement>> listElements(int floorId) async {
    final rows = await db.query(
      _elements,
      columns: FloorPlanElement.columns,
      where: 'floor_id = ?',
      whereArgs: [floorId],
      orderBy: 'id ASC',
    );
    return [for (final row in rows) ?FloorPlanElement.fromMap(row)];
  }

  /// Γράφει νέο στοιχείο και επιστρέφει το id του.
  Future<int> insertElement(FloorPlanElement element) async {
    return db.transaction((txn) async {
      final id = await txn.insert(_elements, element.toInsertMap());
      await _touch(txn, element.floorId);
      return id;
    });
  }

  /// Ξαναγράφει στοιχεία **με τα δικά τους id** — η αναίρεση μιας διαγραφής.
  ///
  /// Ασφαλές επειδή ο πίνακας είναι AUTOINCREMENT: ένα id που σβήστηκε δεν
  /// δίνεται ποτέ ξανά σε νέο στοιχείο, άρα δεν μπορεί να το έχει πιάσει άλλο.
  Future<void> restoreElements(List<FloorPlanElement> elements) async {
    if (elements.isEmpty) return;
    await db.transaction((txn) async {
      for (final e in elements) {
        await txn.insert(_elements, {
          'id': e.id,
          ...e.toInsertMap(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final floorId in {for (final e in elements) e.floorId}) {
        await _touch(txn, floorId);
      }
    });
  }

  /// Σβήνει τα στοιχεία [ids] **μαζί με ό,τι ανήκει σε αυτά** (τα ανοίγματα
  /// ενός τοίχου) και επιστρέφει όσα έσβησε, για την αναίρεση.
  Future<List<FloorPlanElement>> deleteElements(Iterable<int> ids) async {
    final idList = ids.toSet().toList();
    if (idList.isEmpty) return const [];
    return db.transaction((txn) async {
      final marks = List.filled(idList.length, '?').join(', ');
      final rows = await txn.query(
        _elements,
        columns: FloorPlanElement.columns,
        where: 'id IN ($marks) OR parent_id IN ($marks)',
        whereArgs: [...idList, ...idList],
        orderBy: 'id ASC',
      );
      final removed = [for (final row in rows) ?FloorPlanElement.fromMap(row)];
      await txn.delete(
        _elements,
        where: 'id IN ($marks) OR parent_id IN ($marks)',
        whereArgs: [...idList, ...idList],
      );
      for (final floorId in {for (final e in removed) e.floorId}) {
        await _touch(txn, floorId);
      }
      return removed;
    });
  }

  /// Σε ποιους ορόφους έχει χώρο το τμήμα [departmentId] στον νέο χάρτη.
  Future<Set<int>> floorsWithRoomOfDepartment(int departmentId) async {
    final rows = await db.query(
      _elements,
      columns: ['floor_id'],
      distinct: true,
      where: 'kind = ? AND department_id = ?',
      whereArgs: [FloorPlanElementKind.room.key, departmentId],
    );
    return {for (final r in rows) r['floor_id'] as int};
  }

  /// Οι όροφοι που έχουν περάσει στον νέο χάρτη.
  Future<Set<int>> activeFloorIds() async {
    final rows = await db.query(
      _state,
      columns: ['floor_id'],
      where: 'is_active = 1',
    );
    return {for (final r in rows) r['floor_id'] as int};
  }

  /// Ένα «αποτύπωμα» της κατάστασης κάθε ορόφου (ενεργός και πότε άλλαξε):
  /// αν διαφέρει από την προηγούμενη ανάγνωση, κάποιος σταθμός άλλαξε κάτι.
  /// Μικρή ανάγνωση, χωρίς εικόνες, για τον περιοδικό έλεγχο.
  Future<Map<int, String>> floorStamps() async {
    final rows = await db.query(
      _state,
      columns: ['floor_id', 'is_active', 'changed_at'],
    );
    return {
      for (final r in rows)
        r['floor_id'] as int: '${r['is_active']}|${r['changed_at']}',
    };
  }

  /// Για κάθε τμήμα από τα [departmentIds], οι **ενεργοί** όροφοι όπου έχει
  /// χώρο στον νέο χάρτη.
  Future<Map<int, Set<int>>> activeFloorsWithRoomsOf(
    Set<int> departmentIds,
  ) async {
    if (departmentIds.isEmpty) return const {};
    final ids = departmentIds.toList();
    final marks = List.filled(ids.length, '?').join(', ');
    final rows = await db.rawQuery(
      '''
      SELECT DISTINCT e.department_id, e.floor_id
      FROM $_elements e
      JOIN $_state s ON s.floor_id = e.floor_id AND s.is_active = 1
      WHERE e.kind = ? AND e.department_id IN ($marks)
      ''',
      [FloorPlanElementKind.room.key, ...ids],
    );
    final result = <int, Set<int>>{};
    for (final r in rows) {
      (result[r['department_id'] as int] ??= {}).add(r['floor_id'] as int);
    }
    return result;
  }

  /// Ο όροφος περνά στον νέο χάρτη: από εδώ και πέρα όλοι τον βλέπουν.
  Future<void> setActive(int floorId) async {
    await db.transaction((txn) async {
      await _ensureRow(txn, floorId);
      await txn.update(
        _state,
        {'is_active': 1, 'changed_at': _now()},
        where: 'floor_id = ?',
        whereArgs: [floorId],
      );
    });
  }

  /// Η κατάσταση του ορόφου· οι προεπιλογές όταν δεν έχει γραφτεί ποτέ.
  Future<FloorPlanState> readState(int floorId) async {
    final rows = await db.query(
      _state,
      columns: FloorPlanState.columns,
      where: 'floor_id = ?',
      whereArgs: [floorId],
      limit: 1,
    );
    if (rows.isEmpty) return FloorPlanState(floorId: floorId);
    return FloorPlanState.fromMap(rows.first);
  }

  Future<Uint8List?> readPatternImage(int floorId) async {
    final rows = await db.query(
      _state,
      columns: ['pattern_image'],
      where: 'floor_id = ?',
      whereArgs: [floorId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final data = rows.first['pattern_image'];
    return data is Uint8List ? data : null;
  }

  /// Φορτώνει νέα εικόνα πατρόν με την τοποθέτηση του [placement].
  Future<void> setPattern(
    int floorId,
    Uint8List bytes,
    FloorPlanState placement,
  ) async {
    await db.transaction((txn) async {
      await _ensureRow(txn, floorId);
      await txn.update(
        _state,
        {
          'pattern_image': bytes,
          'pattern_hash': floorImageHash(bytes),
          ...placement.patternPlacementMap(),
          'changed_at': _now(),
        },
        where: 'floor_id = ?',
        whereArgs: [floorId],
      );
    });
  }

  /// Γράφει μόνο την τοποθέτηση του πατρόν — η εικόνα δεν ξαναταξιδεύει.
  Future<void> savePatternPlacement(FloorPlanState state) async {
    await db.transaction((txn) async {
      await _ensureRow(txn, state.floorId);
      await txn.update(
        _state,
        {...state.patternPlacementMap(), 'changed_at': _now()},
        where: 'floor_id = ?',
        whereArgs: [state.floorId],
      );
    });
  }

  /// Αφαιρεί την εικόνα του πατρόν. Η βαθμονόμηση μένει: ένα νέο πατρόν του
  /// ίδιου ορόφου μάλλον έχει την ίδια κλίμακα.
  Future<void> clearPattern(int floorId) async {
    await db.update(
      _state,
      {'pattern_image': null, 'pattern_hash': null, 'changed_at': _now()},
      where: 'floor_id = ?',
      whereArgs: [floorId],
    );
  }

  /// Σβήνει ολόκληρο τον νέο χάρτη του ορόφου, με τα αντικείμενα και τις
  /// θέσεις του — μαζί με τη διαγραφή του ίδιου του ορόφου.
  Future<void> deleteFloorPlan(DatabaseExecutor executor, int floorId) async {
    await executor.delete(
      _elements,
      where: 'floor_id = ?',
      whereArgs: [floorId],
    );
    await executor.delete(_state, where: 'floor_id = ?', whereArgs: [floorId]);
    // Πρώτα το δίκτυο, όσο ξέρουμε ακόμη ποια αντικείμενα ήταν του ορόφου.
    // Καλώδιο προς άλλον όροφο φεύγει ολόκληρο: χωρίς το ένα άκρο δεν
    // είναι καλώδιο.
    const floorPorts =
        'SELECT p.id FROM building_map_ports p '
        'JOIN building_map_objects o ON o.id = p.object_id '
        'WHERE o.floor_id = ?';
    const floorCables =
        'SELECT cable_id FROM building_map_cable_ends '
        'WHERE port_id IN ($floorPorts)';
    await executor.rawDelete(
      'DELETE FROM building_map_cables WHERE id IN ($floorCables)',
      [floorId],
    );
    await executor.rawDelete(
      'DELETE FROM building_map_cable_ends WHERE cable_id IN ($floorCables)',
      [floorId],
    );
    await executor.rawDelete(
      'DELETE FROM building_map_ports WHERE id IN ($floorPorts)',
      [floorId],
    );
    for (final table in const [
      'building_map_objects',
      'building_map_placements',
    ]) {
      await executor.delete(table, where: 'floor_id = ?', whereArgs: [floorId]);
    }
  }

  Future<void> _ensureRow(DatabaseExecutor executor, int floorId) =>
      _ensureFloorStateRow(executor, floorId);

  Future<void> _touch(DatabaseExecutor executor, int floorId) =>
      touchFloorPlan(executor, floorId);

  static String _now() => DateTime.now().toUtc().toIso8601String();
}

Future<void> _ensureFloorStateRow(
  DatabaseExecutor executor,
  int floorId,
) async {
  await executor.insert('building_map_floor_state', {
    'floor_id': floorId,
  }, conflictAlgorithm: ConflictAlgorithm.ignore);
}

/// Σημειώνει ότι ο νέος χάρτης του ορόφου [floorId] άλλαξε μόλις τώρα — από
/// αυτό το «πότε άλλαξε» οι άλλοι σταθμοί ξέρουν ότι πρέπει να ξαναδιαβάσουν.
/// Κάθε εγγραφή στον χάρτη (σχέδιο, αντικείμενα, θέσεις) περνά από εδώ.
Future<void> touchFloorPlan(DatabaseExecutor executor, int floorId) async {
  await _ensureFloorStateRow(executor, floorId);
  await executor.update(
    'building_map_floor_state',
    {'changed_at': DateTime.now().toUtc().toIso8601String()},
    where: 'floor_id = ?',
    whereArgs: [floorId],
  );
}
