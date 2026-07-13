// Τεστ χαρακτηρισμού πριν τη διάσπαση του calls_repository.dart.
//
//   flutter test test/core/database/calls_repository_split_characterization_test.dart

import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:call_logger/features/history/models/dashboard_filter_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

void main() {
  group('CallsRepository split characterization', () {
    late CallsRepository repo;

    Future<void> insertTask({
      required int callId,
      String title = 'linked-task',
    }) async {
      final db = await DatabaseHelper.instance.database;
      final nowIso = DateTime.now().toIso8601String();
      await db.insert('tasks', {
        'title': title,
        'status': 'open',
        'call_id': callId,
        'created_at': nowIso,
        'updated_at': nowIso,
        'is_deleted': 0,
      });
    }

    setUpAll(() async {
      await bindCallLoggerIsolatedTestDatabase();
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

    test('insertCall χτίζει μη κενό search_index από το issue', () async {
      const marker = 'CharSplitMarkerAlpha999';
      final id = await repo.insertCall(
        CallModel(
          issue: marker,
          callerText: 'Caller Split',
          phoneText: '5555',
          departmentText: 'Dept',
          equipmentText: 'PC-SPLIT',
          category: 'Cat',
          duration: 10,
        ),
      );

      final db = await DatabaseHelper.instance.database;
      final rows = await db.query(
        'calls',
        columns: ['search_index'],
        where: 'id = ?',
        whereArgs: [id],
      );
      final index = rows.single['search_index'] as String?;
      expect(index, isNotNull);
      expect(index!.trim(), isNotEmpty);
      expect(
        index,
        contains(SearchTextNormalizer.normalizeForSearch(marker)),
      );
    });

    test(
      'deleteCallWithTasksAction cascade soft-deletes linked task and call',
      () async {
        final callId = await repo.insertCall(
          CallModel(issue: 'cascade-char', duration: 5),
        );
        await insertTask(callId: callId);

        expect(await repo.getTasksCountLinkedToCall(callId), 1);
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
        expect(taskRows.single['is_deleted'], 1);
      },
    );

    test('getDashboardStatistics αθροίζει κλήσεις στο εύρος ημερομηνιών', () async {
      await repo.insertCall(
        CallModel(
          date: '2025-06-01',
          time: '09:00',
          issue: 'dash-a',
          duration: 60,
        ),
      );
      await repo.insertCall(
        CallModel(
          date: '2025-06-01',
          time: '10:00',
          issue: 'dash-b',
          duration: 120,
        ),
      );
      await repo.insertCall(
        CallModel(
          date: '2025-06-02',
          time: '11:00',
          issue: 'dash-c',
          duration: 30,
        ),
      );

      final stats = await repo.getDashboardStatistics(
        DashboardFilterModel(
          dateFrom: DateTime(2025, 6, 1),
          dateTo: DateTime(2025, 6, 1),
        ),
      );

      expect(stats.totalCalls, 2);
      expect(stats.totalDurationSeconds, 180);
      expect(stats.avgDurationSeconds, 90);
    });

    test(
      'getDashboardStatistics — κλήση χωρίς τμήμα/καλούντα → Άγνωστο/Άγνωστος',
      () async {
        await repo.insertCall(
          CallModel(
            date: '2025-08-01',
            time: '09:00',
            issue: 'orphan-dash',
            duration: 45,
            callerText: '',
            departmentText: '',
          ),
        );

        final stats = await repo.getDashboardStatistics(
          DashboardFilterModel(
            dateFrom: DateTime(2025, 8, 1),
            dateTo: DateTime(2025, 8, 1),
          ),
        );

        expect(stats.byDepartment, isNotEmpty);
        expect(stats.byDepartment.first.name, 'Άγνωστο');
        expect(stats.topCallers, isNotEmpty);
        expect(stats.topCallers.first.name, 'Άγνωστος');
      },
    );

    test('getHistoryCalls φιλτράρει με keyword στο search_index', () async {
      const marker = 'HistFilterMarkerZeta777';
      await repo.insertCall(
        CallModel(
          date: '2025-07-10',
          time: '12:00',
          issue: '$marker ιστορικό',
          duration: 15,
        ),
      );
      await repo.insertCall(
        CallModel(
          date: '2025-07-10',
          time: '13:00',
          issue: 'άλλη κλήση χωρίς marker',
          duration: 20,
        ),
      );

      final normalized = SearchTextNormalizer.normalizeForSearch(marker);
      final rows = await repo.getHistoryCalls(keyword: normalized);
      expect(rows.length, 1);
      expect(rows.single['issue'], contains(marker));
    });
  });
}
