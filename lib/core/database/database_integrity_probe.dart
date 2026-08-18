import 'dart:async';

import 'package:sqflite_common/sqflite.dart';

import 'database_busy_timeout.dart';
import 'database_file_identity.dart';

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
  const DatabaseIntegrityOutcome({required this.status, this.rawMessage});

  final DatabaseIntegrityStatus status;
  final String? rawMessage;

  bool get isCorrupt => status == DatabaseIntegrityStatus.corrupt;
}

Future<Database> _openReadOnly(String path) => openDatabase(
  path,
  // Χωρίς `version:` — αλλιώς το sqflite επιχειρεί `PRAGMA user_version = N`
  // πάνω σε readOnly σύνδεση και παίρνει SQLITE_READONLY, δίνοντας ψευδή
  // «αποτυχία» για απολύτως υγιή βάση άλλης έκδοσης σχήματος. Ο έλεγχος
  // ακεραιότητας δεν μεταναστεύει σχήμα.
  readOnly: true,
  singleInstance: false,
  // Σε κοινόχρηστη βάση ακόμη και η ανάγνωση συναντά κλειδώματα: χωρίς
  // αναμονή, ο έλεγχος θα ανέφερε «δεν κατέληξε» κάθε φορά που κάποιος γράφει.
  onConfigure: (db) => applyDatabaseBusyTimeout(db, path),
);

/// Ρωτά το ίδιο το SQLite αν το περιεχόμενο του αρχείου στέκει.
///
/// Απαντά σε ερώτημα που **κανένα** διαγνωστικό πρόσβασης δεν αγγίζει: τα
/// υπόλοιπα ελέγχουν αν το αρχείο υπάρχει, διαβάζεται και γράφεται — εδώ
/// ελέγχεται αν αυτό που περιέχει είναι συνεπής βάση.
///
/// Μετρημένο, όχι υποθετικό: `quick_check` σε τοπική βάση 10 MB κοστίζει
/// ~31 ms. Γι' αυτό τρέχει κανονικά και δεν φυλάγεται για ώρα ανάγκης.
///
/// Αποτυχία ανοίγματος δεν σημαίνει αυτόματα ζημιά: μια υγιής βάση WAL σε
/// φάκελο χωρίς δικαίωμα εγγραφής επίσης δεν ανοίγει. Γι' αυτό
/// [DatabaseIntegrityStatus.corrupt] επιστρέφεται μόνο όταν το κείμενο του
/// σφάλματος το λέει ρητά.
Future<DatabaseIntegrityOutcome> runDatabaseIntegrityProbe(
  String dbPath, {
  Duration timeout = const Duration(seconds: 5),
  Future<Database> Function(String path) open = _openReadOnly,
}) async {
  try {
    return await _runIntegrityProbe(dbPath, open).timeout(timeout);
  } on TimeoutException {
    return const DatabaseIntegrityOutcome(
      status: DatabaseIntegrityStatus.inconclusive,
      rawMessage: 'Ο έλεγχος ακεραιότητας δεν πρόλαβε να ολοκληρωθεί.',
    );
  } catch (e) {
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

Future<DatabaseIntegrityOutcome> _runIntegrityProbe(
  String dbPath,
  Future<Database> Function(String path) open,
) async {
  Database? db;
  try {
    db = await open(dbPath);
    final rows = await db.rawQuery('PRAGMA quick_check;');
    final verdict = rows.isEmpty
        ? ''
        : (rows.first.values.isEmpty
              ? ''
              : rows.first.values.first?.toString().trim() ?? '');

    if (verdict.toLowerCase() == 'ok') {
      return const DatabaseIntegrityOutcome(
        status: DatabaseIntegrityStatus.ok,
      );
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
  } finally {
    try {
      await db?.close();
    } catch (_) {}
  }
}
