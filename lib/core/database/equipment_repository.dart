import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../services/audit_service.dart';
import 'calls_repository.dart';
import 'database_helper.dart';
import 'directory_support.dart';

/// Persistence εξοπλισμού (`equipment`, `user_equipment`).
class EquipmentRepository {
  EquipmentRepository(this.db, {DirectorySupport? support})
      : _support = support ?? DirectorySupport(db);

  final Database db;
  final DirectorySupport _support;

  static int _readCount(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return 0;
    final raw = rows.first['c'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse('$raw') ?? 0;
  }

  Future<Set<int>> _equipmentIdsForUser(DatabaseExecutor e, int userId) async {
    final rows = await e.query(
      'user_equipment',
      columns: ['equipment_id'],
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    return rows.map((r) => r['equipment_id'] as int?).whereType<int>().toSet();
  }

  Future<List<Map<String, dynamic>>> _linkedEquipmentSnapshotsForUser(
    DatabaseExecutor e,
    int userId,
  ) async {
    final rows = await e.rawQuery(
      '''
      SELECT e.id AS id, e.code_equipment AS code
      FROM user_equipment ue
      JOIN equipment e ON e.id = ue.equipment_id
      WHERE ue.user_id = ? AND COALESCE(e.is_deleted, 0) = 0
      ORDER BY e.code_equipment COLLATE NOCASE ASC
      ''',
      [userId],
    );
    return rows
        .map((r) => <String, dynamic>{'id': r['id'], 'code': r['code']})
        .toList();
  }

  Future<List<Map<String, dynamic>>> _linkedUserSnapshotsForEquipment(
    DatabaseExecutor e,
    int equipmentId,
  ) async {
    final rows = await e.rawQuery(
      '''
      SELECT u.id AS id, u.first_name AS first_name, u.last_name AS last_name
      FROM user_equipment ue
      JOIN users u ON u.id = ue.user_id
      WHERE ue.equipment_id = ? AND COALESCE(u.is_deleted, 0) = 0
      ORDER BY u.last_name COLLATE NOCASE ASC, u.first_name COLLATE NOCASE ASC
      ''',
      [equipmentId],
    );
    return rows
        .map(
          (r) => <String, dynamic>{
            'id': r['id'],
            'first_name': r['first_name'],
            'last_name': r['last_name'],
          },
        )
        .toList();
  }

  Future<int?> getEquipmentIdByCode(String code) async {
    final c = code.trim();
    if (c.isEmpty) return null;
    final rows = await db.query(
      'equipment',
      columns: ['id'],
      where:
          'code_equipment = ? AND ${DirectorySupport.notDeletedClause}',
      whereArgs: [c],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['id'] as int?;
  }

  Future<int> countEquipmentReferencesExcludingAudit(int equipmentId) async {
    final userLinks = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM user_equipment WHERE equipment_id = ?',
      [equipmentId],
    );
    final taskLinks = await db.rawQuery(
      '''
      SELECT COUNT(*) AS c FROM tasks
      WHERE equipment_id = ? AND ${DirectorySupport.notDeletedClause}
      ''',
      [equipmentId],
    );
    final callLinks = await db.rawQuery(
      '''
      SELECT COUNT(*) AS c FROM calls
      WHERE equipment_id = ? AND ${DirectorySupport.notDeletedClause}
      ''',
      [equipmentId],
    );
    final codeRows = await db.query(
      'equipment',
      columns: ['code_equipment'],
      where: 'id = ?',
      whereArgs: [equipmentId],
      limit: 1,
    );
    var callTextLinks = 0;
    if (codeRows.isNotEmpty) {
      final code = (codeRows.first['code_equipment'] as String?)?.trim() ?? '';
      if (code.isNotEmpty) {
        final rows = await db.rawQuery(
          '''
          SELECT COUNT(*) AS c FROM calls
          WHERE ${DirectorySupport.notDeletedClause}
            AND equipment_id IS NULL
            AND TRIM(COALESCE(equipment_text, '')) = ?
          ''',
          [code],
        );
        callTextLinks = _readCount(rows);
      }
    }
    return _readCount(userLinks) +
        _readCount(taskLinks) +
        _readCount(callLinks) +
        callTextLinks;
  }

  Future<bool> equipmentCodeExists(String equipmentCode) async {
    final t = equipmentCode.trim();
    if (t.isEmpty) return false;
    final rows = await db.query(
      'equipment',
      columns: ['id'],
      where: 'code_equipment = ? AND ${DirectorySupport.notDeletedClause}',
      whereArgs: [t],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<Map<int, int>> getEquipmentDefaultRemoteToolUsageCounts() async {
    final rows = await db.rawQuery('''
      SELECT TRIM(default_remote_tool) AS tid, COUNT(*) AS c
      FROM equipment
      WHERE ${DirectorySupport.notDeletedClause}
        AND default_remote_tool IS NOT NULL
        AND TRIM(COALESCE(default_remote_tool, '')) != ''
      GROUP BY TRIM(default_remote_tool)
      ''');
    final out = <int, int>{};
    for (final r in rows) {
      final id = int.tryParse((r['tid'] ?? '').toString().trim());
      if (id == null) continue;
      final c = r['c'];
      out[id] = c is int ? c : (c as num).toInt();
    }
    return out;
  }

  Future<void> updateEquipmentDepartment(
    String equipmentCode,
    int departmentId,
  ) async {
    final code = equipmentCode.trim();
    if (code.isEmpty) return;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'equipment',
        columns: ['id', 'department_id'],
        where: 'code_equipment = ? AND ${DirectorySupport.notDeletedClause}',
        whereArgs: [code],
        limit: 1,
      );
      final ap = await _support.auditPerformingUser(executor: txn);
      if (rows.isEmpty) {
        final id = await txn.insert('equipment', {
          'code_equipment': code,
          'department_id': departmentId,
          'is_deleted': 0,
        });
        await AuditService.log(
          txn,
          action: 'ΔΗΜΙΟΥΡΓΙΑ ΕΞΟΠΛΙΣΜΟΥ',
          userPerforming: ap,
          details: 'equipment id=$id (updateEquipmentDepartment)',
          entityType: AuditEntityTypes.equipment,
          entityId: id,
          entityName: code,
          newValues: {
            'code_equipment': code,
            ...await _support.departmentAuditSnapshot(txn, departmentId),
          },
        );
        return;
      }
      final id = rows.first['id'] as int;
      final oldDept = rows.first['department_id'] as int?;
      if (oldDept == departmentId) return;
      await txn.update(
        'equipment',
        {'department_id': departmentId},
        where: 'id = ?',
        whereArgs: [id],
      );
      await AuditService.log(
        txn,
        action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΕΞΟΠΛΙΣΜΟΥ',
        userPerforming: ap,
        details: 'equipment id=$id',
        entityType: AuditEntityTypes.equipment,
        entityId: id,
        entityName: code,
        oldValues: await _support.departmentAuditSnapshot(txn, oldDept),
        newValues: await _support.departmentAuditSnapshot(txn, departmentId),
      );
    });
  }

  Future<void> clearEquipmentSharedDepartment(
    String equipmentCode,
    int departmentId,
  ) async {
    final code = equipmentCode.trim();
    if (code.isEmpty) return;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'equipment',
        columns: ['id', 'department_id'],
        where:
            'code_equipment = ? AND department_id = ? AND ${DirectorySupport.notDeletedClause}',
        whereArgs: [code, departmentId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final id = rows.first['id'] as int;
      final oldDept = rows.first['department_id'] as int?;
      await txn.update(
        'equipment',
        {'department_id': null},
        where: 'id = ?',
        whereArgs: [id],
      );
      final ap = await _support.auditPerformingUser(executor: txn);
      await AuditService.log(
        txn,
        action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΕΞΟΠΛΙΣΜΟΥ',
        userPerforming: ap,
        details:
            'equipment id=$id (αφαίρεση κοινόχρηστου τμήματος $departmentId)',
        entityType: AuditEntityTypes.equipment,
        entityId: id,
        entityName: code,
        oldValues: await _support.departmentAuditSnapshot(txn, oldDept),
        newValues: const {'department_id': null},
      );
    });
  }

