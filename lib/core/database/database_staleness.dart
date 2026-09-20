/// «Πόσο καιρό έχει να γραφτεί κάτι σε αυτή τη βάση;» — και πότε αυτό αξίζει
/// προειδοποίηση.
///
/// **Το περιστατικό που το γέννησε (17/07/2026):** ένα τμήμα «χάθηκε». Δεν
/// είχε χαθεί· ο χρήστης δούλευε πάνω σε **παλαιότερο αντίγραφο** της βάσης
/// νομίζοντας ότι ήταν η τρέχουσα. Αυτό που έλυσε τη διάγνωση ήταν μία γραμμή:
/// η τελευταία εγγραφή Ιστορικού ήταν δέκα μέρες πίσω.
///
/// **Γιατί η ημερομηνία του αρχείου δεν αρκεί:** ένα αντίγραφο που
/// μετακινήθηκε χθες δείχνει χθεσινό, ενώ τα δεδομένα του είναι δίμηνα. Η
/// ημερομηνία αρχείου λέει πότε το **άγγιξε** κάποιος· η τελευταία εγγραφή
/// λέει πότε **δούλεψε** κάποιος πάνω του. Μόνο το δεύτερο απαντά στο «είμαι
/// στη σωστή βάση;».
///
/// Καθαρός υπολογισμός, χωρίς βάση και χωρίς οθόνη: ο κανόνας του «παλιά ή
/// όχι» πρέπει να μπορεί να ελεγχθεί μόνος του.
library;

/// Η προεπιλογή, όταν ο χρήστης δεν έχει ορίσει δικό του όριο.
///
/// Πέντε μέρες: αρκετά ώστε ένα σαββατοκύριακο με αργία να μη γεννά
/// συναγερμό, αρκετά λίγες ώστε μια βάση που έμεινε πίσω να μη δουλευτεί για
/// βδομάδα (απόφαση Διευθυντή 19/09/2026).
const int kDefaultDatabaseStalenessDays = 5;

/// Το κάτω όριο: μηδέν μέρες θα σήμαινε «προειδοποίησέ με πάντα».
const int kMinDatabaseStalenessDays = 1;

/// Το πάνω όριο — πέρα από δύο μήνες η ρύθμιση παύει να προστατεύει.
const int kMaxDatabaseStalenessDays = 60;

/// Φέρνει οποιαδήποτε τιμή μέσα στα επιτρεπτά όρια.
int normalizeDatabaseStalenessDays(int? value) {
  if (value == null) return kDefaultDatabaseStalenessDays;
  return value.clamp(kMinDatabaseStalenessDays, kMaxDatabaseStalenessDays);
}

/// Η ετυμηγορία για μια συγκεκριμένη βάση.
class DatabaseStalenessVerdict {
  const DatabaseStalenessVerdict({
    required this.isStale,
    required this.thresholdDays,
    this.lastChangeAt,
    this.daysSinceLastChange,
  });

  /// Ξεπέρασε το όριο και αξίζει να το μάθει ο χρήστης.
  final bool isStale;

  /// Το όριο που ίσχυε τη στιγμή της κρίσης — ταξιδεύει μαζί, ώστε το μήνυμα
  /// να μπορεί να πει «πάνω από Ν μέρες» χωρίς να ξαναρωτήσει τις ρυθμίσεις.
  final int thresholdDays;

  /// Πότε γράφτηκε τελευταία φορά κάτι· `null` σε βάση χωρίς καμία εγγραφή.
  final DateTime? lastChangeAt;

  /// Πόσες ολόκληρες μέρες πέρασαν· `null` όταν δεν υπάρχει εγγραφή.
  final int? daysSinceLastChange;
}

/// Κρίνει αν η βάση είναι στάσιμη, με βάση την τελευταία της εγγραφή.
///
/// **Η κενή βάση δεν είναι παλιά.** Μια ολοκαίνουργια εγκατάσταση δεν έχει
/// καμία εγγραφή Ιστορικού, και μια προειδοποίηση εκεί θα ήταν το πρώτο που
/// θα έβλεπε ο χρήστης — λάθος μήνυμα τη λάθος στιγμή.
///
/// **Η μελλοντική ημερομηνία δεν είναι παλιά.** Ρολόι σταθμού που τρέχει
/// μπροστά δίνει αρνητική διαφορά· δεν μας αφορά εδώ.
DatabaseStalenessVerdict judgeDatabaseStaleness({
  required DateTime? lastChangeAt,
  required int thresholdDays,
  required DateTime now,
}) {
  final threshold = normalizeDatabaseStalenessDays(thresholdDays);

  if (lastChangeAt == null) {
    return DatabaseStalenessVerdict(isStale: false, thresholdDays: threshold);
  }

  final elapsed = now.difference(lastChangeAt);
  final days = elapsed.inDays;

  return DatabaseStalenessVerdict(
    isStale: days >= threshold,
    thresholdDays: threshold,
    lastChangeAt: lastChangeAt,
    daysSinceLastChange: days < 0 ? 0 : days,
  );
}
