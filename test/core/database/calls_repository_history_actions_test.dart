import 'package:call_logger/core/database/calls_deletion_repository.dart';
import 'package:call_logger/core/database/calls_lansweeper_repository.dart';
import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

void main() {
  group('CallsRepository history actions', () {
    late CallsRepository repo;
    late CallsDeletionRepository deletion;
    late CallsLansweeperRepository lansweeper;

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
      deletion = CallsDeletionRepository(db);
      lansweeper = CallsLansweeperRepository(db);
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      final db = await DatabaseHelper.instance.database;
      await db.delete('audit_log');
      repo = CallsRepository(db);
      deletion = CallsDeletionRepository(db);
      lansweeper = CallsLansweeperRepository(db);
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

      expect(await deletion.getTasksCountLinkedToCalls([call1]), 1);
      expect(await deletion.getTasksCountLinkedToCalls([call2]), 1);
      expect(await deletion.getTasksCountLinkedToCalls([call1, call2]), 2);
      expect(await deletion.getTasksCountLinkedToCalls(const []), 0);
    });

    test(
      'deleteCallWithTasksAction cascade soft-deletes tasks and call',
      () async {
        final callId = await insertCall(issue: 'cascade');
        await insertTask(callId: callId, title: 'task-a');
        await insertTask(callId: callId, title: 'task-b');

        await deletion.deleteCallWithTasksAction(callId, 'cascade');

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

      await deletion.deleteCallWithTasksAction(callId, 'nullify');

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

    test('hard delete removes call and external links', () async {
      final callId = await insertCall(
        issue: 'hard',
        lansweeperState: 'sent',
        ticketId: '123',
      );
      await lansweeper.addExternalLink(
        callId: callId,
        externalId: '123',
        provider: 'lansweeper',
      );

      await deletion.deleteCallWithTasksAction(callId, 'nullify', hard: true);

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

    test('hard delete honours the cascade choice for linked tasks', () async {
      final callId = await insertCall(issue: 'hard-cascade');
      await insertTask(callId: callId, title: 'task-cascade');

      await deletion.deleteCallWithTasksAction(callId, 'cascade', hard: true);

      final db = await DatabaseHelper.instance.database;
      final callRows = await db.query(
        'calls',
        where: 'id = ?',
        whereArgs: [callId],
      );
      // Ο δεσμός σβήνει μόνος του (ON DELETE SET NULL): η αναζήτηση γίνεται με
      // τον τίτλο, γιατί μετά τη διαγραφή δεν υπάρχει πια `call_id` να δείξει.
      final taskRows = await db.query(
        'tasks',
        columns: ['call_id', 'is_deleted'],
        where: 'title = ?',
        whereArgs: ['task-cascade'],
      );
      expect(callRows, isEmpty);
      expect(taskRows.single['is_deleted'], 1);
      expect(taskRows.single['call_id'], isNull);
    });

    test('hard delete honours the nullify choice for linked tasks', () async {
      final callId = await insertCall(issue: 'hard-nullify');
      await insertTask(callId: callId, title: 'task-nullify');

      await deletion.deleteCallWithTasksAction(callId, 'nullify', hard: true);

      final db = await DatabaseHelper.instance.database;
      final orphanRows = await db.query(
        'tasks',
        where: 'call_id = ?',
        whereArgs: [callId],
      );
      final taskRows = await db.query(
        'tasks',
        columns: ['call_id', 'is_deleted'],
        where: 'title = ?',
        whereArgs: ['task-nullify'],
      );
      expect(orphanRows, isEmpty);
      expect(taskRows.single['call_id'], isNull);
      expect(taskRows.single['is_deleted'], 0);
    });

    test('deletion impact reports tasks and lansweeper links', () async {
      final callId = await insertCall(
        issue: 'impact',
        lansweeperState: 'sent',
        ticketId: '5102',
      );
      await insertTask(callId: callId, title: 'impact-task');
      await insertTask(callId: callId, isDeleted: true, title: 'impact-gone');
      await lansweeper.addExternalLink(
        callId: callId,
        externalId: '5102',
        provider: 'lansweeper',
      );
      await lansweeper.addExternalLink(
        callId: callId,
        externalId: '5067',
        provider: 'lansweeper',
      );

      final impact = await deletion.getCallDeletionImpact([callId]);

      expect(impact.linkedTasks, 1);
      expect(impact.taskTitles, ['impact-task']);
      expect(impact.externalLinks, 2);
      expect(impact.lansweeperTicketIds, ['5067', '5102']);
    });

    test('deletion impact de-duplicates repeated ticket ids', () async {
      final callId = await insertCall(issue: 'impact-dupes');
      await lansweeper.addExternalLink(
        callId: callId,
        externalId: '5067',
        provider: 'lansweeper',
      );
      await lansweeper.addExternalLink(
        callId: callId,
        externalId: '5067',
        provider: 'lansweeper',
      );

      final impact = await deletion.getCallDeletionImpact([callId]);

      expect(impact.externalLinks, 2);
      expect(impact.lansweeperTicketIds, ['5067']);
    });

    test('deletion impact groups connections per call, newest first', () async {
      final older = await insertCall(issue: 'older', date: '2026-08-01');
      final newer = await insertCall(
        issue: 'newer',
        date: '2026-08-03',
        lansweeperState: 'sent',
        ticketId: '7001',
      );
      await insertTask(callId: older, title: 'older-task');
      await lansweeper.addExternalLink(
        callId: newer,
        externalId: '7001',
        provider: 'lansweeper',
      );

      final impact = await deletion.getCallDeletionImpact([older, newer]);

      expect(impact.calls.map((c) => c.callId), [newer, older]);
      expect(impact.calls.first.lansweeperTicketIds, ['7001']);
      expect(impact.calls.first.taskTitles, isEmpty);
      expect(impact.calls.last.taskTitles, ['older-task']);
      expect(impact.calls.last.externalLinks, 0);
      expect(impact.totalConnections, 2);
    });

    test('deletion impact separates calls without connections', () async {
      final connected = await insertCall(issue: 'connected');
      final bare = await insertCall(issue: 'bare');
      await insertTask(callId: connected, title: 'only-task');

      final impact = await deletion.getCallDeletionImpact([connected, bare]);

      expect(impact.calls, hasLength(2));
      expect(impact.connectedCalls.map((c) => c.callId), [connected]);
    });

    test('deletion impact is empty for an empty selection', () async {
      final impact = await deletion.getCallDeletionImpact(const []);

      expect(impact.linkedTasks, 0);
      expect(impact.externalLinks, 0);
      expect(impact.lansweeperTicketIds, isEmpty);
    });

    test('bulk soft delete cascades tasks and writes one bulk audit', () async {
      final call1 = await insertCall(issue: 'bulk1');
      final call2 = await insertCall(issue: 'bulk2');
      await insertTask(callId: call1, title: 'task-1');
      await insertTask(callId: call2, title: 'task-2');

      await deletion.bulkDeleteCalls([call1, call2], taskAction: 'cascade');

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

    test('bulk hard delete removes calls, tasks choice and links', () async {
      final call1 = await insertCall(
        issue: 'bulk-hard-1',
        lansweeperState: 'sent',
        ticketId: '7001',
      );
      final call2 = await insertCall(issue: 'bulk-hard-2');
      await insertTask(callId: call1, title: 'bulk-hard-task');
      await lansweeper.addExternalLink(
        callId: call1,
        externalId: '7001',
        provider: 'lansweeper',
      );

      await deletion.bulkDeleteCalls(
        [call1, call2],
        taskAction: 'cascade',
        hard: true,
      );

      final db = await DatabaseHelper.instance.database;
      final callRows = await db.query(
        'calls',
        where: 'id IN (?, ?)',
        whereArgs: [call1, call2],
      );
      final linkRows = await db.query(
        'call_external_links',
        where: 'call_id = ?',
        whereArgs: [call1],
      );
      final taskRows = await db.query(
        'tasks',
        columns: ['is_deleted'],
        where: 'title = ?',
        whereArgs: ['bulk-hard-task'],
      );

      expect(callRows, isEmpty);
      expect(linkRows, isEmpty);
      expect(taskRows.single['is_deleted'], 1);
    });

    test('bulk hard delete records what each call held', () async {
      final call1 = await insertCall(
        issue: 'audit-1',
        lansweeperState: 'sent',
        ticketId: '7001',
      );
      final call2 = await insertCall(issue: 'audit-2');

      await deletion.bulkDeleteCalls(
        [call1, call2],
        taskAction: 'nullify',
        hard: true,
      );

      final db = await DatabaseHelper.instance.database;
      final perCallRows = await db.query(
        'audit_log',
        where: 'action = ? AND entity_type = ?',
        whereArgs: [DatabaseHelper.auditActionDelete, 'call'],
      );
      final bulkRows = await db.query(
        'audit_log',
        where: 'action = ?',
        whereArgs: [DatabaseHelper.auditActionBulkDelete],
      );

      // Μία εγγραφή ανά κλήση: μόνο εκεί χωρούν τα `oldValues` της καθεμιάς.
      // Με μία συγκεντρωτική, ο αριθμός εισιτηρίου θα χανόταν για πάντα.
      expect(perCallRows, hasLength(2));
      expect(bulkRows, isEmpty);
      final withTicket = perCallRows.singleWhere(
        (r) => (r['old_values_json'] as String?)?.contains('7001') ?? false,
      );
      expect(withTicket['entity_id'], call1);
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
