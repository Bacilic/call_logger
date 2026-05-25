import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

void main() {
  group('CallsRepository history actions', () {
    late CallsRepository repo;

    Future<int> insertCall({
      String? issue,
      String? status,
      String? date,
      String? time,
      String? lansweeperState,
      String? ticketId,
    }) async {
      final db = await DatabaseHelper.instance.database;
      final now = DateTime.now();
      return db.insert('calls', {
        'date': date ?? '${now.year.toString().padLeft(4, '0')}-01-01',
        'time': time ?? '10:00',
        'caller_id': null,
        'equipment_id': null,
        'caller_text': 'Test Caller',
        'phone_text': '1000',
        'department_text': 'Support',
        'equipment_text': 'PC-1',
        'issue': issue,
        'solution': null,
        'category_text': 'Κατηγορία',
        'category_id': null,
        'status': status ?? 'completed',
        'duration': 42,
        'is_priority': 0,
        'search_index': 'test search',
        'lansweeper_state': lansweeperState ?? 'unsent',
        'lansweeper_main_ticket_id': ticketId,
        'lansweeper_last_sync_at': null,
        'is_deleted': 0,
      });
    }

    Future<void> insertTask({
      required int callId,
      bool isDeleted = false,
      String title = 'task',
    }) async {
      final db = await DatabaseHelper.instance.database;
      final nowIso = DateTime.now().toIso8601String();
      await db.insert('tasks', {
        'title': title,
        'status': 'open',
        'call_id': callId,
        'created_at': nowIso,
        'updated_at': nowIso,
        'is_deleted': isDeleted ? 1 : 0,
      });
    }

    setUpAll(() async {
      await bindCallLoggerIsolatedTestDatabase();
      final db = await DatabaseHelper.instance.database;
      repo = CallsRepository(db);
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      final db = await DatabaseHelper.instance.database;
      await db.delete('audit_log');
      repo = CallsRepository(db);
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    test('counts linked tasks for single and multiple call ids', () async {
      final call1 = await insertCall(issue: 'one');
      final call2 = await insertCall(issue: 'two');
      await insertTask(callId: call1, title: 'open-1');
      await insertTask(callId: call1, isDeleted: true, title: 'deleted');
      await insertTask(callId: call2, title: 'open-2');

      expect(await repo.getTasksCountLinkedToCall(call1), 1);
      expect(await repo.getTasksCountLinkedToCall(call2), 1);
      expect(await repo.getTasksCountLinkedToCalls([call1, call2]), 2);
      expect(await repo.getTasksCountLinkedToCalls(const []), 0);
    });

    test(
      'deleteCallWithTasksAction cascade soft-deletes tasks and call',
      () async {
        final callId = await insertCall(issue: 'cascade');
        await insertTask(callId: callId, title: 'task-a');
        await insertTask(callId: callId, title: 'task-b');

        await repo.deleteCallWithTasksAction(callId, 'cascade');

        final db = await DatabaseHelper.instance.database;
        final callRows = await db.query(
          'calls',
          columns: ['is_deleted'],
          where: 'id = ?',
          whereArgs: [callId],
        );
        final taskRows = await db.query(
          'tasks',
          columns: ['is_deleted'],
          where: 'call_id = ?',
          whereArgs: [callId],
        );
        expect(callRows.single['is_deleted'], 1);
        expect(taskRows.every((r) => (r['is_deleted'] as int?) == 1), isTrue);
      },
    );

    test('deleteCallWithTasksAction nullify unlinks tasks', () async {
      final callId = await insertCall(issue: 'nullify');
      await insertTask(callId: callId, title: 'task-nullify');

      await repo.deleteCallWithTasksAction(callId, 'nullify');

      final db = await DatabaseHelper.instance.database;
      final callRows = await db.query(
        'calls',
        columns: ['is_deleted'],
        where: 'id = ?',
        whereArgs: [callId],
      );
      final tasks = await db.query('tasks', columns: ['call_id', 'is_deleted']);
      expect(callRows.single['is_deleted'], 1);
      expect(tasks.single['call_id'], isNull);
      expect(tasks.single['is_deleted'], 0);
    });

    test('hardDeleteCall removes call and external links', () async {
      final callId = await insertCall(
        issue: 'hard',
        lansweeperState: 'sent',
        ticketId: '123',
      );
      await repo.addExternalLink(
        callId: callId,
        externalId: '123',
        provider: 'lansweeper',
      );

      await repo.hardDeleteCall(callId);

      final db = await DatabaseHelper.instance.database;
      final callRows = await db.query(
        'calls',
        where: 'id = ?',
        whereArgs: [callId],
      );
      final linkRows = await db.query(
        'call_external_links',
        where: 'call_id = ?',
        whereArgs: [callId],
      );
      final auditRows = await db.query(
        'audit_log',
        where: 'action = ? AND entity_type = ? AND entity_id = ?',
        whereArgs: [DatabaseHelper.auditActionDelete, 'call', callId],
      );
      expect(callRows, isEmpty);
      expect(linkRows, isEmpty);
      expect(auditRows, isNotEmpty);
    });

    test('bulkSoftDeleteCalls cascades tasks and writes bulk audit', () async {
      final call1 = await insertCall(issue: 'bulk1');
      final call2 = await insertCall(issue: 'bulk2');
      await insertTask(callId: call1, title: 'task-1');
      await insertTask(callId: call2, title: 'task-2');

      await repo.bulkSoftDeleteCalls([call1, call2], taskAction: 'cascade');

      final db = await DatabaseHelper.instance.database;
      final callRows = await db.query(
        'calls',
        columns: ['id', 'is_deleted', 'search_index'],
        where: 'id IN (?, ?)',
        whereArgs: [call1, call2],
      );
      final taskRows = await db.query(
        'tasks',
        columns: ['is_deleted'],
        where: 'call_id IN (?, ?)',
        whereArgs: [call1, call2],
      );
      final bulkAuditRows = await db.query(
        'audit_log',
        where: 'action = ? AND entity_type = ?',
        whereArgs: [DatabaseHelper.auditActionBulkDelete, 'call'],
      );

      expect(callRows.length, 2);
      expect(callRows.every((r) => (r['is_deleted'] as int?) == 1), isTrue);
      expect(
        callRows.every(
          (r) => (r['search_index'] as String?)?.isNotEmpty == true,
        ),
        isTrue,
      );
      expect(taskRows.every((r) => (r['is_deleted'] as int?) == 1), isTrue);
      expect(bulkAuditRows.length, 1);
    });

    test('cloneCall creates new unsent call with current datetime', () async {
      final sourceId = await insertCall(
        issue: 'clone-source',
        status: 'pending',
        date: '2000-01-01',
        time: '08:15',
        lansweeperState: 'sent',
        ticketId: '789',
      );

      final clonedId = await repo.cloneCall(sourceId);
      final cloned = await repo.getCallById(clonedId);
      final source = await repo.getCallById(sourceId);

      expect(clonedId, isNot(sourceId));
      expect(cloned, isNotNull);
      expect(cloned!.issue, source!.issue);
      expect(cloned.status, source.status);
      expect(cloned.date, isNot(source.date));
      expect(cloned.time, isNot(source.time));
      expect(cloned.lansweeperState, 'unsent');
      expect(cloned.lansweeperMainTicketId, isNull);
      expect(cloned.lansweeperLastSyncAt, isNull);
    });
  });
}
