// Εφάπαξ script: κανονικοποίηση users – προσθήκη department_id, αφαίρεση department & location.
//
// Τρέξε μία φορά. ΜΗ το ενσωματώνεις στην εφαρμογή (μη auto-run από app init).
//
// Χρήση (από ρίζα project):
//   dart run tool/normalize_users_departments_once.dart
//   dart run tool/normalize_users_departments_once.dart "C:\path\to\call_logger.db"
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main(List<String> args) async {
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

  final db = await openDatabase(dbPath, singleInstance: false);

  try {
    await normalizeUsers(db);
    await db.close();
    print('Migration ολοκληρώθηκε με επιτυχία.');
  } catch (e, st) {
    await db.close();
    print('ΣΦΑΛΜΑ: $e');
    print(st);
    exit(1);
  }
}

Future<void> normalizeUsers(Database db) async {
  final rows = await db.rawQuery(
    "SELECT value FROM app_settings WHERE key = ? AND value = ?",
    ['users_normalized_v1', '1'],
  );
  if (rows.isNotEmpty) {
    print('Flag users_normalized_v1 ήδη ορισμένο. Τίποτα να γίνει.');
    return;
  }

  try {
    await db.transaction((txn) async {
      final info = await txn.rawQuery('PRAGMA table_info(users)');
      final columns = (info.map((e) => e['name'] as String?)).whereType<String>().toSet();
      if (!columns.contains('department_id')) {
        await txn.execute('ALTER TABLE users ADD COLUMN department_id INTEGER DEFAULT NULL');
        print('Προστέθηκε στήλη department_id.');
      }

      await txn.execute('''
        UPDATE users SET department_id = (
          SELECT id FROM departments WHERE departments.name = users.department LIMIT 1
        ) WHERE department IS NOT NULL
      ''');
      print('Mapping department_id ολοκληρώθηκε.');

      await txn.execute('''
        CREATE TABLE users_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          last_name TEXT NOT NULL,
          first_name TEXT NOT NULL,
          phone TEXT,
          notes TEXT,
          department_id INTEGER DEFAULT NULL
        )
      ''');
      print('Πίνακας users_new δημιουργήθηκε.');

      await txn.execute('''
        INSERT INTO users_new (id, last_name, first_name, phone, notes, department_id)
        SELECT id, last_name, first_name, phone, notes, department_id FROM users
      ''');
      print('Αντιγραφή δεδομένων σε users_new ολοκληρώθηκε.');

      await txn.execute('DROP TABLE users');
      await txn.execute('ALTER TABLE users_new RENAME TO users');
      print('Πίνακας users αντικαταστάθηκε.');

      await txn.execute('CREATE INDEX idx_users_department_id ON users(department_id)');
      print('Δημιουργήθηκε ευρετήριο idx_users_department_id.');

      await txn.execute(
        "INSERT OR REPLACE INTO app_settings (key, value) VALUES ('users_normalized_v1', '1')",
      );
      print('Flag users_normalized_v1 ορίστηκε.');
    });
  } catch (e, st) {
    print('ΣΦΑΛΜΑ κατά τη migration: $e');
    print(st);
    rethrow;
  }
}
