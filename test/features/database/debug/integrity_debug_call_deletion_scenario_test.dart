import 'dart:io';

import 'package:call_logger/core/database/call_deletion_impact.dart';
import 'package:call_logger/core/database/calls_deletion_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/features/database/debug/integrity_debug_seeder_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../test_setup.dart';

void main() {
  group('IntegrityDebugSeeder · σενάριο διαγραφής κλήσης', () {
    late Database db;
    late IntegrityDebugSeederService seeder;
    late CallsDeletionRepository deletion;

    Future<int> callIdOf(String issue) async {
      final rows = await db.query(
        'calls',
        columns: ['id'],
        where: 'issue = ? AND COALESCE(is_deleted, 0) = 0',
        whereArgs: [issue],
      );
      expect(rows, hasLength(1), reason: 'κλήση «$issue»');
      return rows.first['id'] as int;
    }

    Future<CallDeletionImpact> impactOf(String issue) async {
      return deletion.getCallDeletionImpact([await callIdOf(issue)]);
    }

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp(
        'integrity_debug_call_deletion_',
      );
      await DatabaseHelper.bindTestDatabaseFile(
        '${dir.path}/integrity_debug_call_deletion.db',
      );
      db = await DatabaseHelper.instance.database;
      seeder = IntegrityDebugSeederService();
      deletion = CallsDeletionRepository(db);
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('call_external_links');
      await db.delete('tasks');
      await db.delete('calls');
      await db.transaction((txn) async {
        await seeder.insertCallDeletionScenario(txn);
      });
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    test('η πρώτη κλήση έχει εκκρεμότητα και κανέναν δεσμό', () async {
      final impact = await impactOf(
        IntegrityDebugSeederService.callDeletionTasksOnlyIssue,
      );

      expect(impact.linkedTasks, 1);
      expect(impact.externalLinks, 0);
      expect(impact.lansweeperTicketIds, isEmpty);
    });

    test('η δεύτερη κλήση έχει έναν δεσμό και καμία εκκρεμότητα', () async {
      final impact = await impactOf(
        IntegrityDebugSeederService.callDeletionLansweeperOnlyIssue,
      );

      expect(impact.linkedTasks, 0);
      expect(impact.externalLinks, 1);
      expect(impact.lansweeperTicketIds, [
        IntegrityDebugSeederService.callDeletionLansweeperOnlyTicket,
      ]);
    });

    test('η τρίτη κλήση έχει και εκκρεμότητες και δύο δεσμούς', () async {
      final impact = await impactOf(
        IntegrityDebugSeederService.callDeletionBothIssue,
      );

      expect(impact.linkedTasks, 2);
      expect(impact.externalLinks, 2);
      expect(
        impact.lansweeperTicketIds,
        IntegrityDebugSeederService.callDeletionBothTickets,
      );
    });

    test('η κλήση με εισιτήριο δηλώνεται περασμένη στο Lansweeper', () async {
      final rows = await db.query(
        'calls',
        columns: ['lansweeper_state', 'lansweeper_main_ticket_id'],
        where: 'issue = ?',
        whereArgs: [
          IntegrityDebugSeederService.callDeletionLansweeperOnlyIssue,
        ],
      );

      expect(rows.single['lansweeper_state'], 'sent');
      expect(
        rows.single['lansweeper_main_ticket_id'],
        IntegrityDebugSeederService.callDeletionLansweeperOnlyTicket,
      );
    });

    test('καμία κλήση ή εκκρεμότητα του σεναρίου δεν γεννά εύρημα', () async {
      // Κενό ευρετήριο ή δεσμός σε ανύπαρκτη κλήση θα εμφανιζόταν στον έλεγχο
      // ακεραιότητας — το σενάριο δοκιμάζει διαγραφή, δεν προσθέτει σφάλματα.
      final calls = await db.query('calls', columns: ['id', 'search_index']);
      final tasks = await db.query('tasks', columns: ['id', 'search_index']);
      final orphanLinks = await db.rawQuery('''
        SELECT l.id FROM call_external_links l
        LEFT JOIN calls c ON c.id = l.call_id
        WHERE c.id IS NULL
        ''');

      expect(calls, hasLength(3));
      expect(tasks, hasLength(3));
      expect(orphanLinks, isEmpty);
      for (final row in [...calls, ...tasks]) {
        expect(
          (row['search_index'] as String?)?.trim() ?? '',
          isNotEmpty,
          reason: 'εγγραφή ${row['id']}',
        );
      }
    });

    test('οι τρεις κλήσεις είναι πρόσφατες και σε διαφορετικές ημέρες', () async {
      final rows = await db.query('calls', columns: ['date']);
      final dates = rows
          .map((r) => DateTime.parse(r['date'] as String))
          .toList();

      expect(dates.toSet(), hasLength(3));
      final oldest = dates.reduce((a, b) => a.isBefore(b) ? a : b);
      expect(DateTime.now().difference(oldest).inDays, lessThanOrEqualTo(4));
    });
  });
}
