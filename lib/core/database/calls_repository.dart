import 'dart:async';
import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../features/calls/models/call_model.dart';
import '../../features/history/models/dashboard_filter_model.dart';
import '../../features/history/models/dashboard_summary_model.dart';
import 'database_helper.dart';
import '../errors/call_save_exception.dart';
import 'audit_service.dart';
import 'directory_support.dart';
import '../utils/history_entity_display_utils.dart';
import '../utils/search_text_normalizer.dart';

part 'calls_repository_search_index.dart';
part 'calls_repository_deletion.dart';
part 'calls_repository_dashboard.dart';
part 'calls_repository_lansweeper.dart';

/// Κοινά μέλη [CallsRepository] προσβάσιμα από θεματικά mixins (χωρίς κυκλική εξάρτηση).
abstract mixin class CallsRepositoryCore {
  Database get db;

  Future<String> buildCallAuditDisplayLine(
    int callId, {
    DatabaseExecutor? executor,
  });
}

/// Πρόσβαση σε πίνακα `calls` και επαναδόμηση `search_index`.
///
/// Δεν εξαρτάται από repositories καταλόγου ούτε από [DictionaryRepository].
class CallsRepository
    with
        CallsRepositoryCore,
        CallsRepositorySearchIndexMixin,
        CallsRepositoryDeletionMixin,
        CallsRepositoryDashboardMixin,
        CallsRepositoryLansweeperMixin {
  CallsRepository(this.db);

  @override
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
    'category_text',
    'category_id',
    'status',
    'duration',
    'is_priority',
    'lansweeper_state',
    'lansweeper_main_ticket_id',
    'lansweeper_last_sync_at',
    'is_deleted',
  ];
  /// Ενημέρωση ενός FK πεδίου κλήσης (integrity fix — χωρίς audit, το κάνει ο caller).
  Future<Map<String, dynamic>?> integrityUpdateCallFk(
    DatabaseExecutor executor,
    int callId,
    String field,
    int? newValue,
  ) async {
    const allowed = {'caller_id', 'equipment_id', 'category_id'};
    if (!allowed.contains(field)) {
      throw ArgumentError('Άκυρο πεδίο κλήσης: $field');
    }
    final rows = await executor.query(
      'calls',
      where: 'id = ?',
      whereArgs: [callId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final oldRow = Map<String, dynamic>.from(rows.first);
    await executor.update(
      'calls',
      {field: newValue},
      where: 'id = ?',
      whereArgs: [callId],
    );
    return oldRow;
  }

  Map<String, dynamic> _callInsertMap(CallModel call) {
    final now = DateTime.now();
    return <String, dynamic>{
      'date': call.date ?? DateFormat('yyyy-MM-dd').format(now),
      'time': call.time ?? DateFormat('HH:mm').format(now),
      'caller_id': call.callerId,
      'equipment_id': call.equipmentId,
      'caller_text': call.callerText,
      'phone_text': call.phoneText,
      'department_text': call.departmentText,
      'equipment_text': call.equipmentText,
      'issue': call.issue,
      'category_text': call.category,
      'category_id': call.categoryId,
      'status': call.status ?? 'completed',
      'duration': call.duration,
      'is_priority': call.isPriority ?? 0,
      'lansweeper_state': call.lansweeperState ?? 'unsent',
      'lansweeper_main_ticket_id': call.lansweeperMainTicketId,
      'lansweeper_last_sync_at': call.lansweeperLastSyncAt,
      'is_deleted': 0,
    };
  }

  /// Εισαγωγή κλήσης σε υπάρχον [DatabaseExecutor] (π.χ. κοινό transaction με task).
  ///
  /// Αν δοθεί [afterCallInserted], εκτελείται μετά την κύρια εγγραφή ΔΗΜΙΟΥΡΓΙΑ ΚΛΗΣΗΣ
  /// και περνά suffix προέλευσης για παράγωγες εγγραφές καταλόγου (Φάση 3).
  /// Βλ. [DirectorySupport] — χάρτης αλυσίδας audit.
  Future<int> insertCallOnExecutor(
    DatabaseExecutor executor,
    CallModel call, {
    Future<void> Function(DatabaseExecutor txn, String auditOriginSuffix)?
        afterCallInserted,
  }) async {
    final map = _callInsertMap(call);
    map['search_index'] = await _buildCallSearchIndex(executor, map);
    final id = await executor.insert('calls', map);
    final user = await AuditService.performingUser(executor);
    final nv = <String, dynamic>{};
    for (final k in _kCallAuditFields) {
      if (map.containsKey(k) && map[k] != null) {
        nv[k] = map[k];
      }
    }
    final entityName = (await buildCallAuditDisplayLine(
      id,
      executor: executor,
    )).trim();
    await AuditService.log(
      executor,
      action: 'ΔΗΜΙΟΥΡΓΙΑ ΚΛΗΣΗΣ',
      userPerforming: user,
      details: 'calls id=$id',
      entityType: AuditEntityTypes.call,
      entityId: id,
      entityName: entityName.isEmpty ? null : entityName,
      newValues: nv.isEmpty ? null : nv,
    );
    if (afterCallInserted != null) {
      await afterCallInserted(
        executor,
        DirectorySupport.auditOriginSuffixFromCall(id),
      );
    }
    return id;
  }

  /// Εισάγει νέα κλήση. date/time τίθενται από τώρα αν δεν δοθούν.
  ///
  /// Κλήση + audit στο ίδιο transaction· σε αποτυχία rollback ([CallSaveException]).
  Future<int> insertCall(CallModel call) async {
    try {
      return await db.transaction(
        (txn) => insertCallOnExecutor(txn, call),
      );
    } catch (e) {
      if (e is CallSaveException) rethrow;
      throw CallSaveException('Η κλήση δεν αποθηκεύτηκε. Δοκιμάστε ξανά.');
    }
  }

  /// Ενημερώνει υπάρχουσα κλήση. Απαιτείται μη-null [CallModel.id].
  ///
  /// Κλήση + audit στο ίδιο transaction· σε αποτυχία rollback ([CallSaveException]).
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
    final oldRow = oldRows.isEmpty
        ? null
        : Map<String, dynamic>.from(oldRows.first);

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
      'category_text': call.category,
      'category_id': call.categoryId,
      'status': call.status,
      'duration': call.duration,
      'is_priority': call.isPriority ?? 0,
      'lansweeper_state': call.lansweeperState,
      'lansweeper_main_ticket_id': call.lansweeperMainTicketId,
      'lansweeper_last_sync_at': call.lansweeperLastSyncAt,
      'is_deleted': call.isDeleted ? 1 : 0,
    };
    try {
      return await db.transaction((txn) async {
        map['search_index'] = await _buildCallSearchIndex(txn, map);
        final n = await txn.update(
          'calls',
          map,
          where: 'id = ?',
          whereArgs: [id],
        );
        if (oldRow != null && n > 0) {
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
            final user = await AuditService.performingUser(txn);
            final entityName = (await buildCallAuditDisplayLine(
              id,
              executor: txn,
            )).trim();
            await AuditService.log(
              txn,
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
        }
        return n;
      });
    } catch (e) {
      if (e is CallSaveException) rethrow;
      throw CallSaveException('Η κλήση δεν ενημερώθηκε. Δοκιμάστε ξανά.');
    }
  }
  Future<int> cloneCall(int sourceCallId) async {
    final source = await getCallById(sourceCallId);
    if (source == null) {
      throw StateError('Call not found: id=$sourceCallId');
    }
    final now = DateTime.now();
    final user = await AuditService.performingUser(db);
    final map = <String, dynamic>{
      'date': DateFormat('yyyy-MM-dd').format(now),
      'time': DateFormat('HH:mm').format(now),
      'caller_id': source.callerId,
      'equipment_id': source.equipmentId,
      'caller_text': source.callerText,
      'phone_text': source.phoneText,
      'department_text': source.departmentText,
      'equipment_text': source.equipmentText,
      'issue': source.issue,
      'category_text': source.category,
      'category_id': source.categoryId,
      'status': source.status ?? 'completed',
      'duration': source.duration,
      'is_priority': source.isPriority ?? 0,
      'lansweeper_state': 'unsent',
      'lansweeper_main_ticket_id': null,
      'lansweeper_last_sync_at': null,
      'is_deleted': 0,
    };

    try {
      return await db.transaction((txn) async {
        map['search_index'] = await _buildCallSearchIndex(txn, map);
        final id = await txn.insert('calls', map);
        final nv = <String, dynamic>{};
        for (final k in _kCallAuditFields) {
          if (map.containsKey(k) && map[k] != null) {
            nv[k] = map[k];
          }
        }
        final entityName = (await buildCallAuditDisplayLine(
          id,
          executor: txn,
        )).trim();
        await AuditService.log(
          txn,
          action: 'ΔΗΜΙΟΥΡΓΙΑ ΚΛΗΣΗΣ',
          userPerforming: user,
          details: 'calls id=$id',
          entityType: AuditEntityTypes.call,
          entityId: id,
          entityName: entityName.isEmpty ? null : entityName,
          newValues: nv.isEmpty ? null : nv,
        );
        return id;
      });
    } catch (e) {
      if (e is CallSaveException) rethrow;
      throw CallSaveException('Η κλήση δεν κλωνοποιήθηκε. Δοκιμάστε ξανά.');
    }
  }

  /// Επιστρέφει τις τελευταίες κλήσεις για καλούντα (calls.caller_id, κατά id DESC).
  Future<List<Map<String, dynamic>>> getRecentCallsByCallerId(
    int callerId, {
    int limit = 3,
  }) async {
    return db.rawQuery(
      '''
      SELECT calls.*,
        COALESCE(users.is_deleted, 0) AS caller_is_deleted,
        COALESCE(equipment.is_deleted, 0) AS equipment_is_deleted
      FROM calls
      LEFT JOIN users ON users.id = calls.caller_id
      LEFT JOIN equipment ON equipment.id = calls.equipment_id
      WHERE calls.caller_id = ? AND COALESCE(calls.is_deleted, 0) = 0
      ORDER BY calls.id DESC
      LIMIT ?
      ''',
      [callerId, limit],
    );
  }

  /// Επιστρέφει τις τελευταίες κλήσεις συνολικά (κατά id DESC).
  Future<List<Map<String, dynamic>>> getRecentCalls({int limit = 7}) async {
    return db.rawQuery(
      '''
      SELECT
        calls.*,
        CASE
          WHEN TRIM(COALESCE(calls.caller_text, '')) <> '' THEN calls.caller_text
          WHEN users.id IS NOT NULL THEN TRIM(
            COALESCE(users.first_name, '') || ' ' || COALESCE(users.last_name, '')
          )
          ELSE ''
        END AS caller_text,
        COALESCE(NULLIF(TRIM(calls.department_text), ''), departments.name, '') AS department_text,
        COALESCE(users.is_deleted, 0) AS caller_is_deleted,
        COALESCE(equipment.is_deleted, 0) AS equipment_is_deleted
      FROM calls
      LEFT JOIN users ON users.id = calls.caller_id
      LEFT JOIN departments ON departments.id = users.department_id
      LEFT JOIN equipment ON equipment.id = calls.equipment_id
      WHERE COALESCE(calls.is_deleted, 0) = 0
      ORDER BY calls.id DESC
      LIMIT ?
      ''',
      [limit],
    );
  }

  /// Επιστρέφει τις τελευταίες κλήσεις για συγκεκριμένο equipment code.
  ///
  /// Γίνεται ταύτιση τόσο με `equipment.code_equipment` (μέσω FK),
  /// όσο και με το snapshot κειμένου `calls.equipment_text`.
  Future<List<Map<String, dynamic>>> getRecentCallsByEquipmentCode(
    String equipmentCode, {
    int limit = 3,
  }) async {
    final code = equipmentCode.trim();
    if (code.isEmpty) return const <Map<String, dynamic>>[];
    return db.rawQuery(
      '''
      SELECT calls.*,
        COALESCE(users.is_deleted, 0) AS caller_is_deleted,
        COALESCE(equipment.is_deleted, 0) AS equipment_is_deleted
      FROM calls
      LEFT JOIN users ON users.id = calls.caller_id
      LEFT JOIN equipment ON equipment.id = calls.equipment_id
      WHERE COALESCE(calls.is_deleted, 0) = 0
        AND (
          LOWER(TRIM(COALESCE(equipment.code_equipment, ''))) = LOWER(TRIM(?))
          OR LOWER(TRIM(COALESCE(calls.equipment_text, ''))) = LOWER(TRIM(?))
        )
      ORDER BY calls.id DESC
      LIMIT ?
      ''',
      [code, code, limit],
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
             calls.issue, calls.caller_text, calls.phone_text, calls.department_text, calls.equipment_text,
             COALESCE(cat.name, calls.category_text, '') AS category, calls.status, calls.duration, calls.is_priority,
             COALESCE(users.first_name, calls.caller_text, '') AS user_first_name,
             COALESCE(users.last_name, '') AS user_last_name,
             COALESCE(users.is_deleted, 0) AS caller_is_deleted,
             COALESCE(cat.is_deleted, 0) AS category_is_deleted,
             COALESCE(equipment.is_deleted, 0) AS equipment_is_deleted,
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

  /// Συνολικό πλήθος μη διαγραμμένων εγγραφών στον πίνακα `calls`.
  Future<int> getTotalCallCount() async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM calls WHERE COALESCE(is_deleted, 0) = 0',
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  /// Πλήθος κλήσεων ιστορικού με φίλτρα ημερομηνίας και κατηγορίας (χωρίς keyword).
  Future<int> getHistoryCallCount({
    String? dateFrom,
    String? dateTo,
    String? category,
  }) async {
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

    whereClauses.insert(0, 'COALESCE(calls.is_deleted, 0) = 0');

    final whereSql = 'WHERE ${whereClauses.join(' AND ')}';
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM calls $whereSql',
      args,
    );
    return (rows.first['c'] as int?) ?? 0;
  }
  Future<CallModel?> getCallById(int callId) async {
    final rows = await db.query(
      'calls',
      where: 'id = ?',
      whereArgs: [callId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CallModel.fromMap(rows.first);
  }

  /// Γραμμή «τηλέφωνο - καλούντας - τμήμα - εξοπλισμός» όπως στο ιστορικό κλήσεων
  /// ([getHistoryCalls]): κενά παραλείπονται, χωρίς placeholder `-`.
  static String formatCallAuditLineFromHistoryQueryRow(Map<String, Object?> r) {
    String nz(dynamic v) {
      final t = v?.toString().trim() ?? '';
      if (t.isEmpty || t == '-') return '';
      return t;
    }

    final phone = nz(r['user_phone']);
    final first = (r['user_first_name'] as String?)?.trim() ?? '';
    final last = (r['user_last_name'] as String?)?.trim() ?? '';
    var caller = '$first $last'.trim();
    if (caller.isNotEmpty && historyEntityIsDeleted(r['caller_is_deleted'])) {
      caller = historyDeletedDisplayLabel(
        caller,
        isDeleted: true,
        deletedSuffix: kHistoryUserDeletedSuffix,
      );
    }
    final dept = nz(r['user_department']);
    var equip = nz(r['equipment_code']);
    if (equip.isNotEmpty && historyEntityIsDeleted(r['equipment_is_deleted'])) {
      equip = historyDeletedDisplayLabel(
        equip,
        isDeleted: true,
        deletedSuffix: kHistoryEquipmentDeletedSuffix,
      );
    }
    return [phone, caller, dept, equip].where((s) => s.isNotEmpty).join(' - ');
  }

  /// Ίδια JOIN/COALESCE με [getHistoryCalls], για μία εγγραφή (π.χ. audit `entity_name`).
  @override
  Future<String> buildCallAuditDisplayLine(
    int callId, {
    DatabaseExecutor? executor,
  }) async {
    const userPhoneExpr =
        "COALESCE(NULLIF(TRIM(calls.phone_text), ''), upl.phone_list, '-')";
    final ex = executor ?? db;
    final rows = await ex.rawQuery(
      '''
      SELECT COALESCE(users.first_name, calls.caller_text, '') AS user_first_name,
             COALESCE(users.last_name, '') AS user_last_name,
             COALESCE(users.is_deleted, 0) AS caller_is_deleted,
             COALESCE(cat.is_deleted, 0) AS category_is_deleted,
             COALESCE(equipment.is_deleted, 0) AS equipment_is_deleted,
             COALESCE(cat.name, calls.category_text, '') AS category,
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
      WHERE calls.id = ?
      LIMIT 1
      ''',
      [callId],
    );
    if (rows.isEmpty) return '';
    return formatCallAuditLineFromHistoryQueryRow(rows.first);
  }
}
