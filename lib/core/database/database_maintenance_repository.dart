import 'package:sqflite_common/sqflite.dart';

import 'database_helper.dart';
/// Λειτουργίες SQL συντήρησης βάσης (VACUUM, REINDEX).
class DatabaseMaintenanceRepository {
  DatabaseMaintenanceRepository(this.db);

  final Database db;

  Future<void> vacuum() => db.execute('VACUUM');

  Future<void> reindex() => db.execute('REINDEX');
}

/// Στατιστικά `COUNT(*)` ανά πίνακα.
class DatabaseStatsRepository {
  DatabaseStatsRepository(this.db);

  final Database db;

  static String quoteId(String tableName) =>
      '"${tableName.replaceAll('"', '""')}"';

  Future<int> countRowsInTable(String tableName) async {
    final q = quoteId(tableName);
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM $q');
    final n = r.first['c'];
    return n is int ? n : int.tryParse(n.toString()) ?? 0;
  }

  Future<Map<String, int>> countRowsForTables(Iterable<String> tableNames) async {
    final out = <String, int>{};
    for (final name in tableNames) {
      out[name] = await countRowsInTable(name);
    }
    return out;
  }
}

/// Αντίγραφο βάσης μέσω `VACUUM INTO`.
class DatabaseBackupRepository {
  DatabaseBackupRepository(this.db);

  final Database db;

  Future<void> vacuumInto(String destinationPath) async {
    final literal = destinationPath.replaceAll("'", "''");
    await db.execute("VACUUM INTO '$literal'");
  }
}

/// Διευκολύνει κλήσεις χωρίς άμεσο κράτημα [Database].
class DatabaseMaintenanceRepositoryFactory {
  static Future<DatabaseMaintenanceRepository> fromHelper() async {
    final db = await DatabaseHelper.instance.database;
    return DatabaseMaintenanceRepository(db);
  }
}

class DatabaseStatsRepositoryFactory {
  static Future<DatabaseStatsRepository> fromHelper() async {
    final db = await DatabaseHelper.instance.database;
    return DatabaseStatsRepository(db);
  }
}

class DatabaseBackupRepositoryFactory {
  static Future<DatabaseBackupRepository> fromHelper() async {
    final db = await DatabaseHelper.instance.database;
    return DatabaseBackupRepository(db);
  }
}
