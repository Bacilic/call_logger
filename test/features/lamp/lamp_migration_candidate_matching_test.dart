import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/old_database/lamp_issue_resolution_service.dart';
import 'package:call_logger/features/lamp/services/lamp_migration_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

class _LowConfidenceResolutionService extends LampIssueResolutionService {
  @override
  int similarityConfidenceScore(
    String source,
    String candidate, {
    String? sourceDepartment,
    String? candidateDepartment,
  }) {
    return 25;
  }
}

void main() {
  group('Lamp migration Top-3 candidate matching', () {
    late LampMigrationService migrationService;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('lamp_candidate_match_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/lamp_candidate_match.db');
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

    Future<void> seedNoiseUsers() async {
      final db = await DatabaseHelper.instance.database;
      await db.insert('users', {
        'first_name': 'Άννα',
        'last_name': 'Πατσαρίκα',
        'is_deleted': 0,
      });
      await db.insert('users', {
        'first_name': '---',
        'last_name': 'ΑΓΝΩΣΤΟ ---',
        'is_deleted': 0,
      });
      await db.insert('users', {
        'first_name': 'Έντμοντ',
        'last_name': 'Χαλίλ',
        'is_deleted': 0,
      });
    }

    test('χωρίς παρόμοιο υποψήφιο → κενή λίστα προτάσεων', () async {
      await seedNoiseUsers();

      final draft = await migrationService.buildDraft(
        target: LampTransferTarget.owner,
        sourceRow: {
          'owner_original_text': 'Ξενογλωσσος Τυχαιος Χρηστης Αλφα',
        },
      );

      expect(draft.candidates, isEmpty);
      expect(draft.selectedCandidateId, isNull);
    });

    test('ακριβής ταύτιση εμφανίζεται ακόμη κάτω από κατώφλι confidence', () async {
      await seedNoiseUsers();
      final db = await DatabaseHelper.instance.database;
      final userId = await db.insert('users', {
        'first_name': 'Γιώργος',
        'last_name': 'Παπαδόπουλος',
        'is_deleted': 0,
      });

      const source = 'Παπαδόπουλος Γιώργος';
      final lowScoreMigration = LampMigrationService(
        resolutionService: _LowConfidenceResolutionService(),
      );

      final draft = await lowScoreMigration.buildDraft(
        target: LampTransferTarget.owner,
        sourceRow: {
          'owner_original_text': source,
        },
      );

      expect(
        draft.candidates.any((c) => c.id == userId && c.isExact),
        isTrue,
        reason: 'Ο ακριβής υποψήφιος πρέπει να εμφανίζεται παρά το χαμηλό fuzzy σκορ',
      );
      expect(
        draft.candidates.every(
          (c) =>
              c.isExact ||
              c.confidence >= LampMigrationService.kSuggestionConfidenceThreshold,
        ),
        isTrue,
      );
    });
  });
}
