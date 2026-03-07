// Εφάπαξ script: μετεγκατάσταση πίνακα equipment.
// - Στήλη code → code_equipment (κωδικός εξοπλισμού)
// - Αφαίρεση στηλών: brand, model, serial_number, buy_date, description
// - Σειρά στηλών: id, code_equipment, type, user_id, notes
// - Αρίθμηση id από 1 (δικό μας id, όχι Excel) με ταύτιση calls.equipment_id
//
// Τρέξε μία φορά. ΜΗ το ενσωματώνεις στην εφαρμογή.
//
// Χρήση (από ρίζα project):
//   dart run tool/migrate_equipment_table_once.dart
//   dart run tool/migrate_equipment_table_once.dart "C:\path\to\call_logger.db"
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main(List<String> args) async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final dbPath = args.isNotEmpty
      ? args.first.trim()
      : path.join(Directory.current.path, 'Data Base', 'call_logger.db');

  final file = File(dbPath);
  if (!await file.exists()) {
    print('ΣΦΑΛΜΑ: Δεν βρέθηκε αρχείο βάσης: $dbPath');
    exit(1);
  }

  final db = await openDatabase(dbPath);

  try {
    final rows = await db.rawQuery(
      'SELECT id, code, type, user_id, notes FROM equipment ORDER BY id',
    );
    if (rows.isEmpty) {
      print('Δεν υπάρχουν εγγραφές στον πίνακα equipment. Τίποτα να γίνει.');
      return;
    }

    final oldToNew = <int, int>{};
    for (var i = 0; i < rows.length; i++) {
      oldToNew[rows[i]['id'] as int] = i + 1;
    }

    await db.transaction((txn) async {
      await txn.execute(
        'CREATE TABLE _equip_id_map (old_id INTEGER PRIMARY KEY, new_id INTEGER)',
      );
      for (final e in oldToNew.entries) {
        await txn.insert('_equip_id_map', {'old_id': e.key, 'new_id': e.value});
      }

      await txn.rawUpdate(
        'UPDATE calls SET equipment_id = (SELECT new_id FROM _equip_id_map WHERE old_id = calls.equipment_id)',
      );

      await txn.execute('''
        CREATE TABLE equipment_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          code_equipment TEXT,
          type TEXT,
          user_id INTEGER,
          notes TEXT
        )
      ''');

      for (var i = 0; i < rows.length; i++) {
        final r = rows[i];
        final newId = i + 1;
        await txn.insert('equipment_new', {
          'id': newId,
          'code_equipment': r['code'],
          'type': r['type'],
          'user_id': r['user_id'],
          'notes': r['notes'],
        });
      }

      await txn.execute('DROP TABLE equipment');
      await txn.execute('ALTER TABLE equipment_new RENAME TO equipment');

      final maxId = await txn.rawQuery('SELECT MAX(id) AS m FROM equipment');
      final seq = (maxId.first['m'] as int?) ?? 0;
      await txn.rawUpdate(
        "UPDATE sqlite_sequence SET seq = ? WHERE name = 'equipment' OR name = 'equipment_new'",
        [seq],
      );
      await txn.rawUpdate(
        "UPDATE sqlite_sequence SET name = 'equipment' WHERE name = 'equipment_new'",
      );

      await txn.execute('DROP TABLE _equip_id_map');
    });

    print('ΟΚ: Πίνακας equipment μετεγκαταστάθηκε (${rows.length} εγγραφές). Στήλες: id, code_equipment, type, user_id, notes.');
  } catch (e, st) {
    print('ΣΦΑΛΜΑ: $e');
    print(st);
    exit(1);
  } finally {
    await db.close();
  }
}
