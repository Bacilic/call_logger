/// Στατιστικά αρχείου βάσης + πλήθη εγγραφών ανά πίνακα.
class DatabaseStats {
  const DatabaseStats({
    required this.fileSizeBytes,
    required this.dbPath,
    required this.rowCountsByTable,
    this.lastBackupTime,
    this.label,
    this.schemaVersion,
    this.lastChangeAt,
    this.firstCallDate,
    this.lastCallDate,
    this.reclaimableBytes,
    this.pendingWalBytes,
  });

  /// Μέγεθος αρχείου `.db` σε byte (από [File.length]).
  final int fileSizeBytes;

  /// Απόλυτη διαδρομή αρχείου βάσης.
  final String dbPath;

  /// Χρονική σήμανση τελευταίου αρχείου αντιγράφου στον φάκελο προορισμού (αν υπάρχει).
  final DateTime? lastBackupTime;

  /// `όνομα_πίνακα` → πλήθος εγγραφών (`COUNT(*)`).
  final Map<String, int> rowCountsByTable;

  /// Το όνομα που έδωσε ο χρήστης σε αυτή τη βάση· `null` όταν δεν έχει οριστεί.
  final String? label;

  /// Έκδοση σχήματος (`PRAGMA user_version`).
  ///
  /// Απαντά στο «γιατί δεν ανοίγει αυτή η βάση στο άλλο μηχάνημα;» — ερώτηση
  /// που ως τώρα δεν είχε απάντηση μέσα από την εφαρμογή.
  final int? schemaVersion;

  /// Πότε άλλαξε κάτι τελευταία φορά (νεότερη εγγραφή ιστορικού).
  ///
  /// Η πιο γρήγορη απάντηση στο «μήπως άνοιξα παλιό αντίγραφο;».
  final DateTime? lastChangeAt;

  /// Πρώτη και τελευταία ημέρα με καταγεγραμμένη κλήση — πόση περίοδο καλύπτει
  /// η βάση. Σε αντίθεση με το ιστορικό, οι κλήσεις δεν καθαρίζονται περιοδικά,
  /// οπότε το εύρος τους λέει την αλήθεια για την ηλικία των δεδομένων.
  final String? firstCallDate;
  final String? lastCallDate;

  /// Χώρος που κρατά το αρχείο αλλά δεν χρησιμοποιείται (`freelist`).
  /// Απαντά στο «αξίζει VACUUM;».
  final int? reclaimableBytes;

  /// Μέγεθος του `-wal`: αλλαγές που δεν έχουν κατέβει ακόμη στο κύριο αρχείο.
  final int? pendingWalBytes;

  int rowCountForTable(String tableName) => rowCountsByTable[tableName] ?? 0;
}
