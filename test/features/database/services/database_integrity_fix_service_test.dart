import 'dart:io';

import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/audit_service.dart';
import 'package:call_logger/features/database/models/database_integrity_finding.dart';
import 'package:call_logger/features/database/models/integrity_fix_models.dart';
import 'package:call_logger/features/database/services/database_integrity_fix_service.dart';
import 'package:call_logger/features/database/services/database_integrity_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../test_setup.dart';

void main() {
  group('DatabaseIntegrityFixService', () {
    late DatabaseIntegrityFixService fixService;
    late DatabaseIntegrityService checkService;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('integrity_fix_test_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/integrity_fix.db');
      await DatabaseHelper.instance.database;
      fixService = DatabaseIntegrityFixService();
      checkService = DatabaseIntegrityService();
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      final db = await DatabaseHelper.instance.database;
      await db.delete('call_external_links');
      await db.delete('department_phones');
      await db.delete('audit_log');
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    test('junction cleanup removes orphan user_phones row', () async {
      final db = await DatabaseHelper.instance.database;
      final userId = await db.insert('users', {
        'first_name': 'X',
        'last_name': 'Y',
        'is_deleted': 1,
      });
      final phoneId = await db.insert('phones', {'number': '1111', 'is_deleted': 0});
      await db.insert('user_phones', {'user_id': userId, 'phone_id': phoneId});

      final before = await checkService.runCheck(IntegrityCheckType.orphanUserPhones);
      expect(before, hasLength(1));

      final result = await fixService.applyFix(
        before.first,
        const IntegrityFixConfirm(),
      );
      expect(result.success, isTrue);

      final after = await checkService.runCheck(IntegrityCheckType.orphanUserPhones);
      expect(after, isEmpty);

      final junction = await db.query(
        'user_phones',
        where: 'user_id = ? AND phone_id = ?',
        whereArgs: [userId, phoneId],
      );
      expect(junction, isEmpty);
    });

    test('rebuilds call search_index', () async {
      final db = await DatabaseHelper.instance.database;
      final callId = await db.insert('calls', {
        'phone_text': '4000',
        'status': 'completed',
        'search_index': '',
        'lansweeper_state': 'unsent',
        'is_deleted': 0,
      });

      final findings = await checkService.runCheck(
        IntegrityCheckType.callsMissingSearchIndex,
      );
      expect(findings, hasLength(1));

      final result = await fixService.applyFix(
        findings.first,
        const IntegrityFixConfirm(),
      );
      expect(result.success, isTrue);

      final row = await db.query('calls', where: 'id = ?', whereArgs: [callId]);
      final si = row.first['search_index'] as String?;
      expect(si, isNotNull);
      expect(si!.trim(), isNotEmpty);
    });

    test('rebuilds task search_index', () async {
      final db = await DatabaseHelper.instance.database;
      final now = DateTime.now().toIso8601String();
      final taskId = await db.insert('tasks', {
        'title': 'fix index task',
        'status': 'open',
        'search_index': '',
        'created_at': now,
        'updated_at': now,
        'is_deleted': 0,
      });

      final findings = await checkService.runCheck(
        IntegrityCheckType.tasksMissingSearchIndex,
      );
      final mine = findings.where((f) => f.affectedId == taskId).toList();
      expect(mine, hasLength(1));

      final result = await fixService.applyFix(
        mine.first,
        const IntegrityFixConfirm(),
      );
      expect(result.success, isTrue);

      final row = await db.query('tasks', where: 'id = ?', whereArgs: [taskId]);
      final si = row.first['search_index'] as String?;
      expect(si, isNotNull);
      expect(si!.trim(), isNotEmpty);
    });

    test('syncs task temporal inconsistency', () async {
      final db = await DatabaseHelper.instance.database;
      final created = '2026-06-10T12:00:00.000';
      final updated = '2026-06-09T12:00:00.000';
      final taskId = await db.insert('tasks', {
        'title': 'temporal task',
        'status': 'open',
        'search_index': 'x',
        'created_at': created,
        'updated_at': updated,
        'is_deleted': 0,
      });

      final findings = await checkService.runCheck(
        IntegrityCheckType.tasksTemporalInconsistency,
      );
      final mine = findings.where((f) => f.affectedId == taskId).toList();
      expect(mine, hasLength(1));

      final result = await fixService.applyFix(
        mine.first,
        const IntegrityFixConfirm(),
      );
      expect(result.success, isTrue);

      final row = await db.query('tasks', where: 'id = ?', whereArgs: [taskId]);
      expect(row.first['updated_at'], created);
    });

    test('fixes department name_key', () async {
      final db = await DatabaseHelper.instance.database;
      final deptId = await db.insert('departments', {
        'name': 'Νέο Τμήμα Fix',
        'name_key': 'wrong',
        'is_deleted': 0,
      });

      final findings = await checkService.runCheck(
        IntegrityCheckType.departmentsInvalidNameKey,
      );
      final mine = findings.where((f) => f.affectedId == deptId).toList();
      expect(mine, hasLength(1));

      final result = await fixService.applyFix(
        mine.first,
        const IntegrityFixConfirm(),
      );
      expect(result.success, isTrue);

      final row = await db.query('departments', where: 'id = ?', whereArgs: [deptId]);
      expect(row.first['name_key'], mine.first.context['expectedNameKey']);
    });

    test('rebuilds audit search_text', () async {
      final db = await DatabaseHelper.instance.database;
      final auditId = await db.insert('audit_log', {
        'action': 'TEST',
        'timestamp': DateTime.now().toIso8601String(),
        'user_performing': 'tester',
        'details': 'δοκιμή audit',
        'entity_type': AuditEntityTypes.user,
        'entity_id': 1,
        'entity_name': 'Test User',
        'search_text': '',
      });

      final findings = await checkService.runCheck(
        IntegrityCheckType.auditMissingSearchText,
      );
      final mine = findings.where((f) => f.affectedId == auditId).toList();
      expect(mine, hasLength(1));

      final result = await fixService.applyFix(
        mine.first,
        const IntegrityFixConfirm(),
      );
      expect(result.success, isTrue);

      final row = await db.query('audit_log', where: 'id = ?', whereArgs: [auditId]);
      final st = row.first['search_text'] as String?;
      expect(st, isNotNull);
      expect(st!.trim(), isNotEmpty);
    });

    test('pragma finding rejects inline fix', () async {
      const finding = DatabaseIntegrityFinding(
        severity: IntegritySeverity.critical,
        category: IntegrityCategory.technicalFlow,
        checkType: IntegrityCheckType.pragmaQuickCheck,
        title: 'PRAGMA fail',
        description: 'corrupt',
      );
      final result = await fixService.applyFix(
        finding,
        const IntegrityFixConfirm(),
      );
      expect(result, isA<IntegrityFixFailure>());
    });

    test('single task deleted FK fix clears only one field', () async {
      final db = await DatabaseHelper.instance.database;
      final now = DateTime.now().toIso8601String();
      final taskId = await db.insert('tasks', {
        'title': 'Multi invalid FK task',
        'status': 'open',
        'search_index': 'multi invalid fk',
        'caller_id': 990011,
        'equipment_id': 990012,
        'department_id': 990013,
        'phone_id': 990014,
        'created_at': now,
        'updated_at': now,
        'is_deleted': 0,
      });

      final findings = await checkService.runCheck(
        IntegrityCheckType.tasksDeletedLinkedEntities,
      );
      expect(findings, hasLength(4));
      expect(
        findings.map((f) => f.findingKey).toSet(),
        hasLength(4),
        reason: 'κάθε ανύπαρκτο πεδίο πρέπει να έχει μοναδικό findingKey',
      );

      final callerFinding = findings.firstWhere(
        (f) => f.context['invalidField'] == 'caller_id',
      );
      final result = await fixService.applyFix(
        callerFinding,
        const IntegrityFixConfirm(),
      );
      expect(result, isA<IntegrityFixSuccess>());

      final row = await db.query('tasks', where: 'id = ?', whereArgs: [taskId]);
      expect(row.first['caller_id'], isNull);
      expect(row.first['equipment_id'], 990012);
      expect(row.first['department_id'], 990013);
      expect(row.first['phone_id'], 990014);

      final after = await checkService.runCheck(
        IntegrityCheckType.tasksDeletedLinkedEntities,
      );
      expect(after, hasLength(3));
      expect(
        after.map((f) => f.context['invalidField']).toSet(),
        equals({'equipment_id', 'department_id', 'phone_id'}),
      );
    });

    test('bulk fix creates separate audit entries', () async {
      final db = await DatabaseHelper.instance.database;
      final userId1 = await db.insert('users', {
        'first_name': 'A',
        'last_name': 'One',
        'is_deleted': 1,
      });
      final userId2 = await db.insert('users', {
        'first_name': 'B',
        'last_name': 'Two',
        'is_deleted': 1,
      });
      final phone1 = await db.insert('phones', {'number': '9001', 'is_deleted': 0});
      final phone2 = await db.insert('phones', {'number': '9002', 'is_deleted': 0});
      await db.insert('user_phones', {'user_id': userId1, 'phone_id': phone1});
      await db.insert('user_phones', {'user_id': userId2, 'phone_id': phone2});

      final findings = await checkService.runCheck(
        IntegrityCheckType.orphanUserPhones,
      );
      expect(findings.length, greaterThanOrEqualTo(2));

      final bulk = await fixService.applyBulkFix(findings);
      expect(bulk.successCount, findings.length);

      final auditRows = await db.query(
        'audit_log',
        where: 'action = ?',
        whereArgs: [DatabaseHelper.auditActionIntegrityFix],
      );
      expect(auditRows.length, greaterThanOrEqualTo(findings.length));
    });

    test('SQLITE_BUSY returns IntegrityFixLockFailure', () async {
      final db = await DatabaseHelper.instance.database;
      final callId = await db.insert('calls', {
        'phone_text': '5000',
        'status': 'completed',
        'search_index': '',
        'lansweeper_state': 'unsent',
        'is_deleted': 0,
      });

      final findings = await checkService.runCheck(
        IntegrityCheckType.callsMissingSearchIndex,
      );
      final mine = findings.where((f) => f.affectedId == callId).toList();
      expect(mine, hasLength(1));

      final lockingService = DatabaseIntegrityFixService(
        callsFactory: (database) => _LockingCallsRepository(database),
      );
      final result = await lockingService.applyFix(
        mine.first,
        const IntegrityFixConfirm(),
      );
      expect(result, isA<IntegrityFixLockFailure>());
      final lock = result as IntegrityFixLockFailure;
      expect(lock.dbPath, isNotEmpty);
    });

    test('user department fix audit contains human labels', () async {
      final db = await DatabaseHelper.instance.database;
      final deptId = await db.insert('departments', {
        'name': 'Κουζίνα',
        'name_key': 'κουζινα',
        'is_deleted': 0,
      });
      final userId = await db.insert('users', {
        'first_name': 'Μαρία',
        'last_name': 'Πανά',
        'department_id': null,
        'is_deleted': 0,
      });

      final findings = await checkService.runCheck(
        IntegrityCheckType.usersWithoutDepartment,
      );
      final mine = findings.where((f) => f.affectedId == userId).toList();
      expect(mine, hasLength(1));

      final result = await fixService.applyFix(
        mine.first,
        IntegrityFixAssignDepartment(deptId),
      );
      expect(result.success, isTrue);

      final auditRows = await db.query(
        'audit_log',
        where: 'action = ?',
        whereArgs: [DatabaseHelper.auditActionIntegrityFix],
        orderBy: 'id DESC',
        limit: 1,
      );
      expect(auditRows, isNotEmpty);
      final details = auditRows.first['details'] as String? ?? '';
      expect(details, contains('Πανά'));
      expect(details, contains('Κουζίνα'));
    });

    test('soft deletes user without department', () async {
      final db = await DatabaseHelper.instance.database;
      final userId = await db.insert('users', {
        'first_name': 'Χωρίς',
        'last_name': 'Τμήμα',
        'department_id': null,
        'is_deleted': 0,
      });

      final findings = await checkService.runCheck(
        IntegrityCheckType.usersWithoutDepartment,
      );
      final mine = findings.where((f) => f.affectedId == userId).toList();
      expect(mine, hasLength(1));

      final result = await fixService.applyFix(
        mine.first,
        const IntegrityFixSoftDeleteUser(),
      );
      expect(result.success, isTrue);

      final row = await db.query('users', where: 'id = ?', whereArgs: [userId]);
      expect(row.first['is_deleted'], 1);

      final after = await checkService.runCheck(
        IntegrityCheckType.usersWithoutDepartment,
      );
      expect(after.where((f) => f.affectedId == userId), isEmpty);
    });
  });
}

class _LockingCallsRepository extends CallsRepository {
  _LockingCallsRepository(super.db);

  @override
  Future<void> rebuildSearchIndexForCallId(int callId) async {
    throw Exception('SqliteException(5): database is locked');
  }
}
