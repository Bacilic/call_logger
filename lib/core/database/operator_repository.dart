import 'package:sqflite_common/sqlite_api.dart';

import '../../features/operators/services/operator_save_conflict.dart';
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
  /// Το προφίλ που κατέχει αυτόν τον λογαριασμό Windows — **ενεργό ή όχι**.
  ///
  /// Η απουσία φίλτρου είναι σκόπιμη: ο έλεγχος «κατέχει ήδη κάποιος αυτόν τον
  /// λογαριασμό;» της φόρμας χρηστών οφείλει να βλέπει και τα αρχειοθετημένα,
  /// αλλιώς ο ίδιος λογαριασμός θα δινόταν σε δεύτερο προφίλ και η αναγνώριση
  /// θα διάλεγε τυχαία μόλις ξαναενεργοποιούνταν το πρώτο.
  ///
  /// Όποιος τη χρησιμοποιεί για **ταυτοποίηση** πρέπει να απορρίπτει ο ίδιος τα
  /// αρχειοθετημένα — δες [OperatorIdentity.resolveAndActivate].
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

  /// Πόσα προφίλ μπορούν να χρησιμοποιηθούν — τα αρχειοθετημένα δεν μετρούν.
  Future<int> countActive() async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM $tableName WHERE is_active = 1',
    );
    if (rows.isEmpty) return 0;
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  /// Πόσοι διαχειριστές μπορούν να **συνδεθούν** — ο τελευταίος δεν
  /// επιτρέπεται να χαθεί.
  ///
  /// Μετρά μόνο τους ενεργούς, και το όνομα το λέει: ο αρχειοθετημένος
  /// διαχειριστής δεν προσφέρεται πουθενά προς επιλογή, οπότε ως δικλείδα
  /// είναι φάντασμα. Μετρώντας τον, ο φρουρός επέτρεπε να ξεσημανθεί ο
  /// τελευταίος ενεργός — και η βάση κλείδωνε: χωρίς διαχειριστή κανείς δεν
  /// μπορεί να ορίσει διαχειριστή.
  Future<int> countActiveAdmins() async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM $tableName WHERE is_admin = 1 AND is_active = 1',
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
  ///
  /// Το [expected] είναι η εικόνα **που είχε φορτώσει η φόρμα**. Είναι
  /// υποχρεωτικό — και δεκτικό `null` μόνο ρητά — γιατί η αποθήκευση γράφει
  /// ολόκληρη τη γραμμή: χωρίς αφετηρία, ο δεύτερος διαχειριστής σβήνει ό,τι
  /// έδωσε ο πρώτος και κανείς δεν το μαθαίνει. Με προαιρετική παράμετρο ο
  /// επόμενος καλών θα την παρέλειπε χωρίς να το προσέξει.
  ///
  /// Με [force] `true` η εγγραφή περνά παρά τη διένεξη: ο χρήστης είδε τι
  /// άλλαξε και επέλεξε να κρατήσει τη δική του εικόνα.
  ///
  /// Πετά [OperatorStaleException] **πριν** γράψει οτιδήποτε.
  Future<void> update(
    Operator operator, {
    required Operator? expected,
    bool force = false,
  }) async {
    final id = operator.id;
    if (id == null) {
      throw ArgumentError.value(
        operator,
        'operator',
        'Το προφίλ δεν έχει αποθηκευτεί ακόμη — δεν υπάρχει id για ενημέρωση.',
      );
    }
    if (!force && expected != null) {
      final conflict = await conflictFor(
        expected: expected,
        attempted: operator,
      );
      if (conflict != null) throw OperatorStaleException(conflict);
    }
    final data = Map<String, Object?>.from(operator.toMap())..remove('id');
    await db.update(tableName, data, where: 'id = ?', whereArgs: [id]);
  }

  /// Άλλαξε το προφίλ από τότε που το διάβασε η φόρμα; `null` = καθαρό.
  ///
  /// Δεν υπάρχει `updated_at` στα προφίλ, οπότε η διένεξη κρίνεται από τις
  /// **τιμές** — και είναι ακριβέστερο: ό,τι δεν άλλαξε δεν είναι διένεξη.
  ///
  /// Ζει χωριστά από το [update] ώστε ο καλών να μπορεί να ρωτήσει **πρώτος**,
  /// πριν από τους δικούς του κανόνες. Ένας έλεγχος που τρέχει μετά τους
  /// υπόλοιπους δίνει σωστή προστασία με λάθος αιτιολογία: ο χρήστης διαβάζει
  /// «πρέπει να μείνει ένας διαχειριστής» ενώ το πραγματικό θέμα είναι ότι η
  /// καρτέλα του είναι παλιά.
  Future<OperatorSaveConflict?> conflictFor({
    required Operator expected,
    required Operator attempted,
  }) async {
    final id = attempted.id ?? expected.id;
    if (id == null) return null;
    final current = await findById(id);
    if (current == null) return null;
    final conflict = OperatorSaveConflict(
      expected: expected,
      fresh: current,
      attempted: attempted,
    );
    return conflict.hasChanges ? conflict : null;
  }
}
