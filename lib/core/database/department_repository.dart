import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../errors/department_exists_exception.dart';
import 'audit_service.dart';
import '../utils/department_display_utils.dart';
import '../utils/department_floor_sync.dart';
import '../utils/search_text_normalizer.dart';
import 'database_helper.dart';
import 'directory_support.dart';

/// Αποτέλεσμα επαναϋπολογισμού `departments.name_key`.
class DepartmentNameKeyBackfillResult {
  const DepartmentNameKeyBackfillResult({
    required this.updated,
    required this.skippedCollision,
    required this.alreadyCorrect,
  });

  final int updated;
  final int skippedCollision;
  final int alreadyCorrect;
}

/// Persistence τμημάτων (`departments`).
class DepartmentRepository {
  DepartmentRepository(this.db, {DirectorySupport? support})
      : _support = support ?? DirectorySupport(db);

  final Database db;
  final DirectorySupport _support;

  Future<bool> departmentNameExists(String? name) async {
    final trimmed = stripDepartmentDeletedDisplaySuffix(name);
    if (trimmed.isEmpty) return false;
    final key = SearchTextNormalizer.normalizeForSearch(trimmed);
    if (key.isEmpty) return false;
    final rows = await db.query(
      'departments',
      columns: ['id'],
      where: '${DirectorySupport.notDeletedClause} AND name_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<int?> getOrCreateDepartmentIdByName(
    String? name, {
    bool recordAudit = true,
    DatabaseExecutor? executor,
    String? auditOriginSuffix,
  }) async {
    final displayName = stripDepartmentDeletedDisplaySuffix(name).trim();
    if (displayName.isEmpty) return null;
    final key = SearchTextNormalizer.normalizeForSearch(displayName);
    if (key.isEmpty) return null;

    Future<int?> run(DatabaseExecutor txn) async {
      Future<int?> findId() async {
        final rows = await txn.query(
          'departments',
          columns: ['id'],
          where: '${DirectorySupport.notDeletedClause} AND name_key = ?',
          whereArgs: [key],
          limit: 1,
        );
        if (rows.isEmpty) return null;
        return rows.first['id'] as int?;
      }

      final existingId = await findId();
      if (existingId != null) return existingId;

      await txn.insert('departments', {
        'name': displayName,
        'name_key': key,
        'is_deleted': 0,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);

      final newId = await findId();
      if (newId != null && recordAudit) {
        final ap = await _support.auditPerformingUser(executor: txn);
        await AuditService.log(
          txn,
          action: 'ΔΗΜΙΟΥΡΓΙΑ ΤΜΗΜΑΤΟΣ',
          userPerforming: ap,
          details: DirectorySupport.appendAuditOriginSuffix(
            'departments id=$newId (getOrCreateDepartmentIdByName)',
            auditOriginSuffix,
          ),
          entityType: AuditEntityTypes.department,
          entityId: newId,
          entityName: displayName,
          newValues: {'name': displayName},
        );
      }
      return newId;
    }

    if (executor != null) return run(executor);
    return db.transaction(run);
  }

  /// Όλα τα τμήματα (συμπεριλαμβανομένων soft-deleted) — migration, ακεραιότητα.
  Future<List<Map<String, dynamic>>> getDepartments() async {
    return db.query('departments', orderBy: 'name COLLATE NOCASE ASC');
  }

  /// Μόνο ενεργά τμήματα — Κατάλογος, dropdown κλήσης, lookup, dashboard, χάρτης.
  Future<List<Map<String, dynamic>>> getActiveDepartments() async {
    return db.query(
      'departments',
      where: DirectorySupport.notDeletedClause,
      orderBy: 'name COLLATE NOCASE ASC',
    );
  }

  Future<Map<String, dynamic>?> getDepartmentRowById(int id) async {
    final rows = await db.query(
      'departments',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> insertDepartment(
    Map<String, dynamic> row, {
    DatabaseExecutor? executor,
  }) async {
    final e = executor ?? db;
    final map = Map<String, dynamic>.from(row);
    map.remove('id');
    map['is_deleted'] = map['is_deleted'] ?? 0;
    final name = (map['name'] as String?)?.trim() ?? '';
    final key = SearchTextNormalizer.normalizeForSearch(name);
    if (key.isNotEmpty) {
      map['name_key'] = map['name_key'] ?? key;
    }
    try {
      final id = await e.insert('departments', map);
      final ap = await _support.auditPerformingUser(executor: executor);
      final nv = <String, dynamic>{};
      for (final k in map.keys) {
        if (k == 'name_key') continue;
        nv[k] = map[k];
      }
      await AuditService.log(
        e,
        action: 'ΔΗΜΙΟΥΡΓΙΑ ΤΜΗΜΑΤΟΣ',
        userPerforming: ap,
        details: 'departments id=$id',
        entityType: AuditEntityTypes.department,
        entityId: id,
        entityName: name.isEmpty ? null : name,
        newValues: nv.isEmpty ? null : nv,
      );
      return id;
    } catch (err) {
      if (_isSqliteUniqueConstraintFailure(err)) {
        final existing = await _findDepartmentRowByKey(
          (map['name_key'] as String?)?.trim() ?? key,
          executor: executor,
        );
        if (existing != null) {
          final deleted = (existing['is_deleted'] as int?) == 1;
          throw DepartmentExistsException(isDeleted: deleted);
        }
        throw DepartmentExistsException(isDeleted: false);
      }
      rethrow;
    }
  }

  static bool _isSqliteUniqueConstraintFailure(Object e) {
    final s = e.toString().toUpperCase();
    return s.contains('UNIQUE') && s.contains('CONSTRAINT');
  }

  Future<Map<String, dynamic>?> _findDepartmentRowByKey(
    String key, {
    DatabaseExecutor? executor,
  }) async {
    final e = executor ?? db;
    final k = key.trim();
    if (k.isEmpty) return null;
    final rows = await e.query(
      'departments',
      where: 'name_key = ?',
      whereArgs: [k],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<void> _restoreDepartmentsInTxn(
    DatabaseExecutor txn,
    List<int> ids,
    String user,
  ) async {
    for (final id in ids) {
      final nameRows = await txn.query(
        'departments',
        columns: ['name'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      final deptName = nameRows.isEmpty
          ? null
          : (nameRows.first['name'] as String?)?.trim();
      await txn.update(
        'departments',
        {'is_deleted': 0},
        where: 'id = ?',
        whereArgs: [id],
      );
      await AuditService.log(
        txn,
        action: DatabaseHelper.auditActionRestore,
        userPerforming: user,
        details: 'departments id=$id',
        entityType: AuditEntityTypes.department,
        entityId: id,
        entityName: deptName != null && deptName.isNotEmpty ? deptName : null,
      );
    }
  }

  Future<void> restoreDepartmentByName(
    String name, {
    String? building,
    String? color,
    String? notes,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw StateError('Κενό όνομα τμήματος.');
    }
    final key = SearchTextNormalizer.normalizeForSearch(trimmed);
    final row = await _findDepartmentRowByKey(key);
    if (row == null) {
      throw StateError('Δεν βρέθηκε τμήμα με αυτό το όνομα.');
    }
    final id = row['id'] as int?;
    if (id == null) {
      throw StateError('Μη έγκυρο id τμήματος.');
    }
    if ((row['is_deleted'] as int?) != 1) {
      throw StateError('Το τμήμα δεν είναι διαγραμμένο.');
    }
    final user = await _support.auditPerformingUser();
    final updates = <String, dynamic>{};
    updates['name'] = trimmed;
    updates['name_key'] = key;
    if (building != null) {
      updates['building'] = building.trim().isEmpty ? null : building.trim();
    }
    if (color != null) {
      updates['color'] = color.trim().isEmpty ? null : color.trim();
    }
    if (notes != null) {
      updates['notes'] = notes.trim().isEmpty ? null : notes.trim();
    }
    await db.transaction((txn) async {
      await _restoreDepartmentsInTxn(txn, [id], user);
      if (updates.isNotEmpty) {
        await txn.update(
          'departments',
          updates,
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    });
  }

  /// Ενημέρωση τμήματος με προαιρετικό συγχρονισμό ορόφου: προτεραιότητα [drawingFloorId],
  /// αλλιώς [manualFloorId]. Όταν υπάρχει τελικός όροφος, γράφονται `floor_id` και `map_floor`.
  Future<int> saveDepartmentWithFloorContext(
    int departmentId,
    Map<String, dynamic> updates, {
    int? drawingFloorId,
    int? manualFloorId,
  }) async {
    final merged = DepartmentFloorSync.mergeFloorContext(
      Map<String, dynamic>.from(updates),
      drawingFloorId: drawingFloorId,
      manualFloorId: manualFloorId,
    );
    return updateDepartment(departmentId, merged);
  }

  /// One-time / συντήρηση: γεμίζει `floor_id` από αριθμητικό `map_floor` όπου λείπει (χωρίς αλλαγή `building`).
  Future<int> backfillDepartmentFloorIdsFromMapFloor() async {
    final rows = await db.query(
      'departments',
      columns: ['id', 'map_floor'],
      where: 'floor_id IS NULL',
    );
    var count = 0;
    for (final r in rows) {
      final mf = r['map_floor'] as String?;
      final fid = int.tryParse(mf?.trim() ?? '');
      if (fid == null) continue;
      await updateDepartment(r['id'] as int, {'floor_id': fid});
      count++;
    }
    return count;
  }

  /// Επαναϋπολογίζει `name_key` για όλα τα τμήματα (ενεργά και soft-deleted)
  /// ως [SearchTextNormalizer.normalizeForSearch] του `name`.
  Future<DepartmentNameKeyBackfillResult> backfillAllDepartmentNameKeys() async {
    final rows = await db.query(
      'departments',
      columns: ['id', 'name', 'name_key'],
      orderBy: 'id ASC',
    );

    final assignedKeys = <String, int>{};
    for (final r in rows) {
      final id = r['id'] as int?;
      if (id == null) continue;
      final name = (r['name'] as String?)?.trim() ?? '';
      final nameKey = (r['name_key'] as String?)?.trim() ?? '';
      final expected = SearchTextNormalizer.normalizeForSearch(name);
      if (expected.isNotEmpty && nameKey == expected) {
        assignedKeys[expected] = id;
      }
    }

    var updated = 0;
    var skippedCollision = 0;
    var alreadyCorrect = 0;

    for (final r in rows) {
      final id = r['id'] as int?;
      if (id == null) continue;
      final name = (r['name'] as String?)?.trim() ?? '';
      final nameKey = (r['name_key'] as String?)?.trim() ?? '';
      final expected = SearchTextNormalizer.normalizeForSearch(name);
      if (expected.isEmpty) continue;
      if (nameKey == expected) {
        alreadyCorrect++;
        continue;
      }

      final existingOwner = assignedKeys[expected];
      if (existingOwner != null && existingOwner != id) {
        skippedCollision++;
        continue;
      }

      try {
        final n = await db.update(
          'departments',
          {'name_key': expected},
          where: 'id = ?',
          whereArgs: [id],
        );
        if (n > 0) {
          assignedKeys[expected] = id;
          updated++;
        }
      } catch (_) {
        skippedCollision++;
      }
    }

    return DepartmentNameKeyBackfillResult(
      updated: updated,
      skippedCollision: skippedCollision,
      alreadyCorrect: alreadyCorrect,
    );
  }

  static void _applyDepartmentNameKeyFromName(Map<String, dynamic> map) {
    if (!map.containsKey('name')) return;
    final name = (map['name'] as String?)?.trim() ?? '';
    final key = SearchTextNormalizer.normalizeForSearch(name);
    if (key.isNotEmpty) {
      map['name_key'] = key;
    }
  }

  static ({Map<String, dynamic> oldDiff, Map<String, dynamic> newDiff})
      _departmentAuditDiff(
    Map<String, dynamic> oldRow,
    Map<String, dynamic> updates,
  ) {
    final oldDiff = <String, dynamic>{};
    final newDiff = <String, dynamic>{};
    for (final k in updates.keys) {
      if (k == 'name_key') continue;
      final a = oldRow[k];
      final b = updates[k];
      if (!DirectorySupport.auditValuesEqual(a, b)) {
        oldDiff[k] = a;
        newDiff[k] = b;
      }
    }
    return (oldDiff: oldDiff, newDiff: newDiff);
  }

  Future<int> updateDepartment(
    int id,
    Map<String, dynamic> values, {
    DatabaseExecutor? executor,
  }) async {
    final e = executor ?? db;
    final map = Map<String, dynamic>.from(values);
    map.remove('id');
    _applyDepartmentNameKeyFromName(map);
    if (map.isEmpty) return 0;
    final oldRows = await e.query(
      'departments',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (oldRows.isEmpty) return 0;
    final oldRow = oldRows.first;
    final n = await e.update(
      'departments',
      map,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (n <= 0) return 0;
    final diff = _departmentAuditDiff(oldRow, map);
    if (diff.oldDiff.isNotEmpty) {
      final ap = await _support.auditPerformingUser(executor: executor);
      final dn = (oldRow['name'] as String?)?.trim() ?? '';
      await AuditService.log(
        e,
        action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΤΜΗΜΑΤΟΣ',
        userPerforming: ap,
        details: 'departments id=$id',
        entityType: AuditEntityTypes.department,
        entityId: id,
        entityName: dn.isEmpty ? null : dn,
        oldValues: diff.oldDiff,
        newValues: diff.newDiff,
      );
    }
    return n;
  }

  Future<void> bulkUpdateDepartments(
    List<int> ids,
    Map<String, dynamic> changes,
  ) async {
    if (ids.isEmpty || changes.isEmpty) return;
    final map = Map<String, dynamic>.from(changes);
    map.remove('id');
    if (map.isEmpty) return;
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.update('departments', map, where: 'id = ?', whereArgs: [id]);
      }
      final user = await _support.auditPerformingUser(executor: txn);
      await AuditService.logBulk(
        txn,
        action: 'ΜΑΖΙΚΗ ΕΝΗΜΕΡΩΣΗ',
        userPerforming: user,
        entityType: AuditEntityTypes.bulkDepartments,
        affectedIds: ids,
        appliedFields: map,
        details: 'bulkUpdateDepartments ids=${ids.length}',
      );
    });
  }

  Future<void> softDeleteDepartment(int id) async {
    await softDeleteDepartments([id]);
  }

  Future<void> softDeleteDepartments(
    List<int> ids, {
    DatabaseExecutor? executor,
  }) async {
    if (ids.isEmpty) return;

    Future<void> run(DatabaseExecutor txn) async {
      final user = await _support.auditPerformingUser(executor: txn);
      for (final id in ids) {
        final nameRows = await txn.query(
          'departments',
          columns: ['name'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        final deptName = nameRows.isEmpty
            ? null
            : (nameRows.first['name'] as String?)?.trim();
        final updated = await txn.update(
          'departments',
          {'is_deleted': 1},
          where: 'id = ? AND ${DirectorySupport.notDeletedClause}',
          whereArgs: [id],
        );
        if (updated == 0) continue;
        await AuditService.log(
          txn,
          action: DatabaseHelper.auditActionDelete,
          userPerforming: user,
          details: 'departments id=$id',
          entityType: AuditEntityTypes.department,
          entityId: id,
          entityName: deptName != null && deptName.isNotEmpty ? deptName : null,
        );
      }
    }

    if (executor != null) return run(executor);
    return db.transaction(run);
  }

  Future<void> restoreDepartments(List<int> ids) async {
    if (ids.isEmpty) return;
    final user = await _support.auditPerformingUser();
    await db.transaction((txn) async {
      await _restoreDepartmentsInTxn(txn, ids, user);
    });
  }

  Future<bool> departmentNameExistsExcluding(
    String? name,
    int excludeId,
  ) async {
    final trimmed = stripDepartmentDeletedDisplaySuffix(name);
    if (trimmed.isEmpty) return false;
    final key = SearchTextNormalizer.normalizeForSearch(trimmed);
    if (key.isEmpty) return false;
    final rows = await db.query(
      'departments',
      columns: ['id'],
      where: '${DirectorySupport.notDeletedClause} AND id != ? AND name_key = ?',
      whereArgs: [excludeId, key],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<String?> getDepartmentNameById(
    int departmentId, {
    DatabaseExecutor? executor,
  }) async {
    final e = executor ?? db;
    final rows = await e.query(
      'departments',
      columns: ['name'],
      where: 'id = ? AND ${DirectorySupport.notDeletedClause}',
      whereArgs: [departmentId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['name'] as String?;
  }

  Future<Map<int, String>> getDepartmentNamesByIds(Set<int> ids) async {
    if (ids.isEmpty) return const {};
    final sorted = ids.toList()..sort();
    final placeholders = List.filled(sorted.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT id, name FROM departments WHERE id IN ($placeholders)',
      sorted,
    );
    final out = <int, String>{};
    for (final row in rows) {
      final id = row['id'] as int?;
      final name = (row['name'] as String?)?.trim();
      if (id != null && name != null && name.isNotEmpty) {
        out[id] = name;
      }
    }
    return out;
  }

  static const String _phoneDeptCte = '''
      WITH phone_dept AS (
        SELECT p.id AS phone_id, p.department_id AS department_id
        FROM phones p
        WHERE p.department_id IS NOT NULL
        UNION
        SELECT dp.phone_id AS phone_id, dp.department_id AS department_id
        FROM department_phones dp
      )
    ''';

  Future<List<int>> resolveActiveDepartmentIdsForUserId(int userId) async {
    final rows = await db.rawQuery(
      '''
      $_phoneDeptCte
      SELECT DISTINCT src.department_id AS department_id
      FROM (
        SELECT u.department_id AS department_id
        FROM users u
        WHERE u.id = ? AND u.department_id IS NOT NULL
        UNION
        SELECT pd.department_id AS department_id
        FROM user_phones up
        JOIN phone_dept pd ON pd.phone_id = up.phone_id
        WHERE up.user_id = ?
      ) src
      JOIN departments d ON d.id = src.department_id
      WHERE COALESCE(d.is_deleted, 0) = 0
      ORDER BY src.department_id ASC
      ''',
      [userId, userId],
    );
    return rows
        .map((row) => row['department_id'] as int?)
        .whereType<int>()
        .toList(growable: false);
  }

  Future<List<int>> resolveActiveDepartmentIdsForPhone(String phone) async {
    final trimmed = phone.trim();
    if (trimmed.isEmpty) return const [];
    final rows = await db.rawQuery(
      '''
      $_phoneDeptCte
      SELECT DISTINCT pd.department_id AS department_id
      FROM phones p
      JOIN phone_dept pd ON pd.phone_id = p.id
      JOIN departments d ON d.id = pd.department_id
      WHERE COALESCE(d.is_deleted, 0) = 0
        AND p.number = ?
      ORDER BY pd.department_id ASC
      ''',
      [trimmed],
    );
    return rows
        .map((row) => row['department_id'] as int?)
        .whereType<int>()
        .toList(growable: false);
  }
}
