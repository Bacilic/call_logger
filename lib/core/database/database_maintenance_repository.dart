import 'package:sqflite_common/sqflite.dart';

import 'database_helper.dart';

/// Λειτουργίες SQL συντήρησης βάσης (VACUUM, REINDEX, εκκαθαρίσεις).
///
/// Οι φραγές πολιτικής (ποιοι πίνακες επιτρέπονται, audit) μένουν στο service —
/// εδώ ζει μόνο η εκτέλεση.
class DatabaseMaintenanceRepository {
  DatabaseMaintenanceRepository(this.db);

  final Database db;

  Future<void> vacuum() => db.execute('VACUUM');

  Future<void> reindex() => db.execute('REINDEX');

  /// `DELETE FROM` χωρίς όρους — άδειασμα ολόκληρου πίνακα.
  Future<int> deleteAllRows(String tableName) => db.delete(tableName);

  /// Εγγραφές audit με `timestamp` (ISO) πριν το [isoCutoff].
  Future<int> deleteAuditLogRowsBefore(String isoCutoff) {
    return db.delete(
      'audit_log',
      where: 'timestamp < ?',
      whereArgs: [isoCutoff],
    );
  }

  /// Κλειστές, μη διαγραμμένες εκκρεμότητες παλαιότερες του [isoCutoff]
  /// (με βάση `updated_at`, αλλιώς `created_at`).
  Future<int> deleteClosedTasksBefore({
    required String closedStatus,
    required String isoCutoff,
  }) {
    return db.delete(
      'tasks',
      where:
          'status = ? AND COALESCE(is_deleted, 0) = 0 AND COALESCE(updated_at, created_at) IS NOT NULL '
          'AND COALESCE(updated_at, created_at) < ?',
      whereArgs: [closedStatus, isoCutoff],
    );
  }
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

  Future<Map<String, int>> countRowsForTables(
    Iterable<String> tableNames,
  ) async {
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
