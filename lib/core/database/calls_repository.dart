import 'dart:async';

import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../features/calls/models/call_model.dart';
import '../services/audit_service.dart';
import '../utils/search_text_normalizer.dart';

/// Πρόσβαση σε πίνακα `calls` και επαναδόμηση `search_index`.
///
/// Δεν εξαρτάται από [DirectoryRepository] / [DictionaryRepository].
class CallsRepository {
  CallsRepository(this.db);

  final Database db;

  static const List<String> _kCallAuditFields = [
    'date',
    'time',
    'caller_id',
    'equipment_id',
    'caller_text',
    'phone_text',
    'department_text',
    'equipment_text',
    'issue',
    'solution',
    'category_text',
    'category_id',
    'status',
    'duration',
    'is_priority',
    'is_deleted',
  ];

  /// Συγκεντρώνει κείμενα κλήσης + συσχετισμένου χρήστη/εξοπλισμού για `search_index` (σχήμα v1).
  Future<String> _buildCallSearchIndex(
    DatabaseExecutor executor,
    Map<String, dynamic> callMap,
  ) async {
    void addNonEmpty(List<String> parts, dynamic v) {
      if (v == null) return;
      final s = v.toString().trim();
      if (s.isNotEmpty) parts.add(s);
    }

    final parts = <String>[];

    addNonEmpty(parts, callMap['issue']);
    addNonEmpty(parts, callMap['solution']);
    addNonEmpty(parts, callMap['category_text']);
    addNonEmpty(parts, callMap['caller_text']);
    addNonEmpty(parts, callMap['phone_text']);
    addNonEmpty(parts, callMap['department_text']);
    addNonEmpty(parts, callMap['equipment_text']);

    final callerId = callMap['caller_id'] as int?;
    if (callerId != null) {
      final userRows = await executor.rawQuery(
        '''
        SELECT u.first_name, u.last_name, d.name AS department_name
        FROM users u
        LEFT JOIN departments d ON u.department_id = d.id
        WHERE u.id = ?
        LIMIT 1
        ''',
        [callerId],
      );
      if (userRows.isNotEmpty) {
        final u = userRows.first;
        addNonEmpty(parts, u['first_name']);
        addNonEmpty(parts, u['last_name']);
        addNonEmpty(parts, u['department_name']);
      }
      final phoneRows = await executor.rawQuery(
        '''
        SELECT p.number FROM user_phones up
        JOIN phones p ON p.id = up.phone_id
        WHERE up.user_id = ?
        ORDER BY p.number
        ''',
        [callerId],
      );
      for (final pr in phoneRows) {
        addNonEmpty(parts, pr['number']);
      }
    }

    final equipmentId = callMap['equipment_id'] as int?;
    if (equipmentId != null) {
      final eqRows = await executor.query(
        'equipment',
        columns: ['code_equipment'],
        where: 'id = ?',
        whereArgs: [equipmentId],
        limit: 1,
      );
      if (eqRows.isNotEmpty) {
        addNonEmpty(parts, eqRows.first['code_equipment']);
      }
    }

    return SearchTextNormalizer.normalizeForSearch(parts.join(' '));
  }

