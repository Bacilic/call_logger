// Εφάπαξ script: μετεγκατάσταση πίνακα users από name σε last_name + first_name.
//
// Λογική split: last_name = τελευταία λέξη του name (trim & split by κενό),
// first_name = όλες οι άλλες λέξεις (join με κενό). Τα πεδία department, location, notes
// δεν αλλάζουν. Το phone παραμένει χωρίς UNIQUE ώστε να επιτρέπονται duplicates (π.χ. πολλά τηλέφωνα).
//
// Τρέξε μία φορά. ΜΗ το ενσωματώνεις στην εφαρμογή.
//
// Χρήση (από ρίζα project):
//   dart run tool/migrate_users_first_last_once.dart
//   dart run tool/migrate_users_first_last_once.dart "C:\path\to\call_logger.db"
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
    final info = await db.rawQuery('PRAGMA table_info(users)');
    final columns = (info.map((e) => e['name'] as String?)).whereType<String>().toSet();
    if (!columns.contains('name')) {
      print('Ο πίνακας users έχει ήδη το νέο σχήμα (last_name, first_name). Τίποτα να γίνει.');
      await _printTableStructure(db);
      await db.close();
      exit(0);
    }

    // 1) Πρόσθεσε first_name, last_name
    await db.execute('ALTER TABLE users ADD COLUMN first_name TEXT');
    await db.execute('ALTER TABLE users ADD COLUMN last_name TEXT');

    // 2) Πλήρωσε με split από name (last_name = τελευταία λέξη, first_name = υπόλοιπο)
    final rows = await db.rawQuery('SELECT id, name FROM users');
    for (final row in rows) {
      final id = row['id'] as int?;
      final nameRaw = row['name'] as String?;
      if (id == null) continue;
      final parts = (nameRaw ?? '').trim().split(RegExp(r'\s+'));
      final String lastName;
      final String firstName;
      if (parts.isEmpty) {
        lastName = '';
        firstName = '';
      } else if (parts.length == 1) {
        lastName = parts.single;
        firstName = parts.single;
      } else {
        lastName = parts.last;
        firstName = parts.sublist(0, parts.length - 1).join(' ');
      }
      await db.rawUpdate(
        'UPDATE users SET first_name = ?, last_name = ? WHERE id = ?',
        [firstName, lastName, id],
      );
    }

    // 3) Αντικατάσταση name: νέος πίνακας με last_name NOT NULL, first_name NOT NULL
    await db.execute('''
      CREATE TABLE users_new (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        last_name TEXT NOT NULL,
        first_name TEXT NOT NULL,
        phone TEXT,
        department TEXT,
        location TEXT,
        notes TEXT
      )
    ''');
    await db.execute('''
      INSERT INTO users_new (id, last_name, first_name, phone, department, location, notes)
      SELECT id, last_name, first_name, phone, department, location, notes FROM users
    ''');
    await db.execute('DROP TABLE users');
    await db.execute('ALTER TABLE users_new RENAME TO users');

    final maxId = await db.rawQuery('SELECT MAX(id) AS m FROM users');
    final seq = (maxId.first['m'] as int?) ?? 0;
    await db.rawUpdate(
      "UPDATE sqlite_sequence SET seq = ? WHERE name = 'users'",
      [seq],
    );

    // 4) Σήμανση έκδοσης ώστε η εφαρμογή να μην ξανατρέξει migration
    await db.execute('PRAGMA user_version = 5');

    print('ΟΚ: Πίνακας users μετεγκαταστάθηκε. Στήλες: id, last_name, first_name, phone, department, location, notes.');
    await _printTableStructure(db);
  } catch (e, st) {
    print('ΣΦΑΛΜΑ: $e');
    print(st);
    exit(1);
  } finally {
    await db.close();
  }
}

Future<void> _printTableStructure(Database db) async {
  final info = await db.rawQuery('PRAGMA table_info(users)');
  print('Δομή πίνακα users:');
  for (final col in info) {
    final name = col['name'];
    final type = col['type'];
    final notnull = col['notnull'] as int?;
    final pk = col['pk'] as int?;
    print('  $name $type${notnull == 1 ? ' NOT NULL' : ''}${pk == 1 ? ' PRIMARY KEY' : ''}');
  }
}
