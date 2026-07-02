import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'audit_service.dart';
import 'database_helper.dart';

/// Κοινοί βοηθοί persistence καταλόγου — κοινό υπόβαθρο των repositories καταλόγου.
class DirectorySupport {
  DirectorySupport(this.db);

  final Database db;

  static const String notDeletedClause = 'COALESCE(is_deleted, 0) = 0';

  Future<String?> getSetting(String key, {DatabaseExecutor? executor}) async {
    final e = executor ?? db;
    final rows = await e.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  String sqlPlaceholders(int count) => List.filled(count, '?').join(',');

  Future<Set<String>> phoneColumnNames(DatabaseExecutor e) async =>
      (await e.rawQuery('PRAGMA table_info(phones)'))
          .map((r) => r['name'] as String)
          .toSet();

  Future<void> ensurePhonesDepartmentColumn(DatabaseExecutor executor) async {
    final names = await phoneColumnNames(executor);
    if (!names.contains('department_id')) {
      await executor.execute(
        'ALTER TABLE phones ADD COLUMN department_id INTEGER',
      );
    }
  }

  Future<void> ensurePhonesIsDeletedColumn(DatabaseExecutor executor) async {
    final names = await phoneColumnNames(executor);
    if (!names.contains('is_deleted')) {
      await executor.execute(
        'ALTER TABLE phones ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0',
      );
    }
  }

  static String phoneDigitsOnly(String s) =>
      s.replaceAll(RegExp(r'[^0-9]'), '');

  Future<String> auditPerformingUser({DatabaseExecutor? executor}) async {
    final v = await getSetting(
      DatabaseHelper.auditUserPerformingSettingsKey,
      executor: executor ?? db,
    );
    final t = v?.trim();
    if (t != null && t.isNotEmpty) return t;
    return '—';
  }

  String userDisplayNameFromRow(Map<String, dynamic>? r) {
    if (r == null) return '';
    final fn = (r['first_name'] as String?)?.trim() ?? '';
    final ln = (r['last_name'] as String?)?.trim() ?? '';
    return '$fn $ln'.trim();
  }

  Future<Map<String, dynamic>?> userRowById(DatabaseExecutor e, int id) async {
    final rows = await e.query(
      'users',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, dynamic>> departmentAuditSnapshot(
    DatabaseExecutor e,
    int? departmentId,
  ) async {
    if (departmentId == null) {
      return const {'department_id': null};
    }
    final rows = await e.query(
      'departments',
      columns: ['name'],
      where: 'id = ?',
      whereArgs: [departmentId],
      limit: 1,
    );
    final name = rows.isEmpty
        ? null
        : (rows.first['name'] as String?)?.trim();
    return {
      'department_id': departmentId,
      if (name != null && name.isNotEmpty) 'department_text': name,
    };
  }

  Future<void> applyDepartmentAuditText(
    DatabaseExecutor e,
    Map<String, dynamic> map,
  ) async {
    if (!map.containsKey('department_id')) return;
    final raw = map['department_id'];
    final id = raw is int ? raw : int.tryParse('$raw');
    if (id == null) {
      map.remove('department_text');
      return;
    }
    final snap = await departmentAuditSnapshot(e, id);
    map['department_id'] = snap['department_id'];
    if (snap.containsKey('department_text')) {
      map['department_text'] = snap['department_text'];
    } else {
      map.remove('department_text');
    }
  }

  Future<Set<int>> userPhoneIds(DatabaseExecutor e, int userId) async {
    final rows = await e.rawQuery(
      'SELECT phone_id FROM user_phones WHERE user_id = ?',
      [userId],
    );
    return rows.map((r) => r['phone_id'] as int).toSet();
  }

  Future<Map<int, String>> idLabelMap(
    DatabaseExecutor e,
    String table,
    String labelColumn,
    Set<int> ids,
  ) async {
    if (ids.isEmpty) return {};
    final placeholders = sqlPlaceholders(ids.length);
    final rows = await e.rawQuery(
      'SELECT id, $labelColumn AS label FROM $table WHERE id IN ($placeholders)',
      ids.toList(),
    );
    final out = <int, String>{};
    for (final r in rows) {
      final id = r['id'] as int?;
      final label = r['label'] as String?;
      if (id != null && label != null) out[id] = label;
    }
    return out;
  }

  Future<Map<int, String>> phoneNumbersByIds(
    DatabaseExecutor e,
    Set<int> ids,
  ) =>
      idLabelMap(e, 'phones', 'number', ids);

  Future<Map<int, String>> equipmentCodesByIds(
    DatabaseExecutor e,
    Set<int> ids,
  ) =>
      idLabelMap(e, 'equipment', 'code_equipment', ids);

  Future<void> auditUserEntityLinkDeltaInTxn(
    DatabaseExecutor txn, {
    required String userPerforming,
    required int userId,
    required Set<int> beforeIds,
    required Set<int> afterIds,
    required String table,
    required String labelColumn,
    required String entityWord,
    required String entityType,
  }) async {
    final removed = beforeIds.difference(afterIds);
    final added = afterIds.difference(beforeIds);
    if (removed.isEmpty && added.isEmpty) return;
    final ids = removed.union(added);
    final labels = switch ((table, labelColumn)) {
      ('phones', 'number') => await phoneNumbersByIds(txn, ids),
      ('equipment', 'code_equipment') => await equipmentCodesByIds(txn, ids),
      _ => await idLabelMap(txn, table, labelColumn, ids),
    };
    for (final id in removed) {
      await AuditService.log(
        txn,
        action: 'ΤΡΟΠΟΠΟΙΗΣΗ',
        userPerforming: userPerforming,
        details: '$entityWord id=$id (αποσύνδεση χρήστη)',
        entityType: entityType,
        entityId: id,
        entityName: labels[id] ?? '#$id',
        oldValues: {'linked_user_id': userId},
        newValues: {'linked_user_id': null},
      );
    }
    for (final id in added) {
      await AuditService.log(
        txn,
        action: 'ΤΡΟΠΟΠΟΙΗΣΗ',
        userPerforming: userPerforming,
        details: '$entityWord id=$id (σύνδεση χρήστη)',
        entityType: entityType,
        entityId: id,
        entityName: labels[id] ?? '#$id',
        oldValues: {'linked_user_id': null},
        newValues: {'linked_user_id': userId},
      );
    }
  }

  Future<void> auditPhoneUserLinkDeltaInTxn(
    DatabaseExecutor txn,
    String userPerforming,
    int userId,
    Set<int> beforeIds,
    Set<int> afterIds,
  ) =>
      auditUserEntityLinkDeltaInTxn(
        txn,
        userPerforming: userPerforming,
        userId: userId,
        beforeIds: beforeIds,
        afterIds: afterIds,
        table: 'phones',
        labelColumn: 'number',
        entityWord: 'phones',
        entityType: AuditEntityTypes.phone,
      );

  Future<void> auditEquipmentUserLinkDeltaInTxn(
    DatabaseExecutor txn,
    String userPerforming,
    int userId,
    Set<int> beforeIds,
    Set<int> afterIds,
  ) =>
      auditUserEntityLinkDeltaInTxn(
        txn,
        userPerforming: userPerforming,
        userId: userId,
        beforeIds: beforeIds,
        afterIds: afterIds,
        table: 'equipment',
        labelColumn: 'code_equipment',
        entityWord: 'equipment',
        entityType: AuditEntityTypes.equipment,
      );

  Future<int?> upsertPhoneIdByNumber(
    DatabaseExecutor txn,
    String number,
  ) async {
    final t = number.trim();
    if (t.isEmpty) return null;
    await txn.insert('phones', {
      'number': t,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    final r = await txn.query(
      'phones',
      columns: ['id'],
      where: 'number = ?',
      whereArgs: [t],
      limit: 1,
    );
    if (r.isEmpty) return null;
    return r.first['id'] as int;
  }

  Future<void> replaceUserPhonesInTxn(
    DatabaseExecutor txn,
    int userId,
    List<String> numbers,
  ) async {
    await txn.delete('user_phones', where: 'user_id = ?', whereArgs: [userId]);
    for (final raw in numbers) {
      final pid = await upsertPhoneIdByNumber(txn, raw);
      if (pid == null) continue;
      await txn.insert('user_phones', {
        'user_id': userId,
        'phone_id': pid,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> addDepartmentPhoneInTxn(
    DatabaseExecutor txn,
    int departmentId,
    String phoneNumber,
  ) async {
    final pid = await upsertPhoneIdByNumber(txn, phoneNumber);
    if (pid == null) return;
    await txn.update(
      'phones',
      {
        'department_id': departmentId,
        'is_deleted': 0,
      },
      where: 'id = ?',
      whereArgs: [pid],
    );
    await txn.delete(
      'department_phones',
      where: 'phone_id = ?',
      whereArgs: [pid],
    );
    await txn.insert('department_phones', {
      'department_id': departmentId,
      'phone_id': pid,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> addDepartmentDirectPhoneInTxn(
    DatabaseExecutor txn,
    int departmentId,
    String phoneNumber,
  ) async {
    final t = phoneNumber.trim();
    if (t.isEmpty) return;
    final beforeDp = await txn.rawQuery(
      '''
      SELECT dp.department_id AS d FROM department_phones dp
      JOIN phones p ON p.id = dp.phone_id
      WHERE p.number = ? AND dp.department_id = ?
      LIMIT 1
      ''',
      [t, departmentId],
    );
    if (beforeDp.isNotEmpty) return;
    await addDepartmentPhoneInTxn(txn, departmentId, phoneNumber);
    final pr = await txn.query(
      'phones',
      columns: ['id'],
      where: 'number = ?',
      whereArgs: [t],
      limit: 1,
    );
    if (pr.isEmpty) return;
    final pid = pr.first['id'] as int;
    final ap = await auditPerformingUser(executor: txn);
    await AuditService.log(
      txn,
      action: 'ΤΡΟΠΟΠΟΙΗΣΗ',
      userPerforming: ap,
      details: 'phones id=$pid (τμήμα $departmentId)',
      entityType: AuditEntityTypes.phone,
      entityId: pid,
      entityName: t,
      newValues: {
        ...await departmentAuditSnapshot(txn, departmentId),
        'via': 'department_phones',
      },
    );
  }

  Future<void> removePhoneFromAllUsersInTxn(
    DatabaseExecutor txn,
    String phoneNumber,
  ) async {
    final t = phoneNumber.trim();
    if (t.isEmpty) return;
    final rows = await txn.query(
      'phones',
      columns: ['id'],
      where: 'number = ?',
      whereArgs: [t],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final pid = rows.first['id'] as int?;
    if (pid == null) return;
    final userRows = await txn.rawQuery(
      'SELECT user_id FROM user_phones WHERE phone_id = ?',
      [pid],
    );
    if (userRows.isEmpty) return;
    await txn.delete('user_phones', where: 'phone_id = ?', whereArgs: [pid]);
    final ap = await auditPerformingUser(executor: txn);
    for (final ur in userRows) {
      final uid = ur['user_id'] as int?;
      if (uid == null) continue;
      await AuditService.log(
        txn,
        action: 'ΤΡΟΠΟΠΟΙΗΣΗ',
        userPerforming: ap,
        details: 'phones id=$pid (αφαίρεση από χρήστη $uid)',
        entityType: AuditEntityTypes.phone,
        entityId: pid,
        entityName: t,
        oldValues: {'linked_user_id': uid},
        newValues: {'linked_user_id': null},
      );
    }
  }
}
