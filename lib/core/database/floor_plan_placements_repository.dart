import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/floor_plan_placement.dart';
import 'floor_plan_repository.dart' show touchFloorPlan;

/// Persistence των **θέσεων** υπαλλήλων, τηλεφώνων και εξοπλισμού του
/// Καταλόγου στον νέο χάρτη (`building_map_placements`).
///
/// Ό,τι έχει διαγραφεί στον Κατάλογο δεν διαβάζεται: εξαφανίζεται από τον
/// χάρτη, και αν επανέλθει από τη διαγραφή, επιστρέφει στη θέση του. Ο
/// Κατάλογος δεν ρωτά τίποτα για τον χάρτη.
class FloorPlanPlacementsRepository {
  FloorPlanPlacementsRepository(this.db);

  final Database db;

  static const String _table = 'building_map_placements';

  /// Η συνθήκη «η εγγραφή του Καταλόγου ζει ακόμη», για τη γραμμή `p`.
  static const String _alive = '''
    ((p.entity_type = 'user' AND EXISTS (
        SELECT 1 FROM users u
        WHERE u.id = p.entity_id AND COALESCE(u.is_deleted, 0) = 0))
     OR (p.entity_type = 'phone' AND EXISTS (
        SELECT 1 FROM phones t
        WHERE t.id = p.entity_id AND COALESCE(t.is_deleted, 0) = 0))
     OR (p.entity_type = 'equipment' AND EXISTS (
        SELECT 1 FROM equipment e
        WHERE e.id = p.entity_id AND COALESCE(e.is_deleted, 0) = 0)))
  ''';

  static final String _columns = [
    for (final c in FloorPlanPlacement.columns) 'p.$c',
  ].join(', ');

  Future<List<FloorPlanPlacement>> listPlacements(int floorId) async {
    final rows = await db.rawQuery(
      'SELECT $_columns FROM $_table p '
      'WHERE p.floor_id = ? AND $_alive ORDER BY p.id ASC',
      [floorId],
    );
    return [for (final row in rows) ?FloorPlanPlacement.fromMap(row)];
  }

  /// Όλες οι θέσεις όλων των ορόφων — για να ξέρει ο κατάλογος του πάνελ
  /// ποιος έχει ήδη θέση και πού.
  Future<List<FloorPlanPlacement>> allPlacements() async {
    final rows = await db.rawQuery(
      'SELECT $_columns FROM $_table p WHERE $_alive ORDER BY p.id ASC',
    );
    return [for (final row in rows) ?FloorPlanPlacement.fromMap(row)];
  }

  /// Οι θέσεις μίας εγγραφής του Καταλόγου σε **ενεργοποιημένους** ορόφους —
  /// ό,τι βλέπουν οι συνάδελφοι, π.χ. στον μικρό χάρτη της κλήσης.
  Future<List<FloorPlanPlacement>> activePlacementsOf(
    FloorPlanPlacementType type,
    int entityId,
  ) async {
    final rows = await db.rawQuery(
      'SELECT $_columns FROM $_table p '
      'JOIN building_map_floor_state s '
      'ON s.floor_id = p.floor_id AND s.is_active = 1 '
      'WHERE p.entity_type = ? AND p.entity_id = ? AND $_alive '
      'ORDER BY p.id ASC',
      [type.key, entityId],
    );
    return [for (final row in rows) ?FloorPlanPlacement.fromMap(row)];
  }

  /// Γράφει νέα θέση και επιστρέφει το id της. Δεύτερη θέση τηλεφώνου ή
  /// εξοπλισμού την αρνείται η ίδια η βάση.
  Future<int> insertPlacement(FloorPlanPlacement placement) async {
    return db.transaction((txn) async {
      final id = await txn.insert(_table, placement.toInsertMap());
      await touchFloorPlan(txn, placement.floorId);
      return id;
    });
  }

