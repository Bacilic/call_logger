import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'audit_service.dart';
import 'database_helper.dart';
import 'directory_support.dart';

/// Persistence τηλεφώνων (`phones`, `department_phones`, σχετικά junctions).
class PhoneRepository {
  PhoneRepository(this.db, {DirectorySupport? support})
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

  Future<void> addDepartmentDirectPhone(
    int departmentId,
    String phoneNumber, {
    DatabaseExecutor? executor,
  }) async {
    if (executor != null) {
      return _support.addDepartmentDirectPhoneInTxn(
        executor,
        departmentId,
        phoneNumber,
      );
    }
    await db.transaction(
      (txn) => _support.addDepartmentDirectPhoneInTxn(
        txn,
        departmentId,
        phoneNumber,
      ),
    );
  }

  Future<void> _removeDepartmentDirectPhoneInTxn(
    DatabaseExecutor txn,
    int departmentId,
    String phoneNumber,
  ) async {
    final t = phoneNumber.trim();
    if (t.isEmpty) return;
    final r = await txn.query(
      'phones',
      columns: ['id', 'department_id'],
      where: 'number = ?',
      whereArgs: [t],
      limit: 1,
    );
    if (r.isEmpty) return;
    final pid = r.first['id'] as int?;
    if (pid == null) return;
    final phoneDeptIdBefore = r.first['department_id'] as int?;
    final pre = await txn.query(
      'department_phones',
      where: 'department_id = ? AND phone_id = ?',
      whereArgs: [departmentId, pid],
      limit: 1,
    );
    final hadDepartmentPhonesRow = pre.isNotEmpty;
    final hadPhonesDepartmentId = phoneDeptIdBefore == departmentId;
    if (!hadDepartmentPhonesRow && !hadPhonesDepartmentId) return;

    if (hadDepartmentPhonesRow) {
      await txn.delete(
        'department_phones',
        where: 'department_id = ? AND phone_id = ?',
        whereArgs: [departmentId, pid],
      );
    }
    if (hadPhonesDepartmentId) {
      await txn.update(
        'phones',
        {'department_id': null},
        where: 'id = ?',
        whereArgs: [pid],
      );
    }
    final ap = await _support.auditPerformingUser(executor: txn);
    await AuditService.log(
      txn,
      action: AuditActions.modifyPhone,
      userPerforming: ap,
      details: 'phones id=$pid (αφαίρεση τμήματος $departmentId)',
      entityType: AuditEntityTypes.phone,
      entityId: pid,
      entityName: t,
      oldValues: await _support.departmentAuditSnapshot(txn, departmentId),
    );
  }

  Future<void> removeDepartmentDirectPhone(
    int departmentId,
    String phoneNumber, {
    DatabaseExecutor? executor,
  }) async {
    if (executor != null) {
      return _removeDepartmentDirectPhoneInTxn(
        executor,
        departmentId,
        phoneNumber,
      );
    }
    await db.transaction(
      (txn) => _removeDepartmentDirectPhoneInTxn(txn, departmentId, phoneNumber),
    );
  }

