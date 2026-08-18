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

/// Δίνει στη σύνδεση [db] την αναμονή που ταιριάζει στη διαδρομή [dbPath].
///
/// Μπαίνει στο `onConfigure`, δηλαδή **πριν** από κάθε δημιουργία ή μετάπτωση
/// σχήματος: κι εκείνες γράφουν, κι εκείνες θα έβρισκαν τη βάση πιασμένη.
Future<void> applyDatabaseBusyTimeout(Database db, String dbPath) async {
  await db.execute('PRAGMA busy_timeout = ${resolveDatabaseBusyTimeoutMs(dbPath)}');
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
