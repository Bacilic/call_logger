part of 'calls_repository.dart';

mixin CallsRepositoryDeletionMixin on CallsRepositorySearchIndexMixin {
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
    for (final field in CallsRepository._kCallAuditFields) {
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
}
