// Τεστ χαρακτηρισμού πριν τη διάσπαση του database_helper.dart.
//
//   flutter test test/core/database/database_helper_split_characterization_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_init_result.dart';
import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/database/database_v1_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

/// Ελάχιστο σχήμα έκδοσης 1 (μόνο calls + equipment χωρίς στήλες v2).
Future<void> _createLegacyV1EquipmentDatabaseFile(String filePath) async {
  final db = await openDatabase(
    filePath,
    version: 1,
    onCreate: (db, version) async {
      await db.execute(
        'CREATE TABLE calls (id INTEGER PRIMARY KEY AUTOINCREMENT, caller_text TEXT)',
      );
      await db.execute(
        'CREATE TABLE equipment (id INTEGER PRIMARY KEY AUTOINCREMENT, code TEXT)',
      );
    },
    singleInstance: false,
  );
  await db.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    initSqfliteFfiForTests();
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();
    tempDir = await Directory.systemTemp.createTemp('db_split_char_test_');
  });

  tearDown(() async {
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('DatabaseHelper split characterization', () {
    test('επιτυχές άνοιγμα βάσης μέσω bindTestDatabaseFile', () async {
      final dbPath = '${tempDir.path}/open_ok.db';
      await DatabaseHelper.bindTestDatabaseFile(dbPath);

      final db = await DatabaseHelper.instance.initializeDatabase();

      expect(db.isOpen, isTrue);
      expect(p.equals(p.normalize(db.path), p.normalize(dbPath)), isTrue);

      final callsInfo = await db.rawQuery('PRAGMA table_info(calls)');
      expect(callsInfo, isNotEmpty);

      final version = await db.rawQuery('PRAGMA user_version');
      expect(version.single['user_version'], databaseSchemaVersionV1);
    });

    test('createNewDatabaseFile παράγει τρέχον σχήμα με στήλες equipment v2', () async {
      final dbPath = '${tempDir.path}/fresh_schema.db';
      await DatabaseHelper.instance.createNewDatabaseFile(dbPath);

      final db = await openDatabase(dbPath, readOnly: true, singleInstance: false);
      try {
        final info = await db.rawQuery('PRAGMA table_info(equipment)');
        final names = info.map((r) => r['name'] as String).toSet();
        expect(names, containsAll(<String>['department_id', 'location']));

        final version = await db.rawQuery('PRAGMA user_version');
        expect(version.single['user_version'], databaseSchemaVersionV1);
      } finally {
        await db.close();
      }
    });

    test('μεταναστεύσεις σε παλιό σχήμα v1 προσθέτουν στήλες εξοπλισμού', () async {
      final dbPath = '${tempDir.path}/legacy_v1.db';
      await _createLegacyV1EquipmentDatabaseFile(dbPath);

      final db = await openDatabase(
        dbPath,
        version: 2,
        onUpgrade: onDatabaseUpgradeSquashed,
        singleInstance: false,
      );
      try {
        final info = await db.rawQuery('PRAGMA table_info(equipment)');
        final names = info.map((r) => r['name'] as String).toSet();
        expect(names, containsAll(<String>['department_id', 'location']));
      } finally {
        await db.close();
      }
    });

    test('getTablePreview επιστρέφει στήλες και γραμμές με όριο', () async {
      final dbPath = '${tempDir.path}/preview.db';
      await DatabaseHelper.bindTestDatabaseFile(dbPath);
      final db = await DatabaseHelper.instance.initializeDatabase();

      await db.insert('calls', {
        'caller_text': 'Δοκιμή Α',
        'phone_text': '1234',
        'issue': 'Θέμα Α',
      });
      await db.insert('calls', {
        'caller_text': 'Δοκιμή Β',
        'phone_text': '5678',
        'issue': 'Θέμα Β',
      });

      final preview = await DatabaseHelper.instance.getTablePreview(
        'calls',
        rowLimit: 1,
      );

      expect(preview.columns, isNotEmpty);
      expect(preview.columns, contains('caller_text'));
      expect(preview.rows, hasLength(1));
      expect(preview.rows.single['caller_text'], isNotNull);
    });

    test('validateSchema απορρίπτει βάση χωρίς πίνακα calls', () async {
      final dbPath = '${tempDir.path}/no_calls.db';
      final db = await openDatabase(
        dbPath,
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE orphan (id INTEGER PRIMARY KEY AUTOINCREMENT)',
          );
        },
        singleInstance: false,
      );
      await db.close();

      final reopened = await openDatabase(dbPath, singleInstance: false);
      try {
        await expectLater(
          DatabaseHelper.validateSchema(reopened, dbPath),
          throwsA(isA<DatabaseInitException>()),
        );
      } finally {
        await reopened.close();
      }
    });
  });
}
