// Φάντασμα δεδομένων tasks μετά αλλαγή δεσμευμένης βάσης χωρίς invalidate.
//
//   flutter test test/core/init/database_reopen_cache_reset_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/init/database_reopen_cache_reset.dart';
import 'package:call_logger/features/tasks/models/task.dart';
import 'package:call_logger/features/tasks/providers/tasks_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

const _kTitleA = 'TaskFromDatabaseA_marker';
const _kTitleB = 'TaskFromDatabaseB_marker';

Future<void> _seedOpenTaskAtPath(String dbPath, String title) async {
  await DatabaseHelper.instance.createNewDatabaseFile(dbPath);
  await DatabaseHelper.bindTestDatabaseFile(dbPath);
  final db = await DatabaseHelper.instance.database;
  final now = DateTime.now();
  final due = now.add(const Duration(hours: 4));
  final iso = now.toIso8601String();
  await db.insert('tasks', {
    'title': title,
    'description': 'database reopen cache reset test',
    'due_date': due.toIso8601String(),
    'status': 'open',
    'origin': Task.originManualFab,
    'created_at': iso,
    'updated_at': iso,
    'is_deleted': 0,
  });
  await DatabaseHelper.instance.closeConnection();
}

List<String> _titlesOf(List<Task> tasks) =>
    tasks.map((t) => t.title).toList(growable: false);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String pathA;
  late String pathB;

  setUp(() async {
    initSqfliteFfiForTests();
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();

    tempDir = await Directory.systemTemp.createTemp('db_reopen_cache_');
    pathA = '${tempDir.path}/db_a.db';
    pathB = '${tempDir.path}/db_b.db';
    await _seedOpenTaskAtPath(pathA, _kTitleA);
    await _seedOpenTaskAtPath(pathB, _kTitleB);
  });

  tearDown(() async {
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets(
    'χωρίς invalidateDatabaseScopedCaches ο tasksProvider κρατά δεδομένα της Α μετά δέσμευση Β',
    (tester) async {
      late WidgetRef widgetRef;
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (context, ref, _) {
              widgetRef = ref;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      await tester.runAsync(() async {
        await DatabaseHelper.bindTestDatabaseFile(pathA);
        final fromA = await container.read(tasksProvider.future);
        expect(_titlesOf(fromA), [_kTitleA]);

        await DatabaseHelper.bindTestDatabaseFile(pathB);

        // Χωρίς εκκαθάριση cache: το Riverpod κρατά την παλιά λίστα.
        final ghost = container.read(tasksProvider).value;
        expect(ghost, isNotNull);
        expect(
          _titlesOf(ghost!),
          [_kTitleA],
          reason: 'Αναμενόμενο φάντασμα: χωρίς invalidate μένουν τα δεδομένα της Α',
        );
        expect(_titlesOf(ghost), isNot(contains(_kTitleB)));

        // Η ζωντανή βάση Β έχει μόνο τη δική της εγγραφή.
        final dbB = await DatabaseHelper.instance.database;
        final rowsB = await dbB.query('tasks', columns: ['title']);
        expect(
          rowsB.map((r) => r['title']).toList(),
          [_kTitleB],
        );

        // Αποφυγή unused / εξασφάλιση ότι το Consumer έδεσε ref.
        expect(widgetRef, isNotNull);
      });
    },
  );

  testWidgets(
    'με invalidateDatabaseScopedCaches ο tasksProvider φορτώνει δεδομένα της Β',
    (tester) async {
      late WidgetRef widgetRef;
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (context, ref, _) {
              widgetRef = ref;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      await tester.runAsync(() async {
        await DatabaseHelper.bindTestDatabaseFile(pathA);
        final fromA = await container.read(tasksProvider.future);
        expect(_titlesOf(fromA), [_kTitleA]);

        await DatabaseHelper.bindTestDatabaseFile(pathB);
        invalidateDatabaseScopedCaches(widgetRef);

        final fromB = await container.read(tasksProvider.future);
        expect(
          _titlesOf(fromB),
          [_kTitleB],
          reason: 'Μετά invalidate πρέπει να φαίνονται μόνο τα δεδομένα της Β',
        );
        expect(_titlesOf(fromB), isNot(contains(_kTitleA)));
      });
    },
  );
}