  /// Επαναδόμηση `search_index` για όλες τις κλήσεις με [categoryId] (ίδιο [DatabaseExecutor] / transaction).
  Future<void> rebuildSearchIndexForCallsByCategoryId(
    DatabaseExecutor executor,
    int categoryId,
  ) async {
    final rows = await executor.query(
      'calls',
      where: 'category_id = ?',
      whereArgs: [categoryId],
    );
    for (final row in rows) {
      final map = Map<String, dynamic>.from(row);
      final si = await _buildCallSearchIndex(executor, map);
      await executor.update(
        'calls',
        {'search_index': si},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }

  /// Εισάγει νέα κλήση. date/time τίθενται από τώρα αν δεν δοθούν.
  Future<int> insertCall(CallModel call) async {
    final now = DateTime.now();
    final map = <String, dynamic>{
      'date': call.date ?? DateFormat('yyyy-MM-dd').format(now),
      'time': call.time ?? DateFormat('HH:mm').format(now),
      'caller_id': call.callerId,
      'equipment_id': call.equipmentId,
      'caller_text': call.callerText,
      'phone_text': call.phoneText,
      'department_text': call.departmentText,
      'equipment_text': call.equipmentText,
      'issue': call.issue,
      'solution': call.solution,
      'category_text': call.category,
      'category_id': call.categoryId,
      'status': call.status ?? 'completed',
      'duration': call.duration,
      'is_priority': call.isPriority ?? 0,
      'is_deleted': 0,
    };
    map['search_index'] = await _buildCallSearchIndex(db, map);
    final id = await db.insert('calls', map);
    try {
      final user = await AuditService.performingUser(db);
      final nv = <String, dynamic>{};
      for (final k in _kCallAuditFields) {
        if (map.containsKey(k) && map[k] != null) {
          nv[k] = map[k];
        }
      }
      final entityName = (await buildCallAuditDisplayLine(id)).trim();
      await AuditService.log(
        db,
        action: 'ΔΗΜΙΟΥΡΓΙΑ ΚΛΗΣΗΣ',
        userPerforming: user,
        details: 'calls id=$id',
        entityType: AuditEntityTypes.call,
        entityId: id,
        entityName: entityName.isEmpty ? null : entityName,
        newValues: nv.isEmpty ? null : nv,
      );
    } catch (_) {}
    return id;
  }

  /// Ενημερώνει υπάρχουσα κλήση. Απαιτείται μη-null [CallModel.id].
  Future<int> updateCall(CallModel call) async {
    final id = call.id;
    if (id == null) {
      throw ArgumentError('CallModel.id is required for updateCall');
    }
    final oldRows = await db.query(
      'calls',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final oldRow = oldRows.isEmpty ? null : Map<String, dynamic>.from(oldRows.first);

    final map = <String, dynamic>{
      'date': call.date,
      'time': call.time,
      'caller_id': call.callerId,
      'equipment_id': call.equipmentId,
      'caller_text': call.callerText,
      'phone_text': call.phoneText,
      'department_text': call.departmentText,
      'equipment_text': call.equipmentText,
      'issue': call.issue,
      'solution': call.solution,
      'category_text': call.category,
      'category_id': call.categoryId,
      'status': call.status,
      'duration': call.duration,
      'is_priority': call.isPriority ?? 0,
      'is_deleted': call.isDeleted ? 1 : 0,
    };
    map['search_index'] = await _buildCallSearchIndex(db, map);
    final n = await db.update('calls', map, where: 'id = ?', whereArgs: [id]);
    if (oldRow != null && n > 0) {
      try {
        final oldDiff = <String, dynamic>{};
        final newDiff = <String, dynamic>{};
        for (final k in _kCallAuditFields) {
          final a = oldRow[k];
          final b = map[k];
          final sa = a?.toString() ?? '';
          final sb = b?.toString() ?? '';
          if (sa != sb) {
            oldDiff[k] = a;
            newDiff[k] = b;
          }
        }
        if (newDiff.isNotEmpty) {
          final user = await AuditService.performingUser(db);
          final entityName = (await buildCallAuditDisplayLine(id)).trim();
          await AuditService.log(
            db,
            action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΚΛΗΣΗΣ',
            userPerforming: user,
            details: 'calls id=$id',
            entityType: AuditEntityTypes.call,
            entityId: id,
            entityName: entityName.isEmpty ? null : entityName,
            oldValues: oldDiff,
            newValues: newDiff,
          );
        }
      } catch (_) {}
    }
    return n;
  }

  /// Επιστρέφει τις τελευταίες κλήσεις για καλούντα (calls.caller_id, κατά id DESC).
  Future<List<Map<String, dynamic>>> getRecentCallsByCallerId(
    int callerId, {
    int limit = 3,
  }) async {
    return db.query(
      'calls',
      where: 'caller_id = ? AND COALESCE(is_deleted, 0) = ?',
      whereArgs: [callerId, 0],
      orderBy: 'id DESC',
      limit: limit,
    );
  }

  /// Ιστορικό κλήσεων με προαιρετικά φίλτρα. LEFT JOIN users και equipment.
  Future<List<Map<String, dynamic>>> getHistoryCalls({
    String? dateFrom,
    String? dateTo,
    String? category,
    String? keyword,
  }) async {
    const userPhoneExpr =
        "COALESCE(NULLIF(TRIM(calls.phone_text), ''), upl.phone_list, '-')";
    final whereClauses = <String>[];
    final args = <dynamic>[];

    if (dateFrom != null && dateFrom.isNotEmpty) {
      whereClauses.add('calls.date >= ?');
      args.add(dateFrom);
    }
    if (dateTo != null && dateTo.isNotEmpty) {
      whereClauses.add('calls.date <= ?');
      args.add(dateTo);
    }
    if (category != null && category.isNotEmpty) {
      whereClauses.add('calls.category_text = ?');
      args.add(category);
    }
    if (keyword != null && keyword.isNotEmpty) {
      whereClauses.add('calls.search_index LIKE ?');
      args.add('%$keyword%');
    }

    whereClauses.insert(0, 'COALESCE(calls.is_deleted, 0) = 0');

    final whereSql = whereClauses.isEmpty
        ? ''
        : 'WHERE ${whereClauses.join(' AND ')}';
    final sql =
        '''
      SELECT calls.id, calls.date, calls.time, calls.caller_id, calls.equipment_id,
             calls.issue, calls.solution, calls.caller_text, calls.phone_text, calls.department_text, calls.equipment_text,
             COALESCE(cat.name, calls.category_text, '') AS category, calls.status, calls.duration, calls.is_priority,
             COALESCE(users.first_name, calls.caller_text, '') AS user_first_name,
             COALESCE(users.last_name, '') AS user_last_name,
             $userPhoneExpr AS user_phone,
             COALESCE(departments.name, calls.department_text, '-') AS user_department,
             COALESCE(equipment.code_equipment, calls.equipment_text, '-') AS equipment_code
      FROM calls
      LEFT JOIN categories cat ON cat.id = calls.category_id
      LEFT JOIN users ON calls.caller_id = users.id
      LEFT JOIN (
        SELECT up.user_id AS uid,
               GROUP_CONCAT(p.number, ', ') AS phone_list
        FROM user_phones up
        JOIN phones p ON p.id = up.phone_id
        GROUP BY up.user_id
      ) upl ON upl.uid = users.id
      LEFT JOIN equipment ON calls.equipment_id = equipment.id
      LEFT JOIN departments ON users.department_id = departments.id
      $whereSql
      ORDER BY calls.date DESC, calls.time DESC
    ''';

    return db.rawQuery(sql, args);
  }

  /// Γραμμή «τηλέφωνο - καλούντας - τμήμα - εξοπλισμός» όπως στο ιστορικό κλήσεων
  /// ([getHistoryCalls]): κενά παραλείπονται, χωρίς placeholder `-`.
  static String formatCallAuditLineFromHistoryQueryRow(
    Map<String, Object?> r,
  ) {
    String nz(dynamic v) {
      final t = v?.toString().trim() ?? '';
      if (t.isEmpty || t == '-') return '';
      return t;
    }

    final phone = nz(r['user_phone']);
    final first = (r['user_first_name'] as String?)?.trim() ?? '';
    final last = (r['user_last_name'] as String?)?.trim() ?? '';
    final caller = '$first $last'.trim();
    final dept = nz(r['user_department']);
    final equip = nz(r['equipment_code']);
    return [phone, caller, dept, equip].where((s) => s.isNotEmpty).join(' - ');
  }

  /// Ίδια JOIN/COALESCE με [getHistoryCalls], για μία εγγραφή (π.χ. audit `entity_name`).
  Future<String> buildCallAuditDisplayLine(int callId) async {
    const userPhoneExpr =
        "COALESCE(NULLIF(TRIM(calls.phone_text), ''), upl.phone_list, '-')";
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(users.first_name, calls.caller_text, '') AS user_first_name,
             COALESCE(users.last_name, '') AS user_last_name,
             $userPhoneExpr AS user_phone,
             COALESCE(departments.name, calls.department_text, '-') AS user_department,
             COALESCE(equipment.code_equipment, calls.equipment_text, '-') AS equipment_code
      FROM calls
      LEFT JOIN users ON calls.caller_id = users.id
      LEFT JOIN (
        SELECT up.user_id AS uid,
               GROUP_CONCAT(p.number, ', ') AS phone_list
        FROM user_phones up
        JOIN phones p ON p.id = up.phone_id
        GROUP BY up.user_id
      ) upl ON upl.uid = users.id
      LEFT JOIN equipment ON calls.equipment_id = equipment.id
      LEFT JOIN departments ON users.department_id = departments.id
      WHERE calls.id = ?
      LIMIT 1
      ''',
      [callId],
    );
    if (rows.isEmpty) return '';
    return formatCallAuditLineFromHistoryQueryRow(rows.first);
  }
}
