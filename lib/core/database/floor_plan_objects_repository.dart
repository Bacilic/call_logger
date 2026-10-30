import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/floor_plan_object.dart';
import '../models/floor_plan_object_kind.dart';
import '../utils/search_text_normalizer.dart';
import 'floor_plan_repository.dart' show touchFloorPlan;

/// Τι έγινε με μια αποθήκευση είδους.
enum FloorPlanKindSaveOutcome {
  saved,

  /// Υπάρχει ήδη είδος με το ίδιο όνομα (αγνοώντας τόνους και κεφαλαία).
  nameTaken,

  /// Το είδος σβήστηκε στο μεταξύ από άλλον σταθμό.
  missing,
}

/// Persistence των **αντικειμένων** του νέου χάρτη: τα είδη τους
/// (`building_map_object_kinds`) και τα ίδια τα αντικείμενα
/// (`building_map_objects`).
///
/// Κάθε εγγραφή αντικειμένου ενημερώνει και το «πότε άλλαξε» του ορόφου, ώστε
/// οι άλλοι σταθμοί να το δουν.
class FloorPlanObjectsRepository {
  FloorPlanObjectsRepository(this.db);

  final Database db;

  static const String _kinds = 'building_map_object_kinds';
  static const String _objects = 'building_map_objects';

  /// Το όνομα όπως συγκρίνεται: χωρίς τόνους, κεφαλαία και διπλά κενά.
  static String nameKey(String name) =>
      SearchTextNormalizer.normalizeForSearch(name.trim())
          .replaceAll(RegExp(r'\s+'), ' ');

  /// Όλα τα είδη, αλφαβητικά, το καθένα με τα αντικείμενά του.
  Future<List<FloorPlanObjectKindUsage>> listKinds() async {
    final kindRows = await db.query(
      _kinds,
      columns: FloorPlanObjectKind.columns,
      orderBy: 'name_key ASC',
    );
    final usageRows = await db.rawQuery(
      'SELECT kind_id, floor_id, COUNT(*) AS n FROM $_objects '
      'GROUP BY kind_id, floor_id',
    );
    final counts = <int, int>{};
    final floors = <int, Set<int>>{};
    for (final r in usageRows) {
      final kindId = r['kind_id'] as int;
      counts[kindId] = (counts[kindId] ?? 0) + (r['n'] as int);
      (floors[kindId] ??= {}).add(r['floor_id'] as int);
    }
    return [
      for (final row in kindRows)
        FloorPlanObjectKindUsage(
          kind: FloorPlanObjectKind.fromMap(row),
          objectCount: counts[row['id']] ?? 0,
          floorIds: floors[row['id']] ?? const {},
        ),
    ];
  }

  /// Νέο είδος. [FloorPlanKindSaveOutcome.nameTaken] αν το όνομα υπάρχει ήδη.
  Future<FloorPlanKindSaveOutcome> addKind({
    required String name,
    required FloorPlanSymbol symbol,
    required bool hasPorts,
    bool showInfo = true,
  }) async {
    final key = nameKey(name);
    return db.transaction((txn) async {
      if (await _nameTaken(txn, key, exceptId: null)) {
        return FloorPlanKindSaveOutcome.nameTaken;
      }
      await txn.insert(_kinds, {
        'name': name.trim(),
        'name_key': key,
        'symbol': symbol.key,
        'has_ports': hasPorts ? 1 : 0,
        'show_info': showInfo ? 1 : 0,
      });
      return FloorPlanKindSaveOutcome.saved;
    });
  }

