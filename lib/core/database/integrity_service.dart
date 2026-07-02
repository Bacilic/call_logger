import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'audit_service.dart';
import 'database_helper.dart';
import 'directory_support.dart';
import 'user_repository.dart';

/// Orchestrator επιδιορθώσεων ακεραιότητας καταλόγου και εκκρεμοτήτων.
class IntegrityService {
  IntegrityService(this.db, {DirectorySupport? support, UserRepository? users})
      : _support = support ?? DirectorySupport(db) {
    _users = users ?? UserRepository(db, support: _support);
  }

  final Database db;
  final DirectorySupport _support;
  late final UserRepository _users;

  Future<void> softDeleteTask(int id) async {
    final user = await _support.auditPerformingUser();
    await db.transaction((txn) async {
      final titleRows = await txn.query(
        'tasks',
        columns: ['title'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      final taskTitle = titleRows.isEmpty
          ? null
          : (titleRows.first['title'] as String?)?.trim();
      await txn.update(
        'tasks',
        {'is_deleted': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
      await AuditService.log(
        txn,
        action: DatabaseHelper.auditActionDelete,
        userPerforming: user,
        details: 'tasks id=$id',
        entityType: AuditEntityTypes.task,
        entityId: id,
        entityName: taskTitle != null && taskTitle.isNotEmpty
            ? taskTitle
            : null,
      );
    });
  }

  Future<void> softDeletePhoneForIntegrity({
    required int phoneId,
    required String details,
    Map<String, dynamic>? oldValues,
    Map<String, dynamic>? newValues,
  }) async {
    final user = await _support.auditPerformingUser();
    await db.transaction((txn) async {
      final rows = await txn.query(
        'phones',
        columns: ['number'],
        where: 'id = ?',
        whereArgs: [phoneId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final number = (rows.first['number'] as String?)?.trim() ?? '';
      await txn.delete(
        'department_phones',
        where: 'phone_id = ?',
        whereArgs: [phoneId],
      );
      await txn.delete(
        'user_phones',
        where: 'phone_id = ?',
        whereArgs: [phoneId],
      );
      await txn.update(
        'phones',
        {'department_id': null, 'is_deleted': 1},
        where: 'id = ?',
        whereArgs: [phoneId],
      );
      await AuditService.log(
        txn,
        action: DatabaseHelper.auditActionIntegrityFix,
        userPerforming: user,
        details: details,
        entityType: AuditEntityTypes.phone,
        entityId: phoneId,
        entityName: number.isEmpty ? null : number,
        oldValues: oldValues,
        newValues: newValues,
      );
    });
  }

  Future<void> deleteCallExternalLinkForIntegrity({
    required int linkId,
    required String details,
    Map<String, dynamic>? oldValues,
    Map<String, dynamic>? newValues,
  }) async {
    await db.transaction((txn) async {
      await txn.delete(
        'call_external_links',
        where: 'id = ?',
        whereArgs: [linkId],
      );
      final ap = await _support.auditPerformingUser(executor: txn);
      await AuditService.log(
        txn,
        action: DatabaseHelper.auditActionIntegrityFix,
        userPerforming: ap,
        details: details,
        entityType: AuditEntityTypes.call,
        entityId: linkId,
        oldValues: oldValues,
        newValues: newValues,
      );
    });
  }

  Future<void> deleteOrphanUserPhonesJunction({
    required int userId,
    required int phoneId,
    required String details,
    Map<String, dynamic>? oldValues,
    Map<String, dynamic>? newValues,
  }) async {
    await db.transaction((txn) async {
      await txn.delete(
        'user_phones',
        where: 'user_id = ? AND phone_id = ?',
        whereArgs: [userId, phoneId],
      );
      final ap = await _support.auditPerformingUser(executor: txn);
      await AuditService.log(
        txn,
        action: DatabaseHelper.auditActionIntegrityFix,
        userPerforming: ap,
        details: details,
        entityType: AuditEntityTypes.phone,
        entityId: phoneId,
        oldValues: oldValues,
        newValues: newValues,
      );
    });
  }

  Future<void> deleteOrphanDepartmentPhonesJunction({
    required int departmentId,
    required int phoneId,
    required String details,
    Map<String, dynamic>? oldValues,
    Map<String, dynamic>? newValues,
  }) async {
    await db.transaction((txn) async {
      await txn.delete(
        'department_phones',
        where: 'department_id = ? AND phone_id = ?',
        whereArgs: [departmentId, phoneId],
      );
      final ap = await _support.auditPerformingUser(executor: txn);
      await AuditService.log(
        txn,
        action: DatabaseHelper.auditActionIntegrityFix,
        userPerforming: ap,
        details: details,
        entityType: AuditEntityTypes.phone,
        entityId: phoneId,
        oldValues: oldValues,
        newValues: newValues,
      );
    });
  }

  Future<void> deleteOrphanUserEquipmentJunction({
    required int userId,
    required int equipmentId,
    required String details,
    Map<String, dynamic>? oldValues,
    Map<String, dynamic>? newValues,
  }) async {
    await db.transaction((txn) async {
      await txn.delete(
        'user_equipment',
        where: 'user_id = ? AND equipment_id = ?',
        whereArgs: [userId, equipmentId],
      );
      final ap = await _support.auditPerformingUser(executor: txn);
      await AuditService.log(
        txn,
        action: DatabaseHelper.auditActionIntegrityFix,
        userPerforming: ap,
        details: details,
        entityType: AuditEntityTypes.equipment,
        entityId: equipmentId,
        oldValues: oldValues,
        newValues: newValues,
      );
    });
  }

  Future<void> linkOrphanPhoneToDepartmentForIntegrity({
    required int phoneId,
    required int departmentId,
    required String details,
    Map<String, dynamic>? oldValues,
    Map<String, dynamic>? newValues,
  }) async {
    await db.transaction((txn) async {
      await _support.ensurePhonesDepartmentColumn(txn);
      final rows = await txn.query(
        'phones',
        columns: ['number'],
        where: 'id = ?',
        whereArgs: [phoneId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final number = rows.first['number'] as String? ?? '';
      await txn.update(
        'phones',
        {'department_id': departmentId, 'is_deleted': 0},
        where: 'id = ?',
        whereArgs: [phoneId],
      );
      await txn.delete(
        'department_phones',
        where: 'phone_id = ?',
        whereArgs: [phoneId],
      );
      await txn.insert(
        'department_phones',
        {'department_id': departmentId, 'phone_id': phoneId},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      final ap = await _support.auditPerformingUser(executor: txn);
      await AuditService.log(
        txn,
        action: DatabaseHelper.auditActionIntegrityFix,
        userPerforming: ap,
        details: details,
        entityType: AuditEntityTypes.phone,
        entityId: phoneId,
        entityName: number.isEmpty ? null : number,
        oldValues: oldValues,
        newValues: newValues,
      );
    });
  }

  Future<void> linkOrphanPhoneToUserForIntegrity({
    required int phoneId,
    required int userId,
    required String details,
    Map<String, dynamic>? oldValues,
    Map<String, dynamic>? newValues,
  }) async {
    final rows = await db.query(
      'phones',
      columns: ['number'],
      where: 'id = ?',
      whereArgs: [phoneId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final number = (rows.first['number'] as String?)?.trim() ?? '';
    if (number.isEmpty) return;
    final existing = await _users.userPhoneNumbersOrdered(db, userId);
    if (existing.contains(number)) return;
    await _users.updateUser(
      userId,
      {'phones': [...existing, number]},
      recordAudit: false,
    );
    final ap = await _support.auditPerformingUser();
    await AuditService.log(
      db,
      action: DatabaseHelper.auditActionIntegrityFix,
      userPerforming: ap,
      details: details,
      entityType: AuditEntityTypes.phone,
      entityId: phoneId,
      entityName: number,
      oldValues: oldValues,
      newValues: newValues,
    );
  }

  Future<void> fixDepartmentNameKeyForIntegrity({
    required int departmentId,
    required String nameKey,
    required String details,
    Map<String, dynamic>? oldValues,
    Map<String, dynamic>? newValues,
  }) async {
    await db.transaction((txn) async {
      await txn.update(
        'departments',
        {'name_key': nameKey},
        where: 'id = ?',
        whereArgs: [departmentId],
      );
      final ap = await _support.auditPerformingUser(executor: txn);
      await AuditService.log(
        txn,
        action: DatabaseHelper.auditActionIntegrityFix,
        userPerforming: ap,
        details: details,
        entityType: AuditEntityTypes.department,
        entityId: departmentId,
        oldValues: oldValues,
        newValues: newValues,
      );
    });
  }

  Future<void> softDeleteUserForIntegrity({
    required int userId,
    required String details,
    Map<String, dynamic>? oldValues,
    Map<String, dynamic>? newValues,
  }) async {
    await _users.deleteUsers([userId]);
    final ap = await _support.auditPerformingUser();
    await AuditService.log(
      db,
      action: DatabaseHelper.auditActionIntegrityFix,
      userPerforming: ap,
      details: details,
      entityType: AuditEntityTypes.user,
      entityId: userId,
      oldValues: oldValues,
      newValues: newValues,
    );
  }

  Future<void> updateUserDepartmentForIntegrity({
    required int userId,
    required int? departmentId,
    required String details,
    Map<String, dynamic>? oldValues,
    Map<String, dynamic>? newValues,
  }) async {
    await _users.updateUser(
      userId,
      {'department_id': departmentId},
      recordAudit: false,
    );
    final ap = await _support.auditPerformingUser();
    await AuditService.log(
      db,
      action: DatabaseHelper.auditActionIntegrityFix,
      userPerforming: ap,
      details: details,
      entityType: AuditEntityTypes.user,
      entityId: userId,
      oldValues: oldValues,
      newValues: newValues,
    );
  }

  Future<Map<String, dynamic>?> integrityUpdateTaskFk(
    DatabaseExecutor e,
    int taskId,
    String field,
    int? newValue,
  ) async {
    const allowed = {
      'call_id',
      'caller_id',
      'equipment_id',
      'department_id',
      'phone_id',
    };
    if (!allowed.contains(field)) {
      throw ArgumentError('Άκυρο πεδίο εκκρεμότητας: $field');
    }
    final rows = await e.query(
      'tasks',
      where: 'id = ?',
      whereArgs: [taskId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final oldRow = Map<String, dynamic>.from(rows.first);
    await e.update(
      'tasks',
      {field: newValue},
      where: 'id = ?',
      whereArgs: [taskId],
    );
    return oldRow;
  }

  Future<Map<String, dynamic>?> integritySyncTaskTimestamps(
    DatabaseExecutor e,
    int taskId,
  ) async {
    final rows = await e.query(
      'tasks',
      where: 'id = ?',
      whereArgs: [taskId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final oldRow = Map<String, dynamic>.from(rows.first);
    final created = oldRow['created_at'];
    if (created == null) return oldRow;
    await e.update(
      'tasks',
      {'updated_at': created},
      where: 'id = ?',
      whereArgs: [taskId],
    );
    return oldRow;
  }

  Future<String> integrityDepartmentLabel(
    DatabaseExecutor e,
    int? departmentId,
  ) async {
    if (departmentId == null) return '—';
    final rows = await e.query(
      'departments',
      columns: ['name', 'is_deleted'],
      where: 'id = ?',
      whereArgs: [departmentId],
      limit: 1,
    );
    if (rows.isEmpty) return 'Τμήμα ID $departmentId [Ανύπαρκτο]';
    final name = (rows.first['name'] as String?)?.trim() ?? '';
    final deleted = (rows.first['is_deleted'] as int?) == 1;
    final status = deleted ? '[Διαγραμμένο]' : '[Ενεργό]';
    if (name.isEmpty) return 'Τμήμα ID $departmentId $status';
    return 'Τμήμα $name $status (ID $departmentId)';
  }

  Future<String> integrityUserLabel(DatabaseExecutor e, int? userId) async {
    if (userId == null) return '—';
    final row = await _support.userRowById(e, userId);
    if (row == null) return 'Χρήστης ID $userId [Ανύπαρκτος]';
    final name = _support.userDisplayNameFromRow(row);
    final deleted = (row['is_deleted'] as int?) == 1;
    final status = deleted ? '[Διαγραμμένος]' : '[Ενεργός]';
    if (name.isEmpty) return 'Χρήστης ID $userId $status';
    return 'Χρήστης $name $status (ID $userId)';
  }
}
