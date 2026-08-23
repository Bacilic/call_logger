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
  /// Το [instance] ταυτοποιεί το **ανοιχτό αντίγραφο** που αφήνει το ίχνος.
  ///
  /// Ένα αντίγραφο έχει έναν χρήστη τη φορά: μόλις κάποιος αναλάβει, οι
  /// προηγούμενοι του ίδιου αντιγράφου **παραδίδουν** — η γραμμή τους μένει ως
  /// ιστορικό («πότε ήταν τελευταία φορά εδώ»), αλλά χάνει τον κάτοχό της και
  /// παύει να μετρά ως ζωντανή σύνδεση.
  ///
  /// Η παράδοση κοιτάζει το αντίγραφο και όχι τον σταθμό: δύο εφαρμογές
  /// ανοιχτές στον ίδιο υπολογιστή (π.χ. η κανονική και η δοκιμαστική) είναι
  /// δύο αληθινές παρουσίες, και δεν επιτρέπεται να σβήνουν η μία την άλλη.
  Future<void> touch({
    required int operatorId,
    required String station,
    required DateTime at,
    String? instance,
  }) async {
    final name = station.trim();
    if (name.isEmpty) return;
    final holder = instance?.trim();

    await db.insert(tableName, {
      'operator_id': operatorId,
      'station': name,
      'last_seen_at': at.toIso8601String(),
      'instance': (holder == null || holder.isEmpty) ? null : holder,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    if (holder == null || holder.isEmpty) return;
    await db.update(
      tableName,
      {'instance': null},
      where: 'instance = ? AND operator_id <> ?',
      whereArgs: [holder, operatorId],
    );
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
