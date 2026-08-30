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

  /// Από πόσους **διαφορετικούς υπολογιστές** έχει ανοίξει αυτή η βάση.
  ///
  /// Το αυθεντικό κριτήριο του «κοινόχρηστη ή όχι». Η διαδρομή του αρχείου και
  /// το όνομα που της έδωσε ο χρήστης είναι ενδείξεις που μπορεί να πέσουν
  /// έξω· τα ίχνη σύνδεσης είναι γεγονός γραμμένο μέσα στο ίδιο το αρχείο, και
  /// ταξιδεύουν μαζί του.
  ///
  /// Μετρά **σταθμούς**, όχι γραμμές: δύο προφίλ στον ίδιο υπολογιστή είναι
  /// ένας υπολογιστής. Και μετρά **ιστορικό**, όχι ζωντανές συνδέσεις — μια
  /// βάση δεν παύει να είναι κοινόχρηστη επειδή ο συνάδελφος έκλεισε.
  Future<int> countDistinctStations() async {
    final rows = await db.rawQuery(
      'SELECT COUNT(DISTINCT station) AS c FROM $tableName',
    );
    if (rows.isEmpty) return 0;
    final raw = rows.first['c'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse('$raw') ?? 0;
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
