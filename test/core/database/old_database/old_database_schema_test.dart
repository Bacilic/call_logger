import 'package:call_logger/core/database/old_database/old_database_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
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
