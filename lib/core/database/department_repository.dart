import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../errors/department_exists_exception.dart';
import '../../features/directory/services/directory_save_conflict.dart';
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

/// Πόσα ενεργά τμήματα ανήκουν σε κάθε κτίριο, και πόσα σε κανένα.
class BuildingUsage {
  const BuildingUsage({
    required this.perBuilding,
    required this.withoutBuilding,
  });

  static const empty = BuildingUsage(
    perBuilding: <String, int>{},
    withoutBuilding: 0,
  );

  final Map<String, int> perBuilding;
  final int withoutBuilding;

  int countFor(String building) => perBuilding[building] ?? 0;
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

  /// Id ενεργού τμήματος με αυτό το όνομα (μέσω `name_key`) — χωρίς δημιουργία.
  Future<int?> findActiveDepartmentIdByName(String? name) async {
    final trimmed = stripDepartmentDeletedDisplaySuffix(name).trim();
    if (trimmed.isEmpty) return null;
    final key = SearchTextNormalizer.normalizeForSearch(trimmed);
    if (key.isEmpty) return null;
    final rows = await db.query(
      'departments',
      columns: ['id'],
      where: '${DirectorySupport.notDeletedClause} AND name_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['id'] as int?;
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
    // Στοχευμένη εγγραφή στηλών χάρτη: δεν υπάρχει καρτέλα, ούτε αφετηρία.
    return updateDepartment(departmentId, merged, expected: null);
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
      await updateDepartment(r['id'] as int, {'floor_id': fid}, expected: null);
      count++;
    }
    return count;
  }

