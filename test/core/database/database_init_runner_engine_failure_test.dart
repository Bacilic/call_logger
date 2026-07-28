// Φρουρός αποτυχίας μηχανής SQLite μέσα στον ΠΡΑΓΜΑΤΙΚΟ runner αρχικοποίησης.
//
// Γιατί καλεί τον πραγματικό runner: τα τεστ που ελέγχουν μόνο την
// `resolveStartupFailureResult` απομονωμένα έμειναν πράσινα ενώ η εφαρμογή
// εμφάνιζε ακόμη το άχρηστο «databaseFactory not initialized» — η διόρθωση
// είχε μπει σε μονοπάτι που δεν εκτελείται ποτέ.
//
//   flutter test test/core/database/database_init_runner_engine_failure_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_init_result.dart';
import 'package:call_logger/core/database/database_init_runner.dart';
import 'package:call_logger/core/init/startup_engine_failure.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_setup.dart';

/// Πραγματικό σφάλμα των Windows όταν λείπει η βιβλιοθήκη της μηχανής SQLite.
ArgumentError _missingSqliteDllError() => ArgumentError(
  "Failed to load dynamic library 'sqlite3.dll': "
  'The specified module could not be found. (error code: 126)',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    clearStartupEngineFailure();
    initSqfliteFfiForTests();
    SharedPreferences.setMockInitialValues({});
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();

    tempDir = await Directory.systemTemp.createTemp('db_init_engine_failure_');
    dbPath = '${tempDir.path}/engine_failure.db';
    await DatabaseHelper.instance.createNewDatabaseFile(dbPath);

    await SettingsService().setDatabasePath(dbPath);
  });

  tearDown(() async {
    clearStartupEngineFailure();
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('Α: λείπει το sqlite3.dll → ο runner επιστρέφει ΟΝΟΜΑΣΤΙΚΑ την '
      'πρωτογενή αιτία, όχι το «databaseFactory not initialized»', () async {
    recordStartupEngineFailure(_missingSqliteDllError(), StackTrace.current);

    final runner = await runDatabaseInitChecks();

    expect(runner.result.message, contains('sqlite3.dll'));
    expect(
      runner.result.recoveryKind,
      DatabaseInitRecoveryKind.missingApplicationFile,
    );
    expect(runner.result.isSuccess, isFalse);
  });

  test('Β: με αποτυχία μηχανής ο runner επιστρέφει ΑΜΕΣΩΣ — κανένα '
      'παραπλανητικό διαγνωστικό αρχείου', () async {
    recordStartupEngineFailure(_missingSqliteDllError(), StackTrace.current);

    final runner = await runDatabaseInitChecks();

    final blob = [
      runner.result.details,
      runner.result.message,
    ].whereType<String>().join(' ').toLowerCase();
    expect(blob, isNot(contains('write probe')));
    expect(blob, isNot(contains('κεφαλίδα sqlite')));
    expect(runner.isLocalDevMode, isFalse);
  });

  test('Γ: χωρίς αποτυχία μηχανής ο φρουρός δεν μπλοκάρει την κανονική '
      'εκκίνηση', () async {
    final runner = await runDatabaseInitChecks();

    expect(
      runner.result.isSuccess,
      isTrue,
      reason:
          'status=${runner.result.status}, msg=${runner.result.message}, '
          'ex=${runner.result.originalExceptionText}',
    );
  });
}
