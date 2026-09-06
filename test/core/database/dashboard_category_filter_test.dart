// Το φίλτρο «Κατηγορία» κρίνει το ίδιο σε Στατιστικά και Ιστορικό.
//
// Οι δύο οθόνες συνδέονται με το «Προβολή όλων»: ο χρήστης βλέπει τα νούμερα
// μιας κατηγορίας στα Στατιστικά και πατά για να δει τις κλήσεις της. Αν το
// κριτήριο διέφερε, το πλήθος της κάρτας και το πλήθος της λίστας θα έλεγαν
// διαφορετικά πράγματα για την ίδια ερώτηση.
//
//   flutter test test/core/database/dashboard_category_filter_test.dart

import 'dart:io';

import 'package:call_logger/core/database/calls_dashboard_repository.dart';
import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/category_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:call_logger/features/history/models/dashboard_filter_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  late CallsRepository calls;
  late CallsDashboardRepository dashboard;
  late Database db;

  setUpAll(() async {
    // Οι ετικέτες των διαγραμμάτων γράφουν μήνες στα ελληνικά.
    await initializeDateFormatting('el');
    initSqfliteFfiForTests();
    final dir = await Directory.systemTemp.createTemp('dashboard_category_');
    await DatabaseHelper.bindTestDatabaseFile('${dir.path}/dashboard_cat.db');
    db = await DatabaseHelper.instance.database;
  });

  setUp(() async {
    await seedIsolatedTestDatabase();
    await db.delete('audit_log');
    await db.delete('calls');
    resetTestOperator();
    calls = CallsRepository(db);
    dashboard = CallsDashboardRepository(db);
  });

  tearDown(resetTestOperator);

  tearDownAll(() async {
    await releaseCallLoggerTestDatabase();
  });

  Future<void> seedCalls() async {
    await calls.insertCall(
      CallModel(
        callerText: 'Βαρβάρα Ψαρρά',
        departmentText: 'Αιματολογικό',
        category: 'Medico',
        issue: 'Δεν ανοίγει',
        status: 'completed',
        duration: 300,
      ),
    );
    await calls.insertCall(
      CallModel(
        callerText: 'Γεωργία Παπαγεωργίου',
        departmentText: 'Γραφείο Κίνησης',
        category: 'Εκτυπωτής',
        issue: 'Αργεί',
        status: 'completed',
        duration: 600,
      ),
    );
    await calls.insertCall(
      CallModel(
        callerText: 'Σωτήρης Τσόγκας',
        departmentText: 'Γραμματεία ΤΕΠ',
        category: 'Medico',
        issue: 'Κολλάει',
        status: 'completed',
        duration: 120,
      ),
    );
  }

  group('Το φίλτρο κατηγορίας στα Στατιστικά', () {
    test('χωρίς κατηγορία μετρώνται όλες οι κλήσεις', () async {
      await seedCalls();
      final stats = await dashboard.getDashboardStatistics(
        const DashboardFilterModel(),
      );
      expect(stats.totalCalls, 3);
    });

    test('με κατηγορία μετρώνται μόνο οι δικές της', () async {
      await seedCalls();
      final stats = await dashboard.getDashboardStatistics(
        const DashboardFilterModel(category: 'Medico'),
      );
      expect(stats.totalCalls, 2);
      expect(stats.totalDurationSeconds, 420);
    });

    test('η κατηγορία στενεύει μαζί με το τμήμα, δεν προσθέτει', () async {
      await seedCalls();
      final stats = await dashboard.getDashboardStatistics(
        const DashboardFilterModel(
          category: 'Medico',
          department: 'Γραφείο Κίνησης',
        ),
      );
      expect(
        stats.totalCalls,
        0,
        reason:
            'Τα φίλτρα ενώνονται με ΚΑΙ: η μόνη κλήση του Γραφείου Κίνησης '
            'είναι «Εκτυπωτής», όχι «Medico».',
      );
    });

    test(
      'τα Στατιστικά και το Ιστορικό μετρούν το ίδιο σύνολο',
      () async {
        await seedCalls();
        final stats = await dashboard.getDashboardStatistics(
          const DashboardFilterModel(category: 'Medico'),
        );
        final historyRows = await calls.getHistoryCalls(category: 'Medico');
        expect(
          stats.totalCalls,
          historyRows.length,
          reason:
              'Το «Προβολή όλων» περνά από τη μία οθόνη στην άλλη — δύο '
              'κριτήρια θα άλλαζαν σιωπηλά το σύνολο των κλήσεων.',
        );
      },
    );

    test(
      'η μετονομασία κατηγορίας δεν χάνει τις παλιές κλήσεις',
      () async {
        await seedCalls();
        final categories = CategoryRepository(db);
        final id = await db.insert('categories', {'name': 'Δίκτυο'});
        await calls.insertCall(
          CallModel(
            callerText: 'Ειρήνη Καρυώτη',
            departmentText: 'Καρδιολογική',
            category: 'Δίκτυο',
            categoryId: id,
            issue: 'Χωρίς σύνδεση',
            status: 'completed',
            duration: 60,
          ),
        );

        await categories.updateCategoryNameAndSyncCalls(
          id: id,
          newCanonicalName: 'Δίκτυο & WiFi',
          rebuildSearchIndexInTxn: (txn, categoryId) async {},
        );

        final stats = await dashboard.getDashboardStatistics(
          const DashboardFilterModel(category: 'Δίκτυο & WiFi'),
        );
        expect(
          stats.totalCalls,
          1,
          reason:
              'Η μετονομασία ενημερώνει το κείμενο κάθε κλήσης· αν το φίλτρο '
              'έψαχνε αλλού, η κλήση θα εξαφανιζόταν από το φίλτρο ενώ θα '
              'φαινόταν κανονικά στη λίστα.',
        );
      },
    );
  });
}
