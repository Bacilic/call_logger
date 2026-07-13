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

  static bool auditValuesEqual(dynamic a, dynamic b) =>
      AuditService.valuesEqual(a, b);

  /// Ενώνει βασικές λεπτομέρειες audit με ονομαστικές γραμμές συνδέσεων.
  static String mergeAuditDetailLines(String base, List<String> extras) {
    final parts = <String>[base, ...extras]
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    return parts.join(' · ');
  }

  // ---------------------------------------------------------------------------
  // Φάση 3 — προέλευση παράγωγων εγγραφών audit (χωρίς αλλαγή σχήματος audit_log)
  //
  // Χάρτης αλυσίδας κατά υποβολή κλήσης (ενιαία συναλλαγή, call_id πρώτα):
  //   1. insertCallOnExecutor → ΔΗΜΙΟΥΡΓΙΑ ΚΛΗΣΗΣ (κύρια · χωρίς προέλευση)
  //   2. getOrCreateDepartmentIdByName → ΔΗΜΙΟΥΡΓΙΑ ΤΜΗΜΑΤΟΣ (παράγωγη)
  //   3. insertUser → ΔΗΜΙΟΥΡΓΙΑ ΧΡΗΣΤΗ + σύνδεση τηλεφώνων (παράγωγη)
  //   4. updateAssociationsIfNeeded → συσχέτιση εξοπλισμού/τηλεφώνου (παράγωγη)
  //   5. addDepartmentDirectPhoneInTxn → ΤΡΟΠΟΠΟΙΗΣΗ ΤΗΛΕΦΩΝΟΥ (παράγωγη, αν χρειάζεται)
  //   6. createFromCallOnExecutor → ΔΗΜΙΟΥΡΓΙΑ ΕΚΚΡΕΜΟΤΗΤΑΣ (κύρια · χωρίς προέλευση)
  //
  // Ροή UI (associate πριν submit): τα βήματα 2–4 μπορεί να τρέξουν ΠΡΙΝ το id κλήσης·
  // τότε καταγράφονται χωρίς suffix και ενημερώνονται στο τέλος της ίδιας συναλλαγής
  // μέσω [PendingAuditOriginRows.applyOriginSuffix].
  // ---------------------------------------------------------------------------

  static String auditOriginSuffixFromCall(int callId) =>
      ' — από κλήση #$callId';

  static String auditOriginSuffixFromTask(int taskId) =>
      ' — από εκκρεμότητα #$taskId';

  static final RegExp _auditOriginSuffixPattern = RegExp(
    r' — από (κλήση|εκκρεμότητα) #(\d+)$',
  );

  /// Προσθέτει ενιαίο suffix προέλευσης στο τέλος των `details` (idempotent).
  static String appendAuditOriginSuffix(String? base, String? suffix) {
    if (suffix == null || suffix.trim().isEmpty) {
      return base?.trim() ?? '';
    }
    // ΜΗΝ κάνουμε trim στο suffix — το « — » πρέπει να διατηρηθεί.
    final s = suffix.startsWith(' — ')
        ? suffix
        : ' — ${suffix.trim()}';
    final b = base?.trim() ?? '';
    if (b.isEmpty) return s;
    if (b.endsWith(s) || b.contains(s)) return b;
    return '$b$s';
  }

  /// Αφαιρεί το suffix προέλευσης από `details` (εμφάνιση UI).
  static String stripAuditOriginSuffix(String? details) {
    final t = details?.trim() ?? '';
    if (t.isEmpty) return t;
    return t.replaceFirst(_auditOriginSuffixPattern, '').trim();
  }

  /// Γραμμή «Προέλευση: Κλήση #N» / «Προέλευση: Εκκρεμότητα #N» για UI.
  static String? auditOriginDisplayLine(String? details) {
    final m = _auditOriginSuffixPattern.firstMatch(details?.trim() ?? '');
    if (m == null) return null;
    final kind = m.group(1)!;
    final id = m.group(2)!;
    if (kind == 'κλήση') return 'Προέλευση: Κλήση #$id';
    return 'Προέλευση: Εκκρεμότητα #$id';
  }

  /// Καταγραφή audit + επιστροφή id (για deferred stamping στην ίδια συναλλαγή).
  static Future<int?> auditLogReturnId(
    DatabaseExecutor executor, {
    required String action,
    required String userPerforming,
    String? details,
    String? entityType,
    int? entityId,
    String? entityName,
    Map<String, dynamic>? oldValues,
    Map<String, dynamic>? newValues,
    String? auditOriginSuffix,
  }) async {
    final mergedDetails = appendAuditOriginSuffix(details, auditOriginSuffix);
    await AuditService.log(
      executor,
      action: action,
      userPerforming: userPerforming,
      details: mergedDetails.isEmpty ? null : mergedDetails,
      entityType: entityType,
      entityId: entityId,
      entityName: entityName,
      oldValues: oldValues,
      newValues: newValues,
    );
    final rows = await executor.rawQuery('SELECT last_insert_rowid() AS id');
    if (rows.isEmpty) return null;
    final raw = rows.first['id'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse('$raw');
  }

  Future<List<String>> describeUserEntityLinkDeltaInTxn(
    DatabaseExecutor txn, {
    required int userId,
    required Set<int> beforeIds,
    required Set<int> afterIds,
    required String table,
    required String labelColumn,
    required String entityType,
  }) async {
    final removed = beforeIds.difference(afterIds);
    final added = afterIds.difference(beforeIds);
    if (removed.isEmpty && added.isEmpty) return const [];
    final ids = removed.union(added);
    final labels = switch ((table, labelColumn)) {
      ('phones', 'number') => await phoneNumbersByIds(txn, ids),
      ('equipment', 'code_equipment') => await equipmentCodesByIds(txn, ids),
      _ => await idLabelMap(txn, table, labelColumn, ids),
    };
    final lines = <String>[];
    for (final id in removed) {
      final label = labels[id] ?? '#$id';
      lines.add(_userEntityLinkDetailLine(entityType, label, linked: false));
    }
    for (final id in added) {
      final label = labels[id] ?? '#$id';
      lines.add(_userEntityLinkDetailLine(entityType, label, linked: true));
    }
    return lines;
  }

  static String _userEntityLinkDetailLine(
    String entityType,
    String label, {
    required bool linked,
  }) {
    switch (entityType) {
      case AuditEntityTypes.phone:
        return linked
            ? 'Προσθήκη τηλεφώνου $label'
            : 'Αποσύνδεση τηλεφώνου $label';
      case AuditEntityTypes.equipment:
        return linked
            ? 'Προσθήκη εξοπλισμού $label'
            : 'Αποσύνδεση εξοπλισμού $label';
      default:
        return linked
            ? 'Προσθήκη $entityType $label'
            : 'Αποσύνδεση $entityType $label';
    }
  }

  Future<List<String>> auditPhoneUserLinkDeltaInTxn(
    DatabaseExecutor txn,
    String userPerforming,
    int userId,
    Set<int> beforeIds,
    Set<int> afterIds,
  ) =>
      describeUserEntityLinkDeltaInTxn(
        txn,
        userId: userId,
        beforeIds: beforeIds,
        afterIds: afterIds,
        table: 'phones',
        labelColumn: 'number',
        entityType: AuditEntityTypes.phone,
      );

  Future<List<String>> auditEquipmentUserLinkDeltaInTxn(
    DatabaseExecutor txn,
    String userPerforming,
    int userId,
    Set<int> beforeIds,
    Set<int> afterIds,
  ) =>
      describeUserEntityLinkDeltaInTxn(
        txn,
        userId: userId,
        beforeIds: beforeIds,
        afterIds: afterIds,
        table: 'equipment',
        labelColumn: 'code_equipment',
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
    String phoneNumber, {
    String? auditOriginSuffix,
  }) async {
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
      action: AuditActions.modifyPhone,
      userPerforming: ap,
      details: appendAuditOriginSuffix(
        'phones id=$pid (τμήμα $departmentId)',
        auditOriginSuffix,
      ),
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
        action: AuditActions.modifyPhone,
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

/// Συλλέκτης id audit που γράφτηκαν πριν υπάρξει id κλήσης/εκκρεμότητας.
class PendingAuditOriginRows {
  final Set<int> _ids = {};

  void track(int? auditLogId) {
    if (auditLogId != null) _ids.add(auditLogId);
  }

  bool get isEmpty => _ids.isEmpty;

  void clear() => _ids.clear();

  Future<void> applyOriginSuffix(
    DatabaseExecutor txn,
    String originSuffix,
  ) async {
    if (_ids.isEmpty) return;
    for (final auditId in _ids) {
      final rows = await txn.query(
        'audit_log',
        columns: ['details'],
        where: 'id = ?',
        whereArgs: [auditId],
        limit: 1,
      );
      if (rows.isEmpty) continue;
      final updated = DirectorySupport.appendAuditOriginSuffix(
        rows.first['details'] as String?,
        originSuffix,
      );
      await txn.update(
        'audit_log',
        {'details': updated.isEmpty ? null : updated},
        where: 'id = ?',
        whereArgs: [auditId],
      );
      await AuditService.rebuildAndPersistSearchText(txn, auditId);
    }
    _ids.clear();
  }
}
