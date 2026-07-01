// Αντι-deadlock στη 2η προσπάθεια ανοίγματος βάσης (self-wait στο closeConnection).
//
//   flutter test test/core/database/database_helper_open_retry_test.dart

import 'dart:async';
import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_init_result.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_setup.dart';

const _kInitWatchdog = Duration(seconds: 15);

Future<T> _withInitWatchdog<T>(Future<T> future) {
  return future.timeout(
    _kInitWatchdog,
    onTimeout: () => throw TimeoutException(
      'initializeDatabase κόλλησε — πιθανό self-deadlock στο retry ανοίγματος',
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    initSqfliteFfiForTests();
    SharedPreferences.setMockInitialValues({});
    DatabaseHelper.resetTestOpenSimulation();
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();

    tempDir = await Directory.systemTemp.createTemp('db_open_retry_test_');
    dbPath = '${tempDir.path}/open_retry.db';
    await DatabaseHelper.instance.createNewDatabaseFile(dbPath);

    final settings = SettingsService();
    await settings.setDatabasePath(dbPath);
    await settings.setDatabaseOpenTimeoutSeconds(2);
    await settings.setDatabaseOpenMaxAttempts(2);
  });

  tearDown(() async {
    DatabaseHelper.resetTestOpenSimulation();
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('DatabaseHelper open retry — anti-deadlock', () {
    test(
      '2η προσπάθεια δεν κρεμάει όταν η 1η αποτύχει (μονοπάτι Απελευθέρωση lock)',
      () async {
        DatabaseHelper.testSimulatedRetriableOpenFailures = 1;

        final db = await _withInitWatchdog(
          DatabaseHelper.instance.initializeDatabase(),
        );

        expect(db.isOpen, isTrue);
        expect(await db.rawQuery('SELECT 1'), isNotEmpty);
      },
    );

    test('αποτυχία και των δύο προσπαθειών επιστρέφει DatabaseInitException', () async {
      DatabaseHelper.testSimulatedRetriableOpenFailures = 99;

      await expectLater(
        _withInitWatchdog(DatabaseHelper.instance.initializeDatabase()),
        throwsA(
          isA<DatabaseInitException>().having(
            (e) => e.result.status,
            'status',
            isNot(DatabaseStatus.success),
          ),
        ),
      );
    });

    test('επιτυχία στη 2η προσπάθεια επιστρέφει έγκυρη σύνδεση με σχήμα', () async {
      DatabaseHelper.testSimulatedRetriableOpenFailures = 1;

      final db = await _withInitWatchdog(
        DatabaseHelper.instance.initializeDatabase(),
      );

      expect(db.isOpen, isTrue);
      final tables = await db.query(
        'sqlite_master',
        where: 'type = ?',
        whereArgs: ['table'],
      );
      expect(tables, isNotEmpty);
    });
  });
}
