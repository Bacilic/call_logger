import 'dart:async';

import 'package:sqflite_common/sqflite.dart';

import 'database_file_identity.dart';
import 'database_snapshot.dart';

export 'database_snapshot.dart' show DatabaseSnapshotStats;

/// Ετυμηγορία ελέγχου ακεραιότητας περιεχομένου.
enum DatabaseIntegrityStatus {
  /// Το SQLite διάβασε τη βάση και δεν βρήκε πρόβλημα.
  ok,

  /// Το περιεχόμενο είναι χαλασμένο — απόδειξη, όχι υποψία.
  corrupt,

  /// Δεν βγήκε απάντηση (timeout, κλείδωμα, δικαιώματα, δίκτυο).
  /// **Ποτέ δεν εκλαμβάνεται ως ζημιά.**
  inconclusive,
}

/// Το αποτέλεσμα, μαζί με το **ωμό** κείμενο του SQLite.
///
/// Το [rawMessage] δεν μεταφράζεται και δεν ωραιοποιείται πουθενά: είναι η
/// μόνη πρόταση που λέει τι πραγματικά συνέβη, και ταξιδεύει αυτούσια ως την
/// οθόνη. Το περιστατικό που γέννησε αυτό το αρχείο ήταν ακριβώς η απώλειά
/// της — ο χρήστης είδε οκτώ «[OK]» και ένα «φαίνεται κατεστραμμένο».
class DatabaseIntegrityOutcome {
  const DatabaseIntegrityOutcome({
    required this.status,
    this.rawMessage,
    this.snapshot,
  });

  final DatabaseIntegrityStatus status;
  final String? rawMessage;

  /// Τι κόστισε το στιγμιότυπο πάνω στο οποίο έγινε ο έλεγχος — `null` όταν
  /// ο έλεγχος έγινε απευθείας στο αρχείο (βάση σε WAL) ή δεν έφτασε ως εκεί.
  final DatabaseSnapshotStats? snapshot;

  bool get isCorrupt => status == DatabaseIntegrityStatus.corrupt;

  DatabaseIntegrityOutcome _withSnapshot(DatabaseSnapshotStats stats) =>
      DatabaseIntegrityOutcome(
        status: status,
        rawMessage: rawMessage,
        snapshot: stats,
      );
}

/// Ρωτά το ίδιο το SQLite αν το περιεχόμενο του αρχείου στέκει.
///
/// Απαντά σε ερώτημα που **κανένα** διαγνωστικό πρόσβασης δεν αγγίζει: τα
/// υπόλοιπα ελέγχουν αν το αρχείο υπάρχει, διαβάζεται και γράφεται — εδώ
/// ελέγχεται αν αυτό που περιέχει είναι συνεπής βάση.
///
/// **Ο έλεγχος γίνεται πάνω σε στιγμιότυπο** (`takeDatabaseSnapshot`), όχι
/// πάνω στο ίδιο το αρχείο. Η παλιά παραδοχή — «`quick_check` σε βάση 10 MB
/// κοστίζει ~31 ms, άρα τρέχει κανονικά» — μετρήθηκε σε **τοπική** βάση. Σε
/// κοινόχρηστη βάση με δεύτερο σταθμό ανοιχτό το ίδιο ερώτημα κόστισε 20
/// δευτερόλεπτα, κάθε φορά (23/09/2026): τα Windows δεν κρατούν πια το αρχείο
/// στη μνήμη, και κάθε σελίδα ταξιδεύει χωριστά. Το στιγμιότυπο φέρνει τα
/// ίδια ακριβώς bytes με λίγα μεγάλα ταξίδια, και ο έλεγχος τρέχει τοπικά,
/// ξανά στα ~31 ms. Η ετυμηγορία είναι η ίδια· αλλάζει μόνο ο δρόμος.
///
/// Αποτυχία ανοίγματος δεν σημαίνει αυτόματα ζημιά: μια υγιής βάση WAL σε
/// φάκελο χωρίς δικαίωμα εγγραφής επίσης δεν ανοίγει. Γι' αυτό
/// [DatabaseIntegrityStatus.corrupt] επιστρέφεται μόνο όταν το κείμενο του
/// σφάλματος το λέει ρητά.
Future<DatabaseIntegrityOutcome> runDatabaseIntegrityProbe(
  String dbPath, {
  Duration timeout = const Duration(seconds: 5),
  Future<Database> Function(String path) open =
      openDatabaseReadOnlyWithBusyTimeout,
}) async {
  // Το ίδιο όριο φτάνει και ΜΕΣΑ στο στιγμιότυπο: όταν λήξει, η αντιγραφή
  // σταματά και αφήνει το κλείδωμα — δεν συνεχίζει στο παρασκήνιο να κρατά
  // την ουρά πίσω της.
  final deadline = DateTime.now().add(timeout);
  try {
    return await _runIntegrityProbeOnSnapshot(
      dbPath,
      open,
      deadline,
    ).timeout(timeout);
  } on TimeoutException {
    return const DatabaseIntegrityOutcome(
      status: DatabaseIntegrityStatus.inconclusive,
      rawMessage: 'Ο έλεγχος ακεραιότητας δεν πρόλαβε να ολοκληρωθεί.',
    );
  } catch (e) {
    // Εδώ φτάνει μόνο η αποτυχία ΑΝΟΙΓΜΑΤΟΣ ή ΣΤΙΓΜΙΟΤΥΠΟΥ του αρχείου (π.χ.
    // «file is not a database», χαλασμένος κατάλογος πινάκων, κομμένο δίκτυο
    // στη μέση της αντιγραφής) — το ίδιο το ερώτημα μεταφράζει τα δικά του
    // σφάλματα παρακάτω. Κρατά την ίδια διάκριση: ρητό «malformed» είναι
    // απόδειξη, όλα τα άλλα επιφύλαξη.
    final raw = e.toString();
    final corrupt =
        looksLikeCopiedWhileInUseError(raw) || looksLikeCorruptImageError(raw);
    return DatabaseIntegrityOutcome(
      status: corrupt
          ? DatabaseIntegrityStatus.corrupt
          : DatabaseIntegrityStatus.inconclusive,
      rawMessage: raw,
    );
  }
}

