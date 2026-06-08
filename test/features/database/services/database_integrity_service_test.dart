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
      expect(progressSteps, equals(List.generate(16, (i) => i + 1)));
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

      expect(progress, hasLength(16));
      expect(progress.first.currentStep, 1);
      expect(progress.last.currentStep, 16);
      expect(progress.first.totalSteps, 16);
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
            title: 'Κρίσιμο A',
            description: 'Περιγραφή A',
            affectedId: 1,
            affectedEntity: 'tasks',
          ),
          DatabaseIntegrityFinding(
            severity: IntegritySeverity.warning,
            category: IntegrityCategory.searchIndex,
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