  Future<void> _removeEquipmentFromAllUsersInTxn(
    DatabaseExecutor txn,
    String equipmentCode,
  ) async {
    final code = equipmentCode.trim();
    if (code.isEmpty) return;
    final rows = await txn.query(
      'equipment',
      columns: ['id'],
      where: 'code_equipment = ? AND ${DirectorySupport.notDeletedClause}',
      whereArgs: [code],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final eid = rows.first['id'] as int?;
    if (eid == null) return;
    final oldUsers = await _linkedUserSnapshotsForEquipment(txn, eid);
    if (oldUsers.isEmpty) return;
    await txn.delete(
      'user_equipment',
      where: 'equipment_id = ?',
      whereArgs: [eid],
    );
    final ap = await _support.auditPerformingUser(executor: txn);
    await AuditService.log(
      txn,
      action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΕΞΟΠΛΙΣΜΟΥ',
      userPerforming: ap,
      details: 'equipment id=$eid (αφαίρεση όλων των χρηστών)',
      entityType: AuditEntityTypes.equipment,
      entityId: eid,
      entityName: code,
      oldValues: {'linked_users': oldUsers},
      newValues: {'linked_users': <Map<String, dynamic>>[]},
    );
    for (final u in oldUsers) {
      final uid = u['id'] as int?;
      if (uid == null) continue;
      final uSnap = await _linkedEquipmentSnapshotsForUser(txn, uid);
      final uRow = await _support.userRowById(txn, uid);
      await AuditService.log(
        txn,
        action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΧΡΗΣΤΗ',
        userPerforming: ap,
        details: 'users id=$uid (αποσύνδεση εξοπλισμού)',
        entityType: AuditEntityTypes.user,
        entityId: uid,
        entityName: _support.userDisplayNameFromRow(uRow).isEmpty
            ? null
            : _support.userDisplayNameFromRow(uRow),
        newValues: {'linked_equipment': uSnap},
      );
    }
  }

  Future<void> removeEquipmentFromAllUsers(
    String equipmentCode, {
    DatabaseExecutor? executor,
  }) async {
    if (executor != null) {
      return _removeEquipmentFromAllUsersInTxn(executor, equipmentCode);
    }
    await db.transaction(
      (txn) => _removeEquipmentFromAllUsersInTxn(txn, equipmentCode),
    );
  }

  Future<List<Map<String, dynamic>>> getAllEquipment() async {
    return db.query(
      'equipment',
      where: 'COALESCE(is_deleted, 0) = ?',
      whereArgs: [0],
    );
  }

  Future<List<Map<String, dynamic>>> getAllUserEquipmentLinks() async {
    return db.query('user_equipment');
  }

  Future<int> countUsersLinkedToEquipment(int equipmentId) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM user_equipment WHERE equipment_id = ?',
      [equipmentId],
    );
    if (rows.isEmpty) return 0;
    final raw = rows.first['c'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse('$raw') ?? 0;
  }

