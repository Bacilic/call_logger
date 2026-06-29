import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/old_database/lamp_issue_resolution_service.dart';
import 'package:call_logger/features/lamp/services/lamp_migration_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

void main() {
  group('Lamp owner matching unified identity', () {
    late LampMigrationService migrationService;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('lamp_owner_match_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/lamp_owner_match.db');
      await DatabaseHelper.instance.database;
      migrationService = LampMigrationService();
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      final db = await DatabaseHelper.instance.database;
      await db.delete('user_equipment');
      await db.delete('user_phones');
      await db.delete('phones');
      await db.delete('equipment');
      await db.delete('users');
      await db.delete('departments');
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Future<int> insertDepartment(String name) async {
      final db = await DatabaseHelper.instance.database;
      return db.insert('departments', {
        'name': name,
        'name_key': name.toLowerCase(),
        'is_deleted': 0,
      });
    }

    test('auto-select and isExact agree on reversed full name', () async {
      final db = await DatabaseHelper.instance.database;
      final userId = await db.insert('users', {
        'first_name': 'Γιώργος',
        'last_name': 'Παπαδόπουλος',
        'is_deleted': 0,
      });

      final draft = await migrationService.buildDraft(
        target: LampTransferTarget.owner,
        sourceRow: {
          'first_name': '',
          'last_name': '',
          'owner_original_text': 'Παπαδόπουλος Γιώργος',
        },
      );

      expect(draft.selectedCandidateId, userId);
      expect(draft.candidates, isNotEmpty);
      final candidate = draft.candidates.firstWhere((c) => c.id == userId);
      expect(candidate.isExact, isTrue);
    });

    test('single surname auto-selects existing user', () async {
      final db = await DatabaseHelper.instance.database;
      final userId = await db.insert('users', {
        'first_name': '',
        'last_name': 'Παπαδόπουλος',
        'is_deleted': 0,
      });

      final draft = await migrationService.buildDraft(
        target: LampTransferTarget.owner,
        sourceRow: {
          'owner_original_text': 'Παπαδόπουλος',
        },
      );

      expect(draft.selectedCandidateId, userId);
    });

    test('department-aware scoring prefers same department homonym', () {
      final resolution = LampIssueResolutionService();
      const label = 'Γιώργος Παπαδόπουλος';

      final sameDept = resolution.similarityConfidenceScore(
        'Παπαδόπουλος',
        label,
        sourceDepartment: 'Τμήμα IT',
        candidateDepartment: 'Τμήμα IT',
      );
      final otherDept = resolution.similarityConfidenceScore(
        'Παπαδόπουλος',
        label,
        sourceDepartment: 'Τμήμα IT',
        candidateDepartment: 'Τμήμα HR',
      );

      expect(sameDept, LampIssueResolutionService.substringContainmentConfidence);
      expect(otherDept, isNot(LampIssueResolutionService.substringContainmentConfidence));
      expect(sameDept, greaterThan(otherDept));
    });

    test('homonym ranking in migration candidates respects department', () async {
      final deptIt = await insertDepartment('Τμήμα IT');
      final deptHr = await insertDepartment('Τμήμα HR');
      final db = await DatabaseHelper.instance.database;
      await db.insert('users', {
        'first_name': 'Γιώργος',
        'last_name': 'Παπαδόπουλος',
        'department_id': deptHr,
        'is_deleted': 0,
      });
      final userIt = await db.insert('users', {
        'first_name': 'Γιώργος',
        'last_name': 'Παπαδόπουλος',
        'department_id': deptIt,
        'is_deleted': 0,
      });

      final draft = await migrationService.buildDraft(
        target: LampTransferTarget.owner,
        sourceRow: {
          'owner_original_text': 'Παπαδόπουλος',
          'office_name': 'Τμήμα IT',
        },
      );

      expect(draft.candidates, isNotEmpty);
      expect(draft.candidates.first.id, userIt);
    });

    test('substring containment confidence is defined in one place', () {
      expect(LampIssueResolutionService.substringContainmentConfidence, 72);
    });
  });
}
