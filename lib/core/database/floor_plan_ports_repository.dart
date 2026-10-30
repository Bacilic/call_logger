import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/floor_plan_port.dart';
import 'floor_plan_repository.dart' show touchFloorPlan;

/// Persistence των **θυρών** των αντικειμένων του νέου χάρτη
/// (`building_map_ports`), και το «ποιες είναι κατειλημμένες» από τα
/// καλώδια.
///
/// Κάθε εγγραφή ενημερώνει το «πότε άλλαξε» του ορόφου του αντικειμένου,
/// ώστε οι άλλοι σταθμοί να το δουν.
class FloorPlanPortsRepository {
  FloorPlanPortsRepository(this.db);

  final Database db;

  static const String _ports = 'building_map_ports';
  static const String _objects = 'building_map_objects';
  static const String _ends = 'building_map_cable_ends';
  static const String _cables = 'building_map_cables';

  static String _marks(int n) => List.filled(n, '?').join(', ');

  /// Οι θύρες των αντικειμένων του ορόφου [floorId], κατά αντικείμενο και
  /// αριθμό.
  Future<List<FloorPlanPort>> listForFloor(int floorId) async {
    final rows = await db.rawQuery(
      'SELECT ${[for (final c in FloorPlanPort.columns) 'p.$c'].join(', ')} '
      'FROM $_ports p JOIN $_objects o ON o.id = p.object_id '
      'WHERE o.floor_id = ? ORDER BY p.object_id ASC, p.number ASC',
      [floorId],
    );
    return [for (final row in rows) FloorPlanPort.fromMap(row)];
  }

  /// Ποιες από τις θύρες [portIds] έχουν καλώδιο — οι υπόλοιπες είναι
  /// ελεύθερες. Δεν αποθηκεύεται πουθενά: υπολογίζεται από τα καλώδια.
  Future<Set<int>> occupiedPortIds(Iterable<int> portIds) async {
    final ids = portIds.toSet().toList();
    if (ids.isEmpty) return const {};
    final occupied = <int>{};
    // Σε κομμάτια: ένας όροφος με εκατοντάδες πρίζες ξεπερνά το όριο
    // παραμέτρων μιας ερώτησης.
    for (var i = 0; i < ids.length; i += 500) {
      final chunk = ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
      final rows = await db.query(
        _ends,
        columns: ['port_id'],
        where: 'port_id IN (${_marks(chunk.length)})',
        whereArgs: chunk,
      );
      for (final r in rows) {
        occupied.add(r['port_id'] as int);
      }
    }
    return occupied;
  }

  /// Γράφει θύρες **με τα δικά τους id** — νέες, αλλαγμένες, ή αναίρεση
  /// διαγραφής. Ασφαλές επειδή ο πίνακας είναι AUTOINCREMENT.
  Future<void> restorePorts(List<FloorPlanPort> ports) async {
    if (ports.isEmpty) return;
    await db.transaction((txn) async {
      for (final p in ports) {
        await txn.insert(_ports, {
          'id': p.id,
          ...p.toInsertMap(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await _touchFloorsOf(txn, {for (final p in ports) p.objectId});
    });
  }

  /// Νέες θύρες· επιστρέφονται με τα id τους.
  Future<List<FloorPlanPort>> insertPorts(List<FloorPlanPort> ports) async {
    if (ports.isEmpty) return const [];
    return db.transaction((txn) async {
      final stored = <FloorPlanPort>[];
      for (final p in ports) {
        final id = await txn.insert(_ports, p.toInsertMap());
        stored.add(p.copyWith(id: id));
      }
      await _touchFloorsOf(txn, {for (final p in ports) p.objectId});
      return stored;
    });
  }

  /// Σβήνει τις θύρες [ids] — και τα καλώδιά τους — και επιστρέφει όσες
  /// έσβησε, για την αναίρεση.
  Future<List<FloorPlanPort>> deletePorts(Iterable<int> ids) =>
      _delete('id', ids.toSet().toList());

  /// Σβήνει όλες τις θύρες των αντικειμένων [objectIds] — π.χ. γιατί
  /// σβήστηκαν τα ίδια — και τις επιστρέφει για την αναίρεση.
  Future<List<FloorPlanPort>> deletePortsOfObjects(Iterable<int> objectIds) =>
      _delete('object_id', objectIds.toSet().toList());

  Future<List<FloorPlanPort>> _delete(String column, List<int> ids) async {
    if (ids.isEmpty) return const [];
    return db.transaction((txn) async {
      final rows = await txn.query(
        _ports,
        columns: FloorPlanPort.columns,
        where: '$column IN (${_marks(ids.length)})',
        whereArgs: ids,
        orderBy: 'object_id ASC, number ASC',
      );
      final removed = [for (final r in rows) FloorPlanPort.fromMap(r)];
      if (removed.isEmpty) return removed;
      final portIds = [for (final p in removed) p.id];
      final marks = _marks(portIds.length);
      // Καλώδιο χωρίς το ένα του άκρο δεν είναι καλώδιο: φεύγει ολόκληρο.
      const cablesOf = 'SELECT cable_id FROM $_ends WHERE port_id IN';
      await txn.rawDelete(
        'DELETE FROM $_cables WHERE id IN ($cablesOf ($marks))',
        portIds,
      );
      await txn.rawDelete(
        'DELETE FROM $_ends WHERE cable_id IN ($cablesOf ($marks))',
        portIds,
      );
      await txn.delete(_ports, where: 'id IN ($marks)', whereArgs: portIds);
      await _touchFloorsOf(txn, {for (final p in removed) p.objectId});
      return removed;
    });
  }

  Future<void> _touchFloorsOf(DatabaseExecutor txn, Set<int> objectIds) async {
    if (objectIds.isEmpty) return;
    final ids = objectIds.toList();
    final rows = await txn.query(
      _objects,
      columns: ['DISTINCT floor_id'],
      where: 'id IN (${_marks(ids.length)})',
      whereArgs: ids,
    );
    for (final r in rows) {
      await touchFloorPlan(txn, r['floor_id'] as int);
    }
  }
}