  Future<void> _unlinkUserFromEquipmentInTxn(
    DatabaseExecutor txn,
    int userId,
    int equipmentId,
  ) async {
    final pre = await txn.query(
      'user_equipment',
      where: 'user_id = ? AND equipment_id = ?',
      whereArgs: [userId, equipmentId],
      limit: 1,
    );
    if (pre.isEmpty) return;
    await txn.delete(
      'user_equipment',
      where: 'user_id = ? AND equipment_id = ?',
      whereArgs: [userId, equipmentId],
    );
    final ap = await _support.auditPerformingUser(executor: txn);
    final uSnap = await _linkedEquipmentSnapshotsForUser(txn, userId);
    final eSnap = await _linkedUserSnapshotsForEquipment(txn, equipmentId);
    final uRow = await _support.userRowById(txn, userId);
    final eRows = await txn.query(
      'equipment',
      columns: ['code_equipment'],
      where: 'id = ?',
      whereArgs: [equipmentId],
      limit: 1,
    );
    final code = eRows.isEmpty
        ? ''
        : (eRows.first['code_equipment'] as String?)?.trim() ?? '';
    await AuditService.log(
      txn,
      action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΧΡΗΣΤΗ',
      userPerforming: ap,
      details: 'users id=$userId (αποσύνδεση εξοπλισμού)',
      entityType: AuditEntityTypes.user,
      entityId: userId,
      entityName: _support.userDisplayNameFromRow(uRow).isEmpty
          ? null
          : _support.userDisplayNameFromRow(uRow),
      newValues: {'linked_equipment': uSnap},
    );
    await AuditService.log(
      txn,
      action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΕΞΟΠΛΙΣΜΟΥ',
      userPerforming: ap,
      details: 'equipment id=$equipmentId (αποσύνδεση χρήστη)',
      entityType: AuditEntityTypes.equipment,
      entityId: equipmentId,
      entityName: code.isEmpty ? null : code,
      newValues: {'linked_users': eSnap},
    );
  }

