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
  ///
  /// **Όλα σε μία συναλλαγή, επίτηδες.** Σε βάση πάνω από κοινόχρηστο φάκελο το
  /// κόστος πληρώνεται **ανά συναλλαγή**, όχι ανά δεδομένο: κάθε μία φτιάχνει,
  /// συγχρονίζει και σβήνει το αρχείο ημερολογίου. Μετρημένο στην πραγματική
  /// βάση 21/09/2026: μία συναλλαγή 2,4 δευτ., δύο διαδοχικές 4,9 δευτ., οι
  /// ίδιες δύο εντολές μαζί 2,4 δευτ. Ο χτύπος τρέχει κάθε λεπτό από κάθε
  /// σταθμό, οπότε η διαφορά είναι μόνιμη διαμάχη για το κλείδωμα.
  ///
  /// Το [handOverOtherOperators] ζητά **και** την παράδοση. Χρειάζεται μόνο
  /// όταν άλλαξε ο χρήστης· στους περιοδικούς χτύπους είναι δεύτερη εγγραφή
  /// που δεν βρίσκει ποτέ τίποτα να αλλάξει.
  Future<void> touch({
    required int operatorId,
    required String station,
    required DateTime at,
    String? instance,
    String? appVersion,
    bool handOverOtherOperators = true,
  }) async {
    final name = station.trim();
    if (name.isEmpty) return;
    final holder = instance?.trim();
    final version = appVersion?.trim();

    Future<void> write(DatabaseExecutor target) async {
      await target.insert(tableName, {
        'operator_id': operatorId,
        'station': name,
        'last_seen_at': at.toIso8601String(),
        'instance': (holder == null || holder.isEmpty) ? null : holder,
        'app_version': (version == null || version.isEmpty) ? null : version,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      if (!handOverOtherOperators) return;
      if (holder == null || holder.isEmpty) return;
      await target.update(
        tableName,
        {'instance': null},
        where: 'instance = ? AND operator_id <> ?',
        whereArgs: [holder, operatorId],
      );
    }

    // Όταν ο καλών μας έδωσε ήδη ανοιχτή συναλλαγή, γράφουμε μέσα της: μια
    // δεύτερη φωλιασμένη συναλλαγή θα περίμενε τον εαυτό της.
    final executor = db;
    if (executor is Database) {
      await executor.transaction(write);
      return;
    }
    await write(executor);
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

  /// Όλα τα σημάδια μαζί με το όνομα του ανθρώπου, νεότερο πρώτο.
  ///
  /// Ένα ερώτημα αντί για δύο: η λίστα «ποιοι κρατούν τη βάση ανοιχτή» θέλει
  /// πάντα και τα δύο, και η βάση ζει σε δικτυακό φάκελο όπου κάθε επιπλέον
  /// διαδρομή μετράει. Το `LEFT JOIN` κρατά και ίχνη χρηστών που διαγράφηκαν
  /// στο μεταξύ — καλύτερα ένας σταθμός χωρίς όνομα παρά μια συνεδρία που
  /// εξαφανίζεται από τη λίστα ενώ κρατά ακόμη το αρχείο.
  Future<List<({OperatorPresence presence, String? operatorName})>>
  getAllWithNames() async {
    final rows = await db.rawQuery(
      'SELECT p.*, o.display_name AS operator_name '
      'FROM $tableName p '
      'LEFT JOIN operators o ON o.id = p.operator_id '
      'ORDER BY p.last_seen_at DESC',
    );
    final out = <({OperatorPresence presence, String? operatorName})>[];
    for (final row in rows) {
      final presence = OperatorPresence.fromMap(row);
      if (presence == null) continue;
      final name = (row['operator_name'] as String?)?.trim();
      out.add((
        presence: presence,
        operatorName: (name == null || name.isEmpty) ? null : name,
      ));
    }
    return out;
  }

  /// Παραδίδει το ίχνος αυτού του ανοιχτού αντιγράφου: η γραμμή μένει ως
  /// ιστορικό, αλλά παύει να μετρά ως ζωντανή σύνδεση.
  ///
  /// Καλείται στο **κανονικό** κλείσιμο. Χωρίς αυτό, όποιος κλείνει σωστά την
  /// εφαρμογή φαίνεται συνδεδεμένος για όσο κρατά το παράθυρο φρεσκάδας —
  /// ακριβώς την ώρα που ο επόμενος κοιτάζει αν άδειασε το πεδίο.
  Future<void> release({required String instance}) async {
    final holder = instance.trim();
    if (holder.isEmpty) return;
    await db.update(
      tableName,
      {'instance': null},
      where: 'instance = ?',
      whereArgs: [holder],
    );
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
