// Εφάπαξ migration: snapshot κειμένων/τηλεφώνου στον πίνακα tasks.
// Τρέξιμο: dart run tool/add_tasks_snapshot_text_columns.dart

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
      'Δεν βρέθηκε βάση. Ψάχτηκαν:\n${candidates.map((e) => '  - $e').join('\n')}',
    );
    exit(1);
  }

  stdout.writeln('Σύνδεση: $dbPath');
  final db = await openDatabase(dbPath, singleInstance: false);

  try {
    await addColumnIfNotExists(db, 'tasks', 'phone_id', 'INTEGER');
    await addColumnIfNotExists(db, 'tasks', 'phone_text', 'TEXT');
    await addColumnIfNotExists(db, 'tasks', 'user_text', 'TEXT');
    await addColumnIfNotExists(db, 'tasks', 'equipment_text', 'TEXT');
    await addColumnIfNotExists(db, 'tasks', 'department_text', 'TEXT');

    stdout.writeln('\nPRAGMA table_info(tasks):');
    final info = await db.rawQuery('PRAGMA table_info(tasks)');
    for (final row in info) {
      stdout.writeln('  ${row['name']} (${row['type']})');
    }
    stdout.writeln(
      '\nΟλοκληρώθηκε (ALTER μόνο· τα υπάρχοντα rows παραμένουν).',
    );
  } catch (e, st) {
    stderr.writeln('Σφάλμα: $e\n$st');
    exit(1);
  } finally {
    await db.close();
  }
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
    stdout.writeln('Προσθήκη $table.$column ($type)...');
    await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
  } else {
    stdout.writeln('Υπάρχει ήδη: $table.$column');
  }
}
