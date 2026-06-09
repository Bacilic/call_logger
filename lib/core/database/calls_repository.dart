import 'dart:async';
import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../features/calls/models/call_model.dart';
import '../../features/history/models/dashboard_filter_model.dart';
import '../../features/history/models/dashboard_summary_model.dart';
import 'database_helper.dart';
import '../errors/call_save_exception.dart';
import '../services/audit_service.dart';
import '../utils/history_entity_display_utils.dart';
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

  /// Φίλτρο «όνομα χρήστη» dashboard — κανονικοποιημένο όπως keyword Ιστορικού.
  void _appendDashboardUserFilter(
    List<String> whereClauses,
    List<dynamic> args,
    String userPhoneExpr,
    String userQuery,
  ) {
    final nq = SearchTextNormalizer.normalizeForSearch(userQuery);
    if (nq.isEmpty) return;
    whereClauses.add('(calls.search_index LIKE ? OR $userPhoneExpr LIKE ?)');
    args.add('%$nq%');
    args.add('%$nq%');
  }

  Future<void> _rebuildSearchIndexForCallRows(
    DatabaseExecutor executor,
    List<Map<String, dynamic>> rows,
  ) async {
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

  /// Επαναδόμηση `search_index` για μία κλήση βάσει id (integrity fix).
  Future<void> rebuildSearchIndexForCallId(int callId) async {
    await db.transaction((txn) async {
      await rebuildSearchIndexForCallIdInTxn(txn, callId);
    });
  }

  /// Επαναδόμηση `search_index` για μία κλήση μέσα σε transaction.
  Future<void> rebuildSearchIndexForCallIdInTxn(
    DatabaseExecutor executor,
    int callId,
  ) async {
    final rows = await executor.query(
      'calls',
      where: 'id = ?',
      whereArgs: [callId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    await _rebuildSearchIndexForCallRows(executor, rows);
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
    await _rebuildSearchIndexForCallRows(executor, rows);
  }

  /// Επαναδόμηση `search_index` για μη-διαγραμμένες κλήσεις με [callerId].
  Future<void> rebuildSearchIndexForCallsByCallerId(
    DatabaseExecutor executor,
    int callerId,
  ) async {
    final rows = await executor.query(
      'calls',
      where: 'caller_id = ? AND COALESCE(is_deleted, 0) = 0',
      whereArgs: [callerId],
    );
    await _rebuildSearchIndexForCallRows(executor, rows);
  }

  /// Επαναδόμηση `search_index` για μη-διαγραμμένες κλήσεις με [equipmentId].
  Future<void> rebuildSearchIndexForCallsByEquipmentId(
    DatabaseExecutor executor,
    int equipmentId,
  ) async {
    final rows = await executor.query(
      'calls',
      where: 'equipment_id = ? AND COALESCE(is_deleted, 0) = 0',
      whereArgs: [equipmentId],
    );
    await _rebuildSearchIndexForCallRows(executor, rows);
  }

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

  /// Εισάγει νέα κλήση. date/time τίθενται από τώρα αν δεν δοθούν.
  ///
  /// Κλήση + audit στο ίδιο transaction· σε αποτυχία rollback ([CallSaveException]).
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
    try {
      return await db.transaction((txn) async {
        map['search_index'] = await _buildCallSearchIndex(txn, map);
        final id = await txn.insert('calls', map);
        final user = await AuditService.performingUser(txn);
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

  Future<int> getTasksCountLinkedToCall(int callId) async {
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS c
      FROM tasks
      WHERE call_id = ? AND COALESCE(is_deleted, 0) = 0
      ''',
      [callId],
    );
    if (rows.isEmpty) return 0;
    final value = rows.first['c'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<int> getTasksCountLinkedToCalls(List<int> callIds) async {
    if (callIds.isEmpty) return 0;
    final placeholders = List.filled(callIds.length, '?').join(', ');
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS c
      FROM tasks
      WHERE call_id IN ($placeholders) AND COALESCE(is_deleted, 0) = 0
      ''', callIds);
    if (rows.isEmpty) return 0;
    final value = rows.first['c'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<List<int>> _getTaskIdsLinkedToCall(
    DatabaseExecutor executor,
    int callId,
  ) async {
    final rows = await executor.query(
      'tasks',
      columns: ['id'],
      where: 'call_id = ? AND COALESCE(is_deleted, 0) = 0',
      whereArgs: [callId],
    );
    return rows.map((r) => r['id']).whereType<int>().toList(growable: false);
  }

  Future<void> _softDeleteTaskInTxn(
    DatabaseExecutor txn,
    int taskId,
    String userPerforming,
  ) async {
    final titleRows = await txn.query(
      'tasks',
      columns: ['title'],
      where: 'id = ?',
      whereArgs: [taskId],
      limit: 1,
    );
    if (titleRows.isEmpty) return;
    final taskTitle = (titleRows.first['title'] as String?)?.trim();
    await txn.update(
      'tasks',
      {'is_deleted': 1},
      where: 'id = ?',
      whereArgs: [taskId],
    );
    await AuditService.log(
      txn,
      action: DatabaseHelper.auditActionDelete,
      userPerforming: userPerforming,
      details: 'tasks id=$taskId',
      entityType: AuditEntityTypes.task,
      entityId: taskId,
      entityName: taskTitle != null && taskTitle.isNotEmpty ? taskTitle : null,
    );
  }

  Future<void> _softDeleteCallInTxn(
    DatabaseExecutor txn,
    int callId,
    String userPerforming, {
    bool logAudit = true,
  }) async {
    final rows = await txn.query(
      'calls',
      where: 'id = ?',
      whereArgs: [callId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final row = Map<String, dynamic>.from(rows.first);
    row['is_deleted'] = 1;
    final si = await _buildCallSearchIndex(txn, row);
    await txn.update(
      'calls',
      {'is_deleted': 1, 'search_index': si},
      where: 'id = ?',
      whereArgs: [callId],
    );
    if (!logAudit) return;
    final entityName = (await buildCallAuditDisplayLine(
      callId,
      executor: txn,
    )).trim();
    await AuditService.log(
      txn,
      action: DatabaseHelper.auditActionDelete,
      userPerforming: userPerforming,
      details: 'calls id=$callId',
      entityType: AuditEntityTypes.call,
      entityId: callId,
      entityName: entityName.isEmpty ? null : entityName,
      oldValues: {'is_deleted': 0},
      newValues: {'is_deleted': 1},
    );
  }

  Future<void> _hardDeleteCallInTxn(
    DatabaseExecutor txn,
    int callId,
    String userPerforming,
  ) async {
    final rows = await txn.query(
      'calls',
      where: 'id = ?',
      whereArgs: [callId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final oldRow = Map<String, dynamic>.from(rows.first);
    final oldValues = <String, dynamic>{};
    for (final field in _kCallAuditFields) {
      if (oldRow.containsKey(field)) {
        oldValues[field] = oldRow[field];
      }
    }
    final entityName = (await buildCallAuditDisplayLine(
      callId,
      executor: txn,
    )).trim();
    await txn.delete(
      'call_external_links',
      where: 'call_id = ?',
      whereArgs: [callId],
    );
    await txn.delete('calls', where: 'id = ?', whereArgs: [callId]);
    await AuditService.log(
      txn,
      action: DatabaseHelper.auditActionDelete,
      userPerforming: userPerforming,
      details: 'calls id=$callId',
      entityType: AuditEntityTypes.call,
      entityId: callId,
      entityName: entityName.isEmpty ? null : entityName,
      oldValues: oldValues,
    );
  }

  Future<void> deleteCallWithTasksAction(
    int callId,
    String action, {
    bool hard = false,
  }) async {
    if (action != 'cascade' && action != 'nullify') {
      throw ArgumentError.value(action, 'action', 'Unsupported tasks action');
    }
    final user = await AuditService.performingUser(db);
    await db.transaction((txn) async {
      if (action == 'cascade') {
        final taskIds = await _getTaskIdsLinkedToCall(txn, callId);
        for (final taskId in taskIds) {
          await _softDeleteTaskInTxn(txn, taskId, user);
        }
      } else {
        await txn.update(
          'tasks',
          {'call_id': null},
          where: 'call_id = ?',
          whereArgs: [callId],
        );
      }
      if (hard) {
        await _hardDeleteCallInTxn(txn, callId, user);
      } else {
        await _softDeleteCallInTxn(txn, callId, user);
      }
    });
  }

  Future<void> hardDeleteCall(int callId) async {
    final user = await AuditService.performingUser(db);
    await db.transaction((txn) async {
      await _hardDeleteCallInTxn(txn, callId, user);
    });
  }

  Future<void> bulkSoftDeleteCalls(
    List<int> callIds, {
    String? taskAction,
  }) async {
    if (callIds.isEmpty) return;
    if (taskAction != null &&
        taskAction != 'cascade' &&
        taskAction != 'nullify') {
      throw ArgumentError.value(
        taskAction,
        'taskAction',
        'Unsupported tasks action',
      );
    }
    if (taskAction == null) {
      final linkedCount = await getTasksCountLinkedToCalls(callIds);
      if (linkedCount > 0) {
        throw StateError('Linked tasks exist; choose a tasks action.');
      }
    }

    final user = await AuditService.performingUser(db);
    await db.transaction((txn) async {
      final placeholders = List.filled(callIds.length, '?').join(', ');
      if (taskAction == 'cascade') {
        final taskRows = await txn.query(
          'tasks',
          columns: ['id'],
          where: 'call_id IN ($placeholders) AND COALESCE(is_deleted, 0) = 0',
          whereArgs: callIds,
        );
        final taskIds = taskRows.map((r) => r['id']).whereType<int>();
        for (final taskId in taskIds) {
          await _softDeleteTaskInTxn(txn, taskId, user);
        }
      } else if (taskAction == 'nullify') {
        await txn.update(
          'tasks',
          {'call_id': null},
          where: 'call_id IN ($placeholders)',
          whereArgs: callIds,
        );
      }

      for (final callId in callIds) {
        await _softDeleteCallInTxn(txn, callId, user, logAudit: false);
      }

      await AuditService.logBulk(
        txn,
        action: DatabaseHelper.auditActionBulkDelete,
        userPerforming: user,
        entityType: AuditEntityTypes.call,
        affectedIds: callIds,
        appliedFields: const {'is_deleted': 1},
        details: 'calls count=${callIds.length}',
      );
    });
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

  /// Στατιστικά κλήσεων για πίνακα ελέγχου: KPIs, ανά τμήμα, ανά βλάβη (`issue`).
  Future<DashboardSummaryModel> getDashboardStatistics(
    DashboardFilterModel filter,
  ) async {
    const userPhoneExpr =
        "COALESCE(NULLIF(TRIM(calls.phone_text), ''), upl.phone_list, '-')";
    const deptExpr = "COALESCE(departments.name, calls.department_text, '-')";
    const equipExpr =
        "COALESCE(equipment.code_equipment, calls.equipment_text, '')";
    const callerNameExpr =
        "TRIM(COALESCE(users.first_name, '') || ' ' || COALESCE(users.last_name, ''))";
    const callerLabelExpr =
        "CASE WHEN TRIM($callerNameExpr) = '' "
        "THEN COALESCE(NULLIF(TRIM(calls.caller_text), ''), '-') "
        "ELSE TRIM($callerNameExpr) END";

    final whereClausesBase = <String>['COALESCE(calls.is_deleted, 0) = 0'];
    final argsBase = <dynamic>[];

    final dept = filter.department?.trim();
    if (dept != null && dept.isNotEmpty) {
      whereClausesBase.add('$deptExpr = ?');
      argsBase.add(dept);
    }

    final userQ = filter.userName?.trim();
    if (userQ != null && userQ.isNotEmpty) {
      _appendDashboardUserFilter(
        whereClausesBase,
        argsBase,
        userPhoneExpr,
        userQ,
      );
    }

    final eqQ = filter.equipmentCode?.trim();
    if (eqQ != null && eqQ.isNotEmpty) {
      whereClausesBase.add('$equipExpr LIKE ?');
      argsBase.add('%$eqQ%');
    }

    final kw = filter.keyword.trim();
    if (kw.isNotEmpty) {
      final nk = SearchTextNormalizer.normalizeForSearch(kw);
      if (nk.isNotEmpty) {
        whereClausesBase.add('calls.search_index LIKE ?');
        argsBase.add('%$nk%');
      }
    }

    final whereClauses = List<String>.from(whereClausesBase);
    final args = List<dynamic>.from(argsBase);
    final df = filter.dateFromSql;
    final dt = filter.dateToSql;
    final isAllDatesMode =
        (df == null || df.isEmpty) && (dt == null || dt.isEmpty);
    if (df != null && df.isNotEmpty) {
      whereClauses.add('calls.date >= ?');
      args.add(df);
    }
    if (dt != null && dt.isNotEmpty) {
      whereClauses.add('calls.date <= ?');
      args.add(dt);
    }
    final whereSql = 'WHERE ${whereClauses.join(' AND ')}';

    final fromJoin =
        '''
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
''';

    final kpiRows = await db.rawQuery('''
      SELECT COUNT(*) AS c,
             COALESCE(SUM(calls.duration), 0) AS total_dur,
             AVG(calls.duration) AS avg_dur
      $fromJoin
      ''', args);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final anchorDate =
        filter.dateTo ??
        filter.dateFrom ??
        DateTime(today.year, today.month, today.day);
    final anchorDay = DateTime(
      anchorDate.year,
      anchorDate.month,
      anchorDate.day,
    );
    final anchorDaySql = DateFormat('yyyy-MM-dd').format(anchorDay);
    final previousDay = anchorDay.subtract(const Duration(days: 1));
    final previousDaySql = DateFormat('yyyy-MM-dd').format(previousDay);

    final List<Map<String, dynamic>> previousKpiRows;
    if (isAllDatesMode) {
      previousKpiRows = const [];
    } else {
      final prevRange = filter.previousComparisonRangeInclusive;
      final wherePreviousPeriod = List<String>.from(whereClausesBase);
      final argsPreviousPeriod = List<dynamic>.from(argsBase);
      if (prevRange != null) {
        wherePreviousPeriod.add('calls.date >= ?');
        argsPreviousPeriod.add(
          DateFormat('yyyy-MM-dd').format(prevRange.start),
        );
        wherePreviousPeriod.add('calls.date <= ?');
        argsPreviousPeriod.add(DateFormat('yyyy-MM-dd').format(prevRange.end));
      } else {
        wherePreviousPeriod.add('calls.date = ?');
        argsPreviousPeriod.add(previousDaySql);
      }
      final fromJoinPreviousPeriod =
          '''
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
WHERE ${wherePreviousPeriod.join(' AND ')}
''';
      previousKpiRows = await db.rawQuery('''
      SELECT COUNT(*) AS c,
             COALESCE(SUM(calls.duration), 0) AS total_dur,
             AVG(calls.duration) AS avg_dur
      $fromJoinPreviousPeriod
      ''', argsPreviousPeriod);
    }

    final deptRows = await db.rawQuery('''
      SELECT $deptExpr AS dept_name,
             COUNT(*) AS cnt,
             COALESCE(SUM(calls.duration), 0) AS sum_dur
      $fromJoin
      GROUP BY $deptExpr
      ORDER BY cnt DESC
      ''', args);

    final escapedNoIssue = kDashboardNoIssueLabel.replaceAll("'", "''");
    final issueLabelExpr =
        "CASE WHEN calls.issue IS NULL OR TRIM(calls.issue) = '' "
        "THEN '$escapedNoIssue' "
        "ELSE TRIM(calls.issue) END";

    final issueRows = await db.rawQuery('''
      SELECT $issueLabelExpr AS issue_label,
             COUNT(*) AS cnt,
             COALESCE(SUM(calls.duration), 0) AS sum_dur
      $fromJoin
      GROUP BY $issueLabelExpr
      ORDER BY cnt DESC
      LIMIT 15
      ''', args);

    final trendStart = anchorDay.subtract(const Duration(days: 6));
    final trendStartSql = DateFormat('yyyy-MM-dd').format(trendStart);
    final whereTrend = List<String>.from(whereClausesBase)
      ..add('calls.date >= ?')
      ..add('calls.date <= ?');
    final argsTrend = List<dynamic>.from(argsBase)
      ..add(trendStartSql)
      ..add(anchorDaySql);
    final fromJoinTrend =
        '''
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
WHERE ${whereTrend.join(' AND ')}
''';
    final trendRows = await db.rawQuery('''
      SELECT calls.date AS day,
             COUNT(*) AS cnt,
             COALESCE(SUM(calls.duration), 0) AS sum_dur
      $fromJoinTrend
      GROUP BY calls.date
      ORDER BY calls.date ASC
      ''', argsTrend);

    final topCallerRows = await db.rawQuery('''
      SELECT $callerLabelExpr AS caller_name,
             COUNT(*) AS cnt
      $fromJoin
      GROUP BY $callerLabelExpr
      ORDER BY cnt DESC, caller_name ASC
      LIMIT 10
      ''', args);

    final longestRows = await db.rawQuery('''
      SELECT $callerLabelExpr AS caller_name,
             $deptExpr AS dept_name,
             COALESCE(calls.duration, 0) AS dur
      $fromJoin
      ORDER BY dur DESC, caller_name ASC
      LIMIT 20
      ''', args);

    final hourRows = await db.rawQuery('''
      SELECT CAST(SUBSTR(COALESCE(calls.time, '00:00'), 1, 2) AS INTEGER) AS hh,
             COUNT(*) AS cnt
      $fromJoin
      GROUP BY hh
      ORDER BY hh ASC
      ''', args);

    final kpi = kpiRows.isEmpty ? <String, dynamic>{} : kpiRows.first;
    final previousKpi = previousKpiRows.isEmpty
        ? <String, dynamic>{}
        : previousKpiRows.first;
    final totalCalls = (kpi['c'] as num?)?.toInt() ?? 0;
    final totalDurationSeconds = (kpi['total_dur'] as num?)?.toInt() ?? 0;
    final avgDurationSeconds = totalCalls == 0
        ? 0.0
        : ((kpi['avg_dur'] as num?)?.toDouble() ?? 0.0);
    final previousPeriodTotalCalls = (previousKpi['c'] as num?)?.toInt() ?? 0;
    final previousPeriodTotalDurationSeconds =
        (previousKpi['total_dur'] as num?)?.toInt() ?? 0;
    final previousPeriodAvgDurationSeconds = previousPeriodTotalCalls == 0
        ? 0.0
        : ((previousKpi['avg_dur'] as num?)?.toDouble() ?? 0.0);

    final byDepartment = deptRows
        .map(
          (row) => DepartmentStat(
            name: (row['dept_name'] as String?)?.trim().isNotEmpty == true
                ? (row['dept_name'] as String).trim()
                : '-',
            count: (row['cnt'] as num?)?.toInt() ?? 0,
            sumDurationSeconds: (row['sum_dur'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList();

    final byIssue = issueRows
        .map(
          (row) => IssueStat(
            name: (row['issue_label'] as String?)?.trim() ?? '',
            count: (row['cnt'] as num?)?.toInt() ?? 0,
            sumDurationSeconds: (row['sum_dur'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList();

    final trendByDate = <String, Map<String, dynamic>>{
      for (final row in trendRows) (row['day'] as String? ?? ''): row,
    };
    final dailyTrend = List<DailyTrendPoint>.generate(7, (index) {
      final day = trendStart.add(Duration(days: index));
      final dayKey = DateFormat('yyyy-MM-dd').format(day);
      final row = trendByDate[dayKey];
      return DailyTrendPoint(
        date: day,
        callCount: (row?['cnt'] as num?)?.toInt() ?? 0,
        totalDurationSeconds: (row?['sum_dur'] as num?)?.toInt() ?? 0,
      );
    });

    final sparkStart = anchorDay.subtract(const Duration(days: 6));
    final sparkStartSql = DateFormat('yyyy-MM-dd').format(sparkStart);
    final todaySql = DateFormat('yyyy-MM-dd').format(anchorDay);
    final whereSpark = List<String>.from(whereClausesBase)
      ..add('calls.date >= ?')
      ..add('calls.date <= ?');
    final argsSpark = List<dynamic>.from(argsBase)
      ..add(sparkStartSql)
      ..add(todaySql);
    final fromJoinSpark =
        '''
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
WHERE ${whereSpark.join(' AND ')}
''';
    final sparkRows = await db.rawQuery('''
      SELECT calls.date AS day,
             COUNT(*) AS cnt,
             COALESCE(SUM(calls.duration), 0) AS sum_dur
      $fromJoinSpark
      GROUP BY calls.date
      ORDER BY calls.date ASC
      ''', argsSpark);
    final sparkByDate = <String, Map<String, dynamic>>{
      for (final row in sparkRows) (row['day'] as String? ?? ''): row,
    };
    final sparklineLast7Days = List<DailyTrendPoint>.generate(7, (index) {
      final day = sparkStart.add(Duration(days: index));
      final dayKey = DateFormat('yyyy-MM-dd').format(day);
      final row = sparkByDate[dayKey];
      return DailyTrendPoint(
        date: day,
        callCount: (row?['cnt'] as num?)?.toInt() ?? 0,
        totalDurationSeconds: (row?['sum_dur'] as num?)?.toInt() ?? 0,
      );
    });

    final topCallers = topCallerRows
        .map(
          (row) => CallerStat(
            name: (row['caller_name'] as String?)?.trim().isNotEmpty == true
                ? (row['caller_name'] as String).trim()
                : '-',
            count: (row['cnt'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList();

    final longestCalls = longestRows
        .map(
          (row) => LongestCallEntry(
            callerName:
                (row['caller_name'] as String?)?.trim().isNotEmpty == true
                ? (row['caller_name'] as String).trim()
                : '-',
            department: (row['dept_name'] as String?)?.trim().isNotEmpty == true
                ? (row['dept_name'] as String).trim()
                : '-',
            durationSeconds: (row['dur'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList();

    final hourCountMap = <int, int>{
      for (final row in hourRows)
        (row['hh'] as num?)?.toInt() ?? 0: (row['cnt'] as num?)?.toInt() ?? 0,
    };
    final hourlyDistribution = List<HourlyBucket>.generate(
      24,
      (hour) => HourlyBucket(hour: hour, callCount: hourCountMap[hour] ?? 0),
    );

    var totalActiveDays = 0;
    var medianDurationSeconds = 0;
    DateTime? historyDateFrom;
    DateTime? historyDateTo;
    KpiAllDatesBarSparklines? allDatesBarSparklines;
    if (isAllDatesMode && totalCalls > 0) {
      final activeDaysRows = await db.rawQuery('''
        SELECT COUNT(DISTINCT calls.date) AS active_days,
               MIN(calls.date) AS min_date,
               MAX(calls.date) AS max_date
        $fromJoin
        ''', args);
      final activeRow = activeDaysRows.isEmpty ? null : activeDaysRows.first;
      totalActiveDays = (activeRow?['active_days'] as num?)?.toInt() ?? 0;
      historyDateFrom = parseDashboardSqlDate(
        activeRow?['min_date'] as String?,
      );
      historyDateTo = parseDashboardSqlDate(activeRow?['max_date'] as String?);

      final durationRows = await db.rawQuery('''
        SELECT calls.duration AS dur
        $fromJoin
        ORDER BY calls.duration ASC
        ''', args);
      final durations = durationRows
          .map((row) => (row['dur'] as num?)?.toInt() ?? 0)
          .toList(growable: false);
      medianDurationSeconds = medianDurationSecondsFromList(durations);

      final monthRows = await db.rawQuery('''
        SELECT strftime('%Y-%m', calls.date) AS month_key,
               COUNT(*) AS cnt
        $fromJoin
        GROUP BY month_key
        ORDER BY month_key ASC
        ''', args);
      final List<KpiBarSparklinePoint> callsByMonth = monthRows
          .map((row) {
            final monthKey = row['month_key'] as String? ?? '';
            final count = (row['cnt'] as num?)?.toDouble() ?? 0.0;
            return KpiBarSparklinePoint(
              value: count,
              tooltip: formatKpiMonthCallsTooltip(monthKey, count),
            );
          })
          .toList(growable: false);

      final weekdayRows = await db.rawQuery('''
        SELECT CAST(strftime('%w', calls.date) AS INTEGER) AS dow,
               COALESCE(SUM(calls.duration), 0) AS sum_dur
        $fromJoin
        AND CAST(strftime('%w', calls.date) AS INTEGER) BETWEEN 1 AND 5
        GROUP BY dow
        ORDER BY dow ASC
        ''', args);
      final weekdayDurationMap = <int, double>{
        for (final row in weekdayRows)
          (row['dow'] as num?)?.toInt() ?? 0:
              (row['sum_dur'] as num?)?.toDouble() ?? 0.0,
      };
      final durationByWeekdayMonToFri = List<KpiBarSparklinePoint>.generate(
        5,
        (index) => kpiWeekdayDurationPoint(
          index,
          weekdayDurationMap[index + 1] ?? 0.0,
        ),
      );

      final longestDurRows = await db.rawQuery('''
        SELECT COALESCE(calls.duration, 0) AS dur
        $fromJoin
        ORDER BY dur DESC
        LIMIT 3
        ''', args);
      final shortestDurRows = await db.rawQuery('''
        SELECT COALESCE(calls.duration, 0) AS dur
        $fromJoin
        AND COALESCE(calls.duration, 0) > 0
        ORDER BY dur ASC
        LIMIT 3
        ''', args);
      final List<KpiBarSparklinePoint> durationExtremesSix =
          padBarSparklinePoints([
            ...longestDurRows.asMap().entries.map(
              (entry) => kpiDurationExtremePoint(
                entry.key,
                (entry.value['dur'] as num?)?.toDouble() ?? 0,
              ),
            ),
            ...shortestDurRows.asMap().entries.map(
              (entry) => kpiDurationExtremePoint(
                entry.key + 3,
                (entry.value['dur'] as num?)?.toDouble() ?? 0,
              ),
            ),
          ], 6);

      allDatesBarSparklines = KpiAllDatesBarSparklines(
        callsByMonth: callsByMonth.isEmpty
            ? const [KpiBarSparklinePoint(value: 0, tooltip: '')]
            : callsByMonth,
        durationByWeekdayMonToFri: durationByWeekdayMonToFri,
        durationExtremesSix: durationExtremesSix,
        departmentCountsRank2To6: runnerUpPointsFromDepartmentStats(
          byDepartment,
          5,
        ),
        callerCountsRank2To6: runnerUpPointsFromCallerStats(topCallers, 5),
        issueCountsRank2To6: runnerUpPointsFromIssueStats(byIssue, 5),
      );
    }

    return DashboardSummaryModel(
      totalCalls: totalCalls,
      totalDurationSeconds: totalDurationSeconds,
      avgDurationSeconds: avgDurationSeconds,
      previousPeriodTotalCalls: previousPeriodTotalCalls,
      previousPeriodTotalDurationSeconds: previousPeriodTotalDurationSeconds,
      previousPeriodAvgDurationSeconds: previousPeriodAvgDurationSeconds,
      isAllDatesMode: isAllDatesMode,
      totalActiveDays: totalActiveDays,
      medianDurationSeconds: medianDurationSeconds,
      historyDateFrom: historyDateFrom,
      historyDateTo: historyDateTo,
      allDatesBarSparklines: allDatesBarSparklines,
      dailyTrend: dailyTrend,
      sparklineLast7Days: sparklineLast7Days,
      topCallers: topCallers,
      longestCalls: longestCalls,
      hourlyDistribution: hourlyDistribution,
      byDepartment: byDepartment,
      byIssue: byIssue,
    );
  }

  /// Κλήσεις για αναφορά dashboard (Lansweeper) με τα ίδια φίλτρα των KPIs.
  Future<List<CallModel>> getDashboardCalls(DashboardFilterModel filter) async {
    const userPhoneExpr =
        "COALESCE(NULLIF(TRIM(calls.phone_text), ''), upl.phone_list, '-')";
    const deptExpr = "COALESCE(departments.name, calls.department_text, '-')";
    const equipExpr =
        "COALESCE(equipment.code_equipment, calls.equipment_text, '')";
    const callerNameExpr =
        "TRIM(COALESCE(users.first_name, '') || ' ' || COALESCE(users.last_name, ''))";
    const callerLabelExpr =
        "CASE WHEN TRIM($callerNameExpr) = '' "
        "THEN COALESCE(NULLIF(TRIM(calls.caller_text), ''), '-') "
        "ELSE TRIM($callerNameExpr) END";

    final whereClauses = <String>['COALESCE(calls.is_deleted, 0) = 0'];
    final args = <dynamic>[];

    final dept = filter.department?.trim();
    if (dept != null && dept.isNotEmpty) {
      whereClauses.add('$deptExpr = ?');
      args.add(dept);
    }

    final userQ = filter.userName?.trim();
    if (userQ != null && userQ.isNotEmpty) {
      _appendDashboardUserFilter(whereClauses, args, userPhoneExpr, userQ);
    }

    final eqQ = filter.equipmentCode?.trim();
    if (eqQ != null && eqQ.isNotEmpty) {
      whereClauses.add('$equipExpr LIKE ?');
      args.add('%$eqQ%');
    }

    final kw = filter.keyword.trim();
    if (kw.isNotEmpty) {
      final nk = SearchTextNormalizer.normalizeForSearch(kw);
      if (nk.isNotEmpty) {
        whereClauses.add('calls.search_index LIKE ?');
        args.add('%$nk%');
      }
    }

    final df = filter.dateFromSql;
    final dt = filter.dateToSql;
    if (df != null && df.isNotEmpty) {
      whereClauses.add('calls.date >= ?');
      args.add(df);
    }
    if (dt != null && dt.isNotEmpty) {
      whereClauses.add('calls.date <= ?');
      args.add(dt);
    }

    final rows = await db.rawQuery('''
      SELECT
        calls.id,
        calls.date,
        calls.time,
        calls.caller_id,
        calls.equipment_id,
        $callerLabelExpr AS caller_text,
        calls.phone_text,
        calls.department_text,
        calls.equipment_text,
        calls.issue,
        calls.category_text,
        calls.category_id,
        calls.status,
        calls.duration,
        calls.is_priority,
        calls.lansweeper_state,
        calls.lansweeper_main_ticket_id,
        calls.lansweeper_last_sync_at,
        calls.is_deleted
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
      WHERE ${whereClauses.join(' AND ')}
      ORDER BY calls.date DESC, calls.time DESC, calls.id DESC
      ''', args);

    return rows.map(CallModel.fromMap).toList();
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

  /// Μέγιστο αριθμητικό Lansweeper ticket id από κλήσεις και ιστορικό links.
  Future<int?> maxNumericLansweeperTicketId() async {
    final rows = await db.rawQuery('''
      SELECT MAX(CAST(ticket_id AS INTEGER)) AS max_id
      FROM (
        SELECT trim(lansweeper_main_ticket_id) AS ticket_id
        FROM calls
        WHERE trim(lansweeper_main_ticket_id) != ''
          AND trim(lansweeper_main_ticket_id) GLOB '[0-9]*'
          AND (is_deleted IS NULL OR is_deleted = 0)
        UNION
        SELECT trim(external_id) AS ticket_id
        FROM call_external_links
        WHERE provider = 'lansweeper'
          AND trim(external_id) != ''
          AND trim(external_id) GLOB '[0-9]*'
      )
      ''');
    if (rows.isEmpty) return null;
    final value = rows.first['max_id'];
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  /// Πρόταση επόμενου ticket id (μέγιστο αριθμητικό + 1), ή null αν δεν υπάρχει.
  Future<String?> suggestedNextLansweeperTicketId() async {
    final maxId = await maxNumericLansweeperTicketId();
    if (maxId == null) return null;
    return '${maxId + 1}';
  }

  /// Πλήθος κλήσεων με το ίδιο Lansweeper ticket id (trimmed σύγκριση).
  Future<int> countCallsWithLansweeperTicketId(
    String ticketId, {
    int? excludeCallId,
    bool registeredOnly = false,
  }) async {
    final normalized = ticketId.trim();
    if (normalized.isEmpty) return 0;
    final clauses = <String>[
      "trim(lansweeper_main_ticket_id) = ?",
      '(is_deleted IS NULL OR is_deleted = 0)',
    ];
    final args = <Object?>[normalized];
    if (excludeCallId != null) {
      clauses.add('id != ?');
      args.add(excludeCallId);
    }
    if (registeredOnly) {
      clauses.add("lansweeper_state = 'sent'");
    }
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM calls WHERE ${clauses.join(' AND ')}',
      args,
    );
    if (rows.isEmpty) return 0;
    final value = rows.first['c'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  /// Ενημερώνει την κατάσταση Lansweeper μιας κλήσης.
  Future<void> updateLansweeperState({
    required int callId,
    required String state,
    String? ticketId,
    bool updateTicketId = false,
    bool clearTicketId = false,
    String? syncedAt,
  }) async {
    final payload = <String, Object?>{
      'lansweeper_state': state,
      'lansweeper_last_sync_at': syncedAt ?? DateTime.now().toIso8601String(),
    };
    if (updateTicketId || clearTicketId) {
      payload['lansweeper_main_ticket_id'] = clearTicketId ? null : ticketId;
    }
    await db.update('calls', payload, where: 'id = ?', whereArgs: [callId]);
  }

  /// Ορίζει/ενημερώνει το κύριο ticket Lansweeper μιας κλήσης.
  Future<void> setLansweeperMainTicket({
    required int callId,
    required String? ticketId,
    String? syncedAt,
  }) async {
    await db.update(
      'calls',
      {
        'lansweeper_main_ticket_id': ticketId,
        'lansweeper_last_sync_at': syncedAt ?? DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [callId],
    );
  }

  /// Καταγράφει εξωτερικό link (π.χ. ticket id) για κλήση.
  Future<int> addExternalLink({
    required int callId,
    required String externalId,
    required String provider,
    String? createdAt,
    Map<String, dynamic>? metadata,
    DatabaseExecutor? executor,
  }) async {
    final e = executor ?? db;
    return e.insert('call_external_links', {
      'call_id': callId,
      'external_id': externalId,
      'provider': provider,
      'created_at': createdAt ?? DateTime.now().toIso8601String(),
      'metadata': metadata == null ? null : jsonEncode(metadata),
    });
  }

  /// Επιστρέφει το ιστορικό links εξωτερικών συστημάτων για μια κλήση.
  Future<List<Map<String, dynamic>>> getCallExternalLinks(
    int callId, {
    String? provider,
  }) async {
    final where = provider == null
        ? 'call_id = ?'
        : 'call_id = ? AND provider = ?';
    final args = provider == null
        ? <Object?>[callId]
        : <Object?>[callId, provider];
    final rows = await db.query(
      'call_external_links',
      where: where,
      whereArgs: args,
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Χειροκίνητη σήμανση κλήσης ως περασμένη, με transactional write (state + link history).
  Future<void> markManualPassed({
    required int callId,
    required String ticketId,
    String? comment,
  }) async {
    final nowIso = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.update(
        'calls',
        {
          'lansweeper_state': 'sent',
          'lansweeper_main_ticket_id': ticketId,
          'lansweeper_last_sync_at': nowIso,
        },
        where: 'id = ?',
        whereArgs: [callId],
      );
      await addExternalLink(
        callId: callId,
        externalId: ticketId,
        provider: 'lansweeper',
        createdAt: nowIso,
        metadata: <String, dynamic>{
          'mode': 'manual',
          if (comment != null && comment.trim().isNotEmpty)
            'comment': comment.trim(),
        },
        executor: txn,
      );
    });
  }

  /// Επιτυχής συγχρονισμός Lansweeper με transactional write (state + link history).
  Future<void> markLansweeperSynced({
    required int callId,
    required String ticketId,
    required String provider,
    Map<String, dynamic>? metadata,
  }) async {
    final nowIso = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.update(
        'calls',
        {
          'lansweeper_state': 'sent',
          'lansweeper_main_ticket_id': ticketId,
          'lansweeper_last_sync_at': nowIso,
        },
        where: 'id = ?',
        whereArgs: [callId],
      );
      await addExternalLink(
        callId: callId,
        externalId: ticketId,
        provider: provider,
        createdAt: nowIso,
        metadata: metadata,
        executor: txn,
      );
    });
  }
}
