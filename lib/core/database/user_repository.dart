import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../directory/phone_department_policy.dart';
import '../utils/phone_list_parser.dart';
import 'user_delete_equipment_policy.dart';
import 'user_delete_phone_policy.dart';
import 'audit_service.dart';
import 'calls_search_index.dart';
import 'database_helper.dart';
import 'directory_audit_helpers.dart';
import 'department_repository.dart';
import 'directory_support.dart';

/// Persistence χρηστών (`users`, `user_phones`, `user_equipment`).
class UserRepository {
  UserRepository(
    this.db, {
    DirectorySupport? support,
    DepartmentRepository? departments,
  }) : _support = support ?? DirectorySupport(db) {
    _departments = departments ?? DepartmentRepository(db, support: _support);
  }

  final Database db;
  final DirectorySupport _support;
  late final DepartmentRepository _departments;

  static const Set<String> _kUserAuditColumns = {
    'first_name',
    'last_name',
    'department_id',
    'location',
    'notes',
    'lansweeper_username',
    'is_deleted',
  };

  Future<void> replaceUserPhones(
    int userId,
    List<String> numbers, {
    DatabaseExecutor? executor,
  }) async {
    if (executor != null) {
      await _support.replaceUserPhonesInTxn(executor, userId, numbers);
      return;
    }
    await updateUser(userId, {'phones': numbers});
  }

  /// Ονόματα εμφάνισης («Επώνυμο Όνομα») για τα δοσμένα ids — και διαγραμμένων:
  /// οι εγγραφές audit αναφέρουν χρήστες που μπορεί να μην υπάρχουν πια.
  Future<Map<int, String>> getUserDisplayNamesByIds(Iterable<int> ids) async {
    final idList = ids.toSet().toList();
    if (idList.isEmpty) return const <int, String>{};
    final placeholders = List.filled(idList.length, '?').join(',');
    final rows = await db.query(
      'users',
      columns: ['id', 'last_name', 'first_name'],
      where: 'id IN ($placeholders)',
      whereArgs: idList,
    );
    final out = <int, String>{};
    for (final row in rows) {
      final id = row['id'] as int?;
      if (id == null) continue;
      final lastName = (row['last_name'] as String?)?.trim() ?? '';
      final firstName = (row['first_name'] as String?)?.trim() ?? '';
      final name = '$lastName $firstName'.trim();
      if (name.isNotEmpty) out[id] = name;
    }
    return out;
  }

