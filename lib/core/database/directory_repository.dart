import 'dart:async';
import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../errors/department_exists_exception.dart';
import '../utils/department_display_utils.dart';
import '../utils/name_parser.dart';
import '../utils/phone_list_parser.dart';
import '../utils/search_text_normalizer.dart';
import '../services/audit_service.dart';
import 'database_helper.dart';
import 'directory_audit_helpers.dart';

/// Callback από orchestrator: επαναδόμηση `search_index` στο ίδιο transaction (π.χ. [CallsRepository]).
typedef RebuildCallSearchIndexForCategoryInTxn = Future<void> Function(
  Transaction txn,
  int categoryId,
);

/// Persistence καταλόγου: χρήστες, τμήματα, εξοπλισμός, κατηγορίες, ρυθμίσεις, εισαγωγές.
///
/// Δεν εισάγει [CallsRepository] — το rebuild `search_index` γίνεται μέσω [RebuildCallSearchIndexForCategoryInTxn].
class DirectoryRepository {
  DirectoryRepository(this.db);

  final Database db;

  Future<void> _ensurePhonesDepartmentColumn(DatabaseExecutor executor) async {
    final info = await executor.rawQuery('PRAGMA table_info(phones)');
    final names = info.map((r) => r['name'] as String).toSet();
    if (!names.contains('department_id')) {
      await executor.execute('ALTER TABLE phones ADD COLUMN department_id INTEGER');
    }
  }

  Future<String> _auditPerformingUser() async {
    final v = await getSetting(DatabaseHelper.auditUserPerformingSettingsKey);
    final t = v?.trim();
    if (t != null && t.isNotEmpty) return t;
    return '—';
  }

  static const Set<String> _kUserAuditColumns = {
    'first_name',
    'last_name',
    'department_id',
    'location',
    'notes',
    'is_deleted',
  };

  String _userDisplayNameFromRow(Map<String, Object?>? r) {
    if (r == null) return '';
    final fn = (r['first_name'] as String?)?.trim() ?? '';
    final ln = (r['last_name'] as String?)?.trim() ?? '';
    return '$fn $ln'.trim();
  }