  Future<void> unlinkUserFromEquipment(
    int userId,
    int equipmentId, {
    DatabaseExecutor? executor,
  }) async {
    if (executor != null) {
      return _unlinkUserFromEquipmentInTxn(executor, userId, equipmentId);
    }
    await db.transaction(
      (txn) => _unlinkUserFromEquipmentInTxn(txn, userId, equipmentId),
    );
  }

  Future<void> _linkUserToEquipmentInTxn(
    DatabaseExecutor txn,
    int userId,
    int equipmentId,
  ) async {
    final pre = await txn.query(
      'user_equipment',
      where: 'user_id = ? AND equipment_id = ?',
      whereArgs: [userId, equipmentId],
      limit: 1,
    );
    if (pre.isNotEmpty) return;
    await txn.insert('user_equipment', {
      'user_id': userId,
      'equipment_id': equipmentId,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    final post = await txn.query(
      'user_equipment',
      where: 'user_id = ? AND equipment_id = ?',
      whereArgs: [userId, equipmentId],
      limit: 1,
    );
    if (post.isEmpty) return;
    final ap = await _support.auditPerformingUser(executor: txn);
    final uSnap = await _linkedEquipmentSnapshotsForUser(txn, userId);
    final eSnap = await _linkedUserSnapshotsForEquipment(txn, equipmentId);
    final uRow = await _support.userRowById(txn, userId);
    final eRows = await txn.query(
      'equipment',
      columns: ['code_equipment'],
      where: 'id = ?',
      whereArgs: [equipmentId],
      limit: 1,
    );
    final code = eRows.isEmpty
        ? ''
        : (eRows.first['code_equipment'] as String?)?.trim() ?? '';
    await AuditService.log(
      txn,
      action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΧΡΗΣΤΗ',
      userPerforming: ap,
      details: 'users id=$userId (σύνδεση εξοπλισμού)',
      entityType: AuditEntityTypes.user,
      entityId: userId,
      entityName: _support.userDisplayNameFromRow(uRow).isEmpty
          ? null
          : _support.userDisplayNameFromRow(uRow),
      newValues: {'linked_equipment': uSnap},
    );
    await AuditService.log(
      txn,
      action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΕΞΟΠΛΙΣΜΟΥ',
      userPerforming: ap,
      details: 'equipment id=$equipmentId (σύνδεση χρήστη)',
      entityType: AuditEntityTypes.equipment,
      entityId: equipmentId,
      entityName: code.isEmpty ? null : code,
      newValues: {'linked_users': eSnap},
    );
  }

  Future<void> linkUserToEquipment(
    int userId,
    int equipmentId, {
    DatabaseExecutor? executor,
  }) async {
    if (executor != null) {
      return _linkUserToEquipmentInTxn(executor, userId, equipmentId);
    }
    await db.transaction(
      (txn) => _linkUserToEquipmentInTxn(txn, userId, equipmentId),
    );
  }

  Future<void> copyUserEquipmentLinks(int fromUserId, int toUserId) async {
    if (fromUserId == toUserId) return;
    final rows = await db.query(
      'user_equipment',
      columns: ['equipment_id'],
      where: 'user_id = ?',
      whereArgs: [fromUserId],
    );
    if (rows.isEmpty) return;
    final beforeEq = await _equipmentIdsForUser(db, toUserId);
    await db.transaction((txn) async {
      for (final r in rows) {
        final eid = r['equipment_id'] as int?;
        if (eid == null) continue;
        await txn.insert('user_equipment', {
          'user_id': toUserId,
          'equipment_id': eid,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
    final afterEq = await _equipmentIdsForUser(db, toUserId);
    final added = afterEq.difference(beforeEq);
    if (added.isEmpty) return;
    await db.transaction((txn) async {
      final ap = await _support.auditPerformingUser(executor: txn);
      final uSnap = await _linkedEquipmentSnapshotsForUser(txn, toUserId);
      final uRow = await _support.userRowById(txn, toUserId);
      await AuditService.log(
        txn,
        action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΧΡΗΣΤΗ',
        userPerforming: ap,
        details: 'users id=$toUserId (αντιγραφή συνδέσεων εξοπλισμού)',
        entityType: AuditEntityTypes.user,
        entityId: toUserId,
        entityName: _support.userDisplayNameFromRow(uRow).isEmpty
            ? null
            : _support.userDisplayNameFromRow(uRow),
        newValues: {'linked_equipment': uSnap},
      );
      for (final eid in added) {
        final eSnap = await _linkedUserSnapshotsForEquipment(txn, eid);
        final eRows = await txn.query(
          'equipment',
          columns: ['code_equipment'],
          where: 'id = ?',
          whereArgs: [eid],
          limit: 1,
        );
        final code = eRows.isEmpty
            ? ''
            : (eRows.first['code_equipment'] as String?)?.trim() ?? '';
        await AuditService.log(
          txn,
          action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΕΞΟΠΛΙΣΜΟΥ',
          userPerforming: ap,
          details: 'equipment id=$eid (αντιγραφή συνδέσεων)',
          entityType: AuditEntityTypes.equipment,
          entityId: eid,
          entityName: code.isEmpty ? null : code,
          newValues: {'linked_users': eSnap},
        );
      }
    });
  }

  Future<void> _replaceEquipmentUsersInTxn(
    DatabaseExecutor txn,
    int equipmentId,
    List<int> userIds,
  ) async {
    final unique = userIds.toSet().toList();
    final oldU = await _linkedUserSnapshotsForEquipment(txn, equipmentId);
    await txn.delete(
      'user_equipment',
      where: 'equipment_id = ?',
      whereArgs: [equipmentId],
    );
    for (final uid in unique) {
      await txn.insert('user_equipment', {
        'user_id': uid,
        'equipment_id': equipmentId,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    final newU = await _linkedUserSnapshotsForEquipment(txn, equipmentId);
    if (jsonEncode(oldU) == jsonEncode(newU)) return;
    final ap = await _support.auditPerformingUser(executor: txn);
    final eRows = await txn.query(
      'equipment',
      columns: ['code_equipment'],
      where: 'id = ?',
      whereArgs: [equipmentId],
      limit: 1,
    );
    final code = eRows.isEmpty
        ? ''
        : (eRows.first['code_equipment'] as String?)?.trim() ?? '';
    await AuditService.log(
      txn,
      action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΕΞΟΠΛΙΣΜΟΥ',
      userPerforming: ap,
      details: 'equipment id=$equipmentId (αντικατάσταση χρηστών)',
      entityType: AuditEntityTypes.equipment,
      entityId: equipmentId,
      entityName: code.isEmpty ? null : code,
      oldValues: {'linked_users': oldU},
      newValues: {'linked_users': newU},
    );
    final oldIds = oldU.map((m) => m['id'] as int?).whereType<int>().toSet();
    final newIds = newU.map((m) => m['id'] as int?).whereType<int>().toSet();
    for (final uid in oldIds.union(newIds)) {
      final uSnap = await _linkedEquipmentSnapshotsForUser(txn, uid);
      final uRow = await _support.userRowById(txn, uid);
      await AuditService.log(
        txn,
        action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΧΡΗΣΤΗ',
        userPerforming: ap,
        details: 'users id=$uid (αντικατάσταση εξοπλισμού)',
        entityType: AuditEntityTypes.user,
        entityId: uid,
        entityName: _support.userDisplayNameFromRow(uRow).isEmpty
            ? null
            : _support.userDisplayNameFromRow(uRow),
        newValues: {'linked_equipment': uSnap},
      );
    }
  }

  Future<void> replaceEquipmentUsers(
    int equipmentId,
    List<int> userIds, {
    DatabaseExecutor? executor,
  }) async {
    if (executor != null) {
      return _replaceEquipmentUsersInTxn(executor, equipmentId, userIds);
    }
    await db.transaction(
      (txn) => _replaceEquipmentUsersInTxn(txn, equipmentId, userIds),
    );
  }

  Future<int> insertEquipmentFromMap(
    Map<String, dynamic> row, {
    DatabaseExecutor? executor,
  }) async {
    final e = executor ?? db;
    final map = Map<String, dynamic>.from(row);
    map.remove('id');
    final id = await e.insert('equipment', map);
    final ap = await _support.auditPerformingUser(executor: executor);
    final code = (map['code_equipment'] as String?)?.trim() ?? '';
    await AuditService.log(
      e,
      action: 'ΔΗΜΙΟΥΡΓΙΑ ΕΞΟΠΛΙΣΜΟΥ',
      userPerforming: ap,
      details: 'equipment id=$id',
      entityType: AuditEntityTypes.equipment,
      entityId: id,
      entityName: code.isEmpty ? null : code,
      newValues: Map<String, dynamic>.from(map),
    );
    return id;
  }

  Future<int> updateEquipment(
    int id,
    Map<String, dynamic> values, {
    DatabaseExecutor? executor,
  }) async {
    final e = executor ?? db;
    final map = Map<String, dynamic>.from(values);
    map.remove('id');
    if (map.isEmpty) return 0;
    final oldRows = await e.query(
      'equipment',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (oldRows.isEmpty) return 0;
    final oldRow = oldRows.first;
    final n = await e.update(
      'equipment',
      map,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (n <= 0) return 0;
    final oldDiff = <String, dynamic>{};
    final newDiff = <String, dynamic>{};
    for (final k in map.keys) {
      final a = oldRow[k];
      final b = map[k];
      if ('$a' != '$b') {
        oldDiff[k] = a;
        newDiff[k] = b;
      }
    }
    if (oldDiff.isNotEmpty) {
      final ap = await _support.auditPerformingUser(executor: executor);
      final code = (oldRow['code_equipment'] as String?)?.trim() ?? '';
      await AuditService.log(
        e,
        action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΕΞΟΠΛΙΣΜΟΥ',
        userPerforming: ap,
        details: 'equipment id=$id',
        entityType: AuditEntityTypes.equipment,
        entityId: id,
        entityName: code.isEmpty ? null : code,
        oldValues: oldDiff,
        newValues: newDiff,
      );
    }
    await CallsRepository(db).rebuildSearchIndexForCallsByEquipmentId(e, id);
    return n;
  }

  Future<void> bulkUpdateEquipments(
    List<int> ids,
    Map<String, dynamic> changes,
  ) async {
    if (ids.isEmpty || changes.isEmpty) return;
    final map = Map<String, dynamic>.from(changes);
    map.remove('id');
    if (map.isEmpty) return;
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.update('equipment', map, where: 'id = ?', whereArgs: [id]);
      }
      final user = await _support.auditPerformingUser(executor: txn);
      await AuditService.logBulk(
        txn,
        action: 'ΜΑΖΙΚΗ ΕΝΗΜΕΡΩΣΗ',
        userPerforming: user,
        entityType: AuditEntityTypes.bulkEquipment,
        affectedIds: ids,
        appliedFields: map,
        details: 'bulkUpdateEquipments ids=${ids.length}',
      );
    });
  }

  Future<void> deleteEquipments(List<int> ids) async {
    if (ids.isEmpty) return;
    final user = await _support.auditPerformingUser();
    await db.transaction((txn) async {
      for (final id in ids) {
        final codeRows = await txn.query(
          'equipment',
          columns: ['code_equipment'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        final code = codeRows.isEmpty
            ? null
            : (codeRows.first['code_equipment'] as String?)?.trim();
        await txn.delete(
          'user_equipment',
          where: 'equipment_id = ?',
          whereArgs: [id],
        );
        await txn.update(
          'equipment',
          {'is_deleted': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
        await AuditService.log(
          txn,
          action: DatabaseHelper.auditActionDelete,
          userPerforming: user,
          details: 'equipment id=$id',
          entityType: AuditEntityTypes.equipment,
          entityId: id,
          entityName: code != null && code.isNotEmpty ? code : null,
        );
      }
    });
  }

  Future<void> restoreEquipment(List<int> ids) async {
    if (ids.isEmpty) return;
    final user = await _support.auditPerformingUser();
    await db.transaction((txn) async {
      for (final id in ids) {
        final codeRows = await txn.query(
          'equipment',
          columns: ['code_equipment'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        final code = codeRows.isEmpty
            ? null
            : (codeRows.first['code_equipment'] as String?)?.trim();
        await txn.update(
          'equipment',
          {'is_deleted': 0},
          where: 'id = ?',
          whereArgs: [id],
        );
        await AuditService.log(
          txn,
          action: DatabaseHelper.auditActionRestore,
          userPerforming: user,
          details: 'equipment id=$id',
          entityType: AuditEntityTypes.equipment,
          entityId: id,
          entityName: code != null && code.isNotEmpty ? code : null,
        );
      }
    });
  }
}
