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
  /// 2. **Μία φορά ανά συμβάν.** Ο περιοδικός έλεγχος «αναβαθμίζει» το
  ///    [failed] σε [folderMissing] μόλις διαπιστώσει ότι λείπει ο φάκελος·
  ///    είναι η ίδια αποτυχία που μαθαίνει το όνομά της, όχι καινούρια. Χωρίς
  ///    αυτόν τον κανόνα ο χρήστης έβλεπε δύο διαδοχικούς διαλόγους.
  static bool shouldAnnounce({String? previous, required String? current}) {
    final now = normalize(current);
    if (now != failed && now != folderMissing) return false;
    final before = normalize(previous);
    if (before == now) return false;
    if (before == failed && now == folderMissing) return false;
    return true;
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
