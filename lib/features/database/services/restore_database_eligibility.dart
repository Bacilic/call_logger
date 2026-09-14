import '../../../core/database/database_file_classifier.dart';
import '../../../core/database/database_open_trial.dart';
import '../../../core/database/database_schema_version.dart';

/// Αν —και πώς— μια βάση μέσα σε αντίγραφο μπορεί να αντικαταστήσει την ενεργή.
///
/// Τρεις κλειδωμένες αποφάσεις, και οι διαφορές τους είναι ουσιαστικές:
///
/// - **Ασύμβατη ή ελλιπής βάση: απαγόρευση** (13/09/2026) — ούτε με
///   προειδοποίηση, ούτε με δεύτερη επιβεβαίωση. Μια βάση που δεν ανοίγει δεν
///   προσφέρει τίποτα σε κανέναν, και το τίμημα ήταν να πέφτει η εφαρμογή πάνω
///   σε βάση που είχε ήδη αντικατασταθεί.
/// - **Βάση με φθαρμένο περιεχόμενο: προειδοποίηση με δεύτερη επιβεβαίωση**
///   (13/09/2026) — εδώ τα δεδομένα υπάρχουν και είναι συνήθως τα περισσότερα.
///   Η απαγόρευση θα άφηνε τον χρήστη χωρίς τίποτα ακριβώς τη στιγμή που
///   χρειάζεται ό,τι σώζεται.
/// - **Βάση που αποδεδειγμένα δεν ανοίγει: απαγόρευση** (14/09/2026) — το
///   δοκιμαστικό άνοιγμα σε αντίγραφο είναι η μόνη ένδειξη που δεν μαντεύει.
///   Έρχεται ΤΕΛΕΥΤΑΙΟ, ώστε να μην ακυρώνει την απόφαση του χρήστη για τη
///   φθαρμένη βάση σκάζοντας πάνω στην ίδια ζημιά που εκείνος αποδέχθηκε.
class RestoreDatabaseVerdict {
  const RestoreDatabaseVerdict.allowed()
    : restorable = true,
      requiresConfirmation = false,
      reason = null,
      technicalDetail = null;

  const RestoreDatabaseVerdict.blocked(this.reason, {this.technicalDetail})
    : restorable = false,
      requiresConfirmation = false;

  /// Επιτρέπεται, αλλά μόνο με ρητή απόφαση του χρήστη.
  ///
  /// Η τρίτη κατάσταση δεν είναι χλιαρότητα — είναι η διαφορά ανάμεσα σε δύο
  /// πραγματικά διαφορετικά πράγματα. Μια ασύμβατη βάση δεν προσφέρει τίποτα
  /// σε κανέναν και σωστά κλειδώνεται. Μια βάση με φθαρμένες σελίδες κρατά
  /// συνήθως το μεγαλύτερο μέρος των δεδομένων, και μπορεί να είναι το μόνο
  /// αντίγραφο που απέμεινε: η άρνηση θα άφηνε τον χρήστη χωρίς τίποτα.
  /// Απόφαση Διευθυντή 13/09/2026.
  const RestoreDatabaseVerdict.risky(this.reason, {this.technicalDetail})
    : restorable = true,
      requiresConfirmation = true;

  final bool restorable;

  /// `true` όταν το πάτημα της επαναφοράς οφείλει να ρωτήσει δεύτερη φορά.
  final bool requiresConfirmation;

  /// Τι να διαβάσει ο χρήστης δίπλα στο κουτάκι. `null` όταν όλα είναι εντάξει.
  final String? reason;

  /// Το ωμό κείμενο του SQLite, για τον διάλογο της δεύτερης επιβεβαίωσης ή
  /// για τις τεχνικές λεπτομέρειες μιας άρνησης.
  /// Δεν μπαίνει ποτέ στο [reason] — εκεί χρειάζεται μία καθαρή πρόταση.
  final String? technicalDetail;
}

