// Εφάπαξ script: προσθήκη στηλών απομακρυσμένης σύνδεσης στον πίνακα equipment.
// Στήλες: custom_ip TEXT, anydesk_id TEXT, default_remote_tool TEXT.
// Idempotent: ελέγχει ύπαρξη στηλών πριν την προσθήκη.
//
// Τρέξε μία φορά. ΜΗ το ενσωματώνεις στην εφαρμογή.
//
// Χρήση (από ρίζα project):
//   dart run tool/add_equipment_remote_columns_once.dart
//   dart run tool/add_equipment_remote_columns_once.dart "C:\path\to\call_logger.db"
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _columnsToAdd = [
  ('custom_ip', 'TEXT'),
  ('anydesk_id', 'TEXT'),
  ('default_remote_tool', 'TEXT'),
];

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
    final info = await db.rawQuery('PRAGMA table_info(equipment)');
    final existingColumns =
        (info.map((e) => e['name'] as String?)).whereType<String>().toSet();

    int added = 0;
    for (final (name, type) in _columnsToAdd) {
      if (!existingColumns.contains(name)) {
        await db.execute('ALTER TABLE equipment ADD COLUMN $name $type');
        added++;
        print('Προστέθηκε στήλη: $name');
      } else {
        print('Στήλη υπάρχει ήδη: $name');
      }
    }

    if (added == 0) {
      print('Όλες οι στήλες υπάρχουν ήδη. Τίποτα να γίνει.');
    } else {
      print('ΟΚ: Προστέθηκαν $added στήλες στον πίνακα equipment.');
    }
  } catch (e, st) {
    print('ΣΦΑΛΜΑ: $e');
    print(st);
    exit(1);
  } finally {
    await db.close();
  }
}
