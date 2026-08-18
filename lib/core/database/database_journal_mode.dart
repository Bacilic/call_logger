import 'package:sqflite_common/sqflite.dart';

/// Ο τρόπος με τον οποίο το SQLite προστατεύει μια συναλλαγή από διακοπή.
///
/// Δεν είναι στρώματα που προστίθενται — είναι **διακόπτης με δύο θέσεις**.
/// Κάθε στιγμή ισχύει ο ένας, ποτέ και οι δύο.
enum DatabaseJournalMode {
  /// Κλασικό ημερολόγιο αναίρεσης: οι παλιές σελίδες φυλάγονται δίπλα και η
  /// εγγραφή πάει κατευθείαν στο κύριο αρχείο. Χρειάζεται μόνο κλειδώματα
  /// αρχείου, που τα υποστηρίζει και το δίκτυο.
  delete,

  /// Write-Ahead Log: οι νέες σελίδες γράφονται σε `-wal` και συγχρονίζονται
  /// μέσω `-shm`, που είναι **παράθυρο σε κοινή μνήμη RAM**. Γι' αυτό δεν
  /// περνά από δίκτυο: η μνήμη ενός μηχανήματος δεν ταξιδεύει σε καλώδιο.
  wal,
}

/// Τι ίσχυε, τι ισχύει, και αν η αλλαγή έπιασε.
///
/// Το [applied] είναι ο λόγος ύπαρξης αυτού του τύπου. Μια βάση που νομίζουμε
/// ότι γύρισε σε κλασικό ημερολόγιο ενώ έμεινε σε WAL είναι ακριβώς το
/// επικίνδυνο σενάριο — και η αποτυχία δεν είναι θεωρητική: όσο κάποιος άλλος
/// κρατά τη βάση, το `PRAGMA journal_mode` **πετάει** «database is locked».
class DatabaseJournalModeOutcome {
  const DatabaseJournalModeOutcome({
    required this.previous,
    required this.effective,
    required this.requested,
    this.error,
  });

  final DatabaseJournalMode? previous;
  final DatabaseJournalMode? effective;
  final DatabaseJournalMode requested;

  /// Ωμό κείμενο σφάλματος όταν η αλλαγή απορρίφθηκε· `null` όταν δεν υπήρξε.
  final String? error;

  /// Ισχύει πλέον αυτό που ζητήθηκε;
  bool get applied => effective == requested;

  /// Άλλαξε κάτι, ή ήταν ήδη σωστά;
  bool get changed => previous != effective;
}

/// Ποιον τρόπο πρέπει να έχει η βάση στη διαδρομή [dbPath].
///
/// **Κλασικό ημερολόγιο παντού** — ένας τρόπος, όχι δύο. Η διαδρομή είναι
/// παράμετρος επίτηδες: αν κάποτε χρειαστεί διαφορετική συμπεριφορά τοπικά,
/// αλλάζει μόνο αυτή η συνάρτηση και το τεστ της.
///
/// Γιατί όχι WAL τοπικά, όπου δουλεύει μια χαρά: γιατί το WAL **κρύβει** τα
/// προβλήματα που εμφανίζονται στο δίκτυο. Μια κακή ομαδοποίηση εγγραφών
/// κοστίζει 2 δευτερόλεπτα με WAL και 38 με ημερολόγιο (μετρημένο). Αν η
/// ανάπτυξη γίνεται με WAL και η παραγωγή με ημερολόγιο, κάθε τέτοιο πρόβλημα
/// εμφανίζεται πρώτη φορά μπροστά στους χρήστες.
DatabaseJournalMode resolveDatabaseJournalMode(String dbPath) =>
    DatabaseJournalMode.delete;

DatabaseJournalMode? _parse(Object? raw) {
  final value = raw?.toString().trim().toLowerCase();
  if (value == null || value.isEmpty) return null;
  if (value == 'wal') return DatabaseJournalMode.wal;
  // delete / truncate / persist / memory / off: όλα κλασικό ημερολόγιο ως
  // προς αυτό που μας απασχολεί — δεν χρειάζονται κοινή μνήμη.
  return DatabaseJournalMode.delete;
}

/// Ο τρόπος που ισχύει αυτή τη στιγμή για τη βάση [db].
Future<DatabaseJournalMode?> readDatabaseJournalMode(Database db) async {
  final rows = await db.rawQuery('PRAGMA journal_mode');
  if (rows.isEmpty || rows.first.values.isEmpty) return null;
  return _parse(rows.first.values.first);
}

/// Βάζει τη βάση στον τρόπο που ορίζει το [resolveDatabaseJournalMode].
///
/// Η μετάβαση από WAL είναι ασφαλής για τα δεδομένα: το ίδιο το SQLite κάνει
/// checkpoint πριν αλλάξει τρόπο, δηλαδή κατεβάζει στο κύριο αρχείο ό,τι ζει
/// ακόμη στο `-wal`.
///
/// **Ποτέ δεν σφάλλει, ποτέ δεν εμποδίζει το άνοιγμα.** Η αλλαγή απαιτεί
/// αποκλειστική πρόσβαση: όσο κάποιος άλλος κρατά τη βάση σε WAL, το SQLite
/// απαντά «database is locked» — και μάλιστα πετώντας εξαίρεση, όχι
/// επιστρέφοντας τον παλιό τρόπο. Αν αυτό άφηνε την εξαίρεση να ανέβει, ένας
/// συνάδελφος με ανοιχτή την κοινόχρηστη βάση θα εμπόδιζε **όλους** τους
/// άλλους να την ανοίξουν: πολύ χειρότερο από το πρόβλημα που λύνεται εδώ.
///
/// Η βάση δουλεύει μια χαρά και σε WAL· απλώς δεν αντέχει πολλά μηχανήματα.
/// Άρα η σωστή απάντηση στην αποτυχία είναι «συνέχισε και κατέγραψέ το», και
/// ο καλών το μαθαίνει από το [DatabaseJournalModeOutcome.applied].
Future<DatabaseJournalModeOutcome> applyDatabaseJournalMode(
  Database db,
  String dbPath,
) async {
  final requested = resolveDatabaseJournalMode(dbPath);
  DatabaseJournalMode? previous;
  try {
    previous = await readDatabaseJournalMode(db);
  } catch (_) {
    previous = null;
  }
  final keyword = requested == DatabaseJournalMode.wal ? 'WAL' : 'DELETE';

  try {
    // Το PRAGMA επιστρέφει τον τρόπο που ΙΣΧΥΕΙ μετά την προσπάθεια.
    final rows = await db.rawQuery('PRAGMA journal_mode = $keyword');
    final effective = rows.isEmpty || rows.first.values.isEmpty
        ? await readDatabaseJournalMode(db)
        : _parse(rows.first.values.first);
    return DatabaseJournalModeOutcome(
      previous: previous,
      effective: effective,
      requested: requested,
    );
  } catch (e) {
    return DatabaseJournalModeOutcome(
      previous: previous,
      effective: previous,
      requested: requested,
      error: e.toString(),
    );
  }
}