  /// Επαναϋπολογίζει `name_key` για όλα τα τμήματα (ενεργά και soft-deleted)
  /// ως [SearchTextNormalizer.normalizeForSearch] του `name`.
  Future<DepartmentNameKeyBackfillResult>
  backfillAllDepartmentNameKeys() async {
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

  /// Ενημερώνει υπάρχον τμήμα.
  ///
  /// Το [expected] είναι η καρτέλα **όπως τη φόρτωσε η φόρμα**. Υποχρεωτικό —
  /// και δεκτικό `null` μόνο ρητά — γιατί η καρτέλα γράφεται ΟΛΟΚΛΗΡΗ:
  /// στοχευμένες εγγραφές (χάρτης, χρώμα, μία στήλη) περνούν `null`.
  ///
  /// Ο έλεγχος γίνεται πάνω στη γραμμή που διαβάζεται ούτως ή άλλως για το
  /// Ιστορικό, άρα δεν κοστίζει ερώτημα. Πετά [DirectoryStaleException]
  /// **πριν** γράψει οτιδήποτε.
  Future<int> updateDepartment(
    int id,
    Map<String, dynamic> values, {
    required Map<String, Object?>? expected,
    bool force = false,
    DatabaseExecutor? executor,
  }) async {
    final map = Map<String, dynamic>.from(values);
    map.remove('id');
    _applyDepartmentNameKeyFromName(map);
    if (map.isEmpty) return 0;

    // Φρουρός, εγγραφή και ίχνος Ιστορικού γίνονται ΜΟΝΟΜΙΑΣ: χωρίς
    // συναλλαγή, μια διακοπή ανάμεσα στην εγγραφή και το Ιστορικό άφηνε
    // την καρτέλα αλλαγμένη χωρίς κανένα ίχνος του ποιος και τι άλλαξε —
    // και ο φρουρός διένεξης έκρινε πάνω σε γραμμή που μπορούσε να
    // ξαναγραφτεί πριν προλάβει η δική μας εγγραφή.
    Future<int> run(DatabaseExecutor txn) async {
      final oldRows = await txn.query(
        'departments',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (oldRows.isEmpty) return 0;
      final oldRow = oldRows.first;
      if (!force && expected != null) {
        final conflict = DirectorySaveConflict.between(
          entityType: AuditEntityTypes.department,
          expected: expected,
          fresh: oldRow,
          attempted: map,
        );
        if (conflict != null) throw DirectoryStaleException(conflict);
      }
      final n = await txn.update(
        'departments',
        map,
        where: 'id = ?',
        whereArgs: [id],
      );
      if (n <= 0) return 0;
      final diff = _departmentAuditDiff(oldRow, map);
      if (diff.oldDiff.isNotEmpty) {
        // Πάντα μέσω του txn: ανάγνωση στο γυμνό db όσο η συναλλαγή είναι
        // ανοιχτή θα περίμενε τη συναλλαγή — δηλαδή για πάντα.
        final ap = await _support.auditPerformingUser(executor: txn);
        final dn = (oldRow['name'] as String?)?.trim() ?? '';
        await AuditService.log(
          txn,
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

    if (executor != null) return run(executor);
    return db.transaction(run);
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

  // ───────────────────────── Κατάλογος κτιρίων ─────────────────────────

  /// Τα κτίρια που χρησιμοποιούν σήμερα τα ενεργά τμήματα, με το πλήθος τους,
  /// **και** πόσα τμήματα δεν έχουν κτίριο.
  ///
  /// Μία ερώτηση για τα δύο, επίτηδες: η οθόνη διαχείρισης τα δείχνει μαζί
  /// («τόσα τμήματα θα μείνουν χωρίς κτίριο αν το σβήσεις» / «τόσα δεν έχουν
  /// ήδη»), και δύο ξεχωριστές αναγνώσεις θα μπορούσαν να διαφωνήσουν.
  Future<BuildingUsage> countDepartmentsPerBuilding({
    DatabaseExecutor? executor,
  }) async {
    final ex = executor ?? db;
    final rows = await ex.query(
      'departments',
      columns: ['building'],
      where: DirectorySupport.notDeletedClause,
    );
    final counts = <String, int>{};
    var without = 0;
    for (final row in rows) {
      final value = (row['building'] as String?)?.trim() ?? '';
      if (value.isEmpty) {
        without++;
        continue;
      }
      counts[value] = (counts[value] ?? 0) + 1;
    }
    return BuildingUsage(perBuilding: counts, withoutBuilding: without);
  }

  /// Αδειάζει το κτίριο από όσα ενεργά τμήματα το έχουν — η πράξη που
  /// ακολουθεί τη διαγραφή ενός κτιρίου από τον κατάλογο.
  ///
  /// Επιστρέφει πόσα τμήματα έμειναν χωρίς κτίριο.
  Future<int> clearBuildingFromDepartments(String building) async {
    final value = building.trim();
    if (value.isEmpty) return 0;
    return _rewriteBuilding(from: value, to: null, action: 'ΜΑΖΙΚΗ ΕΝΗΜΕΡΩΣΗ');
  }

  /// Μετονομάζει το κτίριο σε όσα ενεργά τμήματα το έχουν, ώστε η διόρθωση
  /// στον κατάλογο να μη διχάσει κατάλογο και δεδομένα.
  ///
  /// Επιστρέφει πόσα τμήματα ενημερώθηκαν.
  Future<int> renameBuildingInDepartments({
    required String from,
    required String to,
  }) async {
    final source = from.trim();
    final target = to.trim();
    if (source.isEmpty || target.isEmpty || source == target) return 0;
    return _rewriteBuilding(
      from: source,
      to: target,
      action: 'ΜΑΖΙΚΗ ΕΝΗΜΕΡΩΣΗ',
    );
  }

  /// Η κοινή εγγραφή των δύο παραπάνω: μία συναλλαγή, ένα ίχνος στο Ιστορικό.
  Future<int> _rewriteBuilding({
    required String from,
    required String? to,
    required String action,
  }) async {
    return db.transaction<int>((txn) async {
      final rows = await txn.query(
        'departments',
        columns: ['id'],
        where: '${DirectorySupport.notDeletedClause} AND TRIM(building) = ?',
        whereArgs: [from],
      );
      final ids = [
        for (final row in rows)
          if (row['id'] case final int id) id,
      ];
      if (ids.isEmpty) return 0;

      final changes = <String, dynamic>{'building': to};
      for (final id in ids) {
        await txn.update(
          'departments',
          changes,
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      final user = await _support.auditPerformingUser(executor: txn);
      await AuditService.logBulk(
        txn,
        action: action,
        userPerforming: user,
        entityType: AuditEntityTypes.bulkDepartments,
        affectedIds: ids,
        appliedFields: changes,
        details: to == null
            ? 'clearBuildingFromDepartments building=$from ids=${ids.length}'
            : 'renameBuildingInDepartments $from -> $to ids=${ids.length}',
      );
      return ids.length;
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

  Future<void> restoreDepartments(
    List<int> ids, {
    DatabaseExecutor? executor,
  }) async {
    if (ids.isEmpty) return;

    Future<void> run(DatabaseExecutor txn) async {
      final user = await _support.auditPerformingUser(executor: txn);
      await _restoreDepartmentsInTxn(txn, ids, user);
    }

    if (executor != null) return run(executor);
    return db.transaction(run);
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
      where:
          '${DirectorySupport.notDeletedClause} AND id != ? AND name_key = ?',
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
