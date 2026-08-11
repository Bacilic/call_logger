// Υπηρεσία υποβάθμισης βάσης στην έκδοση σχήματος της εφαρμογής.
//
// Η υποβάθμιση δεν μετατρέπει τίποτα: όταν το αρχείο είναι υπερσύνολο του
// αναμενόμενου σχήματος, η μόνη εγγραφή είναι ο αριθμός έκδοσης. Όταν δεν
// είναι, η υπηρεσία αρνείται με ονομαστικό λόγο — ποτέ δεν «προσπαθεί».
//
//   flutter test test/features/database/database_downgrade_service_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_v1_schema.dart';
import 'package:call_logger/features/database/services/database_downgrade_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

Future<String> _createNewerDb(
  Directory dir,
  String name, {
  required int fileVersion,
  Future<void> Function(Database db)? mutate,
}) async {
  final dbPath = p.join(dir.path, name);
  await DatabaseHelper.instance.createNewDatabaseFile(dbPath);
  final db = await openDatabase(dbPath, singleInstance: false);
  if (mutate != null) {
    await mutate(db);
  }
  await db.rawQuery('PRAGMA user_version = $fileVersion');
  await db.close();
  return dbPath;
}

Future<int> _readUserVersion(String dbPath) async {
  final db = await openDatabase(dbPath, readOnly: true, singleInstance: false);
  try {
    final rows = await db.rawQuery('PRAGMA user_version');
    return (rows.first['user_version'] as int?) ?? -1;
  } finally {
    await db.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() {
    initSqfliteFfiForTests();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('downgrade_service_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('γεφυρώσιμη βάση → ο αριθμός έκδοσης γυρίζει, οι στήλες μένουν',
      () async {
    final dbPath = await _createNewerDb(
      tempDir,
      'bridgeable.db',
      fileVersion: databaseSchemaVersionV1 + 2,
      mutate: (db) =>
          db.execute('ALTER TABLE calls ADD COLUMN future_note TEXT'),
    );

    final outcome = await downgradeDatabaseFileToAppVersion(dbPath);

    expect(outcome.isSuccess, isTrue, reason: outcome.errorMessage);
    expect(await _readUserVersion(dbPath), databaseSchemaVersionV1);

    // Η νεότερη στήλη ΔΕΝ σβήστηκε — μένει στη θέση της, αγνοημένη.
    final db = await openDatabase(dbPath, readOnly: true, singleInstance: false);
    try {
      final info = await db.rawQuery('PRAGMA table_info(calls)');
      final names = info.map((r) => r['name'] as String).toSet();
      expect(names, contains('future_note'));
    } finally {
      await db.close();
    }
  });

  test('μη γεφυρώσιμη βάση → άρνηση με ονομαστικό λόγο, καμία εγγραφή',
      () async {
    final fileVersion = databaseSchemaVersionV1 + 2;
    final dbPath = await _createNewerDb(
      tempDir,
      'blocked.db',
      fileVersion: fileVersion,
      mutate: (db) => db.execute(
        'ALTER TABLE tasks RENAME COLUMN completed_at TO completed_at_v2',
      ),
    );

    final outcome = await downgradeDatabaseFileToAppVersion(dbPath);

    expect(outcome.isSuccess, isFalse);
    expect(outcome.errorMessage, contains('completed_at'));
    // Η έκδοση του αρχείου δεν πειράχτηκε.
    expect(await _readUserVersion(dbPath), fileVersion);
  });

  test('υποβάθμιση αντιγράφου → το πρωτότυπο ανέγγιχτο, το αντίγραφο έτοιμο',
      () async {
    final fileVersion = databaseSchemaVersionV1 + 1;
    final dbPath = await _createNewerDb(
      tempDir,
      'original.db',
      fileVersion: fileVersion,
    );

    final outcome = await downgradeCopyToAppVersion(dbPath);

    expect(outcome.isSuccess, isTrue, reason: outcome.errorMessage);
    expect(outcome.dbPath, isNot(dbPath));
    expect(p.basename(outcome.dbPath!), contains('_υποβαθμισμένη_'));
    expect(await _readUserVersion(outcome.dbPath!), databaseSchemaVersionV1);
    // Το πρωτότυπο παραμένει στη νεότερη έκδοση για τη νεότερη εφαρμογή.
    expect(await _readUserVersion(dbPath), fileVersion);
  });

  test('βάση ήδη στην έκδοση της εφαρμογής → επιτυχία χωρίς καμία ενέργεια',
      () async {
    final dbPath = p.join(tempDir.path, 'current.db');
    await DatabaseHelper.instance.createNewDatabaseFile(dbPath);

    final outcome = await downgradeDatabaseFileToAppVersion(dbPath);

    expect(outcome.isSuccess, isTrue);
    expect(await _readUserVersion(dbPath), databaseSchemaVersionV1);
  });
}