/// Κρίνει το προφίλ του αρχείου που εξήχθη από το αντίγραφο.
///
/// Ο ίδιος κριτής με την αλλαγή βάσης — αλλά καλείται **πριν** αντικατασταθεί
/// οτιδήποτε, ώστε η απόρριψη να είναι επιλογή του χρήστη και όχι κατάρρευση.
RestoreDatabaseVerdict judgeBackupDatabase(
  DatabaseFileProfile? profile, {
  int appSchemaVersion = kDatabaseSchemaVersion,
  DatabaseOpenTrial? openTrial,
}) {
  if (profile == null) {
    return const RestoreDatabaseVerdict.blocked(
      'Δεν ήταν δυνατό να διαβαστεί αυτή η βάση.',
    );
  }
  switch (profile.kind) {
    case DatabaseFileKind.callLogger:
      // Πρώτα η έκδοση, και πριν από κάθε άλλη κρίση: μια βάση γραμμένη από
      // νεότερη εγκατάσταση δεν ανοίγει εδώ με κανέναν τρόπο. Ο φρουρός του
      // ανοίγματος το έλεγε ήδη — αλλά το έλεγε ΜΕΤΑ, όταν η βάση εργασίας
      // είχε ήδη αντικατασταθεί. Ό,τι μπορεί να κριθεί πριν από την
      // αντιγραφή, κρίνεται πριν.
      final fileVersion = profile.userVersion;
      if (fileVersion != null && fileVersion > appSchemaVersion) {
        return RestoreDatabaseVerdict.blocked(
          'Το αντίγραφο φτιάχτηκε από νεότερη έκδοση της εφαρμογής '
          '(σχήμα $fileVersion· εδώ διαβάζεται ως την έκδοση '
          '$appSchemaVersion). Χρειάζεται νεότερη εγκατάσταση για να ανοίξει.',
        );
      }
      // Το σχήμα πέρασε. Το περιεχόμενο είναι χωριστό ερώτημα, και μόνο
      // ΑΠΟΔΕΙΞΗ φθοράς μετρά εδώ: αν ο έλεγχος δεν πρόλαβε ή δεν έτρεξε,
      // η βάση δεν κατηγορείται για κάτι που δεν ειπώθηκε.
      if (profile.contentIsCorrupt) {
        return RestoreDatabaseVerdict.risky(
          'Το αρχείο έχει φθορά — μέρος του περιεχομένου δεν διαβάζεται. '
          'Ό,τι σώζεται θα επαναφερθεί, αλλά κάποιες εγγραφές μπορεί να '
          'λείπουν ή να βγάζουν σφάλμα.',
          technicalDetail: profile.integrityDetail,
        );
      }
      // Τελευταίο, γιατί είναι το ακριβότερο και το μόνο που δεν μαντεύει:
      // το αρχείο άνοιξε ή δεν άνοιξε. Έρχεται ΜΕΤΑ τη φθορά επίτηδες — μια
      // φθαρμένη βάση παραμένει απόφαση του χρήστη (13/09/2026), και δεν
      // επιτρέπεται να του την ακυρώσει μια δοκιμή που σκάει πάνω στη ζημιά
      // που εκείνος έχει ήδη δει και αποδεχθεί.
      if (openTrial != null && openTrial.provenToFail) {
        return RestoreDatabaseVerdict.blocked(
          openTrial.reason,
          technicalDetail: openTrial.technicalDetail,
        );
      }
      return const RestoreDatabaseVerdict.allowed();
    case DatabaseFileKind.incompleteCallLogger:
      final missing = profile.missingCoreTables.join(', ');
      return RestoreDatabaseVerdict.blocked(
        missing.isEmpty
            ? 'Ελλιπής βάση της Καταγραφής Κλήσεων — λείπουν βασικοί πίνακες.'
            : 'Ελλιπής βάση — λείπουν οι πίνακες: $missing.',
      );
    case DatabaseFileKind.lamp:
      return const RestoreDatabaseVerdict.blocked(
        'Είναι η βάση της Λάμπας, όχι της Καταγραφής Κλήσεων.',
      );
    case DatabaseFileKind.hybrid:
      return const RestoreDatabaseVerdict.blocked(
        'Ανακατεμένο σχήμα Καταγραφής και Λάμπας — δεν χρησιμεύει σε καμία '
        'από τις δύο.',
      );
    case DatabaseFileKind.empty:
      return const RestoreDatabaseVerdict.blocked(
        'Το αρχείο δεν περιέχει δεδομένα.',
      );
    case DatabaseFileKind.unknown:
      return RestoreDatabaseVerdict.blocked(
        profile.userVersion == 0
            ? 'Περιέχει πίνακες αλλά δηλώνει έκδοση 0 — δεν αναγνωρίζεται ως '
                  'βάση της Καταγραφής Κλήσεων.'
            : 'Δεν είναι βάση της Καταγραφής Κλήσεων.',
      );
    case DatabaseFileKind.undetermined:
      return const RestoreDatabaseVerdict.blocked(
        'Ο έλεγχος του αρχείου απέτυχε — μπορεί να είναι κατεστραμμένο.',
      );
  }
}
