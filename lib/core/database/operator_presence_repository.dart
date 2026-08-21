import 'package:sqflite_common/sqlite_api.dart';

import '../models/operator_presence.dart';

/// Persistence του «ποιος είδε τη βάση, από πού, πότε» (πίνακας
/// `operator_presence`).
///
/// Μία γραμμή ανά **συνδυασμό χρήστη και σταθμού**: το ίδιο προφίλ μπορεί να
/// χρησιμοποιείται από δύο θέσεις ταυτόχρονα, και μία γραμμή ανά πρόσωπο θα
/// έσβηνε σιωπηλά τη μία με την άλλη.
class OperatorPresenceRepository {
  OperatorPresenceRepository(this.db);

  final DatabaseExecutor db;

  static const String tableName = 'operator_presence';

  /// Σημειώνει «είμαι εδώ» για αυτόν τον χρήστη σε αυτόν τον σταθμό.
  ///
  /// Αντικαθιστά τη χρονοσφραγίδα της ίδιας γραμμής — δεν συσσωρεύει ιστορικό.
  /// Το πλήθος των γραμμών φράσσεται από «πρόσωπα × μηχανήματα», οπότε δεν
  /// χρειάζεται εκκαθάριση.
  Future<void> touch({
    required int operatorId,
    required String station,
    required DateTime at,
  }) async {
    final name = station.trim();
    if (name.isEmpty) return;
    await db.insert(tableName, {
      'operator_id': operatorId,
      'station': name,
      'last_seen_at': at.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Όλα τα σημάδια, νεότερο πρώτο. Ο πίνακας είναι μικροσκοπικός.
  Future<List<OperatorPresence>> getAll() async {
    final rows = await db.query(tableName, orderBy: 'last_seen_at DESC');
    return [for (final row in rows) ?OperatorPresence.fromMap(row)];
  }

  /// Τα σημάδια ενός χρήστη, νεότερο πρώτο.
  Future<List<OperatorPresence>> forOperator(int operatorId) async {
    final rows = await db.query(
      tableName,
      where: 'operator_id = ?',
      whereArgs: [operatorId],
      orderBy: 'last_seen_at DESC',
    );
    return [for (final row in rows) ?OperatorPresence.fromMap(row)];
  }
}
