// Εφάπαξ script: μετεγκατάσταση πίνακα users.
// - Κατάργηση στήλης email
// - Σειρά στηλών: id, name, phone, department, location, notes
//
// Τρέξε μία φορά. ΜΗ το ενσωματώνεις στην εφαρμογή.
//
// Χρήση (από ρίζα project):
//   dart run tool/migrate_users_table_once.dart
//   dart run tool/migrate_users_table_once.dart "C:\path\to\call_logger.db"
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
    final count = await db.rawQuery('SELECT COUNT(*) AS c FROM users');
    final n = (count.first['c'] as int?) ?? 0;
    if (n == 0) {
      print('Δεν υπάρχουν χρήστες. Αναδημιουργία πίνακα users με νέο σχήμα.');
    }

    await db.transaction((txn) async {
      await txn.execute('''
        CREATE TABLE users_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT,
          phone TEXT,
          department TEXT,
          location TEXT,
          notes TEXT
        )
      ''');

      await txn.rawInsert('''
        INSERT INTO users_new (id, name, phone, department, location, notes)
        SELECT id, name, phone, department, location, notes FROM users
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
    });

    print('ΟΚ: Πίνακας users μετεγκαταστάθηκε. Στήλες: id, name, phone, department, location, notes (χωρίς email).');
  } catch (e, st) {
    print('ΣΦΑΛΜΑ: $e');
    print(st);
    exit(1);
  } finally {
    await db.close();
  }
}
