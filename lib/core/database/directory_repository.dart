import 'dart:async';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../errors/department_exists_exception.dart';
import '../utils/department_display_utils.dart';
import '../utils/name_parser.dart';
import '../utils/phone_list_parser.dart';
import '../utils/search_text_normalizer.dart';
import 'database_helper.dart';

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

  Future<void> _appendAuditLog(
    DatabaseExecutor executor,
    String performingUser,
    String action,
    String details,
  ) async {
    await executor.insert('audit_log', {
      'action': action,
      'timestamp': DateTime.now().toIso8601String(),
      'user_performing': performingUser,
      'details': details,
    });
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
      await _addDepartmentPhoneInTxn(txn, departmentId, phoneNumber);
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
      await txn.delete(
        'department_phones',
        where: 'department_id = ? AND phone_id = ?',
        whereArgs: [departmentId, pid],
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

  Future<void> updatePhoneDepartment(
    String phoneNumber,
    int departmentId,
  ) async {
    final t = phoneNumber.trim();
    if (t.isEmpty) return;
    await db.transaction((txn) async {
      await _ensurePhonesDepartmentColumn(txn);
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
        columns: ['id'],
        where: 'code_equipment = ? AND COALESCE(is_deleted, 0) = 0',
        whereArgs: [code],
        limit: 1,
      );
      if (rows.isEmpty) {
        await txn.insert('equipment', {
          'code_equipment': code,
          'department_id': departmentId,
          'is_deleted': 0,
        });
        return;
      }
      final id = rows.first['id'] as int;
      await txn.update(
        'equipment',
        {'department_id': departmentId},
        where: 'id = ?',
        whereArgs: [id],
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
      await txn.delete('user_phones', where: 'phone_id = ?', whereArgs: [pid]);
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
      await txn.delete(
        'user_equipment',
        where: 'equipment_id = ?',
        whereArgs: [eid],
      );
    });
  }

  Future<void> replaceUserPhones(int userId, List<String> numbers) async {
    await db.transaction(
      (txn) => _replaceUserPhonesInTxn(txn, userId, numbers),
    );
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
      final id = await txn.insert('users', map);
      if (phones.isNotEmpty) {
        await _replaceUserPhonesInTxn(txn, id, phones);
      }
      return id;
    });
  }

  Future<int> updateUser(int id, Map<String, dynamic> values) async {
    final map = Map<String, dynamic>.from(values);
    map.remove('id');
    final phonesRaw = map.remove('phones');
    map.remove('phone');
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
      if (map.isNotEmpty) {
        for (final id in ids) {
          await txn.update('users', map, where: 'id = ?', whereArgs: [id]);
        }
      }
      if (phoneBulk != null) {
        final list = PhoneListParser.splitPhones(phoneBulk);
        for (final id in ids) {
          await _replaceUserPhonesInTxn(txn, id, list);
        }
      }
    });
  }

  Future<void> deleteUsers(List<int> ids) async {
    if (ids.isEmpty) return;
    final user = await _auditPerformingUser();
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.update(
          'users',
          {'is_deleted': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
        await _appendAuditLog(
          txn,
          user,
          DatabaseHelper.auditActionDelete,
          'users id=$id',
        );
      }
    });
  }

  Future<void> restoreUsers(List<int> ids) async {
    if (ids.isEmpty) return;
    final user = await _auditPerformingUser();
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.update(
          'users',
          {'is_deleted': 0},
          where: 'id = ?',
          whereArgs: [id],
        );
        await _appendAuditLog(
          txn,
          user,
          DatabaseHelper.auditActionRestore,
          'users id=$id',
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

  Future<int?> getOrCreateDepartmentIdByName(String? name) async {
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

      return findId();
    });
  }

  Future<List<Map<String, dynamic>>> getDepartments() async {
    return db.query('departments', orderBy: 'name COLLATE NOCASE ASC');
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
      return await db.insert('departments', map);
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
      await txn.update(
        'departments',
        {'is_deleted': 0},
        where: 'id = ?',
        whereArgs: [id],
      );
      await _appendAuditLog(
        txn,
        user,
        DatabaseHelper.auditActionRestore,
        'departments id=$id',
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
    return db.update('departments', map, where: 'id = ?', whereArgs: [id]);
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
        await txn.update(
          'departments',
          {'is_deleted': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
        await _appendAuditLog(
          txn,
          user,
          DatabaseHelper.auditActionDelete,
          'departments id=$id',
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
    await db.delete(
      'user_equipment',
      where: 'user_id = ? AND equipment_id = ?',
      whereArgs: [userId, equipmentId],
    );
  }

  Future<void> linkUserToEquipment(int userId, int equipmentId) async {
    await db.insert(
      'user_equipment',
      {'user_id': userId, 'equipment_id': equipmentId},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
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
  }

  Future<void> replaceEquipmentUsers(int equipmentId, List<int> userIds) async {
    final unique = userIds.toSet().toList();
    await db.transaction((txn) async {
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
    });
  }

  Future<int> insertEquipmentFromMap(Map<String, dynamic> row) async {
    final map = Map<String, dynamic>.from(row);
    map.remove('id');
    return db.insert('equipment', map);
  }

  Future<int> updateEquipment(int id, Map<String, dynamic> values) async {
    final map = Map<String, dynamic>.from(values);
    map.remove('id');
    return db.update('equipment', map, where: 'id = ?', whereArgs: [id]);
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
    });
  }

  Future<void> deleteEquipments(List<int> ids) async {
    if (ids.isEmpty) return;
    final user = await _auditPerformingUser();
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.update(
          'equipment',
          {'is_deleted': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
        await _appendAuditLog(txn, user, DatabaseHelper.auditActionDelete, 'equipment id=$id');
      }
    });
  }

  Future<void> restoreEquipment(List<int> ids) async {
    if (ids.isEmpty) return;
    final user = await _auditPerformingUser();
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.update(
          'equipment',
          {'is_deleted': 0},
          where: 'id = ?',
          whereArgs: [id],
        );
        await _appendAuditLog(
          txn,
          user,
          DatabaseHelper.auditActionRestore,
          'equipment id=$id',
        );
      }
    });
  }

  Future<void> clearImportedData() async {
    final user = await _auditPerformingUser();
    await db.transaction((txn) async {
      await txn.rawUpdate('UPDATE equipment SET is_deleted = 1');
      await txn.rawUpdate('UPDATE users SET is_deleted = 1');
      await _appendAuditLog(
        txn,
        user,
        DatabaseHelper.auditActionBulkDelete,
        'clearImportedData: users+equipment (soft)',
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
      deptNameToId[name] = await getOrCreateDepartmentIdByName(name);
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
    final list = phones ?? const <String>[];
    return db.transaction((txn) async {
      final id = await txn.insert('users', map);
      if (list.isNotEmpty) {
        await _replaceUserPhonesInTxn(txn, id, list);
      }
      return id;
    });
  }

  Future<void> updateAssociationsIfNeeded(
    int? userId,
    String? phone,
    String? equipmentCode,
  ) async {
    if (userId == null) return;
    await db.transaction((txn) async {
      if (phone != null && phone.trim().isNotEmpty) {
        final trimmed = phone.trim();
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
        if (!existing.contains(trimmed)) {
          await _replaceUserPhonesInTxn(txn, userId, [...existing, trimmed]);
        }
      }
      if (equipmentCode != null && equipmentCode.isNotEmpty) {
        final code = equipmentCode.trim();
        if (code.isNotEmpty) {
          final existing = await txn.query(
            'equipment',
            columns: ['id'],
            where: 'code_equipment = ? AND COALESCE(is_deleted, 0) = 0',
            whereArgs: [code],
            limit: 1,
          );
          final int equipmentId;
          if (existing.isEmpty) {
            equipmentId = await txn.insert('equipment', {
              'code_equipment': code,
              'is_deleted': 0,
            });
          } else {
            equipmentId = existing.first['id'] as int;
          }
          await txn.insert('user_equipment', {
            'user_id': userId,
            'equipment_id': equipmentId,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
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
        await _appendAuditLog(
          txn,
          user,
          DatabaseHelper.auditActionRestore,
          'categories id=$id (επαναφορά από διαγραμμένη)',
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
      await _appendAuditLog(
        txn,
        user,
        'ΤΡΟΠΟΠΟΙΗΣΗ',
        'categories id=$id',
      );
      await rebuildSearchIndexInTxn(txn, id);
    });
  }

  Future<void> softDeleteCategories(List<int> ids) async {
    if (ids.isEmpty) return;
    final user = await _auditPerformingUser();
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.update(
          'categories',
          {'is_deleted': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
        await _appendAuditLog(
          txn,
          user,
          DatabaseHelper.auditActionDelete,
          'categories id=$id',
        );
      }
    });
  }

  Future<void> restoreCategories(List<int> ids) async {
    if (ids.isEmpty) return;
    final user = await _auditPerformingUser();
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.update(
          'categories',
          {'is_deleted': 0},
          where: 'id = ?',
          whereArgs: [id],
        );
        await _appendAuditLog(
          txn,
          user,
          DatabaseHelper.auditActionRestore,
          'categories id=$id',
        );
      }
    });
  }

  Future<void> softDeleteTask(int id) async {
    final user = await _auditPerformingUser();
    await db.transaction((txn) async {
      await txn.update(
        'tasks',
        {'is_deleted': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
      await _appendAuditLog(txn, user, DatabaseHelper.auditActionDelete, 'tasks id=$id');
    });
  }
}
