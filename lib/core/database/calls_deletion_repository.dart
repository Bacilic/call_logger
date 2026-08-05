import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'audit_service.dart';
import 'call_deletion_impact.dart';
import 'calls_audit_line.dart';
import 'calls_search_index.dart';
import 'database_helper.dart';

/// Διαγραφή κλήσεων (soft/hard/μαζική) με τα συνδεδεμένα tasks και audit.
class CallsDeletionRepository {
  CallsDeletionRepository(this.db)
    : _searchIndex = CallsSearchIndex(db),
      _auditLine = CallsAuditLine(db);

  final Database db;
  final CallsSearchIndex _searchIndex;
  final CallsAuditLine _auditLine;

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

  /// Ό,τι κρέμεται από τις [callIds] — μία ερώτηση, μία απάντηση.
  ///
  /// Επιστρέφει σύνοψη **ανά κλήση** και όχι μόνο αθροίσματα: στη μαζική
  /// διαγραφή το ερώτημα δεν είναι «πόσα εισιτήρια» αλλά «ποια από τις κλήσεις
  /// μου κρύβει εισιτήριο».
  ///
  /// Το ιστορικό `call_external_links` μετριέται ολόκληρο (κάθε provider), γιατί
  /// ολόκληρο σβήνεται από την οριστική διαγραφή· τα εισιτήρια ονομάζονται μόνο
  /// για το Lansweeper, που είναι και το μοναδικό σύστημα που γράφει σήμερα.
  ///
  /// Οι κλήσεις επιστρέφονται με την πιο πρόσφατη πρώτη — ίδια σειρά με το
  /// Ιστορικό, ώστε η λίστα του διαλόγου να διαβάζεται δίπλα στον πίνακα.
  Future<CallDeletionImpact> getCallDeletionImpact(List<int> callIds) async {
    if (callIds.isEmpty) return CallDeletionImpact.empty;
    final placeholders = List.filled(callIds.length, '?').join(', ');
    final callRows = await db.query(
      'calls',
      columns: ['id', 'date', 'time'],
      where: 'id IN ($placeholders)',
      whereArgs: callIds,
      orderBy: 'date DESC, time DESC, id DESC',
    );
    final linkRows = await db.query(
      'call_external_links',
      columns: ['call_id', 'external_id', 'provider'],
      where: 'call_id IN ($placeholders)',
      whereArgs: callIds,
    );
    final taskRows = await db.query(
      'tasks',
      columns: ['call_id', 'title'],
      where: 'call_id IN ($placeholders) AND COALESCE(is_deleted, 0) = 0',
      whereArgs: callIds,
      orderBy: 'id ASC',
    );

    final linkCounts = <int, int>{};
    final ticketsByCall = <int, Set<String>>{};
    for (final row in linkRows) {
      final callId = row['call_id'] as int?;
      if (callId == null) continue;
      linkCounts[callId] = (linkCounts[callId] ?? 0) + 1;
      if ((row['provider'] as String?)?.trim() != 'lansweeper') continue;
      final ticketId = (row['external_id'] as String?)?.trim() ?? '';
      if (ticketId.isEmpty) continue;
      (ticketsByCall[callId] ??= <String>{}).add(ticketId);
    }

    final titlesByCall = <int, List<String>>{};
    for (final row in taskRows) {
      final callId = row['call_id'] as int?;
      if (callId == null) continue;
      (titlesByCall[callId] ??= <String>[]).add(
        (row['title'] as String?)?.trim() ?? '',
      );
    }

    return CallDeletionImpact([
      for (final row in callRows)
        if (row['id'] case final int callId)
          CallConnectionSummary(
            callId: callId,
            date: (row['date'] as String?)?.trim() ?? '',
            time: (row['time'] as String?)?.trim() ?? '',
            taskTitles: titlesByCall[callId] ?? const <String>[],
            lansweeperTicketIds:
                (ticketsByCall[callId]?.toList() ?? <String>[])
                  ..sort(compareTicketIds),
            externalLinks: linkCounts[callId] ?? 0,
          ),
    ]);
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
    final si = await _searchIndex.buildCallSearchIndex(txn, row);
    await txn.update(
      'calls',
      {'is_deleted': 1, 'search_index': si},
      where: 'id = ?',
      whereArgs: [callId],
    );
    if (!logAudit) return;
    final entityName = (await _auditLine.buildCallAuditDisplayLine(
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
    for (final field in kCallAuditFields) {
      if (oldRow.containsKey(field)) {
        oldValues[field] = oldRow[field];
      }
    }
    final entityName = (await _auditLine.buildCallAuditDisplayLine(
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

  /// Διαγραφή κλήσης — αναστρέψιμη ή οριστική — με ρητή απόφαση για τις
  /// συνδεδεμένες εκκρεμότητες.
  ///
  /// **Μοναδική** δημόσια είσοδος διαγραφής μίας κλήσης, και σκόπιμα χωρίς
  /// συντομότερη παραλλαγή: μια `hardDeleteCall(callId)` που δεν ζητά [action]
  /// επιτρέπει στον καλούντα να σβήσει την κλήση αφήνοντας τις εκκρεμότητές της
  /// να δείχνουν σε γραμμή που δεν υπάρχει πια.
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

  /// Μαζική διαγραφή κλήσεων — αναστρέψιμη ή οριστική.
  ///
  /// **Το Ιστορικό γράφεται διαφορετικά ανά περίπτωση, και όχι από αβλεψία.**
  /// Η αναστρέψιμη αφήνει μία συγκεντρωτική εγγραφή: τα δεδομένα ζουν ακόμη
  /// στις γραμμές τους και η εγγραφή χρειάζεται μόνο για να πει «ποιος, πότε,
  /// πόσες». Η οριστική γράφει **μία εγγραφή ανά κλήση**, γιατί μόνο εκεί
  /// χωρούν τα `oldValues` της κάθε κλήσης — αριθμός εισιτηρίου, καλών,
  /// εξοπλισμός. Μια συγκεντρωτική εγγραφή θα κατέγραφε ότι κάτι σβήστηκε
  /// χωρίς να κρατά τι, και το `is_deleted: 1` που θα ανέφερε δεν συνέβη ποτέ.
  Future<void> bulkDeleteCalls(
    List<int> callIds, {
    String? taskAction,
    bool hard = false,
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

      if (hard) {
        for (final callId in callIds) {
          await _hardDeleteCallInTxn(txn, callId, user);
        }
        return;
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
}
