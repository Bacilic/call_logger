// Εφάπαξ script: αντιμετάθεση τιμών first_name ↔ last_name στον πίνακα users.
// Διορθώνει το λάθος όπου το μικρό όνομα ήταν στο last_name και το επώνυμο στο first_name.
// Τρέξε μία φορά μόνο.
//
// Χρήση (από ρίζα project):
//   dart run tool/swap_users_first_last_once.dart
//   dart run tool/swap_users_first_last_once.dart "C:\path\to\call_logger.db"
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
    final rows = await db.rawQuery('SELECT id, first_name, last_name FROM users');
    if (rows.isEmpty) {
      print('Ο πίνακας users είναι κενός. Τίποτα να γίνει.');
      await db.close();
      exit(0);
    }

    for (final row in rows) {
      final id = row['id'] as int?;
      if (id == null) continue;
      final oldFirst = row['first_name'] as String?;
      final oldLast = row['last_name'] as String?;
      await db.rawUpdate(
        'UPDATE users SET first_name = ?, last_name = ? WHERE id = ?',
        [oldLast ?? '', oldFirst ?? '', id],
      );
    }

    print('ΟΚ: Αντιμετατέθηκαν οι τιμές first_name ↔ last_name σε ${rows.length} εγγραφές.');
  } catch (e, st) {
    print('ΣΦΑΛΜΑ: $e');
    print(st);
    exit(1);
  } finally {
    await db.close();
  }
}
