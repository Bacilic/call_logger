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
    test('α) βάση με μόνο πίνακα calls → incompleteCallLogger', () async {
      final dbPath = await _createTempDb(tempDir, 'calls.db', (db) async {
        await db.execute(
          'CREATE TABLE calls (id INTEGER PRIMARY KEY, note TEXT)',
        );
      });

      expect(
        await classifyDatabaseFile(dbPath),
        DatabaseFileKind.incompleteCallLogger,
      );
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

    test(
      'ι) υβρίδιο calls + υπογραφή Λάμπας → hybrid',
      () async {
        final dbPath = await _createTempDb(tempDir, 'hybrid.db', (db) async {
          await db.execute(
            'CREATE TABLE calls (id INTEGER PRIMARY KEY, date TEXT)',
          );
          await db.execute(
            'CREATE TABLE owners (owner INTEGER PRIMARY KEY)',
          );
          await db.execute(
            'CREATE TABLE offices (office INTEGER PRIMARY KEY)',
          );
          await db.execute(
            'CREATE TABLE equipment ('
            'code INTEGER PRIMARY KEY, model INTEGER, office INTEGER)',
          );
        });

        final profile = await profileDatabaseFile(dbPath);
        expect(profile.kind, DatabaseFileKind.hybrid);
        expect(profile.hasLampSignature, isTrue);
      },
    );

    test(
      'ια) ελλιπές αρχείο με μόνο calls → incompleteCallLogger με missing',
      () async {
        final dbPath = await _createTempDb(
          tempDir,
          'incomplete.db',
          (db) async {
            await db.execute(
              'CREATE TABLE calls (id INTEGER PRIMARY KEY, date TEXT)',
            );
          },
        );

        final profile = await profileDatabaseFile(dbPath);
        expect(profile.kind, DatabaseFileKind.incompleteCallLogger);
        expect(profile.missingCoreTables, isNotEmpty);
        expect(profile.missingCoreTables, contains('users'));
        expect(profile.missingCoreTables, contains('departments'));
        expect(profile.missingCoreTables, contains('phones'));
        expect(profile.missingCoreTables, isNot(contains('calls')));
      },
    );

    test(
      'ιβ) Λάμπα μόνο με equipment (code/model, χωρίς code_equipment) → lamp',
      () async {
        final dbPath = await _createTempDb(
          tempDir,
          'lamp_equipment_only.db',
          (db) async {
            await db.execute(
              'CREATE TABLE equipment ('
              'code INTEGER PRIMARY KEY, model INTEGER, office INTEGER)',
            );
          },
        );

        final profile = await profileDatabaseFile(dbPath);
        expect(profile.kind, DatabaseFileKind.lamp);
        expect(profile.hasLampSignature, isTrue);
      },
    );

    test(
      'ιγ) πίνακες με user_version 0 → unknown (όχι empty)',
      () async {
        final dbPath = await _createTempDb(
          tempDir,
          'version_zero.db',
          (db) async {
            await db.execute(
              'CREATE TABLE unrelated (id INTEGER PRIMARY KEY)',
            );
          },
        );

        final profile = await profileDatabaseFile(dbPath);
        expect(profile.kind, DatabaseFileKind.unknown);
        expect(profile.userVersion, 0);
      },
    );

    test(
      'ιδ) κενή βάση με πλήρες σχήμα → callLogger με μηδενικά πλήθη',
      () async {
        final dbPath = p.join(tempDir.path, 'full_empty.db');
        await DatabaseHelper.instance.createNewDatabaseFile(dbPath);

        final profile = await profileDatabaseFile(dbPath);
        expect(profile.kind, DatabaseFileKind.callLogger);
        expect(profile.callCount, 0);
        expect(profile.userCount, 0);
        expect(profile.phoneCount, 0);
        expect(profile.equipmentCount, 0);
        expect(profile.departmentCount, 0);
        expect(profile.latestCallDate, isNull);
        expect(profile.missingCoreTables, isEmpty);
      },
    );

    test(
      'ιε) πλήρης βάση με δύο κλήσεις → callCount 2 και latestCallDate',
      () async {
        final dbPath = p.join(tempDir.path, 'with_calls.db');
        await DatabaseHelper.instance.createNewDatabaseFile(dbPath);

        final writer = await openDatabase(dbPath, singleInstance: false);
        await writer.insert('calls', <String, Object?>{
          'date': '2026-07-20',
          'issue': 'πρώτη',
        });
        await writer.insert('calls', <String, Object?>{
          'date': '2026-07-25',
          'issue': 'δεύτερη',
        });
        await writer.close();

        final profile = await profileDatabaseFile(dbPath);
        expect(profile.kind, DatabaseFileKind.callLogger);
        expect(profile.callCount, 2);
        expect(profile.latestCallDate, isNotNull);
        expect(profile.latestCallDate, isNotEmpty);
      },
    );
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

    test(
      'ζ) βάση Λάμπας με ενεργό WAL: καμία εγγραφή/checkpoint πριν την απόρριψη',
      () async {
        final fileName = 'old_equipment 2.db';
        final dbPath = p.join(tempDir.path, fileName);

        final writer = await openDatabase(dbPath, singleInstance: false);
        await writer.execute('PRAGMA journal_mode = WAL');
        for (final statement in oldDatabaseCreateStatements) {
          await writer.execute(statement);
        }
        // Δεύτερη σύνδεση: κρατά το -wal ζωντανό μετά το κλείσιμο του writer.
        final holder = await openDatabase(dbPath, singleInstance: false);
        addTearDown(() async {
          if (holder.isOpen) await holder.close();
        });
        await holder.rawQuery('SELECT 1');
        await writer.close();

        final walFile = File('$dbPath-wal');
        expect(
          await walFile.exists(),
          isTrue,
          reason: 'Το σενάριο απαιτεί ενεργό -wal στη ξένη βάση',
        );
        final walSizeBefore = await walFile.length();
        expect(walSizeBefore, greaterThan(0));
        final mainBefore = await _fileBytes(dbPath);

        final settings = SettingsService();
        await settings.setDatabasePath(dbPath);
        await settings.setDatabaseOpenTimeoutSeconds(2);
        await settings.setDatabaseOpenMaxAttempts(1);

        final runner = await runDatabaseInitChecks(closeConnectionFirst: true);

        final mainAfter = await _fileBytes(dbPath);
        expect(
          mainAfter,
          orderedEquals(mainBefore),
          reason:
              'Ο προληπτικός καθαρισμός WAL δεν πρέπει να τρέχει σε αρχείο '
              'που δεν έχει ακόμη ταξινομηθεί',
        );
        expect(
          await walFile.exists(),
          isTrue,
          reason: 'Το -wal της ξένης βάσης δεν πρέπει να διαγράφεται',
        );
        expect(await walFile.length(), walSizeBefore);
        expect(runner.result.isSuccess, isFalse);
        expect(
          runner.result.message,
          contains('είναι η βάση δεδομένων της Λάμπας'),
        );
      },
    );

    test(
      'η) αρχείο που δεν είναι SQLite δεν πετάει ωμό σφάλμα',
      () async {
        final dbPath = p.join(tempDir.path, 'fake.db');
        await File(dbPath).writeAsBytes(
          List<int>.generate(64, (i) => (i * 17 + 3) % 256),
        );

        expect(
          await classifyDatabaseFile(dbPath),
          DatabaseFileKind.undetermined,
        );

        final settings = SettingsService();
        await settings.setDatabasePath(dbPath);
        await settings.setDatabaseOpenTimeoutSeconds(2);
        await settings.setDatabaseOpenMaxAttempts(1);

        final runner = await runDatabaseInitChecks(closeConnectionFirst: true);
        expect(runner.result.isSuccess, isFalse);
        expect(
          runner.result.message,
          anyOf(
            contains('έγκυρη βάση SQLite'),
            contains('έγκυρη κεφαλίδα SQLite'),
            contains('κεφαλίδα SQLite'),
          ),
        );
      },
    );

    test(
      'θ) υγιής βάση Καταγραφής με ενεργό WAL ανοίγει κανονικά',
      () async {
        final dbPath = p.join(tempDir.path, 'call_logger.db');
        await DatabaseHelper.instance.createNewDatabaseFile(dbPath);

        final writer = await openDatabase(dbPath, singleInstance: false);
        await writer.execute('PRAGMA journal_mode = WAL');
        final holder = await openDatabase(dbPath, singleInstance: false);
        addTearDown(() async {
          if (holder.isOpen) await holder.close();
        });
        await holder.rawQuery('SELECT 1');
        await writer.close();

        expect(await classifyDatabaseFile(dbPath), DatabaseFileKind.callLogger);

        final settings = SettingsService();
        await settings.setDatabasePath(dbPath);
        await settings.setDatabaseOpenTimeoutSeconds(2);
        await settings.setDatabaseOpenMaxAttempts(1);

        final runner = await runDatabaseInitChecks(closeConnectionFirst: true);
        expect(
          runner.result.isSuccess,
          isTrue,
          reason:
              'Η νέα σειρά (ταξινόμηση πριν από probe/WAL) δεν πρέπει να '
              'απορρίπτει υγιή βάση Καταγραφής με ενεργό WAL',
        );
      },
    );
  });
}
