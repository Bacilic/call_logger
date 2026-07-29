import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/init/app_initializer.dart';
import 'package:call_logger/core/init/startup_engine_failure.dart';
import 'package:call_logger/core/init/startup_notices.dart';
import 'package:call_logger/core/services/crash_log_service.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;

  setUp(() async {
    clearStartupNotices();
    clearStartupEngineFailure();
    tempRoot = await Directory.systemTemp.createTemp('startup_notices_test_');
  });

  tearDown(() async {
    clearStartupNotices();
    clearStartupEngineFailure();
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  final missingSqliteDllError = ArgumentError(
    "Failed to load dynamic library 'sqlite3.dll': "
    'The specified module could not be found. (error code: 126)',
  );

  test(
    'Α: CrashLogService.initialize δεν καταπίνει όταν το logs είναι αρχείο',
    () async {
      final logsFile = File(p.join(tempRoot.path, 'logs'));
      await logsFile.writeAsString('not a directory');

      final databasePath = p.join(tempRoot.path, 'engine.db');

      await expectLater(
        () => CrashLogService.initialize(
          databasePath: databasePath,
          appVersion: '0.0.0-test',
          retentionCount: 3,
        ),
        throwsA(isA<Exception>()),
      );
    },
  );

  test(
    'Β: end-to-end — recordStartupNotice + flush γράφει στο ημερήσιο log',
    () async {
      final databasePath = p.join(tempRoot.path, 'engine.db');
      await CrashLogService.initialize(
        databasePath: databasePath,
        appVersion: '0.0.0-test',
        retentionCount: 3,
      );

      recordStartupNotice('Δοκιμή φάσης', StateError('σκόπιμη αποτυχία'));
      flushStartupNoticesToCrashLog();

      final logsDir = CrashLogService.logsDirectoryForDatabasePath(
        databasePath,
      );
      final todayLog = File(
        p.join(logsDir, CrashLogService.dailyLogFileName(DateTime.now())),
      );

      final content = await todayLog.readAsString();
      expect(content, contains('Δοκιμή φάσης'));
      expect(content, contains('σκόπιμη αποτυχία'));
    },
  );

  test('Γ: χωρίς διαθέσιμο ημερολόγιο, flush δεν αδειάζει την ουρά', () async {
    recordStartupNotice(
      'Φάση χωρίς ημερολόγιο',
      StateError('σφάλμα χωρίς I/O'),
    );

    flushStartupNoticesToCrashLog();

    final report = startupNoticesReport();
    expect(report, isNotNull);
    expect(report, contains('Φάση χωρίς ημερολόγιο'));
  });

  test(
    'Δ: end-to-end — το AppInitializer ενσωματώνει startupNotices στο details',
    () async {
      clearStartupNotices();
      clearStartupEngineFailure();

      initSqfliteFfiForTests();
      SharedPreferences.setMockInitialValues({});

      await DatabaseHelper.instance.closeConnection();
      DatabaseHelper.releaseTestDatabaseBinding();

      final dbPath = p.join(tempRoot.path, 'engine_failure.db');
      await DatabaseHelper.instance.createNewDatabaseFile(dbPath);
      await SettingsService().setDatabasePath(dbPath);

      recordStartupEngineFailure(missingSqliteDllError, StackTrace.current);
      recordStartupNotice('Δοκιμή φάσης', StateError('σκόπιμη αποτυχία'));

      final result = await AppInitializer.initialize();
      expect(result.success, isFalse);
      expect(result.details, contains('Δοκιμή φάσης'));
    },
  );

  test(
    'Ε: end-to-end — σε επιτυχία, τα startup notices δεν μολύνουν το details',
    () async {
      clearStartupNotices();
      clearStartupEngineFailure();

      initSqfliteFfiForTests();
      SharedPreferences.setMockInitialValues({});

      await DatabaseHelper.instance.closeConnection();
      DatabaseHelper.releaseTestDatabaseBinding();

      final dbPath = p.join(tempRoot.path, 'success.db');
      await DatabaseHelper.instance.createNewDatabaseFile(dbPath);
      await SettingsService().setDatabasePath(dbPath);

      recordStartupNotice('Μηχανή δεν απέτυχε', StateError('σκόπιμη αποτυχία'));

      final result = await AppInitializer.initialize();
      expect(result.success, isTrue);
      expect(result.details ?? '', isNot(contains('Μηχανή δεν απέτυχε')));
    },
  );
}