  /// Ταυτότητα Lansweeper (`τομέας\όνομα` ή email) του χρήστη — null όταν
  /// δεν έχει συμπληρωθεί. Διαβάζει και διαγραμμένους: η κλήση κρατά τον
  /// καλούντα της ακόμη κι αν έφυγε αργότερα από τον Κατάλογο.
  Future<String?> getLansweeperUsernameById(int userId) async {
    final rows = await db.query(
      'users',
      columns: ['lansweeper_username'],
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final value = (rows.first['lansweeper_username'] as String?)?.trim() ?? '';
    return value.isEmpty ? null : value;
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
    // Όνομα τμήματος ως κανονικό πεδίο του row (`department_name`) ώστε το
    // [UserModel] να μη χρειάζεται lookup σε καθολική κατάσταση. Σημασιολογία
    // ταυτόσημη με το παλιό cache: null = χωρίς τμήμα, '' = id χωρίς ενεργή εγγραφή.
    final deptNameById = <int, String>{};
    for (final d in await _departments.getActiveDepartments()) {
      final did = d['id'] as int?;
      final name = d['name'] as String?;
      if (did != null && name != null) deptNameById[did] = name;
    }
    return users.map((m) {
      final copy = Map<String, dynamic>.from(m);
      final id = m['id'] as int?;
      copy['phones'] = id != null
          ? List<String>.from(byUser[id] ?? const [])
          : <String>[];
      final deptId = m['department_id'] as int?;
      copy['department_name'] = deptId == null
          ? null
          : (deptNameById[deptId] ?? '');
      return copy;
    }).toList();
  }

  Map<String, dynamic> _userRowAuditValues(Map<String, dynamic> row) {
    final m = <String, dynamic>{};
    for (final k in _kUserAuditColumns) {
      if (row.containsKey(k)) m[k] = row[k];
    }
    return m;
  }

  Future<void> _validateUserPhoneAssignmentPolicy({
    required List<String> phones,
    required int? targetDepartmentId,
    int? excludeUserId,
  }) async {
    if (phones.isEmpty) return;
    final conflicts = PhoneDepartmentPolicy.findConflictsForUserAssignment(
      phones: phones,
      targetDepartmentId: targetDepartmentId,
      editingUserId: excludeUserId,
    );
    PhoneDepartmentPolicy.assertNoUnresolvedConflicts(conflicts);
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

  Future<Set<int>> equipmentIdsForUser(int userId) =>
      _equipmentIdsForUser(db, userId);

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

  Future<int> _insertUserFromMapInTxn(
    DatabaseExecutor txn,
    Map<String, dynamic> map,
    List<String> phones, {
    String? auditOriginSuffix,
  }) async {
    final beforePhoneIds = <int>{};
    final id = await txn.insert('users', map);
    if (phones.isNotEmpty) {
      await _support.replaceUserPhonesInTxn(txn, id, phones);
    }
    final afterPhoneIds = await _support.userPhoneIds(txn, id);
    final ap = await _support.auditPerformingUser(executor: txn);
    final rowSnap = await _support.userRowById(txn, id);
    final nv = _userRowAuditValues(rowSnap ?? {});
    final nums = await _userPhoneNumbersOrdered(txn, id);
    nv['linked_phone_numbers'] = nums;
    final linkedEq = await _linkedEquipmentSnapshotsForUser(txn, id);
    nv['linked_equipment'] = linkedEq;
    await _support.applyDepartmentAuditText(txn, nv);
    final phoneLinkDetails = await _support.auditPhoneUserLinkDeltaInTxn(
      txn,
      ap,
      id,
      beforePhoneIds,
      afterPhoneIds,
    );
    await AuditService.log(
      txn,
      action: 'ΔΗΜΙΟΥΡΓΙΑ ΧΡΗΣΤΗ',
      userPerforming: ap,
      details: DirectorySupport.appendAuditOriginSuffix(
        DirectorySupport.mergeAuditDetailLines(
          'users id=$id',
          phoneLinkDetails,
        ),
        auditOriginSuffix,
      ),
      entityType: AuditEntityTypes.user,
      entityId: id,
      entityName: _support.userDisplayNameFromRow(rowSnap).isEmpty
          ? null
          : _support.userDisplayNameFromRow(rowSnap),
      newValues: nv,
    );
    return id;
  }

  Future<int> insertUserFromMap(
    Map<String, dynamic> row, {
    DatabaseExecutor? executor,
    bool skipPhonePolicyValidation = false,
    String? auditOriginSuffix,
  }) async {
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
    if (phones.isNotEmpty && !skipPhonePolicyValidation) {
      await _validateUserPhoneAssignmentPolicy(
        phones: phones,
        targetDepartmentId: map['department_id'] as int?,
        excludeUserId: null,
      );
    }
    if (executor != null) {
      return _insertUserFromMapInTxn(
        executor,
        map,
        phones,
        auditOriginSuffix: auditOriginSuffix,
      );
    }
    return db.transaction(
      (txn) => _insertUserFromMapInTxn(
        txn,
        map,
        phones,
        auditOriginSuffix: auditOriginSuffix,
      ),
    );
  }

  Future<List<String>> userPhoneNumbersOrdered(
    DatabaseExecutor e,
    int userId,
  ) => _userPhoneNumbersOrdered(e, userId);

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
    return rows.map((r) => r['number'] as String?).whereType<String>().toList();
  }

  Future<String?> _departmentNameForUserTxn(
    DatabaseExecutor txn,
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

  Future<List<Map<String, dynamic>>> getEquipmentOwnerSnapshots(
    int equipmentId,
  ) async {
    return _linkedUserSnapshotsForEquipment(db, equipmentId);
  }

  Future<int> _updateUserInTxn(
    DatabaseExecutor txn,
    int id,
    Map<String, dynamic> map,
    Object? phonesRaw, {
    required Map<String, dynamic>? oldRow,
    required Set<int> beforePhoneIds,
    required List<String> oldPhoneList,
    required List<Map<String, dynamic>> oldEq,
    required bool recordAudit,
    String? auditOriginSuffix,
  }) async {
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
      await _support.replaceUserPhonesInTxn(txn, id, phones);
    }
    if (map.isNotEmpty || phonesRaw != null) {
      await CallsSearchIndex(db).rebuildSearchIndexForCallsByCallerId(txn, id);
    }
    if (!recordAudit) return n;

    final newRow = await _support.userRowById(txn, id);
    final afterPhoneIds = await _support.userPhoneIds(txn, id);
    final ap = await _support.auditPerformingUser(executor: txn);
    final oldAudit = oldRow == null
        ? <String, dynamic>{}
        : _userRowAuditValues(oldRow);
    final newAudit = newRow == null
        ? <String, dynamic>{}
        : _userRowAuditValues(newRow);
    oldAudit['linked_phone_numbers'] = oldPhoneList;
    newAudit['linked_phone_numbers'] = await _userPhoneNumbersOrdered(txn, id);
    oldAudit['linked_equipment'] = oldEq;
    newAudit['linked_equipment'] = await _linkedEquipmentSnapshotsForUser(
      txn,
      id,
    );
    await _support.applyDepartmentAuditText(txn, oldAudit);
    await _support.applyDepartmentAuditText(txn, newAudit);

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
      final phoneLinkDetails = await _support.auditPhoneUserLinkDeltaInTxn(
        txn,
        ap,
        id,
        beforePhoneIds,
        afterPhoneIds,
      );
      await AuditService.log(
        txn,
        action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΧΡΗΣΤΗ',
        userPerforming: ap,
        details: DirectorySupport.appendAuditOriginSuffix(
          DirectorySupport.mergeAuditDetailLines(
            'users id=$id',
            phoneLinkDetails,
          ),
          auditOriginSuffix,
        ),
        entityType: AuditEntityTypes.user,
        entityId: id,
        entityName: _support.userDisplayNameFromRow(newRow).isEmpty
            ? null
            : _support.userDisplayNameFromRow(newRow),
        oldValues: oldDiff,
        newValues: newDiff,
      );
    }
    return n;
  }

