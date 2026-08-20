import 'package:sqflite_common/sqlite_api.dart';

import '../models/operator.dart';
import '../utils/search_text_normalizer.dart';

/// Persistence των χρηστών της εφαρμογής (πίνακας `operators`).
///
/// Δεν έχει σχέση με το `UserRepository`: εκείνο χειρίζεται τους **υπαλλήλους
/// του νοσοκομείου**. Εδώ ζουν όσοι χειρίζονται την εφαρμογή.
class OperatorRepository {
  OperatorRepository(this.db);

  final DatabaseExecutor db;

  static const String tableName = 'operators';

  /// Όλα τα προφίλ, με τους διαχειριστές πρώτους και μετά αλφαβητικά.
  Future<List<Operator>> getAll() async {
    final rows = await db.query(
      tableName,
      orderBy: 'is_admin DESC, display_name COLLATE NOCASE ASC',
    );
    return [for (final row in rows) Operator.fromMap(row)];
  }

  /// Το προφίλ που ταυτίζεται με λογαριασμό Windows· `null` όταν δεν υπάρχει.
  ///
  /// Ο λογαριασμός κανονικοποιείται πριν τη σύγκριση, ώστε «VDrosos» και
  /// «vdrosos» να είναι το ίδιο πρόσωπο.
  Future<Operator?> findByWindowsAccount(String? rawAccount) async {
    final account = normalizeWindowsAccount(rawAccount);
    if (account == null) return null;
    final rows = await db.query(
      tableName,
      where: 'windows_account = ?',
      whereArgs: [account],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Operator.fromMap(rows.first);
  }

  Future<Operator?> findById(int id) async {
    final rows = await db.query(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Operator.fromMap(rows.first);
  }

  Future<int> count() async {
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $tableName');
    if (rows.isEmpty) return 0;
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  /// Πόσοι διαχειριστές υπάρχουν — ο τελευταίος δεν επιτρέπεται να χαθεί.
  Future<int> countAdmins() async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM $tableName WHERE is_admin = 1',
    );
    if (rows.isEmpty) return 0;
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  /// Άλλο προφίλ με ισοδύναμο εμφανιζόμενο όνομα.
  ///
  /// Το Ιστορικό κρατά **ονόματα**, όχι παραπομπές: δύο ίδια ονόματα δεν
  /// ξεχωρίζουν ποτέ ξανά.
  ///
  /// Η σύγκριση γίνεται στον κώδικα και όχι με `COLLATE NOCASE`: η συλλογή
  /// της SQLite αγνοεί πεζά/κεφαλαία **μόνο στα λατινικά**, οπότε «Μαρία Π.»
  /// και «μαρία π.» θα περνούσαν ως διαφορετικοί άνθρωποι. Ο κανονικοποιητής
  /// της εφαρμογής ισοπεδώνει και τους τόνους — που είναι το ζητούμενο, αφού
  /// «Μαρια» και «Μαρία» ούτε αυτά ξεχωρίζουν σε μια λίστα ιστορικού.
  Future<Operator?> findByDisplayName(
    String displayName, {
    int? excludeId,
  }) async {
    final target = SearchTextNormalizer.normalizeForSearch(displayName.trim());
    if (target.isEmpty) return null;
    for (final row in await db.query(tableName)) {
      final candidate = Operator.fromMap(row);
      if (candidate.id == excludeId) continue;
      final normalized = SearchTextNormalizer.normalizeForSearch(
        candidate.displayName,
      );
      if (normalized == target) return candidate;
    }
    return null;
  }

  /// Καταχωρεί νέο προφίλ και επιστρέφει το αποθηκευμένο, με το id του.
  Future<Operator> insert(Operator operator) async {
    final data = Map<String, Object?>.from(operator.toMap())..remove('id');
    final id = await db.insert(tableName, data);
    return operator.copyWith(id: id);
  }

  /// Ενημερώνει υπάρχον προφίλ. Χωρίς id δεν υπάρχει τι να ενημερωθεί.
  Future<void> update(Operator operator) async {
    final id = operator.id;
    if (id == null) {
      throw ArgumentError.value(
        operator,
        'operator',
        'Το προφίλ δεν έχει αποθηκευτεί ακόμη — δεν υπάρχει id για ενημέρωση.',
      );
    }
    final data = Map<String, Object?>.from(operator.toMap())..remove('id');
    await db.update(tableName, data, where: 'id = ?', whereArgs: [id]);
  }
}