  /// Αλλαγή ονόματος, συμβόλου ή «έχει θύρες». Φαίνεται αμέσως σε όλα τα
  /// αντικείμενα του είδους, γιατί εκείνα κρατούν μόνο το id του.
  Future<FloorPlanKindSaveOutcome> updateKind({
    required int id,
    required String name,
    required FloorPlanSymbol symbol,
    required bool hasPorts,
    bool showInfo = true,
  }) async {
    final key = nameKey(name);
    return db.transaction((txn) async {
      if (await _nameTaken(txn, key, exceptId: id)) {
        return FloorPlanKindSaveOutcome.nameTaken;
      }
      final changed = await txn.update(
        _kinds,
        {
          'name': name.trim(),
          'name_key': key,
          'symbol': symbol.key,
          'has_ports': hasPorts ? 1 : 0,
          'show_info': showInfo ? 1 : 0,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      return changed == 0
          ? FloorPlanKindSaveOutcome.missing
          : FloorPlanKindSaveOutcome.saved;
    });
  }

  /// Αφαιρεί το είδος **μόνο αν δεν έχει κανένα αντικείμενο**. Επιστρέφει
  /// `null` όταν αφαιρέθηκε· αλλιώς τη χρήση του, για να πει το παράθυρο πόσα
  /// αντικείμενα το κρατούν και πού.
  Future<FloorPlanObjectKindUsage?> deleteKind(int id) async {
    return db.transaction((txn) async {
      final rows = await txn.rawQuery(
        'SELECT floor_id, COUNT(*) AS n FROM $_objects '
        'WHERE kind_id = ? GROUP BY floor_id',
        [id],
      );
      if (rows.isNotEmpty) {
        final kindRows = await txn.query(
          _kinds,
          columns: FloorPlanObjectKind.columns,
          where: 'id = ?',
          whereArgs: [id],
        );
        return FloorPlanObjectKindUsage(
          kind: kindRows.isEmpty
              ? FloorPlanObjectKind(id: id, name: '', symbol: null)
              : FloorPlanObjectKind.fromMap(kindRows.first),
          objectCount: rows.fold<int>(0, (sum, r) => sum + (r['n'] as int)),
          floorIds: {for (final r in rows) r['floor_id'] as int},
        );
      }
      await txn.delete(_kinds, where: 'id = ?', whereArgs: [id]);
      return null;
    });
  }

  /// Τα είδη χωρίς τη χρήση τους — για να ζωγραφιστούν τα αντικείμενα.
  Future<Map<int, FloorPlanObjectKind>> kinds() async {
    final rows = await db.query(_kinds, columns: FloorPlanObjectKind.columns);
    return {
      for (final row in rows)
        row['id'] as int: FloorPlanObjectKind.fromMap(row),
    };
  }

  // ── Αντικείμενα ───────────────────────────────────────────────────────

  Future<List<FloorPlanObject>> listObjects(int floorId) async {
    final rows = await db.query(
      _objects,
      columns: FloorPlanObject.columns,
      where: 'floor_id = ?',
      whereArgs: [floorId],
      orderBy: 'id ASC',
    );
    return [for (final row in rows) FloorPlanObject.fromMap(row)];
  }

  /// Τα αντικείμενα των ορόφων [floorIds] που έχουν όνομα, IP ή όνομα
  /// Lansweeper — ό,τι μπορεί να βρει η αναζήτηση του χάρτη.
  Future<List<FloorPlanObject>> searchableObjects(Set<int> floorIds) async {
    if (floorIds.isEmpty) return const [];
    final ids = floorIds.toList();
    final marks = List.filled(ids.length, '?').join(', ');
    final rows = await db.query(
      _objects,
      columns: FloorPlanObject.columns,
      where:
          "floor_id IN ($marks) AND (TRIM(COALESCE(name, '')) <> '' "
          "OR TRIM(COALESCE(ip, '')) <> '' "
          "OR TRIM(COALESCE(lansweeper_name, '')) <> '')",
      whereArgs: ids,
      orderBy: 'id ASC',
    );
    return [for (final row in rows) FloorPlanObject.fromMap(row)];
  }

  /// Τα αντικείμενα [ids], κατά id — π.χ. οι καμπίνες όσων βρήκε η
  /// αναζήτηση.
  Future<Map<int, FloorPlanObject>> objectsById(Set<int> ids) async {
    if (ids.isEmpty) return const {};
    final idList = ids.toList();
    final marks = List.filled(idList.length, '?').join(', ');
    final rows = await db.query(
      _objects,
      columns: FloorPlanObject.columns,
      where: 'id IN ($marks)',
      whereArgs: idList,
    );
    return {
      for (final row in rows) row['id'] as int: FloorPlanObject.fromMap(row),
    };
  }

  /// Γράφει νέο αντικείμενο και επιστρέφει το id του.
  Future<int> insertObject(FloorPlanObject object) async {
    return db.transaction((txn) async {
      final id = await txn.insert(_objects, object.toInsertMap());
      await touchFloorPlan(txn, object.floorId);
      return id;
    });
  }

  /// Ξαναγράφει αντικείμενα **με τα δικά τους id** — αλλαγή ή αναίρεση
  /// διαγραφής. Ασφαλές επειδή ο πίνακας είναι AUTOINCREMENT: ένα id που
  /// σβήστηκε δεν δίνεται ποτέ σε νέο αντικείμενο.
  Future<void> restoreObjects(List<FloorPlanObject> objects) async {
    if (objects.isEmpty) return;
    await db.transaction((txn) async {
      for (final o in objects) {
        await txn.insert(_objects, {
          'id': o.id,
          ...o.toInsertMap(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final floorId in {for (final o in objects) o.floorId}) {
        await touchFloorPlan(txn, floorId);
      }
    });
  }

  /// Σβήνει τα αντικείμενα [ids] και επιστρέφει όσα έσβησε, για την αναίρεση.
  ///
  /// Καμπίνα παίρνει μαζί **και ό,τι έχει μέσα**: χωρίς αυτήν δεν έχει θέση
  /// πουθενά. Επιστρέφονται κι αυτά, ώστε η αναίρεση να τα φέρει όλα πίσω.
  Future<List<FloorPlanObject>> deleteObjects(Iterable<int> ids) async {
    final idList = ids.toSet().toList();
    if (idList.isEmpty) return const [];
    return db.transaction((txn) async {
      final marks = List.filled(idList.length, '?').join(', ');
      final rows = await txn.query(
        _objects,
        columns: FloorPlanObject.columns,
        where: 'id IN ($marks) OR cabinet_id IN ($marks)',
        whereArgs: [...idList, ...idList],
        orderBy: 'id ASC',
      );
      final removed = [for (final row in rows) FloorPlanObject.fromMap(row)];
      await txn.delete(
        _objects,
        where: 'id IN ($marks) OR cabinet_id IN ($marks)',
        whereArgs: [...idList, ...idList],
      );
      for (final floorId in {for (final o in removed) o.floorId}) {
        await touchFloorPlan(txn, floorId);
      }
      return removed;
    });
  }

  Future<bool> _nameTaken(
    DatabaseExecutor executor,
    String key, {
    required int? exceptId,
  }) async {
    final rows = await executor.query(
      _kinds,
      columns: ['id'],
      where: exceptId == null ? 'name_key = ?' : 'name_key = ? AND id != ?',
      whereArgs: exceptId == null ? [key] : [key, exceptId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }
}
