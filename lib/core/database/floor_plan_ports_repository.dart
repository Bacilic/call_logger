import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/floor_plan_object_kind.dart';
import '../models/floor_plan_port.dart';
import 'floor_plan_repository.dart' show touchFloorPlan;

/// Ό,τι έσβησε μια διαγραφή θυρών, για την αναίρεση: οι θύρες και τα καλώδιά
/// τους.
typedef FloorPlanPortsRemoval = ({
  List<FloorPlanPort> ports,
  List<FloorPlanCable> cables,
});

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
  static const String _kinds = 'building_map_object_kinds';
  static const String _ends = 'building_map_cable_ends';
  static const String _cables = 'building_map_cables';

  static String _marks(int n) => List.filled(n, '?').join(', ');

  /// Το όνομα του stack του αντικειμένου [alias]: το όνομα του μικρότερου
  /// μέλους. Το CASE δεν είναι διακοσμητικό: χωρίς αυτό, κάθε θύρα σαρώνει όλα
  /// τα αντικείμενα ακόμη κι όταν δεν ανήκει σε stack (μετρημένο 04/11/2026:
  /// 4 δευτερόλεπτα σε 17.600 θύρες).
  static String _stackNameOf(String alias) =>
      'CASE WHEN $alias.stack_id IS NULL THEN NULL ELSE '
      '(SELECT s.name FROM $_objects s WHERE s.stack_id = $alias.stack_id '
      'ORDER BY s.stack_unit LIMIT 1) END';

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

  /// Σβήνει τις θύρες [ids] — και τα καλώδιά τους — και επιστρέφει όσα
  /// έσβησε, για την αναίρεση.
  Future<FloorPlanPortsRemoval> deletePorts(Iterable<int> ids) =>
      _delete('id', ids.toSet().toList());

  /// Σβήνει όλες τις θύρες των αντικειμένων [objectIds] — π.χ. γιατί
  /// σβήστηκαν τα ίδια — και επιστρέφει όσα έσβησε για την αναίρεση.
  Future<FloorPlanPortsRemoval> deletePortsOfObjects(Iterable<int> objectIds) =>
      _delete('object_id', objectIds.toSet().toList());

  Future<FloorPlanPortsRemoval> _delete(String column, List<int> ids) async {
    if (ids.isEmpty) {
      return const (ports: <FloorPlanPort>[], cables: <FloorPlanCable>[]);
    }
    return db.transaction((txn) async {
      final rows = await txn.query(
        _ports,
        columns: FloorPlanPort.columns,
        where: '$column IN (${_marks(ids.length)})',
        whereArgs: ids,
        orderBy: 'object_id ASC, number ASC',
      );
      final removed = [for (final r in rows) FloorPlanPort.fromMap(r)];
      if (removed.isEmpty) return (ports: removed, cables: <FloorPlanCable>[]);
      final portIds = [for (final p in removed) p.id];
      final marks = _marks(portIds.length);
      // Καλώδιο χωρίς το ένα του άκρο δεν είναι καλώδιο: φεύγει ολόκληρο.
      final cables = await _cablesTouching(txn, portIds);
      await _deleteCablesTouching(txn, portIds);
      await txn.delete(_ports, where: 'id IN ($marks)', whereArgs: portIds);
      await _touchFloorsOf(txn, {for (final p in removed) p.objectId});
      await _touchFloorsOfPorts(txn, _cablePorts(cables));
      return (ports: removed, cables: cables);
    });
  }

  // ── Καλώδια ───────────────────────────────────────────────────────────

  /// Οι συνδέσεις πρίζας — patch panel που αγγίζουν τον όροφο [floorId], από
  /// όποια μεριά: η πρίζα μπορεί να είναι εδώ και το patch panel αλλού, ή το
  /// ανάποδο.
  Future<List<FloorPlanPortLink>> linksForFloor(int floorId) async {
    final rows = await db.rawQuery(
      'SELECT oe.port_id AS outlet_port_id, oo.floor_id AS outlet_floor_id, '
      'pe.port_id AS patch_port_id, pp.number AS patch_number, '
      'pp.written_name AS patch_written_name, po.id AS panel_id, '
      'po.name AS panel_name, po.floor_id AS panel_floor_id, '
      'po.cabinet_id AS cabinet_id, c.name AS cabinet_name, '
      'op.connected_equipment_id, '
      'op.connected_object_id, op.connected_text, '
      "COALESCE(NULLIF(TRIM(co.name), ''), ck.name) AS connected_label "
      'FROM $_ends pe '
      'JOIN $_ends oe ON oe.cable_id = pe.cable_id AND oe.port_id <> pe.port_id '
      'JOIN $_ports pp ON pp.id = pe.port_id '
      'JOIN $_objects po ON po.id = pp.object_id '
      'LEFT JOIN $_objects c ON c.id = po.cabinet_id '
      'JOIN $_ports op ON op.id = oe.port_id '
      'JOIN $_objects oo ON oo.id = op.object_id '
      'LEFT JOIN $_objects co ON co.id = op.connected_object_id '
      'LEFT JOIN $_kinds ck ON ck.id = co.kind_id '
      'WHERE pe.side = ? AND (oo.floor_id = ? OR po.floor_id = ?)',
      [kFloorPlanCableBack, floorId, floorId],
    );
    return [
      for (final r in rows)
        FloorPlanPortLink(
          outletPortId: r['outlet_port_id'] as int,
          outletFloorId: r['outlet_floor_id'] as int,
          patchPortId: r['patch_port_id'] as int,
          patchNumber: r['patch_number'] as int,
          patchWrittenName: r['patch_written_name'] as String?,
          panelId: r['panel_id'] as int,
          panelName: r['panel_name'] as String?,
          panelFloorId: r['panel_floor_id'] as int,
          cabinetId: r['cabinet_id'] as int?,
          cabinetName: r['cabinet_name'] as String?,
          connection: FloorPlanPortConnection(
            equipmentId: r['connected_equipment_id'] as int?,
            objectId: r['connected_object_id'] as int?,
            text: r['connected_text'] as String?,
          ),
          connectedObjectLabel: r['connected_label'] as String?,
        ),
    ];
  }

  /// Όλα τα καλώδια που αγγίζουν τον όροφο [floorId], με τα ονόματα και των
  /// δύο άκρων τους.
  Future<List<FloorPlanCableLine>> cableLinesForFloor(int floorId) async {
    String end(String e, String p, String o, String c, String k) =>
        '$e.port_id AS ${e}_port, $e.side AS ${e}_side, '
        '$p.number AS ${e}_number, $p.written_name AS ${e}_written, '
        '$o.id AS ${e}_object, $o.name AS ${e}_name, '
        '$o.floor_id AS ${e}_floor, $c.name AS ${e}_cabinet, '
        '$k.symbol AS ${e}_symbol, $k.name AS ${e}_kind, '
        '$o.stack_unit AS ${e}_unit, $o.port_type AS ${e}_type, '
        '${_stackNameOf(o)} AS ${e}_stack';
    String joins(String e, String p, String o, String c, String k) =>
        'JOIN $_ports $p ON $p.id = $e.port_id '
        'JOIN $_objects $o ON $o.id = $p.object_id '
        'LEFT JOIN $_objects $c ON $c.id = $o.cabinet_id '
        'LEFT JOIN $_kinds $k ON $k.id = $o.kind_id ';
    final rows = await db.rawQuery(
      'SELECT a.cable_id, ${end('a', 'pa', 'oa', 'ca', 'ka')}, '
      '${end('b', 'pb', 'ob', 'cb', 'kb')} '
      'FROM $_ends a '
      'JOIN $_ends b ON b.cable_id = a.cable_id AND a.port_id < b.port_id '
      '${joins('a', 'pa', 'oa', 'ca', 'ka')}'
      '${joins('b', 'pb', 'ob', 'cb', 'kb')}'
      'WHERE oa.floor_id = ? OR ob.floor_id = ?',
      [floorId, floorId],
    );
    FloorPlanCableEnd read(Map<String, Object?> r, String e) =>
        FloorPlanCableEnd(
          portId: r['${e}_port'] as int,
          side: r['${e}_side'] as String,
          number: r['${e}_number'] as int,
          writtenName: r['${e}_written'] as String?,
          objectId: r['${e}_object'] as int,
          objectName: r['${e}_name'] as String?,
          floorId: r['${e}_floor'] as int,
          cabinetName: r['${e}_cabinet'] as String?,
          symbol: FloorPlanSymbol.fromKey(r['${e}_symbol'] as String?),
          kindName: r['${e}_kind'] as String?,
          stackName: r['${e}_stack'] as String?,
          stackUnit: r['${e}_unit'] as int?,
          portType: r['${e}_type'] as String?,
        );
    return [
      for (final r in rows)
        FloorPlanCableLine(
          cableId: r['cable_id'] as int,
          a: read(r, 'a'),
          b: read(r, 'b'),
        ),
    ];
  }

  /// Οι θύρες που βρίσκει η αναζήτηση στους ορόφους [floorIds]: πρίζες, patch
  /// panel, switches, router και POE. Οι συσκευές με μία θύρα βρίσκονται με το
  /// όνομά τους.
  Future<List<FloorPlanPortSearchRow>> searchablePorts(
    Set<int> floorIds,
  ) async {
    if (floorIds.isEmpty) return const [];
    final floors = floorIds.toList();
    const symbols = [
      FloorPlanSymbol.outlet,
      FloorPlanSymbol.patchPanel,
      FloorPlanSymbol.networkSwitch,
      FloorPlanSymbol.router,
      FloorPlanSymbol.poe,
    ];
    final rows = await db.rawQuery(
      'SELECT p.id, p.number, p.written_name, o.id AS object_id, o.name, '
      'o.floor_id, o.stack_unit, o.port_type, k.symbol, k.name AS kind_name, '
      'c.id AS cabinet_id, c.name AS cabinet_name, '
      '${_stackNameOf('o')} AS stack_name, '
      'lp.number AS linked_number, lo.name AS linked_panel, '
      'lc.name AS linked_cabinet '
      'FROM $_ports p '
      'JOIN $_objects o ON o.id = p.object_id '
      'JOIN $_kinds k ON k.id = o.kind_id '
      'LEFT JOIN $_objects c ON c.id = o.cabinet_id '
      'LEFT JOIN $_ends oe ON oe.port_id = p.id AND k.symbol = ? '
      'LEFT JOIN $_ends pe ON pe.cable_id = oe.cable_id AND pe.side = ? '
      'LEFT JOIN $_ports lp ON lp.id = pe.port_id '
      'LEFT JOIN $_objects lo ON lo.id = lp.object_id '
      'LEFT JOIN $_objects lc ON lc.id = lo.cabinet_id '
      'WHERE o.floor_id IN (${_marks(floors.length)}) '
      'AND k.symbol IN (${_marks(symbols.length)})',
      [
        FloorPlanSymbol.outlet.key,
        kFloorPlanCableBack,
        ...floors,
        for (final s in symbols) s.key,
      ],
    );
    return [
      for (final r in rows)
        FloorPlanPortSearchRow(
          portId: r['id'] as int,
          number: r['number'] as int,
          writtenName: r['written_name'] as String?,
          objectId: r['object_id'] as int,
          objectName: (r['stack_name'] ?? r['name']) as String?,
          floorId: r['floor_id'] as int,
          stackUnit: r['stack_unit'] as int?,
          portType: r['port_type'] as String?,
          symbol: FloorPlanSymbol.fromKey(r['symbol'] as String?),
          kindName: r['kind_name'] as String?,
          cabinetId: r['cabinet_id'] as int?,
          cabinetName: r['cabinet_name'] as String?,
          linkedNumber: r['linked_number'] as int?,
          linkedPanelName: r['linked_panel'] as String?,
          linkedCabinetName: r['linked_cabinet'] as String?,
        ),
    ];
  }

  /// Όλες οι θύρες patch panel του κτιρίου — διαβάζεται μόνο όταν ανοίγει η
  /// επιλογή «Σύνδεση με patch panel…».
  Future<List<FloorPlanPatchPortOption>> patchPortOptions() async {
    final rows = await db.rawQuery(
      'SELECT p.id, p.number, p.written_name, o.id AS panel_id, '
      'o.name AS panel_name, o.floor_id, c.name AS cabinet_name, '
      'e.port_id AS taken_port '
      'FROM $_ports p '
      'JOIN $_objects o ON o.id = p.object_id '
      'JOIN $_kinds k ON k.id = o.kind_id '
      'LEFT JOIN $_objects c ON c.id = o.cabinet_id '
      'LEFT JOIN $_ends e ON e.port_id = p.id AND e.side = ? '
      'WHERE k.symbol = ? '
      'ORDER BY o.floor_id ASC, c.name ASC, o.name ASC, p.number ASC',
      [kFloorPlanCableBack, FloorPlanSymbol.patchPanel.key],
    );
    return [
      for (final r in rows)
        FloorPlanPatchPortOption(
          portId: r['id'] as int,
          number: r['number'] as int,
          writtenName: r['written_name'] as String?,
          panelId: r['panel_id'] as int,
          panelName: r['panel_name'] as String?,
          floorId: r['floor_id'] as int,
          cabinetName: r['cabinet_name'] as String?,
          taken: r['taken_port'] != null,
        ),
    ];
  }

  /// Δένει τη θύρα πρίζας [outletPortId] με τη θύρα patch panel [patchPortId].
  /// `null` όταν η θύρα του patch panel πιάστηκε στο μεταξύ (π.χ. από άλλον
  /// σταθμό): κάθε πλευρά δέχεται ένα καλώδιο.
  Future<FloorPlanCable?> connectOutletPort(
    int outletPortId,
    int patchPortId,
  ) => connectPorts(
    outletPortId,
    kFloorPlanCableFront,
    patchPortId,
    kFloorPlanCableBack,
  );

  /// Νέο καλώδιο ανάμεσα σε δύο θύρες· `null` όταν κάποια πλευρά έχει ήδη
  /// καλώδιο — το φυλά η βάση και για ό,τι έγραψε στο μεταξύ άλλος σταθμός.
  Future<FloorPlanCable?> connectPorts(
    int portA,
    String sideA,
    int portB,
    String sideB,
  ) async {
    return db.transaction((txn) async {
      for (final (port, side) in [(portA, sideA), (portB, sideB)]) {
        final taken = await txn.query(
          _ends,
          columns: ['cable_id'],
          where: 'port_id = ? AND side = ?',
          whereArgs: [port, side],
        );
        if (taken.isNotEmpty) return null;
      }
      final id = await txn.insert(_cables, {'id': null});
      final cable = FloorPlanCable(
        id: id,
        portA: portA,
        sideA: sideA,
        portB: portB,
        sideB: sideB,
      );
      await _insertEnds(txn, cable);
      await _touchFloorsOfPorts(txn, _cablePorts([cable]));
      return cable;
    });
  }

  /// Σβήνει τα καλώδια που αγγίζουν τις θύρες [portIds] και τα επιστρέφει.
  Future<List<FloorPlanCable>> deleteCablesOfPorts(Iterable<int> portIds) {
    final ids = portIds.toSet().toList();
    if (ids.isEmpty) return Future.value(const []);
    return db.transaction((txn) async {
      final cables = await _cablesTouching(txn, ids);
      await _deleteCablesTouching(txn, ids);
      await _touchFloorsOfPorts(txn, _cablePorts(cables));
      return cables;
    });
  }

  /// Σβήνει τα καλώδια [ids] και επιστρέφει όσα βρήκε.
  Future<List<FloorPlanCable>> deleteCables(Iterable<int> ids) {
    final list = ids.toSet().toList();
    if (list.isEmpty) return Future.value(const []);
    return db.transaction((txn) async {
      final rows = await txn.query(
        _ends,
        columns: ['cable_id', 'port_id', 'side'],
        where: 'cable_id IN (${_marks(list.length)})',
        whereArgs: list,
        orderBy: 'cable_id ASC, port_id ASC',
      );
      final cables = _cablesFromEnds(rows);
      await _deleteCableRows(txn, list);
      await _touchFloorsOfPorts(txn, _cablePorts(cables));
      return cables;
    });
  }

  /// Ξαναγράφει καλώδια **με τα δικά τους id** — αναίρεση διαγραφής. Όσα δεν
  /// γίνεται να ξαναμπούν (μια θύρα δεν υπάρχει πια, ή η πλευρά της πιάστηκε
  /// στο μεταξύ) παραλείπονται και επιστρέφονται, για να το μάθει ο χρήστης.
  Future<List<FloorPlanCable>> restoreCables(List<FloorPlanCable> cables) {
    if (cables.isEmpty) return Future.value(const []);
    return db.transaction((txn) async {
      final skipped = <FloorPlanCable>[];
      for (final c in cables) {
        if (!await _endFree(txn, c.id, c.portA, c.sideA) ||
            !await _endFree(txn, c.id, c.portB, c.sideB)) {
          skipped.add(c);
          continue;
        }
        await txn.insert(_cables, {
          'id': c.id,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await txn.delete(_ends, where: 'cable_id = ?', whereArgs: [c.id]);
        await _insertEnds(txn, c);
      }
      await _touchFloorsOfPorts(txn, _cablePorts(cables));
      return skipped;
    });
  }

  Future<bool> _endFree(
    DatabaseExecutor txn,
    int cableId,
    int portId,
    String side,
  ) async {
    final port = await txn.query(
      _ports,
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [portId],
    );
    if (port.isEmpty) return false;
    final taken = await txn.query(
      _ends,
      columns: ['cable_id'],
      where: 'port_id = ? AND side = ? AND cable_id <> ?',
      whereArgs: [portId, side, cableId],
    );
    return taken.isEmpty;
  }

  Future<void> _insertEnds(DatabaseExecutor txn, FloorPlanCable c) async {
    await txn.insert(_ends, {
      'cable_id': c.id,
      'port_id': c.portA,
      'side': c.sideA,
    });
    await txn.insert(_ends, {
      'cable_id': c.id,
      'port_id': c.portB,
      'side': c.sideB,
    });
  }

  Future<List<FloorPlanCable>> _cablesTouching(
    DatabaseExecutor txn,
    List<int> portIds,
  ) async {
    final rows = await txn.rawQuery(
      'SELECT cable_id, port_id, side FROM $_ends WHERE cable_id IN '
      '(SELECT cable_id FROM $_ends '
      'WHERE port_id IN (${_marks(portIds.length)})) '
      'ORDER BY cable_id ASC, port_id ASC',
      portIds,
    );
    return _cablesFromEnds(rows);
  }

  /// Κάθε καλώδιο έχει δύο άκρα· όσα μείνουν μισά δεν επιστρέφονται, αφού η
  /// αναίρεση δεν θα μπορούσε να τα ξαναγράψει.
  static List<FloorPlanCable> _cablesFromEnds(List<Map<String, Object?>> rows) {
    final byCable = <int, List<Map<String, Object?>>>{};
    for (final r in rows) {
      (byCable[r['cable_id'] as int] ??= []).add(r);
    }
    return [
      for (final MapEntry(key: id, value: ends) in byCable.entries)
        if (ends.length == 2)
          FloorPlanCable(
            id: id,
            portA: ends[0]['port_id'] as int,
            sideA: ends[0]['side'] as String,
            portB: ends[1]['port_id'] as int,
            sideB: ends[1]['side'] as String,
          ),
    ];
  }

  Future<void> _deleteCablesTouching(
    DatabaseExecutor txn,
    List<int> portIds,
  ) async {
    final marks = _marks(portIds.length);
    const cablesOf = 'SELECT cable_id FROM $_ends WHERE port_id IN';
    await txn.rawDelete(
      'DELETE FROM $_cables WHERE id IN ($cablesOf ($marks))',
      portIds,
    );
    await txn.rawDelete(
      'DELETE FROM $_ends WHERE cable_id IN ($cablesOf ($marks))',
      portIds,
    );
  }

  Future<void> _deleteCableRows(DatabaseExecutor txn, List<int> ids) async {
    if (ids.isEmpty) return;
    final marks = _marks(ids.length);
    await txn.delete(_ends, where: 'cable_id IN ($marks)', whereArgs: ids);
    await txn.delete(_cables, where: 'id IN ($marks)', whereArgs: ids);
  }

  static Set<int> _cablePorts(List<FloorPlanCable> cables) => {
    for (final c in cables) ...[c.portA, c.portB],
  };

  /// Το καλώδιο μπορεί να περνά από όροφο σε όροφο: ενημερώνονται και οι δύο.
  Future<void> _touchFloorsOfPorts(
    DatabaseExecutor txn,
    Set<int> portIds,
  ) async {
    if (portIds.isEmpty) return;
    final ids = portIds.toList();
    final rows = await txn.query(
      _ports,
      columns: ['DISTINCT object_id'],
      where: 'id IN (${_marks(ids.length)})',
      whereArgs: ids,
    );
    await _touchFloorsOf(txn, {for (final r in rows) r['object_id'] as int});
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
