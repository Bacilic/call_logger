import 'package:sqflite_common/sqflite.dart';

import '../config/app_config.dart';

/// Πόσο περιμένει μια εγγραφή όταν τη βάση την κρατά ήδη κάποιος άλλος.
///
/// Η SQLite ξεκινά **κάθε** σύνδεση με μηδενική αναμονή: μόλις βρει τη βάση
/// πιασμένη, παραιτείται αμέσως με «database is locked». Σε βάση ενός χρήστη
/// αυτό δεν φαίνεται ποτέ — σε κοινόχρηστη είναι το πρώτο πράγμα που σπάει.
///
/// Μετρημένο σε πραγματική κοινόχρηστη βάση (18/08/2026): με δύο εφαρμογές
/// να γράφουν, ο δεύτερος αποτυγχάνει σε **3 χιλιοστά** χωρίς αναμονή, ενώ με
/// αναμονή περνά κανονικά μόλις ελευθερωθεί η βάση. Ισχύει **και στους δύο**
/// τρόπους ημερολογίου — δεν είναι πρόβλημα του WAL, είναι απλώς κάτι που
/// δεν είχε τεθεί ποτέ.
int resolveDatabaseBusyTimeoutMs(String dbPath) =>
    AppConfig.isUncDatabasePath(dbPath)
    ? AppConfig.databaseBusyTimeoutNetworkMs
    : AppConfig.databaseBusyTimeoutLocalMs;

/// Πόσο περιθώριο πάνω από την αναμονή κλειδώματος.
///
/// Η αναμονή τελειώνει όταν η βάση ελευθερωθεί — και τότε αρχίζει η ίδια η πράξη,
/// που στο δίκτυο θέλει κι αυτή τον χρόνο της. Όριο ακριβώς ίσο με την αναμονή
/// θα έκοβε την πράξη τη στιγμή που επιτέλους μπόρεσε να ξεκινήσει.
const int kLockWaitHeadroomMs = 3000;

/// Το **δάπεδο** κάθε ορίου που περιμένει τη βάση σε αυτή τη διαδρομή.
///
/// **Το συμβόλαιο:** όποιος ζητά αναμονή, δίνει και τον χρόνο να γίνει. Όσο οι
/// δύο αριθμοί έζησαν χωριστά, το άνοιγμα (8 δευτ.) και κάθε ερώτημα (10 δευτ.)
/// έκοβαν την αναμονή των 15 δευτερολέπτων στη μέση: η SQLite περίμενε όπως της
/// ζητήθηκε και παρατούσε άλλος για λογαριασμό της (αναφορά 21/09/2026).
///
/// Είναι **δάπεδο, όχι ταβάνι**: όποιος θέλει να περιμένει περισσότερο, περιμένει.
Duration minimumWaitBudget(String dbPath) => Duration(
  milliseconds: resolveDatabaseBusyTimeoutMs(dbPath) + kLockWaitHeadroomMs,
);

/// Η μικρότερη «Αναμονή» των Ρυθμίσεων που έχει αποτέλεσμα, σε δευτερόλεπτα.
///
/// Κάτω από αυτήν το [resolveDatabaseOpenTimeout] ανεβάζει την τιμή στο δάπεδο,
/// οπότε η οθόνη δεν δέχεται μικρότερη — αλλιώς θα έδειχνε 5 ενώ ισχύουν 8.
int minimumDatabaseOpenTimeoutSeconds({required bool network}) {
  final busyMs = network
      ? AppConfig.databaseBusyTimeoutNetworkMs
      : AppConfig.databaseBusyTimeoutLocalMs;
  return ((busyMs + kLockWaitHeadroomMs) / 1000).ceil();
}

/// Πόσο περιμένει το άνοιγμα της βάσης σε αυτή τη διαδρομή.
///
/// Το [configuredSeconds] είναι η ρύθμιση του χρήστη από τις Επιλογές. Γίνεται σεβαστή
/// όταν ζητά περισσότερο — αλλά δεν επιτρέπεται να σπάσει το συμβόλαιο: μικρή
/// τιμή θα ξανέφερνε το ίδιο σφάλμα, σιωπηλά και από την οθόνη των Ρυθμίσεων.
Duration resolveDatabaseOpenTimeout(String dbPath, {int? configuredSeconds}) {
  final floor = minimumWaitBudget(dbPath);
  final requested = Duration(
    seconds: (configuredSeconds != null && configuredSeconds > 0)
        ? configuredSeconds
        : AppConfig.databaseOpenTimeoutSeconds,
  );
  return requested > floor ? requested : floor;
}

/// Η ένδειξη της αναμονής στις Ρυθμίσεις: η τιμή που **ισχύει** για τη βάση
/// [dbPath], όχι η αποθηκευμένη.
///
/// Σε βάση δικτύου μια ρύθμιση κάτω από το δάπεδο ανεβαίνει στο δάπεδο — και
/// η ένδειξη λέει γιατί, ώστε όποιος έγραψε 8 να μη βλέπει ανεξήγητο 18.
String databaseOpenWaitLabel(String dbPath, {required int configuredSeconds}) {
  final effective = resolveDatabaseOpenTimeout(
    dbPath,
    configuredSeconds: configuredSeconds,
  ).inSeconds;
  final raisedOnNetwork =
      effective > configuredSeconds && AppConfig.isUncDatabasePath(dbPath);
  return raisedOnNetwork
      ? 'Αναμονή: $effective δευτ. (ελάχιστο δικτύου)'
      : 'Αναμονή: $effective δευτ.';
}

/// Δίνει στη σύνδεση [db] την αναμονή που ταιριάζει στη διαδρομή [dbPath].
///
/// Μπαίνει στο `onConfigure`, δηλαδή **πριν** από κάθε δημιουργία ή μετάπτωση
/// σχήματος: κι εκείνες γράφουν, κι εκείνες θα έβρισκαν τη βάση πιασμένη.
Future<void> applyDatabaseBusyTimeout(Database db, String dbPath) async {
  await db.execute(
    'PRAGMA busy_timeout = ${resolveDatabaseBusyTimeoutMs(dbPath)}',
  );
}

/// Η αναμονή που δηλώνει αυτή τη στιγμή η σύνδεση, σε χιλιοστά.
///
/// Υπάρχει για να αποδεικνύεται ότι η ρύθμιση **έφτασε** — ένα `PRAGMA` που
/// σιωπηλά δεν εφαρμόστηκε μοιάζει ακριβώς με ένα που εφαρμόστηκε.
Future<int?> readDatabaseBusyTimeoutMs(Database db) async {
  final rows = await db.rawQuery('PRAGMA busy_timeout');
  if (rows.isEmpty) return null;
  final value = rows.first.values.first;
  if (value is int) return value;
  return int.tryParse('$value');
}
