import 'package:sqflite_common/sqlite_api.dart';

import 'audit_service.dart';

/// Ο μετρητής αφύλακτων αλλαγών των αντιγράφων ασφαλείας.
///
/// «Ρολόι» είναι ο αύξων αριθμός του `audit_log` (AUTOINCREMENT — μονότονος
/// ακόμη και μετά από εκκαθάριση Ιστορικού): ζει μέσα στην κοινόχρηστη βάση,
/// άρα μετρά και τις αλλαγές των συναδέλφων, και δεν τον «δηλητηριάζει» ο
/// παλμός παρουσίας (που δεν γράφει στο Ιστορικό). Οι εγγραφές του ίδιου του
/// μηχανισμού αντιγράφων (entity_type `backup`) εξαιρούνται από το μέτρημα —
/// αλλιώς κάθε αντίγραφο θα «γεννούσε» μία αλλαγή και ο κύκλος δεν θα
/// έκλεινε ποτέ.
class BackupPendingChangesRepository {
  BackupPendingChangesRepository(this.db);

  final DatabaseExecutor db;

  /// Πλήθος αλλαγών μετά το σημάδι [lastBackupAuditId], χωρίς τις εγγραφές
  /// του μηχανισμού αντιγράφων.
  ///
  /// Χωρίς σημάδι (βάση που δεν έχει ακόμη αντίγραφο με το νέο σύστημα)
  /// μετρά από το [fallbackSince] — τη στιγμή του τελευταίου γνωστού
  /// αντιγράφου. Χωρίς ούτε αυτό, μετρά από την αρχή: τίποτα δεν είναι
  /// αποδεδειγμένα φυλαγμένο.
  ///
  /// Το `timestamp` είναι ISO8601 κείμενο, οπότε η σύγκριση είναι
  /// λεξικογραφική — ίδιο μοτίβο με τα φίλτρα ημερομηνίας του Ιστορικού.
  Future<int> countPendingSince(
    int? lastBackupAuditId, {
    DateTime? fallbackSince,
  }) async {
    if (lastBackupAuditId == null && fallbackSince != null) {
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM audit_log '
        'WHERE timestamp > ? AND (entity_type IS NULL OR entity_type != ?)',
        [fallbackSince.toIso8601String(), AuditEntityTypes.backup],
      );
      return (rows.first['c'] as int?) ?? 0;
    }
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM audit_log '
      'WHERE id > ? AND (entity_type IS NULL OR entity_type != ?)',
      [lastBackupAuditId ?? 0, AuditEntityTypes.backup],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  /// Ο μεγαλύτερος αύξων αριθμός του Ιστορικού αυτή τη στιγμή — το νέο σημάδι
  /// μετά από επιτυχές αντίγραφο. `0` σε άδειο Ιστορικό.
  Future<int> latestAuditId() async {
    final rows = await db.rawQuery('SELECT MAX(id) AS m FROM audit_log');
    return (rows.first['m'] as int?) ?? 0;
  }
}
