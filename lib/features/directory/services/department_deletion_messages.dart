// Καθαρή λογική μηνυμάτων διαγραφής τμήματος (χωρίς widgets/βάση).

/// Τι ακυρώνεται συνολικά αν ο χρήστης πατήσει «Ακύρωση» στη μέση της ροής.
///
/// Μπαίνει στο μήνυμα του διαλόγου ακύρωσης: «Θα ακυρωθεί <αυτό>.»
String departmentDeletionCancelScopeDescription(int departmentCount) {
  if (departmentCount <= 1) return 'η διαγραφή του τμήματος';
  return 'η διαγραφή $departmentCount τμημάτων';
}

/// Ετικέτα πλαισίου μπροστά από τον μετρητή βημάτων, όταν διαγράφονται πολλά
/// τμήματα: χωρίς αυτήν ο μετρητής θα φαινόταν να μηδενίζεται ανεξήγητα.
String? departmentDeletionContextLabel({
  required int departmentIndex,
  required int departmentCount,
}) {
  if (departmentCount <= 1) return null;
  return 'Τμήμα $departmentIndex από $departmentCount';
}

/// Τι ακυρώνεται όταν ο χρήστης εγκαταλείπει τη ροή αποδέσμευσης που ανοίγει
/// κατά την αποθήκευση της φόρμας τμήματος.
String departmentFormSaveCancelScopeDescription(String? departmentName) {
  final name = departmentName?.trim() ?? '';
  if (name.isEmpty) return 'η αποθήκευση του τμήματος';
  return 'η αποθήκευση του τμήματος «$name»';
}
