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