  Future<Map<String, Object?>?> _userRowById(
    DatabaseExecutor e,
    int id,
  ) async {
    final rows = await e.query(
      'users',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Set<int>> _userPhoneIds(DatabaseExecutor e, int userId) async {
    final rows = await e.rawQuery(
      'SELECT phone_id FROM user_phones WHERE user_id = ?',
      [userId],
    );
    return rows.map((r) => r['phone_id'] as int).toSet();
  }

  Future<Map<int, String>> _phoneNumbersByIds(
    DatabaseExecutor e,
    Set<int> ids,
  ) async {
    if (ids.isEmpty) return {};
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await e.rawQuery(
      'SELECT id, number FROM phones WHERE id IN ($placeholders)',
      ids.toList(),
    );
    final out = <int, String>{};
    for (final r in rows) {
      final id = r['id'] as int?;
      final n = r['number'] as String?;
      if (id != null && n != null) out[id] = n;
    }
    return out;
  }

  Future<void> _auditPhoneUserLinkDeltaInTxn(
    Transaction txn,
    String userPerforming,
    int userId,
    Set<int> beforeIds,
    Set<int> afterIds,
  ) async {
    final removed = beforeIds.difference(afterIds);
    final added = afterIds.difference(beforeIds);
    if (removed.isEmpty && added.isEmpty) return;
    final all = removed.union(added);
    final nums = await _phoneNumbersByIds(txn, all);
    for (final pid in removed) {
      final num = nums[pid] ?? '#$pid';
      await AuditService.log(
        txn,
        action: 'ΤΡΟΠΟΠΟΙΗΣΗ',
        userPerforming: userPerforming,
        details: 'phones id=$pid (αποσύνδεση χρήστη)',
        entityType: AuditEntityTypes.phone,
        entityId: pid,
        entityName: num,
        oldValues: {'linked_user_id': userId},
        newValues: {'linked_user_id': null},
      );
    }
    for (final pid in added) {
      final num = nums[pid] ?? '#$pid';
      await AuditService.log(
        txn,
        action: 'ΤΡΟΠΟΠΟΙΗΣΗ',
        userPerforming: userPerforming,
        details: 'phones id=$pid (σύνδεση χρήστη)',
        entityType: AuditEntityTypes.phone,
        entityId: pid,
        entityName: num,
        oldValues: {'linked_user_id': null},
        newValues: {'linked_user_id': userId},
      );
    }
  }

  Future<void> _replaceUserPhonesInTxn(
    Transaction txn,
    int userId,
    List<String> numbers,
  ) async {
    await txn.delete('user_phones', where: 'user_id = ?', whereArgs: [userId]);
    for (final raw in numbers) {
      final t = raw.trim();
      if (t.isEmpty) continue;
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
      if (r.isEmpty) continue;
      final pid = r.first['id'] as int;
      await txn.insert('user_phones', {
        'user_id': userId,
        'phone_id': pid,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> _addDepartmentPhoneInTxn(
    Transaction txn,
    int departmentId,
    String phoneNumber,
  ) async {
    final t = phoneNumber.trim();
    if (t.isEmpty) return;
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
    if (r.isEmpty) return;
    final pid = r.first['id'] as int;
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
  }

  Future<void> addDepartmentDirectPhone(
    int departmentId,
    String phoneNumber,
  ) async {
    await db.transaction((txn) async {
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
      await _addDepartmentPhoneInTxn(txn, departmentId, phoneNumber);
      final pr = await txn.query(
        'phones',
        columns: ['id'],
        where: 'number = ?',
        whereArgs: [t],
        limit: 1,
      );
      if (pr.isEmpty) return;
      final pid = pr.first['id'] as int;
      final ap = await _auditPerformingUser();
      await AuditService.log(
        txn,
        action: 'ΤΡΟΠΟΠΟΙΗΣΗ',
        userPerforming: ap,
        details: 'phones id=$pid (τμήμα $departmentId)',
        entityType: AuditEntityTypes.phone,
        entityId: pid,
        entityName: t,
        newValues: {'department_id': departmentId, 'via': 'department_phones'},
      );
    });
  }

  Future<void> removeDepartmentDirectPhone(
    int departmentId,
    String phoneNumber,
  ) async {
    final t = phoneNumber.trim();
    if (t.isEmpty) return;
    await db.transaction((txn) async {
      final r = await txn.query(
        'phones',
        columns: ['id'],
        where: 'number = ?',
        whereArgs: [t],
        limit: 1,
      );
      if (r.isEmpty) return;
      final pid = r.first['id'] as int?;
      if (pid == null) return;
      final pre = await txn.query(
        'department_phones',
        where: 'department_id = ? AND phone_id = ?',
        whereArgs: [departmentId, pid],
        limit: 1,
      );
      if (pre.isEmpty) return;
      await txn.delete(
        'department_phones',
        where: 'department_id = ? AND phone_id = ?',
        whereArgs: [departmentId, pid],
      );
      final ap = await _auditPerformingUser();
      await AuditService.log(
        txn,
        action: 'ΤΡΟΠΟΠΟΙΗΣΗ',
        userPerforming: ap,
        details: 'phones id=$pid (αφαίρεση τμήματος $departmentId)',
        entityType: AuditEntityTypes.phone,
        entityId: pid,
        entityName: t,
        oldValues: {'department_id': departmentId},
      );
    });
  }

  Future<Map<int, List<String>>> getDepartmentDirectPhonesMap() async {
    await _ensurePhonesDepartmentColumn(db);
    final rows = await db.rawQuery('''
      SELECT src.department_id AS department_id, src.number AS number
      FROM (
        SELECT dp.department_id AS department_id, p.number AS number
        FROM department_phones dp
        JOIN phones p ON p.id = dp.phone_id
        UNION
        SELECT p.department_id AS department_id, p.number AS number
        FROM phones p
        WHERE p.department_id IS NOT NULL
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

  Future<bool> phoneNumberExists(String phoneNumber) async {
    final t = phoneNumber.trim();
    if (t.isEmpty) return false;
    final rows = await db.query(
      'phones',
      columns: ['id'],
      where: 'number = ?',
      whereArgs: [t],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<bool> equipmentCodeExists(String equipmentCode) async {
    final t = equipmentCode.trim();
    if (t.isEmpty) return false;
    final rows = await db.query(
      'equipment',
      columns: ['id'],
      where: 'code_equipment = ? AND COALESCE(is_deleted, 0) = 0',
      whereArgs: [t],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Πόσοι μη διαγραμμένοι εξοπλισμοί έχουν `default_remote_tool` = id εργαλείου (κείμενο).
  Future<Map<int, int>> getEquipmentDefaultRemoteToolUsageCounts() async {
    final rows = await db.rawQuery(
      '''
      SELECT TRIM(default_remote_tool) AS tid, COUNT(*) AS c
      FROM equipment
      WHERE COALESCE(is_deleted, 0) = 0
        AND default_remote_tool IS NOT NULL
        AND TRIM(COALESCE(default_remote_tool, '')) != ''
      GROUP BY TRIM(default_remote_tool)
      ''',
    );
    final out = <int, int>{};
    for (final r in rows) {
      final id = int.tryParse((r['tid'] ?? '').toString().trim());
      if (id == null) continue;
      final c = r['c'];
      out[id] = c is int ? c : (c as num).toInt();
    }
    return out;
  }

  Future<void> updatePhoneDepartment(
    String phoneNumber,
    int departmentId,
  ) async {
    final t = phoneNumber.trim();
    if (t.isEmpty) return;
    await db.transaction((txn) async {
      await _ensurePhonesDepartmentColumn(txn);
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
      final beforeId =
          beforeRows.isEmpty ? null : beforeRows.first['id'] as int?;
      await txn.insert('phones', {
        'number': t,
        'department_id': departmentId,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      final rows = await txn.query(
        'phones',
        columns: ['id'],
        where: 'number = ?',
        whereArgs: [t],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final pid = rows.first['id'] as int;
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
        limit: 1,
      );
      if (beforeDept == departmentId &&
          beforeId != null &&
          dp.isNotEmpty) {
        return;
      }
      final ap = await _auditPerformingUser();
      await AuditService.log(
        txn,
        action: 'ΤΡΟΠΟΠΟΙΗΣΗ',
        userPerforming: ap,
        details: 'phones id=$pid',
        entityType: AuditEntityTypes.phone,
        entityId: pid,
        entityName: t,
        oldValues: beforeDept == null ? null : {'department_id': beforeDept},
        newValues: {'department_id': departmentId},
      );
    });
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
        where: 'code_equipment = ? AND COALESCE(is_deleted, 0) = 0',
        whereArgs: [code],
        limit: 1,
      );
      final ap = await _auditPerformingUser();
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
            'department_id': departmentId,
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
        oldValues: {'department_id': oldDept},
        newValues: {'department_id': departmentId},
      );
    });
  }

  Future<void> removePhoneFromAllUsers(String phoneNumber) async {
    final t = phoneNumber.trim();
    if (t.isEmpty) return;
    await db.transaction((txn) async {
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
      final ap = await _auditPerformingUser();
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
    });
  }

  Future<void> removeEquipmentFromAllUsers(String equipmentCode) async {
    final code = equipmentCode.trim();
    if (code.isEmpty) return;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'equipment',
        columns: ['id'],
        where: 'code_equipment = ? AND COALESCE(is_deleted, 0) = 0',
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
      final ap = await _auditPerformingUser();
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
        final uRow = await _userRowById(txn, uid);
        await AuditService.log(
          txn,
          action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΧΡΗΣΤΗ',
          userPerforming: ap,
          details: 'users id=$uid (αποσύνδεση εξοπλισμού)',
          entityType: AuditEntityTypes.user,
          entityId: uid,
          entityName: _userDisplayNameFromRow(uRow).isEmpty
              ? null
              : _userDisplayNameFromRow(uRow),
          newValues: {'linked_equipment': uSnap},
        );
      }
    });
  }

  Future<void> replaceUserPhones(int userId, List<String> numbers) async {
    await updateUser(userId, {'phones': numbers});
  }

  Future<List<Map<String, dynamic>>> getAllUsers() async {
    final users = await db.query(
      'users',
      where: 'COALESCE(is_deleted, 0) = ?',
      whereArgs: [0],
    );
    final links = await db.rawQuery('''
      SELECT up.user_id AS user_id, p.number AS number
      FROM user_phones up
      JOIN phones p ON p.id = up.phone_id
      ORDER BY p.number
    ''');
    final byUser = <int, List<String>>{};
    for (final row in links) {
      final uid = row['user_id'] as int?;
      final num = row['number'] as String?;
      if (uid == null || num == null) continue;
      byUser.putIfAbsent(uid, () => []).add(num);
    }
    return users.map((m) {
      final copy = Map<String, dynamic>.from(m);
      final id = m['id'] as int?;
      copy['phones'] = id != null
          ? List<String>.from(byUser[id] ?? const [])
          : <String>[];
      return copy;
    }).toList();
  }

  Map<String, dynamic> _userRowAuditValues(Map<String, Object?> row) {
    final m = <String, dynamic>{};
    for (final k in _kUserAuditColumns) {
      if (row.containsKey(k)) m[k] = row[k];
    }
    return m;
  }

  Future<int> insertUserFromMap(Map<String, dynamic> row) async {
    final map = Map<String, dynamic>.from(row);
    map.remove('id');
    final phonesRaw = map.remove('phones');
    map.remove('phone');
    List<String> phones = const [];
    if (phonesRaw is List) {
      phones = phonesRaw
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return db.transaction((txn) async {
      final beforePhoneIds = <int>{};
      final id = await txn.insert('users', map);
      if (phones.isNotEmpty) {
        await _replaceUserPhonesInTxn(txn, id, phones);
      }
      final afterPhoneIds = await _userPhoneIds(txn, id);
      final ap = await _auditPerformingUser();
      final rowSnap = await _userRowById(txn, id);
      final nv = _userRowAuditValues(rowSnap ?? {});
      final nums = await _userPhoneNumbersOrdered(txn, id);
      nv['linked_phone_numbers'] = nums;
      final linkedEq = await _linkedEquipmentSnapshotsForUser(txn, id);
      nv['linked_equipment'] = linkedEq;
      await AuditService.log(
        txn,
        action: 'ΔΗΜΙΟΥΡΓΙΑ ΧΡΗΣΤΗ',
        userPerforming: ap,
        details: 'users id=$id',
        entityType: AuditEntityTypes.user,
        entityId: id,
        entityName: _userDisplayNameFromRow(rowSnap).isEmpty
            ? null
            : _userDisplayNameFromRow(rowSnap),
        newValues: nv,
      );
      await _auditPhoneUserLinkDeltaInTxn(
        txn,
        ap,
        id,
        beforePhoneIds,
        afterPhoneIds,
      );
      return id;
    });
  }

  Future<List<String>> _userPhoneNumbersOrdered(
    DatabaseExecutor e,
    int userId,
  ) async {
    final rows = await e.rawQuery(
      '''
      SELECT p.number AS number FROM user_phones up
      JOIN phones p ON p.id = up.phone_id
      WHERE up.user_id = ?
      ORDER BY p.number COLLATE NOCASE ASC
      ''',
      [userId],
    );
    return rows
        .map((r) => r['number'] as String?)
        .whereType<String>()
        .toList();
  }

  Future<String?> _departmentNameForUserTxn(
    Transaction txn,
    int userId,
  ) async {
    final rows = await txn.rawQuery(
      '''
      SELECT d.name AS name FROM users u
      LEFT JOIN departments d ON d.id = u.department_id
      WHERE u.id = ?
      LIMIT 1
      ''',
      [userId],
    );
    if (rows.isEmpty) return null;
    final n = rows.first['name'] as String?;
    final t = n?.trim();
    if (t == null || t.isEmpty) return null;
    return t;
  }

  Future<Set<int>> _equipmentIdsForUser(
    DatabaseExecutor e,
    int userId,
  ) async {
    final rows = await e.query(
      'user_equipment',
      columns: ['equipment_id'],
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    return rows
        .map((r) => r['equipment_id'] as int?)
        .whereType<int>()
        .toSet();
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
        .map(
          (r) => <String, dynamic>{
            'id': r['id'],
            'code': r['code'],
          },
        )
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

  Future<int> updateUser(
    int id,
    Map<String, dynamic> values, {
    bool recordAudit = true,
  }) async {
    final map = Map<String, dynamic>.from(values);
    map.remove('id');
    final phonesRaw = map.remove('phones');
    map.remove('phone');
    final oldRow = await _userRowById(db, id);
    final beforePhoneIds = await _userPhoneIds(db, id);
    final oldPhoneList = await _userPhoneNumbersOrdered(db, id);
    final oldEq = await _linkedEquipmentSnapshotsForUser(db, id);
    return db.transaction((txn) async {
      var n = 0;
      if (map.isNotEmpty) {
        n = await txn.update('users', map, where: 'id = ?', whereArgs: [id]);
      }
      if (phonesRaw != null) {
        final phones = phonesRaw is List
            ? phonesRaw
                .map((e) => e.toString().trim())
                .where((s) => s.isNotEmpty)
                .toList()
            : <String>[];
        await _replaceUserPhonesInTxn(txn, id, phones);
      }
      if (!recordAudit) return n;

      final newRow = await _userRowById(txn, id);
      final afterPhoneIds = await _userPhoneIds(txn, id);
      final ap = await _auditPerformingUser();
      final oldAudit = oldRow == null
          ? <String, dynamic>{}
          : _userRowAuditValues(oldRow);
      final newAudit = newRow == null
          ? <String, dynamic>{}
          : _userRowAuditValues(newRow);
      oldAudit['linked_phone_numbers'] = oldPhoneList;
      newAudit['linked_phone_numbers'] =
          await _userPhoneNumbersOrdered(txn, id);
      oldAudit['linked_equipment'] = oldEq;
      newAudit['linked_equipment'] =
          await _linkedEquipmentSnapshotsForUser(txn, id);

      final oldDiff = <String, dynamic>{};
      final newDiff = <String, dynamic>{};
      for (final k in {...oldAudit.keys, ...newAudit.keys}) {
        final a = oldAudit[k];
        final b = newAudit[k];
        if (k == 'linked_equipment' || k == 'linked_phone_numbers') {
          if (jsonEncode(a) == jsonEncode(b)) continue;
        } else if ('${a ?? ''}' == '${b ?? ''}') {
          continue;
        }
        oldDiff[k] = a;
        newDiff[k] = b;
      }
      if (oldDiff.isNotEmpty) {
        await AuditService.log(
          txn,
          action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΧΡΗΣΤΗ',
          userPerforming: ap,
          details: 'users id=$id',
          entityType: AuditEntityTypes.user,
          entityId: id,
          entityName: _userDisplayNameFromRow(newRow).isEmpty
              ? null
              : _userDisplayNameFromRow(newRow),
          oldValues: oldDiff,
          newValues: newDiff,
        );
      }
      await _auditPhoneUserLinkDeltaInTxn(
        txn,
        ap,
        id,
        beforePhoneIds,
        afterPhoneIds,
      );
      return n;
    });
  }

  Future<void> bulkUpdateUsers(
    List<int> ids,
    Map<String, dynamic> changes,
  ) async {
    if (ids.isEmpty || changes.isEmpty) return;
    final map = Map<String, dynamic>.from(changes);
    map.remove('id');
    final phoneBulk = map.remove('phone') as String?;
    if (map.isEmpty && phoneBulk == null) return;
    await db.transaction((txn) async {
      final apPhone = await _auditPerformingUser();
      if (map.isNotEmpty) {
        for (final id in ids) {
          await txn.update('users', map, where: 'id = ?', whereArgs: [id]);
        }
      }
      if (phoneBulk != null) {
        final list = PhoneListParser.splitPhones(phoneBulk);
        for (final id in ids) {
          final beforeIds = await _userPhoneIds(txn, id);
          await _replaceUserPhonesInTxn(txn, id, list);
          final afterIds = await _userPhoneIds(txn, id);
          await _auditPhoneUserLinkDeltaInTxn(
            txn,
            apPhone,
            id,
            beforeIds,
            afterIds,
          );
        }
      }
      final user = await _auditPerformingUser();
      final fields = Map<String, dynamic>.from(map);
      if (phoneBulk != null) {
        fields['phone'] = phoneBulk;
      }
      if (fields.isNotEmpty) {
        await AuditService.logBulk(
          txn,
          action: 'ΜΑΖΙΚΗ ΕΝΗΜΕΡΩΣΗ',
          userPerforming: user,
          entityType: AuditEntityTypes.bulkUsers,
          affectedIds: ids,
          appliedFields: fields,
          details: 'bulkUpdateUsers ids=${ids.length}',
        );
      }
    });
  }

  Future<void> deleteUsers(List<int> ids) async {
    if (ids.isEmpty) return;
    final user = await _auditPerformingUser();
    await db.transaction((txn) async {
      for (final id in ids) {
        final nameRows = await txn.query(
          'users',
          columns: ['first_name', 'last_name'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        final fn = nameRows.isEmpty
            ? ''
            : (nameRows.first['first_name'] as String?)?.trim() ?? '';
        final ln = nameRows.isEmpty
            ? ''
            : (nameRows.first['last_name'] as String?)?.trim() ?? '';
        final displayName = '$fn $ln'.trim();
        await txn.update(
          'users',
          {'is_deleted': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
        await AuditService.log(
          txn,
          action: DatabaseHelper.auditActionDelete,
          userPerforming: user,
          details: 'users id=$id',
          entityType: AuditEntityTypes.user,
          entityId: id,
          entityName: displayName.isEmpty ? null : displayName,
        );
      }
    });
  }

  Future<void> restoreUsers(List<int> ids) async {
    if (ids.isEmpty) return;
    final user = await _auditPerformingUser();
    await db.transaction((txn) async {
      for (final id in ids) {
        final nameRows = await txn.query(
          'users',
          columns: ['first_name', 'last_name'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        final fn = nameRows.isEmpty
            ? ''
            : (nameRows.first['first_name'] as String?)?.trim() ?? '';
        final ln = nameRows.isEmpty
            ? ''
            : (nameRows.first['last_name'] as String?)?.trim() ?? '';
        final displayName = '$fn $ln'.trim();
        await txn.update(
          'users',
          {'is_deleted': 0},
          where: 'id = ?',
          whereArgs: [id],
        );
        await AuditService.log(
          txn,
          action: DatabaseHelper.auditActionRestore,
          userPerforming: user,
          details: 'users id=$id',
          entityType: AuditEntityTypes.user,
          entityId: id,
          entityName: displayName.isEmpty ? null : displayName,
        );
      }
    });
  }

  Future<String?> getSetting(String key) async {
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    await db.insert('app_settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool> departmentNameExists(String? name) async {
    final trimmed = stripDepartmentDeletedDisplaySuffix(name);
    if (trimmed.isEmpty) return false;
    final key = SearchTextNormalizer.normalizeForSearch(trimmed);
    if (key.isEmpty) return false;
    final rows = await db.query(
      'departments',
      columns: ['id'],
      where: 'COALESCE(is_deleted, 0) = 0 AND name_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<int?> getOrCreateDepartmentIdByName(
    String? name, {
    bool recordAudit = true,
  }) async {
    final displayName = stripDepartmentDeletedDisplaySuffix(name).trim();
    if (displayName.isEmpty) return null;
    final key = SearchTextNormalizer.normalizeForSearch(displayName);
    if (key.isEmpty) return null;
    return db.transaction<int?>((txn) async {
      Future<int?> findId() async {
        final rows = await txn.query(
          'departments',
          columns: ['id'],
          where: 'COALESCE(is_deleted, 0) = 0 AND name_key = ?',
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
        final ap = await _auditPerformingUser();
        await AuditService.log(
          txn,
          action: 'ΔΗΜΙΟΥΡΓΙΑ ΤΜΗΜΑΤΟΣ',
          userPerforming: ap,
          details: 'departments id=$newId (getOrCreateDepartmentIdByName)',
          entityType: AuditEntityTypes.department,
          entityId: newId,
          entityName: displayName,
          newValues: {'name': displayName},
        );
      }
      return newId;
    });
  }

  Future<List<Map<String, dynamic>>> getDepartments() async {
    return db.query('departments', orderBy: 'name COLLATE NOCASE ASC');
  }

  /// Μία γραμμή `departments` για άνοιγμα φόρμας τμήματος (ή null).
  Future<Map<String, dynamic>?> getDepartmentRowById(int id) async {
    final rows = await db.query(
      'departments',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Τηλέφωνα χωρίς καμία εγγραφή σε `user_phones` (οποιαδήποτε άλλη σχέση επιτρέπεται).
  /// Επιστρέφει `phone_id`, `number`, `dept_names` (GROUP_CONCAT), `primary_department_id` (MIN έγκυρου τμήματος).
  Future<List<Map<String, dynamic>>> getNonUserPhonesCatalogRows() async {
    await _ensurePhonesDepartmentColumn(db);
    return db.rawQuery('''
WITH phone_dept AS (
  SELECT p.id AS phone_id, p.department_id AS dept_id
  FROM phones p
  WHERE p.department_id IS NOT NULL
  UNION
  SELECT dp.phone_id AS phone_id, dp.department_id AS dept_id
  FROM department_phones dp
)
SELECT
  p.id AS phone_id,
  p.number AS number,
  GROUP_CONCAT(DISTINCT d.name) AS dept_names,
  MIN(d.id) AS primary_department_id
FROM phones p
LEFT JOIN phone_dept pd ON pd.phone_id = p.id
LEFT JOIN departments d ON d.id = pd.dept_id AND COALESCE(d.is_deleted, 0) = 0
WHERE NOT EXISTS (SELECT 1 FROM user_phones up WHERE up.phone_id = p.id)
GROUP BY p.id, p.number
ORDER BY p.number COLLATE NOCASE ASC
''');
  }

  Future<int> insertDepartment(Map<String, dynamic> row) async {
    final map = Map<String, dynamic>.from(row);
    map.remove('id');
    map['is_deleted'] = map['is_deleted'] ?? 0;
    final name = (map['name'] as String?)?.trim() ?? '';
    final key = SearchTextNormalizer.normalizeForSearch(name);
    if (key.isNotEmpty) {
      map['name_key'] = map['name_key'] ?? key;
    }
    try {
      final id = await db.insert('departments', map);
      final ap = await _auditPerformingUser();
      final nv = <String, dynamic>{};
      for (final k in map.keys) {
        if (k == 'name_key') continue;
        nv[k] = map[k];
      }
      await AuditService.log(
        db,
        action: 'ΔΗΜΙΟΥΡΓΙΑ ΤΜΗΜΑΤΟΣ',
        userPerforming: ap,
        details: 'departments id=$id',
        entityType: AuditEntityTypes.department,
        entityId: id,
        entityName: name.isEmpty ? null : name,
        newValues: nv.isEmpty ? null : nv,
      );
      return id;
    } catch (e) {
      if (_isSqliteUniqueConstraintFailure(e)) {
        final existing = await _findDepartmentRowByKey(
          (map['name_key'] as String?)?.trim() ?? key,
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

  Future<Map<String, dynamic>?> _findDepartmentRowByKey(String key) async {
    final k = key.trim();
    if (k.isEmpty) return null;
    final rows = await db.query(
      'departments',
      where: 'name_key = ?',
      whereArgs: [k],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<void> _restoreDepartmentsInTxn(Transaction txn, List<int> ids, String user) async {
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
    final user = await _auditPerformingUser();
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
        await txn.update('departments', updates, where: 'id = ?', whereArgs: [id]);
      }
    });
  }

  Future<int> updateDepartment(int id, Map<String, dynamic> values) async {
    final map = Map<String, dynamic>.from(values);
    map.remove('id');
    if (map.isEmpty) return 0;
    final oldRows = await db.query(
      'departments',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (oldRows.isEmpty) return 0;
    final oldRow = oldRows.first;
    final n = await db.update('departments', map, where: 'id = ?', whereArgs: [id]);
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
      final ap = await _auditPerformingUser();
      final dn = (oldRow['name'] as String?)?.trim() ?? '';
      await AuditService.log(
        db,
        action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΤΜΗΜΑΤΟΣ',
        userPerforming: ap,
        details: 'departments id=$id',
        entityType: AuditEntityTypes.department,
        entityId: id,
        entityName: dn.isEmpty ? null : dn,
        oldValues: oldDiff,
        newValues: newDiff,
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
      final user = await _auditPerformingUser();
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

  Future<void> softDeleteDepartments(List<int> ids) async {
    if (ids.isEmpty) return;
    final user = await _auditPerformingUser();
    await db.transaction((txn) async {
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
          {'is_deleted': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
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
    });
  }

  Future<void> restoreDepartments(List<int> ids) async {
    if (ids.isEmpty) return;
    final user = await _auditPerformingUser();
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
      where: 'COALESCE(is_deleted, 0) = 0 AND id != ? AND name_key = ?',
      whereArgs: [excludeId, key],
      limit: 1,
    );
    return rows.isNotEmpty;
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

  Future<void> unlinkUserFromEquipment(int userId, int equipmentId) async {
    await db.transaction((txn) async {
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
      final ap = await _auditPerformingUser();
      final uSnap = await _linkedEquipmentSnapshotsForUser(txn, userId);
      final eSnap = await _linkedUserSnapshotsForEquipment(txn, equipmentId);
      final uRow = await _userRowById(txn, userId);
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
        entityName: _userDisplayNameFromRow(uRow).isEmpty
            ? null
            : _userDisplayNameFromRow(uRow),
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
    });
  }

  Future<void> linkUserToEquipment(int userId, int equipmentId) async {
    await db.transaction((txn) async {
      final pre = await txn.query(
        'user_equipment',
        where: 'user_id = ? AND equipment_id = ?',
        whereArgs: [userId, equipmentId],
        limit: 1,
      );
      if (pre.isNotEmpty) return;
      await txn.insert(
        'user_equipment',
        {'user_id': userId, 'equipment_id': equipmentId},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      final post = await txn.query(
        'user_equipment',
        where: 'user_id = ? AND equipment_id = ?',
        whereArgs: [userId, equipmentId],
        limit: 1,
      );
      if (post.isEmpty) return;
      final ap = await _auditPerformingUser();
      final uSnap = await _linkedEquipmentSnapshotsForUser(txn, userId);
      final eSnap = await _linkedUserSnapshotsForEquipment(txn, equipmentId);
      final uRow = await _userRowById(txn, userId);
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
        entityName: _userDisplayNameFromRow(uRow).isEmpty
            ? null
            : _userDisplayNameFromRow(uRow),
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
    });
  }

  Future<String?> getDepartmentNameById(int departmentId) async {
    final rows = await db.query(
      'departments',
      columns: ['name'],
      where: 'id = ? AND COALESCE(is_deleted, 0) = 0',
      whereArgs: [departmentId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['name'] as String?;
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
      final ap = await _auditPerformingUser();
      final uSnap = await _linkedEquipmentSnapshotsForUser(txn, toUserId);
      final uRow = await _userRowById(txn, toUserId);
      await AuditService.log(
        txn,
        action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΧΡΗΣΤΗ',
        userPerforming: ap,
        details: 'users id=$toUserId (αντιγραφή συνδέσεων εξοπλισμού)',
        entityType: AuditEntityTypes.user,
        entityId: toUserId,
        entityName: _userDisplayNameFromRow(uRow).isEmpty
            ? null
            : _userDisplayNameFromRow(uRow),
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

  Future<void> replaceEquipmentUsers(int equipmentId, List<int> userIds) async {
    final unique = userIds.toSet().toList();
    await db.transaction((txn) async {
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
      final ap = await _auditPerformingUser();
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
        final uRow = await _userRowById(txn, uid);
        await AuditService.log(
          txn,
          action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΧΡΗΣΤΗ',
          userPerforming: ap,
          details: 'users id=$uid (αντικατάσταση εξοπλισμού)',
          entityType: AuditEntityTypes.user,
          entityId: uid,
          entityName: _userDisplayNameFromRow(uRow).isEmpty
              ? null
              : _userDisplayNameFromRow(uRow),
          newValues: {'linked_equipment': uSnap},
        );
      }
    });
  }

  Future<int> insertEquipmentFromMap(Map<String, dynamic> row) async {
    final map = Map<String, dynamic>.from(row);
    map.remove('id');
    final id = await db.insert('equipment', map);
    final ap = await _auditPerformingUser();
    final code = (map['code_equipment'] as String?)?.trim() ?? '';
    await AuditService.log(
      db,
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

  Future<int> updateEquipment(int id, Map<String, dynamic> values) async {
    final map = Map<String, dynamic>.from(values);
    map.remove('id');
    if (map.isEmpty) return 0;
    final oldRows = await db.query(
      'equipment',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (oldRows.isEmpty) return 0;
    final oldRow = oldRows.first;
    final n = await db.update('equipment', map, where: 'id = ?', whereArgs: [id]);
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
      final ap = await _auditPerformingUser();
      final code = (oldRow['code_equipment'] as String?)?.trim() ?? '';
      await AuditService.log(
        db,
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
      final user = await _auditPerformingUser();
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
    final user = await _auditPerformingUser();
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
    final user = await _auditPerformingUser();
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

  Future<void> clearImportedData() async {
    final user = await _auditPerformingUser();
    await db.transaction((txn) async {
      await txn.rawUpdate('UPDATE equipment SET is_deleted = 1');
      await txn.rawUpdate('UPDATE users SET is_deleted = 1');
      await AuditService.log(
        txn,
        action: DatabaseHelper.auditActionBulkDelete,
        userPerforming: user,
        details: 'clearImportedData: users+equipment (soft)',
        entityType: AuditEntityTypes.importData,
        newValues: {'operation': 'clearImportedData'},
      );
    });
  }

  Future<({int usersInserted, int equipmentInserted})> importPreparedData(
    List<Map<String, dynamic>> ownersList,
    List<Map<String, dynamic>> equipmentList,
  ) async {
    if (ownersList.isEmpty && equipmentList.isEmpty) {
      return (usersInserted: 0, equipmentInserted: 0);
    }
    int usersInserted = 0;
    int equipmentInserted = 0;

    final deptNameToId = <String, int?>{};
    for (final u in ownersList) {
      final dn = (u['department'] as String?)?.trim() ?? '';
      if (dn.isNotEmpty) {
        deptNameToId.putIfAbsent(dn, () => null);
      }
    }
    for (final name in deptNameToId.keys.toList()) {
      deptNameToId[name] =
          await getOrCreateDepartmentIdByName(name, recordAudit: false);
    }

    await db.transaction((txn) async {
      final ownerCodeToDbId = <int, int>{};
      for (final u in ownersList) {
        final ownerId = u['ownerId'] as int? ?? 0;
        final fullName = u['fullName'] as String? ?? '';
        final parsed = NameParserUtility.parse(fullName);
        final dn = (u['department'] as String?)?.trim() ?? '';
        final did = dn.isEmpty ? null : deptNameToId[dn];
        final id = await txn.insert('users', {
          'last_name': parsed.lastName,
          'first_name': parsed.firstName,
          'location': null,
          'notes': null,
          'is_deleted': 0,
          'department_id': did,
        });
        final importPhones = PhoneListParser.splitPhones(
          u['phones'] as String?,
        );
        if (importPhones.isNotEmpty) {
          await _replaceUserPhonesInTxn(txn, id, importPhones);
        }
        ownerCodeToDbId[ownerId] = id;
      }
      usersInserted = ownerCodeToDbId.length;

      for (final e in equipmentList) {
        final ownerCodeTemp = e['ownerCodeTemp'] as int? ?? 0;
        final userId = ownerCodeToDbId[ownerCodeTemp];
        final eqId = await txn.insert('equipment', {
          'code_equipment': e['code'] as String?,
          'is_deleted': 0,
        });
        if (userId != null) {
          await txn.insert('user_equipment', {
            'user_id': userId,
            'equipment_id': eqId,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        equipmentInserted++;
      }
    });

    final apImport = await _auditPerformingUser();
    await AuditService.log(
      db,
      action: 'ΕΙΣΑΓΩΓΗ ΔΕΔΟΜΕΝΩΝ',
      userPerforming: apImport,
      details: 'importPreparedData',
      entityType: AuditEntityTypes.importData,
      newValues: {
        'users_inserted': usersInserted,
        'equipment_inserted': equipmentInserted,
      },
    );

    return (usersInserted: usersInserted, equipmentInserted: equipmentInserted);
  }

  Future<int> insertUser({
    required String firstName,
    required String lastName,
    List<String>? phones,
    String? department,
    String? location,
    String? notes,
    int? departmentId,
  }) async {
    var resolvedDeptId = departmentId;
    if (resolvedDeptId == null &&
        department != null &&
        department.trim().isNotEmpty) {
      resolvedDeptId = await getOrCreateDepartmentIdByName(department);
    }
    final map = <String, dynamic>{
      'last_name': lastName,
      'first_name': firstName,
      'location': location,
      'notes': notes,
      'is_deleted': 0,
    };
    if (resolvedDeptId != null) {
      map['department_id'] = resolvedDeptId;
    }
    if (phones != null && phones.isNotEmpty) {
      map['phones'] = phones;
    }
    return insertUserFromMap(map);
  }

  Future<void> updateAssociationsIfNeeded(
    int? userId,
    String? phone,
    String? equipmentCode,
  ) async {
    if (userId == null) return;
    await db.transaction((txn) async {
      var phoneChanged = false;
      var equipmentLinked = false;
      int? equipmentIdForAudit;
      final trimmedPhone = phone?.trim() ?? '';

      if (trimmedPhone.isNotEmpty) {
        final existingRows = await txn.rawQuery(
          '''
          SELECT p.number AS number FROM user_phones up
          JOIN phones p ON p.id = up.phone_id
          WHERE up.user_id = ?
          ''',
          [userId],
        );
        final existing = existingRows
            .map((r) => r['number'] as String?)
            .whereType<String>()
            .toList();
        if (!existing.contains(trimmedPhone)) {
          final beforeIds = await _userPhoneIds(txn, userId);
          await _replaceUserPhonesInTxn(txn, userId, [...existing, trimmedPhone]);
          final afterIds = await _userPhoneIds(txn, userId);
          phoneChanged = true;
          final apPhones = await _auditPerformingUser();
          await _auditPhoneUserLinkDeltaInTxn(
            txn,
            apPhones,
            userId,
            beforeIds,
            afterIds,
          );
        }
      }

      if (equipmentCode != null && equipmentCode.trim().isNotEmpty) {
        final code = equipmentCode.trim();
        final existingEq = await txn.query(
          'equipment',
          columns: ['id'],
          where: 'code_equipment = ? AND COALESCE(is_deleted, 0) = 0',
          whereArgs: [code],
          limit: 1,
        );
        final int equipmentId;
        if (existingEq.isEmpty) {
          equipmentId = await txn.insert('equipment', {
            'code_equipment': code,
            'is_deleted': 0,
          });
        } else {
          equipmentId = existingEq.first['id'] as int;
        }
        equipmentIdForAudit = equipmentId;
        final preLink = await txn.query(
          'user_equipment',
          where: 'user_id = ? AND equipment_id = ?',
          whereArgs: [userId, equipmentId],
          limit: 1,
        );
        if (preLink.isEmpty) {
          await txn.insert(
            'user_equipment',
            {
              'user_id': userId,
              'equipment_id': equipmentId,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          final postLink = await txn.query(
            'user_equipment',
            where: 'user_id = ? AND equipment_id = ?',
            whereArgs: [userId, equipmentId],
            limit: 1,
          );
          if (postLink.isNotEmpty) {
            equipmentLinked = true;
          }
        }
      }

      if (!phoneChanged && !equipmentLinked) return;

      final uRow = await _userRowById(txn, userId);
      final userLabel = _userDisplayNameFromRow(uRow);
      final deptName = await _departmentNameForUserTxn(txn, userId);
      final eqTrim = equipmentCode?.trim() ?? '';
      final action = auditCallAssociationActionLine(
        userPart: userLabel.isEmpty ? null : userLabel,
        departmentPart: deptName,
        phonePart: phoneChanged ? trimmedPhone : null,
        equipmentPart: equipmentLinked && eqTrim.isNotEmpty ? eqTrim : null,
      );

      final ap = await _auditPerformingUser();
      final nv = <String, dynamic>{};
      if (phoneChanged) nv['phone_associated'] = trimmedPhone;
      if (equipmentLinked && equipmentIdForAudit != null) {
        nv['equipment_id'] = equipmentIdForAudit;
        nv['equipment_code'] = eqTrim;
      }

      await AuditService.log(
        txn,
        action: action,
        userPerforming: ap,
        details: 'updateAssociationsIfNeeded userId=$userId',
        entityType: AuditEntityTypes.user,
        entityId: userId,
        entityName: userLabel.isEmpty ? null : userLabel,
        newValues: nv.isEmpty ? null : nv,
      );

      if (equipmentLinked && equipmentIdForAudit != null && eqTrim.isNotEmpty) {
        final usersSnap =
            await _linkedUserSnapshotsForEquipment(txn, equipmentIdForAudit);
        await AuditService.log(
          txn,
          action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΕΞΟΠΛΙΣΜΟΥ',
          userPerforming: ap,
          details: 'equipment id=$equipmentIdForAudit (σύνδεση από κλήση)',
          entityType: AuditEntityTypes.equipment,
          entityId: equipmentIdForAudit,
          entityName: eqTrim,
          newValues: {'linked_users': usersSnap},
        );
      }
    });
  }

  Future<List<String>> getCategoryNames() async {
    final rows = await db.query(
      'categories',
      columns: ['name'],
      where: 'COALESCE(is_deleted, 0) = ?',
      whereArgs: [0],
      orderBy: 'name',
    );
    return rows
        .map((r) => r['name'] as String? ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Future<List<Map<String, dynamic>>> getActiveCategoryRows() async {
    return db.query(
      'categories',
      columns: ['id', 'name'],
      where: 'COALESCE(is_deleted, 0) = 0',
      orderBy: 'name COLLATE NOCASE ASC',
    );
  }

  Future<({int id, String name})?> findActiveCategoryByNormalizedName(
    String input,
  ) async {
    final key = DatabaseHelper.normalizeCategoryNameForLookup(input);
    if (key.isEmpty) return null;
    final rows = await getActiveCategoryRows();
    for (final r in rows) {
      final n = (r['name'] as String?)?.trim() ?? '';
      if (DatabaseHelper.normalizeCategoryNameForLookup(n) == key) {
        return (id: r['id'] as int, name: n);
      }
    }
    return null;
  }

  Future<bool> categoryNormalizedNameTaken(
    String name, {
    int? excludeId,
  }) async {
    final key = DatabaseHelper.normalizeCategoryNameForLookup(name);
    if (key.isEmpty) return false;
    final rows = await getActiveCategoryRows();
    for (final r in rows) {
      if (excludeId != null && r['id'] == excludeId) continue;
      final n = (r['name'] as String?)?.trim() ?? '';
      if (DatabaseHelper.normalizeCategoryNameForLookup(n) == key) return true;
    }
    return false;
  }

  Future<({int id, String name})?> _findSoftDeletedCategoryRowByNormalizedName(
    String input,
  ) async {
    final key = DatabaseHelper.normalizeCategoryNameForLookup(input);
    if (key.isEmpty) return null;
    final rows = await db.query(
      'categories',
      columns: ['id', 'name'],
      where: 'COALESCE(is_deleted, 0) = ?',
      whereArgs: [1],
      orderBy: 'id DESC',
    );
    for (final r in rows) {
      final n = (r['name'] as String?)?.trim() ?? '';
      if (DatabaseHelper.normalizeCategoryNameForLookup(n) == key) {
        return (id: r['id'] as int, name: n);
      }
    }
    return null;
  }

  /// [rebuildSearchIndexInTxn]: από orchestrator — π.χ. [CallsRepository.rebuildSearchIndexForCallsByCategoryId].
  Future<({int id, bool restored})> insertCategoryAndGetId(
    String name, {
    required RebuildCallSearchIndexForCategoryInTxn rebuildSearchIndexInTxn,
  }) async {
    final t = name.trim();
    if (t.isEmpty) {
      throw StateError('Κενό όνομα κατηγορίας.');
    }
    if (await categoryNormalizedNameTaken(t)) {
      throw StateError('Υπάρχει ήδη κατηγορία με ισοδύναμο όνομα.');
    }
    final soft = await _findSoftDeletedCategoryRowByNormalizedName(t);
    if (soft != null) {
      final id = soft.id;
      final user = await _auditPerformingUser();
      await db.transaction((txn) async {
        await txn.update(
          'categories',
          {'is_deleted': 0, 'name': t},
          where: 'id = ?',
          whereArgs: [id],
        );
        await txn.rawUpdate(
          'UPDATE calls SET category_text = ? WHERE category_id = ?',
          [t, id],
        );
        await AuditService.log(
          txn,
          action: DatabaseHelper.auditActionRestore,
          userPerforming: user,
          details: 'categories id=$id (επαναφορά από διαγραμμένη)',
          entityType: AuditEntityTypes.category,
          entityId: id,
          entityName: t,
        );
        await rebuildSearchIndexInTxn(txn, id);
      });
      return (id: id, restored: true);
    }
    final newId = await db.insert('categories', {'name': t, 'is_deleted': 0});
    return (id: newId, restored: false);
  }

  Future<void> updateCategoryNameAndSyncCalls({
    required int id,
    required String newCanonicalName,
    required RebuildCallSearchIndexForCategoryInTxn rebuildSearchIndexInTxn,
  }) async {
    final t = newCanonicalName.trim();
    if (t.isEmpty) throw ArgumentError('empty name');
    if (await categoryNormalizedNameTaken(t, excludeId: id)) {
      throw StateError('Υπάρχει ήδη κατηγορία με ισοδύναμο όνομα.');
    }
    final user = await _auditPerformingUser();
    await db.transaction((txn) async {
      await txn.update(
        'categories',
        {'name': t},
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.rawUpdate(
        'UPDATE calls SET category_text = ? WHERE category_id = ?',
        [t, id],
      );
      await AuditService.log(
        txn,
        action: 'ΤΡΟΠΟΠΟΙΗΣΗ',
        userPerforming: user,
        details: 'categories id=$id',
        entityType: AuditEntityTypes.category,
        entityId: id,
        entityName: t,
        newValues: {'name': t},
      );
      await rebuildSearchIndexInTxn(txn, id);
    });
  }

  Future<void> softDeleteCategories(List<int> ids) async {
    if (ids.isEmpty) return;
    final user = await _auditPerformingUser();
    await db.transaction((txn) async {
      for (final id in ids) {
        final catRows = await txn.query(
          'categories',
          columns: ['name'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        final catName = catRows.isEmpty
            ? null
            : (catRows.first['name'] as String?)?.trim();
        await txn.update(
          'categories',
          {'is_deleted': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
        await AuditService.log(
          txn,
          action: DatabaseHelper.auditActionDelete,
          userPerforming: user,
          details: 'categories id=$id',
          entityType: AuditEntityTypes.category,
          entityId: id,
          entityName: catName != null && catName.isNotEmpty ? catName : null,
        );
      }
    });
  }

  Future<void> restoreCategories(List<int> ids) async {
    if (ids.isEmpty) return;
    final user = await _auditPerformingUser();
    await db.transaction((txn) async {
      for (final id in ids) {
        final catRows = await txn.query(
          'categories',
          columns: ['name'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        final catName = catRows.isEmpty
            ? null
            : (catRows.first['name'] as String?)?.trim();
        await txn.update(
          'categories',
          {'is_deleted': 0},
          where: 'id = ?',
          whereArgs: [id],
        );
        await AuditService.log(
          txn,
          action: DatabaseHelper.auditActionRestore,
          userPerforming: user,
          details: 'categories id=$id',
          entityType: AuditEntityTypes.category,
          entityId: id,
          entityName: catName != null && catName.isNotEmpty ? catName : null,
        );
      }
    });
  }

  Future<void> softDeleteTask(int id) async {
    final user = await _auditPerformingUser();
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
        entityName:
            taskTitle != null && taskTitle.isNotEmpty ? taskTitle : null,
      );
    });
  }
}
