// Φάντασμα δεδομένων tasks μετά αλλαγή δεσμευμένης βάσης χωρίς invalidate.
//
//   flutter test test/core/init/database_reopen_cache_reset_test.dart

import 'dart:io';

import 'package:call_logger/core/database/active_database_generation.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/init/database_reopen_cache_reset.dart';
import 'package:call_logger/features/calls/models/equipment_model.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/calls/provider/call_entry_provider.dart';
import 'package:call_logger/features/calls/provider/smart_entity_selector_provider.dart';
import 'package:call_logger/features/directory/providers/catalog_validation_provider.dart';
import 'package:call_logger/features/tasks/models/task.dart';
import 'package:call_logger/features/tasks/providers/tasks_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    SharedPreferences.setMockInitialValues(<String, Object>{});
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
          reason:
              'Αναμενόμενο φάντασμα: χωρίς invalidate μένουν τα δεδομένα της Α',
        );
        expect(_titlesOf(ghost), isNot(contains(_kTitleB)));

        // Η ζωντανή βάση Β έχει μόνο τη δική της εγγραφή.
        final dbB = await DatabaseHelper.instance.database;
        final rowsB = await dbB.query('tasks', columns: ['title']);
        expect(rowsB.map((r) => r['title']).toList(), [_kTitleB]);

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

  testWidgets(
    'με invalidateDatabaseScopedCaches η φόρμα κλήσης καθαρίζει ξένες ταυτότητες',
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

        final smart = container.read(callSmartEntityProvider.notifier);
        smart.setCaller(
          UserModel(
            id: 42,
            firstName: 'Βάση',
            lastName: 'Άλφα',
            departmentId: 7,
          ),
        );
        smart.setEquipment(EquipmentModel(id: 99, code: 'EQ-A-99'));
        container
            .read(callEntryProvider.notifier)
            .setCategory('Κατηγορία Α', categoryId: 5);

        final before = container.read(callSmartEntityProvider);
        expect(before.selectedCaller?.id, 42);
        expect(before.selectedEquipment?.id, 99);
        expect(before.selectedDepartmentId, 7);
        expect(container.read(callEntryProvider).categoryId, 5);

        invalidateDatabaseScopedCaches(widgetRef);
      });

      // post-frame callback της εκκαθάρισης (αν αναβλήθηκε)
      await tester.pump();

      final after = container.read(callSmartEntityProvider);
      expect(after.selectedCaller, isNull);
      expect(after.selectedEquipment, isNull);
      expect(after.selectedDepartmentId, isNull);
      expect(container.read(callEntryProvider).categoryId, isNull);
    },
  );

  testWidgets(
    'η αλυσίδα Κανόνων Επικύρωσης ξεπλένεται εκτός build μετά την εκκαθάριση',
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
        await DatabaseHelper.bindTestDatabaseFile(pathB);

        // Ο χρήστης δεν έχει ανοίξει φόρμα ή οθόνη κανόνων: η αλυσίδα
        // rules → service δεν έχει χτιστεί ακόμη.
        expect(container.exists(catalogValidationRulesProvider), isFalse);
        expect(container.exists(catalogValidationServiceProvider), isFalse);

        invalidateDatabaseScopedCaches(widgetRef);

        // Ο καλών βρίσκεται εκτός build, οπότε το ξέπλυμα γίνεται αμέσως.
        // Αν η αλυσίδα έμενε «dirty χωρίς listeners», θα ξεπλενόταν σύγχρονα
        // μέσα στο initState/build της επόμενης οθόνης που τη διαβάζει →
        // «setState() called during build» (κατάρρευση 09/08 στους Κανόνες
        // Επικύρωσης μετά από αλλαγή βάσης).
        expect(
          container.exists(catalogValidationRulesProvider),
          isTrue,
          reason:
              'Η εκκαθάριση ακύρωσε τους κανόνες χωρίς να τους ξαναδιαβάσει '
              'εκτός build.',
        );
        expect(
          container.exists(catalogValidationServiceProvider),
          isTrue,
          reason:
              'Ο service παρακολουθεί τους κανόνες με watch — χωρίς eager '
              'flush μένει «βόμβα» για το επόμενο build.',
        );

        // Άφησε τα futures της αλυσίδας να ολοκληρωθούν πριν κλείσει η βάση.
        try {
          await container.read(catalogValidationServiceProvider.future);
        } catch (_) {}
      });
    },
  );

  testWidgets(
    'η εκκαθάριση εκπέμπει σήμα αλλαγής βάσης για τις οθόνες χωρίς provider',
    (tester) async {
      // Οι φορτωμένες γραμμές της προβολής πινάκων ζουν στην κατάσταση του
      // widget, όχι σε provider: το ξέπλυμα των caches δεν τις φτάνει ποτέ.
      // Το σήμα είναι ο μόνος τρόπος να μάθουν ότι διαβάζουμε άλλη βάση.
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
        await DatabaseHelper.bindTestDatabaseFile(pathB);
        final before = container.read(activeDatabaseGenerationProvider);

        invalidateDatabaseScopedCaches(widgetRef);

        expect(
          container.read(activeDatabaseGenerationProvider),
          greaterThan(before),
          reason:
              'Χωρίς το σήμα, η προβολή πίνακα συνεχίζει να δείχνει τη βάση '
              'που δεν διαβάζουμε πια.',
        );

        try {
          await container.read(catalogValidationServiceProvider.future);
        } catch (_) {}
      });
    },
  );
}
