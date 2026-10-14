import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Πώς λέγεται, και πώς αναγνωρίζεται, κάθε αρχείο του φακέλου `logs`.
///
/// Η γνώση αυτή ανήκει στον φάκελο, όχι σε όποιον γράφει: τη χρειάζονται και
/// όσοι διαβάζουν (εξαγωγή διαγνωστικών, αναγνώστης αρχείου, φρουρός
/// αναβάθμισης). Ο κάτοχος του φακέλου είναι το `CrashLogService`, που
/// προωθεί τα ίδια ονόματα για τους υπάρχοντες καλούντες.
abstract final class LogFileNames {
  static String logsDirectoryForDatabasePath(String databasePath) {
    return p.join(p.dirname(p.normalize(databasePath)), 'logs');
  }

  /// Το ημερήσιο αρχείο: σφάλματα, εκκινήσεις και προβληματικά κλεισίματα
  /// της ημέρας, όλων των σταθμών, με τη σειρά που συνέβησαν.
  static String dailyLogFileName(DateTime dateTime) {
    return '$logFilePrefix${_dateStamp(dateTime)}$logFileSuffix';
  }

  /// Αληθές για τα ημερήσια αρχεία της τρέχουσας μορφής.
  static bool isDailyLogFileName(String fileName) =>
      _dailyLogFileName.hasMatch(fileName);

  /// Η ημέρα ενός ημερήσιου αρχείου — της τρέχουσας ή της παλιάς μορφής.
  /// `null` για κάθε άλλο αρχείο του φακέλου.
  static DateTime? dayOfLogFile(String fileName) {
    final match = _anyDatedLogFileName.firstMatch(fileName);
    if (match == null) return null;
    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  static String _dateStamp(DateTime dateTime) {
    final y = dateTime.year.toString().padLeft(4, '0');
    final m = dateTime.month.toString().padLeft(2, '0');
    final d = dateTime.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static const String logFilePrefix = 'events_';
  static const String logFileSuffix = '.jsonl';

  static final RegExp _dailyLogFileName = RegExp(
    '^$logFilePrefix'
    r'\d{4}-\d{2}-\d{2}\.jsonl$',
  );

  /// Οι δύο οικογένειες της παλιάς μορφής κειμένου: σφάλματα και συνεδρίες σε
  /// χωριστά αρχεία. Δεν γράφονται πια· διαβάζονται όσο ζουν και σβήνονται
  /// όταν παλιώσουν. Σε φάκελο όπου κάποιος σταθμός τρέχει ακόμη παλιά
  /// έκδοση, εκείνος συνεχίζει να τα γράφει — γι' αυτό σβήνονται με την
  /// ηλικία τους, όχι όλα μαζί.
  static const String legacyErrorLogPrefix = 'errors_';
  static const String legacySessionLogPrefix = 'session_';

  static final RegExp _legacyDailyLogFileName = RegExp(
    '^(?:$legacyErrorLogPrefix|$legacySessionLogPrefix)'
    r'\d{4}-\d{2}-\d{2}\.log$',
  );

  /// Αληθές για τα ημερήσια αρχεία της παλιάς μορφής κειμένου.
  static bool isLegacyDailyLogFileName(String fileName) =>
      _legacyDailyLogFileName.hasMatch(fileName);

  static final RegExp _anyDatedLogFileName = RegExp(
    '^(?:$logFilePrefix|$legacyErrorLogPrefix|$legacySessionLogPrefix)'
    r'(\d{4})-(\d{2})-(\d{2})\.(?:jsonl|log)$',
  );

  /// Το πρόθεμα των αρχείων ιχνηλάτησης κλεισίματος. Ζει εδώ επειδή η
  /// εκκαθάριση είναι το μόνο σημείο που τα χρειάζεται μαζί με τα υπόλοιπα
  /// αρχεία του φακέλου· ο ίδιος ο ιχνηλάτης χτίζει πάνω του το δικό του όνομα.
  static const String legacyShutdownTracePrefix = 'shutdown_trace_';

  static final RegExp _legacyIncidentFileName = RegExp(
    '^$legacyShutdownTracePrefix'
    r'\d{4}-\d{2}-\d{2}(_[\d-]+)?'
    r'\.log$',
  );

  /// Αληθές για τα αρχεία περιστατικών κλεισίματος της παλιάς εποχής — αυτά
  /// που φέρουν ημερομηνία στο όνομά τους. Τα προσωρινά ίχνη εργασίας δεν
  /// ταιριάζουν.
  static bool isLegacyShutdownIncidentFileName(String fileName) =>
      _legacyIncidentFileName.hasMatch(fileName);

  /// Το όνομα του ίχνους «τρέχω τώρα» μιας εκτέλεσης.
  ///
  /// Ο σταθμός μπαίνει στο όνομα επειδή ο φάκελος ζει δίπλα στη βάση, και η
  /// βάση είναι συχνά κοινόχρηστη: ένα κοινό αρχείο θα σήμαινε ότι το άνοιγμα
  /// του ενός υπολογιστή διαβάζει το ίχνος του άλλου ως δική του κατάρρευση —
  /// και ότι το σβήνει, χάνοντας την ανίχνευση της πραγματικής.
  ///
  /// Η **εκτέλεση** μπαίνει για τον ίδιο ακριβώς λόγο, ένα επίπεδο πιο μέσα:
  /// δύο αντίγραφα στον ίδιο υπολογιστή (η κανονική έκδοση και η δοκιμαστική)
  /// έκαναν μεταξύ τους ό,τι έκαναν κάποτε δύο υπολογιστές μεταξύ τους.
  /// Μπαίνει ως σύντομη αποτύπωση, γιατί η ταυτότητα είναι ολόκληρη διαδρομή
  /// και οι διαδρομές των Windows έχουν όριο μήκους.
  static String sessionLockFileNameFor(String station, [String instance = '']) {
    final run = instance.trim();
    if (run.isEmpty) return 'session_$station.lock';
    return 'session_${station}_${instanceSlug(run)}.lock';
  }

  /// Οκτώ δεκαεξαδικά ψηφία από την ταυτότητα της εκτέλεσης.
  ///
  /// Σταθερή αποτύπωση, όχι `hashCode`: το `hashCode` των συμβολοσειρών δεν
  /// εγγυάται την ίδια τιμή σε άλλη έκδοση του SDK, και μια αλλαγή του θα
  /// άφηνε το προηγούμενο ίχνος ορφανό στον κοινόχρηστο φάκελο για πάντα.
  static String instanceSlug(String instanceId) =>
      sha1.convert(utf8.encode(instanceId)).toString().substring(0, 8);

  /// Το κοινό αρχείο της παλιάς εποχής, όταν όλοι οι σταθμοί μοιράζονταν ένα
  /// ίχνος. **Δεν το αγγίζουμε**: σε φάκελο όπου κάποιος σταθμός τρέχει ακόμη
  /// παλιότερη έκδοση, το αρχείο αυτό είναι ζωντανό ίχνος εκείνου. Σβήνει
  /// μόνο του, από τον τελευταίο μη αναβαθμισμένο σταθμό που θα κλείσει.
  static const String legacySharedSessionLockFileName = 'session.lock';
}