/// Το ίδιο το ερώτημα, πάνω σε ανοιχτή σύνδεση — και η κρίση του «τι σημαίνει
/// η απάντηση», σε ΕΝΑ σημείο.
///
/// Εσωτερικό επίτηδες: καλείται μόνο πάνω στο τοπικό στιγμιότυπο (ή, για βάση
/// σε WAL, στο ίδιο το αρχείο). Ένας καλών που θα το έτρεχε πάνω σε σύνδεση
/// κοινόχρηστης βάσης θα ξαναδιάβαζε ολόκληρο το αρχείο σελίδα-σελίδα από το
/// δίκτυο — ακριβώς ό,τι κόστιζε 20 δευτερόλεπτα στην εκκίνηση.
Future<DatabaseIntegrityOutcome> _readIntegrityFromOpenDatabase(
  Database db,
) async {
  final List<Map<String, Object?>> rows;
  try {
    rows = await db.rawQuery('PRAGMA quick_check;');
  } catch (e) {
    // Σοβαρή φθορά δεν επιστρέφει λίστα ευρημάτων — **πετάει**. Η μετάφραση
    // ζει εδώ και όχι στον καλούντα, ώστε όποιος ρωτήσει τον έλεγχο να πάρει
    // την ίδια ετυμηγορία, από όποια είσοδο κι αν μπήκε.
    final raw = e.toString();
    final corrupt =
        looksLikeCopiedWhileInUseError(raw) || looksLikeCorruptImageError(raw);
    return DatabaseIntegrityOutcome(
      status: corrupt
          ? DatabaseIntegrityStatus.corrupt
          : DatabaseIntegrityStatus.inconclusive,
      rawMessage: raw,
    );
  }
  final verdict = rows.isEmpty
      ? ''
      : (rows.first.values.isEmpty
            ? ''
            : rows.first.values.first?.toString().trim() ?? '');

  if (verdict.toLowerCase() == 'ok') {
    return const DatabaseIntegrityOutcome(status: DatabaseIntegrityStatus.ok);
  }
  if (verdict.isEmpty) {
    return const DatabaseIntegrityOutcome(
      status: DatabaseIntegrityStatus.inconclusive,
      rawMessage: 'Το PRAGMA quick_check δεν επέστρεψε απάντηση.',
    );
  }
  // Πολλαπλά ευρήματα: κρατιούνται όλα, αυτούσια.
  final all = rows
      .map((r) => r.values.first?.toString().trim() ?? '')
      .where((v) => v.isNotEmpty)
      .join('\n');
  return DatabaseIntegrityOutcome(
    status: DatabaseIntegrityStatus.corrupt,
    rawMessage: all.isEmpty ? verdict : all,
  );
}

Future<DatabaseIntegrityOutcome> _runIntegrityProbeOnSnapshot(
  String dbPath,
  Future<Database> Function(String path) open,
  DateTime deadline,
) async {
  final DatabaseSnapshot snapshot;
  try {
    snapshot = await takeDatabaseSnapshot(
      dbPath,
      openSource: open,
      deadline: deadline,
    );
  } on DatabaseSnapshotUnsupported {
    // Βάση που δεν ζει ολόκληρη στο κύριο αρχείο της (WAL): ο παλιός δρόμος.
    return _runIntegrityProbe(dbPath, open);
  }
  try {
    final outcome = await _runIntegrityProbe(
      snapshot.path,
      openDatabaseReadOnlyWithBusyTimeout,
    );
    return outcome._withSnapshot(snapshot.stats);
  } finally {
    await snapshot.dispose();
  }
}

Future<DatabaseIntegrityOutcome> _runIntegrityProbe(
  String dbPath,
  Future<Database> Function(String path) open,
) async {
  Database? db;
  try {
    db = await open(dbPath);
    return await _readIntegrityFromOpenDatabase(db);
  } finally {
    try {
      await db?.close();
    } catch (_) {}
  }
}
