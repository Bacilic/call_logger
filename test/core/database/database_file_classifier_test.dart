// Ταξινόμηση αρχείου βάσης (read-only) και απόρριψη ξένης βάσης χωρίς εγγραφή.
//
//   flutter test test/core/database/database_file_classifier_test.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:call_logger/core/database/database_file_classifier.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_init_runner.dart';
import 'package:call_logger/core/database/old_database/old_database_schema.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

Future<Uint8List> _fileBytes(String path) => File(path).readAsBytes();

Future<String> _createTempDb(
  Directory dir,
  String name,
  Future<void> Function(Database db) setup,
) async {
  final dbPath = p.join(dir.path, name);
  final db = await openDatabase(dbPath);
  await setup(db);
  await db.close();
  return dbPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() {
    initSqfliteFfiForTests();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();
    tempDir = await Directory.systemTemp.createTemp('db_file_classifier_');
  });

  tearDown(() async {
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('classifyDatabaseFile', () {
    test('α) βάση με πίνακα calls → callLogger', () async {
      final dbPath = await _createTempDb(tempDir, 'calls.db', (db) async {
        await db.execute(
          'CREATE TABLE calls (id INTEGER PRIMARY KEY, note TEXT)',
        );
      });

      expect(await classifyDatabaseFile(dbPath), DatabaseFileKind.callLogger);
    });

    test('β) υπογραφή Λάμπας με user_version 0 → lamp', () async {
      final dbPath = await _createTempDb(tempDir, 'lamp.db', (db) async {
        for (final statement in oldDatabaseCreateStatements) {
          await db.execute(statement);
        }
      });

      final versionRows = await databaseFactory
          .openDatabase(dbPath, options: OpenDatabaseOptions(readOnly: true))
          .then((db) async {
            final rows = await db.rawQuery('PRAGMA user_version');
            await db.close();
            return rows;
          });
      expect(versionRows.first['user_version'], 0);

      expect(await classifyDatabaseFile(dbPath), DatabaseFileKind.lamp);
    });

    test('γ) άσχετοι πίνακες → unknown', () async {
      final dbPath = await _createTempDb(tempDir, 'foreign.db', (db) async {
        await db.execute(
          'CREATE TABLE unrelated (id INTEGER PRIMARY KEY, value TEXT)',
        );
      });

      expect(await classifyDatabaseFile(dbPath), DatabaseFileKind.unknown);
    });

    test('δ) κενό αρχείο βάσης → empty', () async {
      final dbPath = await _createTempDb(tempDir, 'empty.db', (_) async {});

      expect(await classifyDatabaseFile(dbPath), DatabaseFileKind.empty);
    });
  });

  group('μη-εγγραφή σε ξένη βάση Λάμπας', () {
    test(
      'ε) classify + runDatabaseInitChecks δεν αλλοιώνουν bytes και δίνουν μήνυμα Λάμπας',
      () async {
        final fileName = 'old_equipment 2.db';
        final dbPath = await _createTempDb(tempDir, fileName, (db) async {
          for (final statement in oldDatabaseCreateStatements) {
            await db.execute(statement);
          }
        });

        final beforeClassify = await _fileBytes(dbPath);
        expect(await classifyDatabaseFile(dbPath), DatabaseFileKind.lamp);
        final afterClassify = await _fileBytes(dbPath);
        expect(
          afterClassify,
          orderedEquals(beforeClassify),
          reason: 'Η ταξινόμηση δεν πρέπει να γράφει στο αρχείο',
        );

        final settings = SettingsService();
        await settings.setDatabasePath(dbPath);
        await settings.setDatabaseOpenTimeoutSeconds(2);
        await settings.setDatabaseOpenMaxAttempts(1);

        final beforeInit = await _fileBytes(dbPath);
        final runner = await runDatabaseInitChecks(closeConnectionFirst: true);
        final afterInit = await _fileBytes(dbPath);

        expect(
          afterInit,
          orderedEquals(beforeInit),
          reason:
              'Το runDatabaseInitChecks δεν πρέπει να μεταναστεύει/γράφει '
              'σε βάση Λάμπας',
        );
        expect(runner.result.isSuccess, isFalse);
        expect(
          runner.result.message,
          contains('είναι η βάση δεδομένων της Λάμπας'),
        );
        expect(runner.result.message, contains(fileName));
        expect(runner.result.details, contains(dbPath));
      },
    );
  });
}