  Future<int> updateUser(
    int id,
    Map<String, dynamic> values, {
    bool recordAudit = true,
    DatabaseExecutor? executor,
    bool skipPhonePolicyValidation = false,
    String? auditOriginSuffix,
  }) async {
    final e = executor ?? db;
    final map = Map<String, dynamic>.from(values);
    map.remove('id');
    final phonesRaw = map.remove('phones');
    map.remove('phone');
    final oldRow = await _support.userRowById(e, id);
    final beforePhoneIds = await _support.userPhoneIds(e, id);
    final oldPhoneList = await _userPhoneNumbersOrdered(e, id);
    final oldEq = await _linkedEquipmentSnapshotsForUser(e, id);
    if (phonesRaw != null) {
      final phones = phonesRaw is List
          ? phonesRaw
                .map((e) => e.toString().trim())
                .where((s) => s.isNotEmpty)
                .toList()
          : <String>[];
      final targetDepartmentId =
          map['department_id'] as int? ?? oldRow?['department_id'] as int?;
      if (!skipPhonePolicyValidation) {
        await _validateUserPhoneAssignmentPolicy(
          phones: phones,
          targetDepartmentId: targetDepartmentId,
          excludeUserId: id,
        );
      }
    }
    if (executor != null) {
      return _updateUserInTxn(
        executor,
        id,
        map,
        phonesRaw,
        oldRow: oldRow,
        beforePhoneIds: beforePhoneIds,
        oldPhoneList: oldPhoneList,
        oldEq: oldEq,
        recordAudit: recordAudit,
        auditOriginSuffix: auditOriginSuffix,
      );
    }
    return db.transaction(
      (txn) => _updateUserInTxn(
        txn,
        id,
        map,
        phonesRaw,
        oldRow: oldRow,
        beforePhoneIds: beforePhoneIds,
        oldPhoneList: oldPhoneList,
        oldEq: oldEq,
        recordAudit: recordAudit,
        auditOriginSuffix: auditOriginSuffix,
      ),
    );
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

    if (phoneBulk != null) {
      final list = PhoneListParser.splitPhones(phoneBulk);
      for (final id in ids) {
        final userRows = await db.query(
          'users',
          columns: ['department_id'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        final deptId =
            map['department_id'] as int? ??
            (userRows.isEmpty ? null : userRows.first['department_id'] as int?);
        await _validateUserPhoneAssignmentPolicy(
          phones: list,
          targetDepartmentId: deptId,
          excludeUserId: id,
        );
      }
    }

    await db.transaction((txn) async {
      if (map.isNotEmpty) {
        for (final id in ids) {
          await txn.update('users', map, where: 'id = ?', whereArgs: [id]);
        }
      }
      if (phoneBulk != null) {
        final list = PhoneListParser.splitPhones(phoneBulk);
        for (final id in ids) {
          await _support.replaceUserPhonesInTxn(txn, id, list);
        }
      }
      final user = await _support.auditPerformingUser(executor: txn);
      final fields = Map<String, dynamic>.from(map);
      if (phoneBulk != null) {
        fields['phone'] = phoneBulk;
      }
      if (fields.containsKey('department_id')) {
        await _support.applyDepartmentAuditText(txn, fields);
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

  /// Τηλέφωνα που μένουν χωρίς κάτοχο όταν διαγραφούν οι [userIds].
  ///
  /// Το κριτήριο είναι «δεν μένει κανένας ενεργός κάτοχος **εκτός** των
  /// διαγραφόμενων» — όχι «ανήκει σε ακριβώς έναν χρήστη». Η παλιά διατύπωση
  /// άφηνε ορφανό κάθε τηλέφωνο που το μοιράζονταν δύο υπάλληλοι οι οποίοι
  /// διαγράφονταν μαζί: ο καθένας «κάλυπτε» τον άλλον ως δήθεν εναπομείναντα
  /// κάτοχο. Ίδιο κριτήριο με το [findExclusiveEquipmentForUserDelete].
  ///
  /// Όταν το τηλέφωνο το μοιράζονται πολλοί διαγραφόμενοι, επιστρέφεται μία
  /// φορά, χρεωμένο στον πρώτο (μικρότερο `user_id`) — μία ερώτηση, όχι Ν.
  Future<List<ExclusivePhoneForUserDelete>> findExclusivePhonesForUserDelete(
    List<int> userIds,
  ) async {
    if (userIds.isEmpty) return const [];
    final placeholders = _support.sqlPlaceholders(userIds.length);
    final rows = await db.rawQuery(
      '''
      SELECT up.user_id AS user_id,
             up.phone_id AS phone_id,
             p.number AS number,
             u.department_id AS department_id,
             d.name AS department_name
      FROM user_phones up
      JOIN phones p ON p.id = up.phone_id
      JOIN users u ON u.id = up.user_id
      LEFT JOIN departments d ON d.id = u.department_id
      WHERE up.user_id IN ($placeholders)
        AND NOT EXISTS (
          SELECT 1
          FROM user_phones up2
          JOIN users u2 ON u2.id = up2.user_id
          WHERE up2.phone_id = up.phone_id
            AND up2.user_id NOT IN ($placeholders)
            AND COALESCE(u2.is_deleted, 0) = 0
        )
      ORDER BY p.number COLLATE NOCASE ASC, up.user_id ASC
      ''',
      [...userIds, ...userIds],
    );

    final seenPhoneIds = <int>{};
    final out = <ExclusivePhoneForUserDelete>[];
    for (final r in rows) {
      final phoneId = r['phone_id'] as int;
      if (!seenPhoneIds.add(phoneId)) continue;
      final number = (r['number'] as String?)?.trim() ?? '';
      if (number.isEmpty) continue;
      out.add(
        ExclusivePhoneForUserDelete(
          phoneId: phoneId,
          number: number,
          userId: r['user_id'] as int,
          departmentId: r['department_id'] as int?,
          departmentName: (r['department_name'] as String?)?.trim(),
        ),
      );
    }
    return out;
  }

  /// Εξοπλισμός σε κίνδυνο ορφανοποίησης τμήματος κατά τη διαγραφή χρηστών.
  ///
  /// Μόνο όταν `equipment.department_id IS NULL` και δεν υπάρχει άλλος ενεργός
  /// κάτοχος εκτός των [userIds]. Αν υπάρχουν πολλοί κάτοχοι μέσα στους
  /// διαγραφόμενους, κρατάται ο πρώτος (μικρότερο `user_id`).
  Future<List<ExclusiveEquipmentForUserDelete>>
  findExclusiveEquipmentForUserDelete(List<int> userIds) async {
    if (userIds.isEmpty) return const [];
    final placeholders = _support.sqlPlaceholders(userIds.length);
    final rows = await db.rawQuery(
      '''
      SELECT ue.user_id AS user_id,
             ue.equipment_id AS equipment_id,
             e.code_equipment AS code_equipment,
             u.department_id AS department_id,
             d.name AS department_name
      FROM user_equipment ue
      JOIN equipment e ON e.id = ue.equipment_id
      JOIN users u ON u.id = ue.user_id
      LEFT JOIN departments d ON d.id = u.department_id
      WHERE ue.user_id IN ($placeholders)
        AND COALESCE(e.is_deleted, 0) = 0
        AND e.department_id IS NULL
        AND NOT EXISTS (
          SELECT 1
          FROM user_equipment ue2
          JOIN users u2 ON u2.id = ue2.user_id
          WHERE ue2.equipment_id = ue.equipment_id
            AND ue2.user_id NOT IN ($placeholders)
            AND COALESCE(u2.is_deleted, 0) = 0
        )
      ORDER BY e.code_equipment COLLATE NOCASE ASC, ue.user_id ASC
      ''',
      [...userIds, ...userIds],
    );

    final seenEquipmentIds = <int>{};
    final out = <ExclusiveEquipmentForUserDelete>[];
    for (final r in rows) {
      final equipmentId = r['equipment_id'] as int;
      if (!seenEquipmentIds.add(equipmentId)) continue;
      final code = (r['code_equipment'] as String?)?.trim() ?? '';
      if (code.isEmpty) continue;
      out.add(
        ExclusiveEquipmentForUserDelete(
          equipmentId: equipmentId,
          codeEquipment: code,
          userId: r['user_id'] as int,
          departmentId: r['department_id'] as int?,
          departmentName: (r['department_name'] as String?)?.trim(),
        ),
      );
    }
    return out;
  }

  Future<void> _unlinkUserFromPhoneInTxn(
    DatabaseExecutor txn,
    int userId,
    int phoneId,
  ) async {
    await txn.delete(
      'user_phones',
      where: 'user_id = ? AND phone_id = ?',
      whereArgs: [userId, phoneId],
    );
  }

  /// Soft-delete υπαλλήλων με πλήρες audit συνδέσεων.
  ///
  /// Με [executor] (εξωτερικό transaction) γράφει εκεί, ώστε διαγραφή και
  /// συνοδευτικές διαθέσεις τηλεφώνων/εξοπλισμού να είναι ΜΙΑ συναλλαγή.
  Future<void> deleteUsers(List<int> ids, {DatabaseExecutor? executor}) async {
    if (ids.isEmpty) return;
    if (executor != null) {
      await _deleteUsersOn(executor, ids);
      return;
    }
    await db.transaction((txn) => _deleteUsersOn(txn, ids));
  }

  Future<void> _deleteUsersOn(DatabaseExecutor txn, List<int> ids) async {
    final user = await _support.auditPerformingUser(executor: txn);
    final phoneIdsByUser = <int, Set<int>>{};
    final equipmentIdsByUser = <int, Set<int>>{};
    for (final uid in ids) {
      phoneIdsByUser[uid] = await _support.userPhoneIds(txn, uid);
      equipmentIdsByUser[uid] = await _equipmentIdsForUser(txn, uid);
    }

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
      final linkedPhoneIds = phoneIdsByUser[id] ?? {};
      final beforePhoneIds = await _support.userPhoneIds(txn, id);

      for (final phoneId in linkedPhoneIds) {
        await _unlinkUserFromPhoneInTxn(txn, id, phoneId);
      }

      final afterPhoneIds = await _support.userPhoneIds(txn, id);
      final linkedEquipmentIds = equipmentIdsByUser[id] ?? {};
      if (linkedEquipmentIds.isNotEmpty) {
        await txn.delete(
          'user_equipment',
          where: 'user_id = ?',
          whereArgs: [id],
        );
      }

      final linkDetails = <String>[
        ...await _support.auditPhoneUserLinkDeltaInTxn(
          txn,
          user,
          id,
          beforePhoneIds,
          afterPhoneIds,
        ),
        ...await _support.auditEquipmentUserLinkDeltaInTxn(
          txn,
          user,
          id,
          linkedEquipmentIds,
          const {},
        ),
      ];

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
        details: DirectorySupport.mergeAuditDetailLines(
          'users id=$id',
          linkDetails,
        ),
        entityType: AuditEntityTypes.user,
        entityId: id,
        entityName: displayName.isEmpty ? null : displayName,
      );
    }
  }

  /// Διαγράφει (soft) υπαλλήλους ΜΕΣΑ σε δοσμένο [txn] και επιστρέφει, ανά
  /// υπάλληλο, τα πρωτότυπα τηλέφωνα (αριθμοί) και equipment ids ώστε να μπορεί
  /// να αναιρεθεί πλήρως η σύνδεσή τους αργότερα.
  Future<Map<int, ({List<String> phoneNumbers, List<int> equipmentIds})>>
  deleteUsersInTxn(DatabaseExecutor txn, List<int> ids) async {
    final result =
        <int, ({List<String> phoneNumbers, List<int> equipmentIds})>{};
    if (ids.isEmpty) return result;
    final user = await _support.auditPerformingUser(executor: txn);
    for (final id in ids) {
      final phoneRows = await txn.rawQuery(
        'SELECT p.number AS number FROM user_phones up '
        'JOIN phones p ON p.id = up.phone_id WHERE up.user_id = ?',
        [id],
      );
      final phoneNumbers = phoneRows
          .map((r) => (r['number'] as String?)?.trim() ?? '')
          .where((n) => n.isNotEmpty)
          .toList();
      final equipmentIds = (await _equipmentIdsForUser(txn, id)).toList();
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

      await txn.delete('user_phones', where: 'user_id = ?', whereArgs: [id]);
      await txn.delete('user_equipment', where: 'user_id = ?', whereArgs: [id]);
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
      result[id] = (phoneNumbers: phoneNumbers, equipmentIds: equipmentIds);
    }
    return result;
  }

  Future<void> restoreUsers(List<int> ids, {DatabaseExecutor? executor}) async {
    if (ids.isEmpty) return;

    Future<void> run(DatabaseExecutor txn) async {
      final user = await _support.auditPerformingUser(executor: txn);
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
    }

    if (executor != null) return run(executor);
    return db.transaction(run);
  }

  Future<int> insertUser({
    required String firstName,
    required String lastName,
    List<String>? phones,
    String? department,
    String? location,
    String? notes,
    int? departmentId,
    DatabaseExecutor? executor,
    bool skipPhonePolicyValidation = false,
    String? auditOriginSuffix,
  }) async {
    var resolvedDeptId = departmentId;
    if (resolvedDeptId == null &&
        department != null &&
        department.trim().isNotEmpty) {
      resolvedDeptId = await _departments.getOrCreateDepartmentIdByName(
        department,
        executor: executor,
        auditOriginSuffix: auditOriginSuffix,
      );
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
    return insertUserFromMap(
      map,
      executor: executor,
      skipPhonePolicyValidation: skipPhonePolicyValidation,
      auditOriginSuffix: auditOriginSuffix,
    );
  }

  Future<void> updateAssociationsIfNeeded(
    int? userId,
    String? phone,
    String? equipmentCode, {
    DatabaseExecutor? executor,
    String? auditOriginSuffix,
  }) async {
    if (userId == null) return;
    Future<void> run(DatabaseExecutor txn) async {
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
          // Δίχτυ ασφαλείας: μην γράφεις σύνδεση που παραβιάζει την πολιτική.
          final userRows = await txn.query(
            'users',
            columns: ['department_id'],
            where: 'id = ?',
            whereArgs: [userId],
            limit: 1,
          );
          final targetDepartmentId = userRows.isEmpty
              ? null
              : userRows.first['department_id'] as int?;
          final conflicts =
              PhoneDepartmentPolicy.findConflictsForUserAssignment(
                phones: [trimmedPhone],
                targetDepartmentId: targetDepartmentId,
                editingUserId: userId,
              );
          if (conflicts.isEmpty) {
            await _support.replaceUserPhonesInTxn(txn, userId, [
              ...existing,
              trimmedPhone,
            ]);
            phoneChanged = true;
          }
        }
      }

      if (equipmentCode != null && equipmentCode.trim().isNotEmpty) {
        final code = equipmentCode.trim();
        final existingEq = await txn.query(
          'equipment',
          columns: ['id'],
          where: 'code_equipment = ? AND ${DirectorySupport.notDeletedClause}',
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
          await txn.insert('user_equipment', {
            'user_id': userId,
            'equipment_id': equipmentId,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
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

      final uRow = await _support.userRowById(txn, userId);
      final userLabel = _support.userDisplayNameFromRow(uRow);
      final deptName = await _departmentNameForUserTxn(txn, userId);
      final eqTrim = equipmentCode?.trim() ?? '';
      final association = buildAuditCallAssociationEntry(
        userPart: userLabel.isEmpty ? null : userLabel,
        departmentPart: deptName,
        phonePart: phoneChanged ? trimmedPhone : null,
        equipmentPart: equipmentLinked && eqTrim.isNotEmpty ? eqTrim : null,
      );
      final auditDetails = DirectorySupport.appendAuditOriginSuffix(
        mergeAuditCallAssociationDetails(
          associationDetails: association.detailsLine,
          existingDetails: 'updateAssociationsIfNeeded userId=$userId',
        ),
        auditOriginSuffix,
      );

      final ap = await _support.auditPerformingUser(executor: txn);
      final nv = <String, dynamic>{};
      if (phoneChanged) nv['phone_associated'] = trimmedPhone;
      if (equipmentLinked && equipmentIdForAudit != null) {
        nv['equipment_id'] = equipmentIdForAudit;
        nv['equipment_code'] = eqTrim;
      }

      await AuditService.log(
        txn,
        action: association.action,
        userPerforming: ap,
        details: auditDetails.isEmpty ? null : auditDetails,
        entityType: AuditEntityTypes.user,
        entityId: userId,
        entityName: userLabel.isEmpty ? null : userLabel,
        newValues: nv.isEmpty ? null : nv,
      );
    }

    if (executor != null) {
      await run(executor);
      return;
    }
    await db.transaction(run);
  }

  Future<Map<String, dynamic>?> getUserPreviewJoinRow(int id) async {
    final rows = await db.rawQuery(
      '''
      SELECT u.first_name, u.last_name, d.name AS dept
      FROM users u
      LEFT JOIN departments d ON u.department_id = d.id
      WHERE u.id = ?
      LIMIT 1
      ''',
      [id],
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }
}
