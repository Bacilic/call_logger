// Μεταφορά δεδομένων από παλιά βάση (π.χ. user_version 17) σε νέο αρχείο σχήματος v1.
//
// Τρέξιμο από τη ρίζα του project:
//   dart run tool/migrate_to_v1.dart "Data Base/call_logger v17.db" "Data Base/call_logger.db"
//
// Αν παραλειφθούν ορίσματα, προεπιλογές (σχετικές με CWD):
//   παλιά: Data Base/call_logger v17.db
//   νέα:   Data Base/call_logger.db
//
// Το νέο αρχείο αντικαθίσταται αν υπάρχει (διαγράφεται πριν τη δημιουργία).

import 'dart:io';

import 'package:call_logger/core/database/database_v1_schema.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Σειρά εισαγωγής (FK): πρώτα γονείς, μετά παιδιά.
const _tablesCopyOrder = <String>[
  'departments',
  'phones',
  'users',
  'user_phones',
  'equipment',
  'user_equipment',
  'categories',
  'calls',
  'tasks',
  'knowledge_base',
  'audit_log',
  'app_settings',
  'remote_tools',
  'remote_tool_args',
];

Future<bool> _tableExists(DatabaseExecutor db, String name) async {
  final r = await db.rawQuery(
    "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1",
    [name],
  );
  return r.isNotEmpty;
}

Future<List<String>> _columnNames(DatabaseExecutor db, String table) async {
  final info = await db.rawQuery('PRAGMA table_info($table)');
  return info
      .map((e) => e['name'] as String?)
      .whereType<String>()
      .toList();
}

Future<void> main(List<String> args) async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final root = Directory.current.path;
  final oldPath = args.isNotEmpty
      ? p.isAbsolute(args[0])
          ? args[0]
          : p.join(root, args[0])
      : p.join(root, 'Data Base', 'call_logger v17.db');
  final newPath = args.length > 1
      ? p.isAbsolute(args[1])
          ? args[1]
          : p.join(root, args[1])
      : p.join(root, 'Data Base', 'call_logger.db');

  final oldFile = File(oldPath);
  if (!oldFile.existsSync()) {
    stderr.writeln('Δεν βρέθηκε η παλιά βάση: $oldPath');
    exit(1);
  }

  final newFile = File(newPath);
  if (newFile.existsSync()) {
    stdout.writeln('Διαγραφή υπάρχοντος νέου αρχείου: $newPath');
    newFile.deleteSync();
  }
  final parent = newFile.parent;
  if (!parent.existsSync()) {
    parent.createSync(recursive: true);
  }

  stdout.writeln('Δημιουργία κενού σχήματος v1: $newPath');
  final fresh = await openDatabase(
    newPath,
    version: databaseSchemaVersionV1,
    onCreate: (db, _) => applyDatabaseV1Schema(db),
    singleInstance: false,
  );
  await fresh.execute('PRAGMA journal_mode = WAL;');
  await fresh.close();

  stdout.writeln('Άνοιγμα παλιάς (μόνο ανάγνωση): $oldPath');
  final oldDb = await openDatabase(
    oldPath,
    readOnly: true,
    singleInstance: false,
  );

  stdout.writeln('Άνοιγμα νέας για εγγραφή: $newPath');
  final newDb = await openDatabase(
    newPath,
    version: databaseSchemaVersionV1,
    singleInstance: false,
  );

  try {
    await newDb.execute('PRAGMA foreign_keys = OFF');

    final deleteOrder = _tablesCopyOrder.reversed.toList();
    await newDb.transaction((txn) async {
      for (final t in deleteOrder) {
        if (!await _tableExists(txn, t)) continue;
        await txn.delete(t);
      }
    });

    for (final table in _tablesCopyOrder) {
      if (!await _tableExists(oldDb, table)) {
        stdout.writeln('Παράλειψη `$table` (δεν υπάρχει στην παλιά βάση).');
        continue;
      }
      if (!await _tableExists(newDb, table)) {
        stderr.writeln('Προειδοποίηση: λείπει `$table` από τη νέα βάση — παράλειψη.');
        continue;
      }

      final targetCols = await _columnNames(newDb, table);
      final colSet = targetCols.toSet();
      final rows = await oldDb.query(table);
      if (rows.isEmpty) {
        stdout.writeln('$table: 0 γραμμές');
        continue;
      }

      await newDb.transaction((txn) async {
        for (final raw in rows) {
          final m = <String, Object?>{};
          for (final e in raw.entries) {
            if (colSet.contains(e.key)) {
              m[e.key] = e.value;
            }
          }
          await txn.insert(
            table,
            m,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
      stdout.writeln('$table: ${rows.length} γραμμές αντιγράφηκαν.');
    }

    await newDb.execute('PRAGMA foreign_keys = ON');
    stdout.writeln('Ολοκληρώθηκε. Ορίστε στις ρυθμίσεις τη διαδρομή: $newPath');
  } finally {
    await oldDb.close();
    await newDb.close();
  }
}
