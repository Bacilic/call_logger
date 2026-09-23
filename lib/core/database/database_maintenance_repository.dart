import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqflite.dart';

import 'database_helper.dart';
import 'database_snapshot.dart';

export 'database_snapshot.dart' show DatabaseSnapshotStats;

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

/// Αντίγραφο βάσης μέσω `VACUUM INTO` — πάνω σε στιγμιότυπο.
class DatabaseBackupRepository {
  DatabaseBackupRepository(this.db);

  final Database db;

  /// Ως πότε επιτρέπεται να κρατιέται το κλείδωμα για το στιγμιότυπο.
  ///
  /// Δεν είναι ο αναμενόμενος χρόνος (≈1,5 δευτ. για 17 MB) αλλά το ταβάνι σε
  /// αρρωστημένο δίκτυο: αν δεν προλάβει, το αντίγραφο αποτυγχάνει με μήνυμα
  /// και ξαναδοκιμάζεται αργότερα, αντί να παγώνει τους συναδέλφους επ' αόριστον.
  static const Duration snapshotBudget = Duration(seconds: 30);

  /// Γράφει πλήρες αντίγραφο της βάσης στο [destinationPath].
  ///
  /// **Όχι απευθείας πάνω στη ζωντανή βάση.** Το `VACUUM INTO` διαβάζει
  /// ολόκληρο το αρχείο, και όσο διαβάζει κανείς άλλος δεν ολοκληρώνει
  /// εγγραφή — ούτε, όσο μια εγγραφή περιμένει, απλή ανάγνωση. Σε κοινόχρηστη
  /// βάση με δεύτερο σταθμό ανοιχτό αυτό κράτησε 12 δευτερόλεπτα (13,7 MB,
  /// 23/09/2026): αρκετά για να λήξουν οι εγγραφές των συναδέλφων και να
  /// φανούν «Χρήστης #2» στις οθόνες τους. Με στιγμιότυπο το κλείδωμα κρατά
  /// όσο η αντιγραφή του αρχείου (~1,3 δευτ.), και το βαρύ κομμάτι γίνεται
  /// τοπικά.
  ///
  /// Επιστρέφει τι κόστισε το στιγμιότυπο, ή `null` όταν η βάση δεν
  /// επιδέχεται στιγμιότυπο (WAL, μνήμη) και το αντίγραφο βγήκε με τον παλιό,
  /// απευθείας τρόπο.
  Future<DatabaseSnapshotStats?> vacuumInto(String destinationPath) async {
    final literal = destinationPath.replaceAll("'", "''");
    final source = db.path;
    if (!p.isAbsolute(source)) {
      await db.execute("VACUUM INTO '$literal'");
      return null;
    }

    final DatabaseSnapshot snapshot;
    try {
      snapshot = await takeDatabaseSnapshot(
        source,
        deadline: DateTime.now().add(snapshotBudget),
      );
    } on DatabaseSnapshotUnsupported {
      await db.execute("VACUUM INTO '$literal'");
      return null;
    }
    try {
      final local = await openDatabase(snapshot.path, singleInstance: false);
      try {
        await local.execute("VACUUM INTO '$literal'");
      } finally {
        await local.close();
      }
      return snapshot.stats;
    } finally {
      await snapshot.dispose();
    }
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