  Future<int?> getPhoneIdByNumber(String phoneNumber) async {
    await _support.ensurePhonesIsDeletedColumn(db);
    final t = phoneNumber.trim();
    if (t.isEmpty) return null;
    final rows = await db.query(
      'phones',
      columns: ['id'],
      where: 'number = ? AND ${DirectorySupport.notDeletedClause}',
      whereArgs: [t],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['id'] as int?;
  }

  Future<int> countPhoneReferencesExcludingAudit(
    int phoneId,
    String phoneNumber,
  ) async {
    await _support.ensurePhonesIsDeletedColumn(db);
    final digits = DirectorySupport.phoneDigitsOnly(phoneNumber.trim());
    final userLinks = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM user_phones WHERE phone_id = ?',
      [phoneId],
    );
    final deptLinks = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM department_phones WHERE phone_id = ?',
      [phoneId],
    );
    final taskLinks = await db.rawQuery(
      '''
      SELECT COUNT(*) AS c FROM tasks
      WHERE phone_id = ? AND ${DirectorySupport.notDeletedClause}
      ''',
      [phoneId],
    );
    final callLinks = await db.rawQuery(
      '''
      SELECT COUNT(*) AS c FROM calls
      WHERE ${DirectorySupport.notDeletedClause}
        AND (
          TRIM(phone_text) = ?
          OR (
            ? != ''
            AND REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
              COALESCE(phone_text, ''), ' ', ''), '-', ''), '(', ''), ')', ''), '+', '')
              LIKE '%' || ? || '%'
          )
        )
      ''',
      [phoneNumber.trim(), digits, digits],
    );
    return _readCount(userLinks) +
        _readCount(deptLinks) +
        _readCount(taskLinks) +
        _readCount(callLinks);
  }

  Future<void> softDeletePhones(List<int> ids) async {
    if (ids.isEmpty) return;
    final user = await _support.auditPerformingUser();
    await db.transaction((txn) async {
      for (final id in ids) {
        final rows = await txn.query(
          'phones',
          columns: ['number'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (rows.isEmpty) continue;
        final number = (rows.first['number'] as String?)?.trim() ?? '';
        await txn.delete(
          'department_phones',
          where: 'phone_id = ?',
          whereArgs: [id],
        );
        await txn.delete(
          'user_phones',
          where: 'phone_id = ?',
          whereArgs: [id],
        );
        await txn.update(
          'phones',
          {
            'department_id': null,
            'is_deleted': 1,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        await AuditService.log(
          txn,
          action: DatabaseHelper.auditActionDelete,
          userPerforming: user,
          details: 'phones id=$id',
          entityType: AuditEntityTypes.phone,
          entityId: id,
          entityName: number.isEmpty ? null : number,
        );
      }
    });
  }

  Future<Map<int, List<String>>> getDepartmentDirectPhonesMap() async {
    await _support.ensurePhonesDepartmentColumn(db);
    await _support.ensurePhonesIsDeletedColumn(db);
    final rows = await db.rawQuery('''
      SELECT src.department_id AS department_id, src.number AS number
      FROM (
        SELECT dp.department_id AS department_id, p.number AS number
        FROM department_phones dp
        JOIN phones p ON p.id = dp.phone_id
        WHERE COALESCE(p.is_deleted, 0) = 0
        UNION
        SELECT p.department_id AS department_id, p.number AS number
        FROM phones p
        WHERE p.department_id IS NOT NULL
          AND COALESCE(p.is_deleted, 0) = 0
      ) src
      ORDER BY src.department_id, src.number
    ''');
    final out = <int, List<String>>{};
    for (final row in rows) {
      final did = row['department_id'] as int?;
      final num = row['number'] as String?;
      if (did == null || num == null) continue;
      out.putIfAbsent(did, () => []).add(num);
    }
    return out;
  }

  /// Κατάλογος τηλεφώνων χωρίς συνδεδεμένο χρήστη (`user_phones`).
  Future<List<Map<String, dynamic>>> getNonUserPhonesCatalogRows() async {
    await _support.ensurePhonesDepartmentColumn(db);
    await _support.ensurePhonesIsDeletedColumn(db);
    return db.rawQuery('''
WITH phone_dept AS (
  SELECT p.id AS phone_id, p.department_id AS dept_id
  FROM phones p
  WHERE p.department_id IS NOT NULL
    AND COALESCE(p.is_deleted, 0) = 0
  UNION
  SELECT dp.phone_id AS phone_id, dp.department_id AS dept_id
  FROM department_phones dp
  JOIN phones p ON p.id = dp.phone_id
  WHERE COALESCE(p.is_deleted, 0) = 0
)
SELECT
  p.id AS phone_id,
  p.number AS number,
  GROUP_CONCAT(DISTINCT d.name) AS dept_names,
  MIN(d.id) AS primary_department_id
FROM phones p
LEFT JOIN phone_dept pd ON pd.phone_id = p.id
LEFT JOIN departments d ON d.id = pd.dept_id AND COALESCE(d.is_deleted, 0) = 0
WHERE COALESCE(p.is_deleted, 0) = 0
  AND NOT EXISTS (SELECT 1 FROM user_phones up WHERE up.phone_id = p.id)
GROUP BY p.id, p.number
ORDER BY p.number COLLATE NOCASE ASC
''');
  }

  Future<bool> phoneNumberExists(String phoneNumber) async {
    final t = phoneNumber.trim();
    if (t.isEmpty) return false;
    await _support.ensurePhonesIsDeletedColumn(db);
    final rows = await db.query(
      'phones',
      columns: ['id'],
      where: 'number = ? AND ${DirectorySupport.notDeletedClause}',
      whereArgs: [t],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> updatePhoneDepartment(
    String phoneNumber,
    int departmentId,
  ) async {
    final t = phoneNumber.trim();
    if (t.isEmpty) return;
    await db.transaction((txn) async {
      await _support.ensurePhonesDepartmentColumn(txn);
      final beforeRows = await txn.query(
        'phones',
        columns: ['id', 'department_id'],
        where: 'number = ?',
        whereArgs: [t],
        limit: 1,
      );
      final beforeDept = beforeRows.isEmpty
          ? null
          : beforeRows.first['department_id'] as int?;
      final beforeId = beforeRows.isEmpty
          ? null
          : beforeRows.first['id'] as int?;
      final pid = await _support.upsertPhoneIdByNumber(txn, t);
      if (pid == null) return;
      await txn.update(
        'phones',
        {'department_id': departmentId},
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
      final dp = await txn.query(
        'department_phones',
        where: 'department_id = ? AND phone_id = ?',
        whereArgs: [departmentId, pid],
      );
      if (beforeDept == departmentId && beforeId != null && dp.isNotEmpty) {
        return;
      }
      final ap = await _support.auditPerformingUser(executor: txn);
      await AuditService.log(
        txn,
        action: AuditActions.modifyPhone,
        userPerforming: ap,
        details: 'phones id=$pid',
        entityType: AuditEntityTypes.phone,
        entityId: pid,
        entityName: t,
        oldValues: beforeDept == null
            ? null
            : await _support.departmentAuditSnapshot(txn, beforeDept),
        newValues: await _support.departmentAuditSnapshot(txn, departmentId),
      );
    });
  }

  Future<void> removePhoneFromAllUsers(
    String phoneNumber, {
    DatabaseExecutor? executor,
  }) async {
    if (executor != null) {
      return _support.removePhoneFromAllUsersInTxn(executor, phoneNumber);
    }
    await db.transaction(
      (txn) => _support.removePhoneFromAllUsersInTxn(txn, phoneNumber),
    );
  }
}
