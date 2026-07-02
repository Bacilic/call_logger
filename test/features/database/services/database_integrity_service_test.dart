import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_v1_schema.dart';
import 'package:call_logger/features/database/models/database_integrity_finding.dart';
import 'package:call_logger/features/database/models/database_integrity_report.dart';
import 'package:call_logger/features/database/services/database_integrity_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../test_setup.dart';

void main() {
  group('DatabaseIntegrityService', () {
    late DatabaseIntegrityService service;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('integrity_test_');
      await DatabaseHelper.bindTestDatabaseFile(
        '${dir.path}/integrity.db',
      );
      await DatabaseHelper.instance.database;
      service = DatabaseIntegrityService();
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

    test('PRAGMA quick_check runs first and passes on clean database', () async {
      final progressSteps = <int>[];
      final checkNames = <String>[];

      final report = await service.runChecks(
        onProgress: (p) {
          progressSteps.add(p.currentStep);
          checkNames.add(p.currentCheckName);
        },
      );

      expect(checkNames.first, 'Έλεγχος SQLite (PRAGMA)');
      expect(
        report.findings.where(
          (f) =>
              f.category == IntegrityCategory.technicalFlow &&
              f.title.contains('PRAGMA'),
        ),
        isEmpty,
      );
      expect(progressSteps, equals(List.generate(19, (i) => i + 1)));
    });

    test('detects orphan phone without user or department link', () async {
      final db = await DatabaseHelper.instance.database;
      await db.insert('phones', {'number': '9999', 'is_deleted': 0});

      final report = await service.runChecks();
      final orphanFindings = report.findings
          .where((f) => f.title == 'Ορφανό τηλέφωνο')
          .toList();

      expect(orphanFindings, hasLength(1));
      expect(orphanFindings.first.severity, IntegritySeverity.warning);
      expect(orphanFindings.first.category, IntegrityCategory.referential);
      expect(orphanFindings.first.checkType, IntegrityCheckType.orphanPhone);
      expect(orphanFindings.first.context['phone_id'], isNotNull);
    });

    test('detects call without search_index', () async {
      final db = await DatabaseHelper.instance.database;
      await db.insert('calls', {
        'phone_text': '1000',
        'status': 'completed',
        'search_index': '',
        'lansweeper_state': 'unsent',
        'is_deleted': 0,
      });

      final report = await service.runChecks();
      expect(
        report.findings.any((f) => f.title == 'Κλήση χωρίς ευρετήριο αναζήτησης'),
        isTrue,
      );
    });

    test('detects task with non-existent call_id via LEFT JOIN', () async {
      final db = await DatabaseHelper.instance.database;
      final now = DateTime.now().toIso8601String();
      await db.insert('tasks', {
        'title': 'orphan task',
        'status': 'open',
        'call_id': 99999,
        'search_index': 'test',
        'created_at': now,
        'updated_at': now,
        'is_deleted': 0,
      });

      final report = await service.runChecks();
      final findings = report.findings
          .where((f) => f.title == 'Εκκρεμότητα με άκυρη κλήση')
          .toList();

      expect(findings, hasLength(1));
      expect(findings.first.severity, IntegritySeverity.critical);
    });

    test('detects task linked to soft-deleted call via LEFT JOIN', () async {
      final db = await DatabaseHelper.instance.database;
      final callId = await db.insert('calls', {
        'phone_text': '2000',
        'status': 'completed',
        'search_index': 'idx',
        'lansweeper_state': 'unsent',
        'is_deleted': 1,
      });
      final now = DateTime.now().toIso8601String();
      await db.insert('tasks', {
        'title': 'deleted call task',
        'status': 'open',
        'call_id': callId,
        'search_index': 'test',
        'created_at': now,
        'updated_at': now,
        'is_deleted': 0,
      });

      final report = await service.runChecks();
      expect(
        report.findings.any((f) => f.title == 'Εκκρεμότητα με άκυρη κλήση'),
        isTrue,
      );
    });

    test('detects user with non-existent department_id via LEFT JOIN', () async {
      final db = await DatabaseHelper.instance.database;
      await db.insert('users', {
        'first_name': 'Test',
        'last_name': 'Orphan',
        'department_id': 99999,
        'is_deleted': 0,
      });

      final report = await service.runChecks();
      final findings = report.findings
          .where((f) => f.title == 'Χρήστης με άκυρο τμήμα')
          .toList();

      expect(findings, hasLength(1));
      expect(findings.first.severity, IntegritySeverity.critical);
    });

    test('detects department with mismatched name_key', () async {
      final db = await DatabaseHelper.instance.database;
      await db.insert('departments', {
        'name': 'Νέο Τμήμα',
        'name_key': 'wrong_key',
        'is_deleted': 0,
      });

      final report = await service.runChecks();
      expect(
        report.findings.any(
          (f) => f.title == 'Τμήμα με μη συμβαδίζον name_key',
        ),
        isTrue,
      );
    });

    test('detects department with empty name_key', () async {
      final db = await DatabaseHelper.instance.database;
      await db.rawInsert('''
INSERT INTO departments (name, name_key, is_deleted)
VALUES ('Κενό κλειδί', '', 0)
''');

      final report = await service.runChecks();
      expect(
        report.findings.any((f) => f.title == 'Τμήμα με κενό name_key'),
        isTrue,
      );
    });

    test('onProgress reports increasing steps and row counts', () async {
      final db = await DatabaseHelper.instance.database;
      await db.insert('phones', {'number': '8888', 'is_deleted': 0});

      final progress = <DatabaseIntegrityProgress>[];
      await service.runChecks(
        onProgress: (p) => progress.add(p),
      );

      expect(progress, hasLength(19));
      expect(progress.first.currentStep, 1);
      expect(progress.last.currentStep, 19);
      expect(progress.first.totalSteps, 19);
      expect(
        progress.any((p) => p.currentCheckName == 'Ορφανά τηλέφωνα'),
        isTrue,
      );
      final orphanStep = progress.firstWhere(
        (p) => p.currentCheckName == 'Ορφανά τηλέφωνα',
      );
      expect(orphanStep.totalRowsChecked, greaterThan(0));
    });

    test('clean seeded database has no critical referential findings', () async {
      final report = await service.runChecks();
      final criticalReferential = report.findings.where(
        (f) =>
            f.severity == IntegritySeverity.critical &&
            f.category == IntegrityCategory.referential,
      );
      expect(criticalReferential, isEmpty);
    });

    test('orphan user_equipment shows employee name and equipment code', () async {
      final db = await DatabaseHelper.instance.database;
      final userId = await db.insert('users', {
        'first_name': 'Γιάννης',
        'last_name': 'Παπαδόπουλος',
        'department_id': null,
        'is_deleted': 1,
      });
      final equipmentId = await db.insert('equipment', {
        'code_equipment': 'PC-LAP-001',
        'is_deleted': 0,
      });
      await db.insert('user_equipment', {
        'user_id': userId,
        'equipment_id': equipmentId,
      });

      final report = await service.runChecks();
      final findings = report.findings
          .where((f) => f.title == 'Ορφανή συσχέτιση χρήστη–εξοπλισμού')
          .toList();

      expect(findings, hasLength(1));
      expect(findings.first.description, contains('Παπαδόπουλος Γιάννης (id=$userId)'));
      expect(findings.first.description, contains('PC-LAP-001 (id=$equipmentId)'));
      expect(findings.first.description, isNot(contains('user_id=')));
      expect(findings.first.description, isNot(contains('equipment_id=')));
    });

    test('runCheck targets single check type', () async {
      final db = await DatabaseHelper.instance.database;
      await db.insert('phones', {'number': '7777', 'is_deleted': 0});

      final findings = await service.runCheck(IntegrityCheckType.orphanPhone);
      expect(findings, isNotEmpty);
      expect(findings.every((f) => f.checkType == IntegrityCheckType.orphanPhone), isTrue);
    });

    test('flags only hard-missing call references, not soft-deleted', () async {
      final db = await DatabaseHelper.instance.database;
      // Soft-deleted αναφορά: ΔΕΝ είναι εύρημα (ιστορική αλήθεια).
      final softDeletedUserId = await db.insert('users', {
        'first_name': 'Del',
        'last_name': 'User',
        'is_deleted': 1,
      });
      await db.insert('calls', {
        'phone_text': '3001',
        'status': 'completed',
        'search_index': 'idx soft',
        'lansweeper_state': 'unsent',
        'caller_id': softDeletedUserId,
        'is_deleted': 0,
      });
      // Hard-missing αναφορές: εύρημα ανά πεδίο.
      await db.insert('calls', {
        'phone_text': '3000',
        'status': 'completed',
        'search_index': 'idx',
        'lansweeper_state': 'unsent',
        'caller_id': 990001,
        'equipment_id': 990002,
        'is_deleted': 0,
      });

      final findings = await service.runCheck(
        IntegrityCheckType.callsDeletedLinkedEntities,
      );
      expect(findings, hasLength(2));
      expect(
        findings.map((f) => f.context['invalidField']).toSet(),
        equals({'caller_id', 'equipment_id'}),
      );
      expect(
        findings.map((f) => f.context['invalidFkId']).toSet(),
        equals({990001, 990002}),
      );
    });

    test('junction finding includes both keys in context', () async {
      final db = await DatabaseHelper.instance.database;
      final userId = await db.insert('users', {
        'first_name': 'A',
        'last_name': 'B',
        'is_deleted': 1,
      });
      final phoneId = await db.insert('phones', {'number': '5555', 'is_deleted': 0});
      await db.insert('user_phones', {'user_id': userId, 'phone_id': phoneId});

      final findings = await service.runCheck(IntegrityCheckType.orphanUserPhones);
      expect(findings, hasLength(1));
      expect(findings.first.context['user_id'], userId);
      expect(findings.first.context['phone_id'], phoneId);
    });

    group('equipmentInvalidDepartment', () {
      test('detects equipment with hard-missing department_id', () async {
        final db = await DatabaseHelper.instance.database;
        final equipmentId = await db.insert('equipment', {
          'code_equipment': 'EQ-MISSING-DEPT',
          'department_id': 990301,
          'is_deleted': 0,
        });

        final findings = await service.runCheck(
          IntegrityCheckType.equipmentInvalidDepartment,
        );
        final mine = findings.where((f) => f.affectedId == equipmentId).toList();

        expect(mine, hasLength(1));
        expect(mine.first.severity, IntegritySeverity.critical);
        expect(mine.first.category, IntegrityCategory.referential);
        expect(mine.first.title, 'Εξοπλισμός με ανύπαρκτο τμήμα');
        expect(mine.first.context['department_id'], 990301);
      });

      test('ignores equipment linked to soft-deleted department', () async {
        final db = await DatabaseHelper.instance.database;
        final deptId = await db.insert('departments', {
          'name': 'Soft Dept Eq',
          'name_key': 'soft_dept_eq',
          'is_deleted': 1,
        });
        final equipmentId = await db.insert('equipment', {
          'code_equipment': 'EQ-SOFT-DEPT',
          'department_id': deptId,
          'is_deleted': 0,
        });

        final findings = await service.runCheck(
          IntegrityCheckType.equipmentInvalidDepartment,
        );
        expect(findings.where((f) => f.affectedId == equipmentId), isEmpty);
      });
    });

    group('departmentInvalidFloor', () {
      test('detects department with hard-missing floor_id', () async {
        final db = await DatabaseHelper.instance.database;
        final deptId = await db.insert('departments', {
          'name': 'Dept Missing Floor',
          'name_key': 'dept_missing_floor',
          'floor_id': 990201,
          'map_x': 10.0,
          'map_y': 20.0,
          'is_deleted': 0,
        });

        final findings = await service.runCheck(
          IntegrityCheckType.departmentInvalidFloor,
        );
        final mine = findings.where((f) => f.affectedId == deptId).toList();

        expect(mine, hasLength(1));
        expect(mine.first.severity, IntegritySeverity.warning);
        expect(mine.first.category, IntegrityCategory.referential);
        expect(mine.first.title, 'Τμήμα με ανύπαρκτο όροφο χάρτη');
        expect(mine.first.context['floor_id'], 990201);
      });
    });

    group('phoneInvalidDepartment', () {
      test('detects phone with hard-missing department_id', () async {
        final db = await DatabaseHelper.instance.database;
        final phoneId = await db.insert('phones', {
          'number': '6999-missing-dept',
          'department_id': 990101,
          'is_deleted': 0,
        });

        final findings = await service.runCheck(
          IntegrityCheckType.phoneInvalidDepartment,
        );
        final mine = findings.where((f) => f.affectedId == phoneId).toList();

        expect(mine, hasLength(1));
        expect(mine.first.severity, IntegritySeverity.critical);
        expect(mine.first.category, IntegrityCategory.referential);
        expect(mine.first.title, 'Τηλέφωνο με ανύπαρκτο τμήμα');
        expect(mine.first.context['department_id'], 990101);
      });

      test('ignores phone linked to soft-deleted department', () async {
        final db = await DatabaseHelper.instance.database;
        final deptId = await db.insert('departments', {
          'name': 'Soft Dept Phone',
          'name_key': 'soft_dept_phone',
          'is_deleted': 1,
        });
        final phoneId = await db.insert('phones', {
          'number': '6999-soft-dept',
          'department_id': deptId,
          'is_deleted': 0,
        });

        final findings = await service.runCheck(
          IntegrityCheckType.phoneInvalidDepartment,
        );
        expect(findings.where((f) => f.affectedId == phoneId), isEmpty);
      });

      test('does not flag orphan phone without department', () async {
        final db = await DatabaseHelper.instance.database;
        final phoneId = await db.insert('phones', {
          'number': '6999-orphan-only',
          'department_id': null,
          'is_deleted': 0,
        });

        final invalidDeptFindings = await service.runCheck(
          IntegrityCheckType.phoneInvalidDepartment,
        );
        expect(invalidDeptFindings.where((f) => f.affectedId == phoneId), isEmpty);

        final orphanFindings = await service.runCheck(
          IntegrityCheckType.orphanPhone,
        );
        expect(orphanFindings.any((f) => f.affectedId == phoneId), isTrue);
      });
    });
  });

  group('DatabaseIntegrityReport.toMarkdown', () {
    test('groups findings by category and severity with summary', () {
      final report = DatabaseIntegrityReport(
        checkedAt: DateTime(2026, 6, 8, 12, 0),
        schemaVersion: databaseSchemaVersionV1,
        findings: const [
          DatabaseIntegrityFinding(
            severity: IntegritySeverity.critical,
            category: IntegrityCategory.referential,
            checkType: IntegrityCheckType.tasksInvalidCall,
            title: 'Κρίσιμο A',
            description: 'Περιγραφή A',
            affectedId: 1,
            affectedEntity: 'tasks',
          ),
          DatabaseIntegrityFinding(
            severity: IntegritySeverity.warning,
            category: IntegrityCategory.searchIndex,
            checkType: IntegrityCheckType.callsMissingSearchIndex,
            title: 'Προειδοποίηση B',
            description: 'Περιγραφή B',
            affectedId: 2,
            affectedEntity: 'calls',
          ),
        ],
      );

      final md = report.toMarkdown();
      expect(md, contains('# Έκθεση ακεραιότητας βάσης δεδομένων'));
      expect(md, contains('## Αναφορές / ορφανές συσχετίσεις'));
      expect(md, contains('### Κρίσιμο'));
      expect(md, contains('## Ευρετήριο αναζήτησης'));
      expect(md, contains('### Προειδοποίηση'));
      expect(md, contains('## Σύνοψη'));
      expect(md, contains('**Κρίσιμα:** 1'));
      expect(md, contains('**Προειδοποιήσεις:** 1'));
      expect(md, contains('Εκκρεμότητες #1'));
      expect(md, contains('Κλήσεις #2'));    });

    test('reports no issues when findings empty', () {
      final report = DatabaseIntegrityReport(
        checkedAt: DateTime.now(),
        schemaVersion: databaseSchemaVersionV1,
        findings: const [],
      );
      expect(report.hasFindings, isFalse);
      expect(report.toMarkdown(), contains('Δεν εντοπίστηκαν προβλήματα'));
    });
  });
}
