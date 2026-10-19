// Η αναβάθμιση v68 φτιάχνει τον πίνακα με τις εικόνες των κατόψεων.
//
// Ο πίνακας ξεκινά ΑΔΕΙΟΣ: τις σημερινές εικόνες τις ανεβάζει ρητά ο
// διαχειριστής, γιατί κάθε σταθμός μπορεί να έχει άλλη.
//
//   flutter test test/core/database/floor_images_migration_v68_test.dart

import 'dart:typed_data';

import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('Αναβάθμιση v68 — εικόνες κατόψεων στη βάση', () {
    late Database db;

    setUp(() async {
      initSqfliteFfiForTests();
      db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
      // Ο όροφος ΟΠΩΣ ΗΤΑΝ πριν την αναβάθμιση — με τοπική εικόνα.
      await db.execute('''
        CREATE TABLE building_map_floors (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sort_order INTEGER NOT NULL DEFAULT 0,
          label TEXT NOT NULL,
          floor_group TEXT,
          image_path TEXT NOT NULL,
          rotation_degrees REAL NOT NULL DEFAULT 0
        )
      ''');
      await db.insert('building_map_floors', {
        'label': '2ος',
        'image_path': 'maps_images/2ος.png',
      });
    });

    tearDown(() async {
      await db.close();
    });

    Future<Set<String>> tables() async {
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      return rows.map((r) => r['name'] as String).toSet();
    }

    test('ο πίνακας μπαίνει σε βάση που δεν τον είχε, άδειος', () async {
      expect(await tables(), isNot(contains('building_map_floor_images')));

      await migrateDatabaseToV68(db);

      expect(await tables(), contains('building_map_floor_images'));
      expect(await db.query('building_map_floor_images'), isEmpty);
      expect(
        (await db.query('building_map_floors')).single['image_path'],
        'maps_images/2ος.png',
      );
    });

    test('ξανατρέχει χωρίς παρενέργειες', () async {
      await migrateDatabaseToV68(db);
      await db.insert('building_map_floor_images', {
        'floor_id': 1,
        'image_data': Uint8List.fromList([1, 2, 3]),
        'image_hash': 'abc',
      });

      await migrateDatabaseToV68(db);

      expect(await db.query('building_map_floor_images'), hasLength(1));
    });
  });
}