  /// Ξαναγράφει θέσεις **με τα δικά τους id** — μετακίνηση, μεταφορά σε
  /// άλλον όροφο ή αναίρεση διαγραφής. Ενημερώνει και τον όροφο που άφησαν.
  Future<void> restorePlacements(List<FloorPlanPlacement> placements) async {
    if (placements.isEmpty) return;
    await db.transaction((txn) async {
      final floors = <int>{};
      for (final p in placements) {
        final old = await txn.query(
          _table,
          columns: ['floor_id'],
          where: 'id = ?',
          whereArgs: [p.id],
        );
        if (old.isNotEmpty) floors.add(old.first['floor_id'] as int);
        await txn.insert(_table, {
          'id': p.id,
          ...p.toInsertMap(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        floors.add(p.floorId);
      }
      for (final floorId in floors) {
        await touchFloorPlan(txn, floorId);
      }
    });
  }

  /// Σβήνει τις θέσεις [ids] — μόνο από τον χάρτη· ο Κατάλογος μένει άθικτος.
  /// Επιστρέφει όσες έσβησε, για την αναίρεση.
  Future<List<FloorPlanPlacement>> deletePlacements(Iterable<int> ids) async {
    final idList = ids.toSet().toList();
    if (idList.isEmpty) return const [];
    return db.transaction((txn) async {
      final marks = List.filled(idList.length, '?').join(', ');
      final rows = await txn.query(
        _table,
        columns: FloorPlanPlacement.columns,
        where: 'id IN ($marks)',
        whereArgs: idList,
        orderBy: 'id ASC',
      );
      final removed = [
        for (final row in rows) ?FloorPlanPlacement.fromMap(row),
      ];
      await txn.delete(_table, where: 'id IN ($marks)', whereArgs: idList);
      for (final floorId in {for (final p in removed) p.floorId}) {
        await touchFloorPlan(txn, floorId);
      }
      return removed;
    });
  }

  /// Οι εγγραφές του Καταλόγου που τοποθετούνται: υπάλληλοι, τηλέφωνα και
  /// εξοπλισμός, χωρίς τα διαγραμμένα, με τα τμήματά τους.
  Future<List<FloorPlanCatalogEntry>> catalogEntries() async {
    final users = await db.rawQuery('''
      SELECT id, last_name, first_name, department_id FROM users
      WHERE COALESCE(is_deleted, 0) = 0
      ORDER BY last_name COLLATE NOCASE, first_name COLLATE NOCASE
    ''');
    final phones = await db.rawQuery('''
      SELECT id, number, department_id FROM phones
      WHERE COALESCE(is_deleted, 0) = 0
      ORDER BY number
    ''');
    final phoneDepartments = await db.rawQuery(
      'SELECT phone_id, department_id FROM department_phones',
    );
    final equipment = await db.rawQuery('''
      SELECT id, code_equipment, department_id, lansweeper_asset_name
      FROM equipment
      WHERE COALESCE(is_deleted, 0) = 0
      ORDER BY code_equipment COLLATE NOCASE
    ''');
    // Οι σχέσεις για την υπόδειξη: ποιος έχει ποιο τηλέφωνο και ποιον
    // εξοπλισμό — μόνο ανάμεσα σε ζωντανές εγγραφές.
    final userPhones = await db.rawQuery('''
      SELECT up.user_id, up.phone_id FROM user_phones up
      JOIN users u ON u.id = up.user_id AND COALESCE(u.is_deleted, 0) = 0
      JOIN phones t ON t.id = up.phone_id AND COALESCE(t.is_deleted, 0) = 0
    ''');
    final userEquipment = await db.rawQuery('''
      SELECT ue.user_id, ue.equipment_id FROM user_equipment ue
      JOIN users u ON u.id = ue.user_id AND COALESCE(u.is_deleted, 0) = 0
      JOIN equipment e ON e.id = ue.equipment_id
        AND COALESCE(e.is_deleted, 0) = 0
    ''');

    final departmentsOfPhone = <int, Set<int>>{};
    for (final r in phoneDepartments) {
      (departmentsOfPhone[r['phone_id'] as int] ??= {}).add(
        r['department_id'] as int,
      );
    }
    Set<int> one(Object? id) => id is int ? {id} : const {};

    String userLabel(Map<String, Object?> r) =>
        '${r['last_name'] ?? ''} ${r['first_name'] ?? ''}'.trim();
    String equipmentLabel(Map<String, Object?> r) {
      final code = (r['code_equipment'] as String?)?.trim() ?? '';
      return code.isNotEmpty ? code : 'Εξοπλισμός ${r['id']}';
    }

    final userNames = {for (final r in users) r['id'] as int: userLabel(r)};
    final phoneNumbers = {
      for (final r in phones) r['id'] as int: r['number'] as String? ?? '',
    };
    final equipmentCodes = {
      for (final r in equipment) r['id'] as int: equipmentLabel(r),
    };
    final phonesOfUser = <int, List<String>>{};
    final holdersOfPhone = <int, List<String>>{};
    for (final r in userPhones) {
      final user = r['user_id'] as int;
      final phone = r['phone_id'] as int;
      (phonesOfUser[user] ??= []).add(phoneNumbers[phone] ?? '');
      (holdersOfPhone[phone] ??= []).add(userNames[user] ?? '');
    }
    final equipmentOfUser = <int, List<String>>{};
    final holdersOfEquipment = <int, List<String>>{};
    for (final r in userEquipment) {
      final user = r['user_id'] as int;
      final item = r['equipment_id'] as int;
      (equipmentOfUser[user] ??= []).add(equipmentCodes[item] ?? '');
      (holdersOfEquipment[item] ??= []).add(userNames[user] ?? '');
    }
    List<String> sorted(List<String>? list) => [...?list]..sort();

    return [
      for (final r in users)
        FloorPlanCatalogEntry(
          type: FloorPlanPlacementType.user,
          entityId: r['id'] as int,
          label: userLabel(r),
          departmentIds: one(r['department_id']),
          phones: sorted(phonesOfUser[r['id'] as int]),
          equipment: sorted(equipmentOfUser[r['id'] as int]),
        ),
      for (final r in phones)
        FloorPlanCatalogEntry(
          type: FloorPlanPlacementType.phone,
          entityId: r['id'] as int,
          label: r['number'] as String? ?? '',
          departmentIds: {
            ...one(r['department_id']),
            ...?departmentsOfPhone[r['id'] as int],
          },
          holders: sorted(holdersOfPhone[r['id'] as int]),
        ),
      for (final r in equipment)
        FloorPlanCatalogEntry(
          type: FloorPlanPlacementType.equipment,
          entityId: r['id'] as int,
          label: equipmentLabel(r),
          departmentIds: one(r['department_id']),
          holders: sorted(holdersOfEquipment[r['id'] as int]),
          lansweeperName: (r['lansweeper_asset_name'] as String?)?.trim(),
        ),
    ];
  }
}
