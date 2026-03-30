// Εφάπαξ migration: προσθήκη στηλών στον πίνακα tasks χωρίς διαγραφή δεδομένων.
// Τρέξιμο από τη ρίζα του project: dart run tool/add_tasks_columns.dart
//
// Διαδρομές (με σειρά προτίμησης):
// 1) Data Base/call_logger.db — CLI: AppConfig.localDevDbPath · εφαρμογή: portable defaultDbPath
// 2) local_dev_db/call_logger_dev.db — εναλλακτικό dev path

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final candidates = <String>[
    p.join(Directory.current.path, 'Data Base', 'call_logger.db'),
    p.join(Directory.current.path, 'local_dev_db', 'call_logger_dev.db'),
  ];

  String? dbPath;
  for (final path in candidates) {
    if (File(path).existsSync()) {
      dbPath = path;
      break;
    }
  }

  if (dbPath == null) {
    stderr.writeln(
      'Το αρχείο της βάσης δεν βρέθηκε. Ψάχτηκαν:\n'
      '${candidates.map((e) => '  - $e').join('\n')}\n'
      'Τρέξε από τη ρίζα του project (call_logger) ή δημιούργησε/άνοιξε την εφαρμογή πρώτα.',
    );
    exit(1);
  }

  stdout.writeln('Σύνδεση στη βάση: $dbPath');

  final db = await openDatabase(dbPath, singleInstance: false);

  try {
    await addColumnIfNotExists(db, 'tasks', 'department_id', 'INTEGER');
    await ensureTasksCallerIdColumn(db);
    await addColumnIfNotExists(db, 'tasks', 'equipment_id', 'INTEGER');

    stdout.writeln('\nΕπαλήθευση PRAGMA table_info(tasks):');
    final info = await db.rawQuery('PRAGMA table_info(tasks)');
    for (final row in info) {
      stdout.writeln('  ${row['name']} (${row['type']})');
    }
    stdout.writeln('\nΗ βάση ενημερώθηκε επιτυχώς (τα υπάρχοντα δεδομένα παραμένουν).');
  } catch (e, st) {
    stderr.writeln('Σφάλμα κατά την ενημέρωση: $e');
    stderr.writeln('$st');
    exit(1);
  } finally {
    await db.close();
  }
}

/// tasks: caller_id (μετονομασία από user_id αν υπάρχει).
Future<void> ensureTasksCallerIdColumn(Database db) async {
  final info = await db.rawQuery('PRAGMA table_info(tasks)');
  final names = info
      .map((row) => row['name'] as String?)
      .whereType<String>()
      .toSet();

  if (names.contains('caller_id')) {
    stdout.writeln('Η στήλη caller_id υπάρχει ήδη στον πίνακα tasks.');
    return;
  }
  if (names.contains('user_id')) {
    stdout.writeln('Μετονομασία user_id → caller_id στον πίνακα tasks...');
    await db.execute('ALTER TABLE tasks RENAME COLUMN user_id TO caller_id');
    return;
  }
  stdout.writeln('Προσθήκη στήλης caller_id στον πίνακα tasks...');
  await db.execute('ALTER TABLE tasks ADD COLUMN caller_id INTEGER');
}

Future<void> addColumnIfNotExists(
  Database db,
  String table,
  String column,
  String type,
) async {
  final info = await db.rawQuery('PRAGMA table_info($table)');
  final exists = info.any((row) => row['name'] == column);

  if (!exists) {
    stdout.writeln('Προσθήκη στήλης $column στον πίνακα $table...');
    await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
  } else {
    stdout.writeln('Η στήλη $column υπάρχει ήδη στον πίνακα $table.');
  }
}
