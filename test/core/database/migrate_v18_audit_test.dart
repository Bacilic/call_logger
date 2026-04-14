import 'package:call_logger/core/database/database_v1_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('migrateDatabaseToV18 είναι idempotent και προσθέτει στήλες', () async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      singleInstance: false,
    );
    try {
      await db.execute('''
        CREATE TABLE audit_log (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          action TEXT,
          timestamp TEXT,
          user_performing TEXT,
          details TEXT
        )
      ''');
      await migrateDatabaseToV18(db);
      await migrateDatabaseToV18(db);

      final info = await db.rawQuery('PRAGMA table_info(audit_log)');
      final names = info.map((r) => r['name'] as String).toSet();
      expect(names, containsAll(<String>[
        'entity_type',
        'entity_id',
        'entity_name',
        'old_values_json',
        'new_values_json',
      ]));

      final idx = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='audit_log'",
      );
      final idxNames = idx.map((r) => r['name'] as String).toSet();
      expect(idxNames, contains('idx_audit_log_entity_type_entity_id'));
      expect(idxNames, contains('idx_audit_log_timestamp'));
      expect(idxNames, contains('idx_audit_log_action'));
    } finally {
      await db.close();
    }
  });
}
