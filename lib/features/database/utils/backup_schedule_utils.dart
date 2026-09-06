/// Καταστάσεις αποτελέσματος αυτόματου αντιγράφου (τυπικά string στη ρύθμιση).
///
/// Από τη Φάση 3 του μηχανισμού αντιγράφων δεν υπάρχει «χαμένο» (missed):
/// χωρίς ημερολογιακό πρόγραμμα δεν υπάρχουν slots να χαθούν — βάση που
/// άνοιξε μετά από καιρό απλώς χρωστά όσες αλλαγές δείχνει ο μετρητής.
/// Παλιές αποθηκευμένες τιμές `missed` κανονικοποιούνται σε [none].
abstract final class BackupScheduleStatus {
  static const String success = 'success';
  static const String failed = 'failed';
  static const String folderMissing = 'folder_missing';
  static const String none = 'none';

  /// Πρέπει να ειδοποιηθεί ο χρήστης για τη μετάβαση [previous] → [current];
  ///
  /// Καθαρή απόφαση, έξω από τον listener που την εφαρμόζει, ώστε να μπορεί να
  /// ελεγχθεί. Δύο κανόνες:
  ///
  /// 1. **Μιλάμε μόνο για αποτυχίες** — η επιτυχία δεν διακόπτει τον χρήστη.
  /// 2. **Μία φορά ανά συμβάν.** Όσο η προηγούμενη κατάσταση είναι κι αυτή
  ///    αποτυχία, δεν υπάρχει νέο συμβάν: είναι η ίδια αποτυχία που αλλάζει
  ///    όνομα. Ο περιοδικός έλεγχος «αναβαθμίζει» το [failed] σε
  ///    [folderMissing] μόλις διαπιστώσει ότι λείπει ο φάκελος — και η
  ///    αποτυχημένη δημιουργία φακέλου κάνει το αντίστροφο, γυρίζοντας το
  ///    [folderMissing] σε [failed].
  ///
  ///    Ο παλιός κανόνας έκλεινε **μόνο τη μία** από τις δύο φορές, και η
  ///    άλλη γεννούσε φαύλο κύκλο: ο χρήστης πατούσε «Δημιουργία εδώ»,
  ///    η δημιουργία αποτύγχανε, και άνοιγε δεύτερος διάλογος που πρότεινε
  ///    «Εκτέλεση τώρα» — δηλαδή ξανά το ίδιο που μόλις είχε αποτύχει.
  ///
  ///    Ένα νέο συμβάν αναγγέλλεται μόνο αφού η κατάσταση περάσει από
  ///    [success] ή [none] — που είναι ακριβώς ό,τι κάνουν η επιτυχία και η
  ///    «Παράβλεψη».
  static bool shouldAnnounce({String? previous, required String? current}) {
    final now = normalize(current);
    if (!isFailure(now)) return false;
    return !isFailure(normalize(previous));
  }

  /// Είναι αυτή η κατάσταση αποτυχία; Οι δύο μορφές της ([failed] και
  /// [folderMissing]) είναι το ίδιο συμβάν με διαφορετική λεπτομέρεια.
  static bool isFailure(String? status) {
    final s = normalize(status);
    return s == failed || s == folderMissing;
  }

  static String normalize(String? raw) {
    final s = raw?.trim() ?? '';
    switch (s) {
      case success:
      case failed:
      case folderMissing:
      case none:
        return s;
      default:
        return none;
    }
  }
}
