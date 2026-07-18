// Κούρσα παράλληλων runDatabaseInitChecks (closeConnectionFirst true/false).
//
//   flutter test test/core/database/database_init_runner_concurrency_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_init_result.dart';
import 'package:call_logger/core/database/database_init_runner.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_setup.dart';

bool _mentionsDatabaseClosed(DatabaseInitResult result) {
  final blob = [
    result.message,
    result.details,
    result.originalExceptionText,
    result.stackTraceText,
  ].whereType<String>().join(' ').toLowerCase();
  return blob.contains('database_closed') || blob.contains('database closed');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    initSqfliteFfiForTests();
    SharedPreferences.setMockInitialValues({});
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();

    tempDir = await Directory.systemTemp.createTemp('db_init_concurrency_');
    dbPath = '${tempDir.path}/concurrency.db';
    await DatabaseHelper.instance.createNewDatabaseFile(dbPath);

    final settings = SettingsService();
    await settings.setDatabasePath(dbPath);
  });

  tearDown(() async {
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'παράλληλες runDatabaseInitChecks δεν αποτυγχάνουν με database_closed',
    () async {
      const rounds = 12;
      for (var i = 0; i < rounds; i++) {
        await DatabaseHelper.instance.closeConnection();

        final withoutClose = runDatabaseInitChecks(closeConnectionFirst: false);
        final withClose = runDatabaseInitChecks(closeConnectionFirst: true);
        final results = await Future.wait([withoutClose, withClose]);

        for (final runner in results) {
          expect(
            _mentionsDatabaseClosed(runner.result),
            isFalse,
            reason:
                'Γύρος $i/${rounds - 1}: αποτυχία database_closed — '
                '${runner.result.originalExceptionText ?? runner.result.message}',
          );
          expect(
            runner.result.isSuccess,
            isTrue,
            reason:
                'Γύρος $i/${rounds - 1}: αναμενόταν επιτυχία — '
                'status=${runner.result.status}, '
                'msg=${runner.result.message}, '
                'ex=${runner.result.originalExceptionText}',
          );
        }
      }
    },
  );
}
