// Εφάπαξ script: αρίθμηση users.id από 1 και ταύτιση equipment.user_id / calls.caller_id.
// Τρέξε μία φορά όταν η βάση είναι ακόμα μικρή. ΜΗ το ενσωματώνεις στην εφαρμογή.
//
// Χρήση (από ρίζα project):
//   dart run tool/renumber_users_id_once.dart
//   dart run tool/renumber_users_id_once.dart "C:\path\to\call_logger.db"
//
// Αν δεν δοθεί διαδρομή, χρησιμοποιείται: Data Base/call_logger.db (τοπική).
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
    final users = await db.rawQuery(
      'SELECT id, name, department, phone, email, location, notes FROM users ORDER BY id',
    );
    if (users.isEmpty) {
      print('Δεν υπάρχουν χρήστες. Τίποτα να γίνει.');
      return;
    }

    final oldToNew = <int, int>{};
    for (var i = 0; i < users.length; i++) {
      oldToNew[users[i]['id'] as int] = i + 1;
    }

    await db.transaction((txn) async {
      await txn.execute(
        'CREATE TABLE IF NOT EXISTS _id_map (old_id INTEGER PRIMARY KEY, new_id INTEGER)',
      );
      for (final e in oldToNew.entries) {
        await txn.insert('_id_map', {'old_id': e.key, 'new_id': e.value});
      }

      await txn.rawUpdate(
        'UPDATE equipment SET user_id = (SELECT new_id FROM _id_map WHERE old_id = equipment.user_id)',
      );
      await txn.rawUpdate(
        'UPDATE calls SET caller_id = (SELECT new_id FROM _id_map WHERE old_id = calls.caller_id)',
      );

      await txn.execute('''
        CREATE TABLE users_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT,
          department TEXT,
          phone TEXT,
          email TEXT,
          location TEXT,
          notes TEXT
        )
      ''');
      await txn.rawInsert('''
        INSERT INTO users_new (id, name, department, phone, email, location, notes)
        SELECT m.new_id, u.name, u.department, u.phone, u.email, u.location, u.notes
        FROM users u
        INNER JOIN _id_map m ON u.id = m.old_id
      ''');

      await txn.execute('DROP TABLE users');
      await txn.execute('ALTER TABLE users_new RENAME TO users');

      final maxId = await txn.rawQuery('SELECT MAX(id) AS m FROM users');
      final seq = (maxId.first['m'] as int?) ?? 0;
      await txn.rawUpdate(
        "UPDATE sqlite_sequence SET seq = ? WHERE name = 'users' OR name = 'users_new'",
        [seq],
      );
      await txn.rawUpdate(
        "UPDATE sqlite_sequence SET name = 'users' WHERE name = 'users_new'",
      );

      await txn.execute('DROP TABLE _id_map');
    });

    print('ΟΚ: Αρίθμηση users.id από 1 ολοκληρώθηκε (${users.length} χρήστες).');
  } finally {
    await db.close();
  }
}
