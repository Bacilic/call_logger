import 'package:call_logger/core/database/old_database/old_database_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  test('το σχήμα equipment περιλαμβάνει τις στήλες δικτύου', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    try {
      for (final statement in oldDatabaseCreateStatements) {
        await db.execute(statement);
      }
      for (final statement in oldDatabaseIndexStatements) {
        await db.execute(statement);
      }
      final columns = (await db.rawQuery('PRAGMA table_info(equipment)'))
          .map((row) => row['name'] as String)
          .toSet();
      expect(columns, containsAll(<String>[
        'ip_address',
        'network_name',
        'network_source',
        'network_node',
        'network_vlan',
        'network_mac',
        'network_description',
        'network_comments',
      ]));
      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' "
        "AND name = 'idx_equipment_ip_address'",
      );
      expect(indexes, hasLength(1));
    } finally {
      await db.close();
    }
  });

  test('createOldDatabaseIntegrityArtifacts applies owner identity index', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    try {
      for (final statement in oldDatabaseCreateStatements) {
        await db.execute(statement);
      }
      await createOldDatabaseIntegrityArtifacts(db);
      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' "
        "AND name = 'ux_owners_identity_key_clean'",
      );
      expect(indexes, hasLength(1));
    } finally {
      await db.close();
    }
  });
}
