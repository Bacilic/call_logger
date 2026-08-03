// Καθαρή λογική μηνυμάτων διαγραφής τμήματος (χωρίς widgets/βάση).

/// Κεφαλίδα του **ενός** επιλογέα προορισμού στη «Μεταφορά όλων σε ένα τμήμα».
///
/// Με ένα τμήμα ονομάζεται· με πολλά μετριέται. Το όνομα ενός τμήματος όταν
/// μεταφέρονται εφτά έκανε τον χρήστη να νομίζει ότι απαντά μόνο γι' αυτό.
String departmentQuickTransferHeader(List<String> departmentNames) {
  final count = departmentNames.length;
  if (count == 1) {
    final name = departmentNames.first.trim();
    return 'Πού μεταφέρονται όλα από «${name.isEmpty ? '—' : name}»;';
  }
  return 'Πού μεταφέρονται όλα από τα $count τμήματα;';
}

// ── Υποδείξεις των κουμπιών απόφασης (hover) ─────────────────────────────────
//
// Τα δύο κουμπιά οδηγούν σε ΤΕΛΕΙΩΣ διαφορετικό πλήθος ερωτήσεων. Χωρίς
// υπόδειξη ο χρήστης το μαθαίνει αφού διαλέξει.

/// Υπόδειξη για «Αναλυτικά (ανά οντότητα)».
///
/// Το [assetCount] είναι τα κοινόχρηστα στοιχεία· το [employeeCount] οι
/// υπάλληλοι, που ρωτιούνται ούτως ή άλλως.
String departmentDeletionDetailedTooltip({
  required int assetCount,
  required int employeeCount,
}) {
  final buf = StringBuffer(
    'Θα ερωτηθείτε για κάθε τηλέφωνο και εξοπλισμό ξεχωριστά και μπορείτε να '
    'πάρετε διαφορετική απόφαση για το καθένα',
  );
  if (assetCount > 0) {
    buf.write(' — $assetCount ${assetCount == 1 ? 'ερώτηση' : 'ερωτήσεις'}');
  }
  buf.write('.');
  if (employeeCount > 0) {
    buf.write(
      ' Για τους υπαλλήλους ερωτάστε ούτως ή άλλως, όποιο κουμπί κι αν '
      'διαλέξετε.',
    );
  }
  return buf.toString();
}

/// Υπόδειξη για «Μεταφορά όλων σε ένα τμήμα…».
String departmentDeletionQuickTransferTooltip({required int assetCount}) {
  final buf = StringBuffer(
    'Μία ερώτηση για όλα: επιλέγετε ένα τμήμα προορισμού και μεταφέρονται '
    'εκεί όλα τα κοινόχρηστα τηλέφωνα και ο εξοπλισμός',
  );
  if (assetCount > 0) {
    buf.write(' — $assetCount ${assetCount == 1 ? 'στοιχείο' : 'στοιχεία'}');
  }
  buf.write('. Τίποτα δεν διαγράφεται.');
  return buf.toString();
}

/// Υπόδειξη για το «Διαγραφή» όταν κανένα τμήμα δεν έχει εξαρτήματα.
String departmentDeletionPlainDeleteTooltip({required int departmentCount}) {
  return departmentCount == 1
      ? 'Το τμήμα δεν έχει τηλέφωνα, εξοπλισμό ή υπαλλήλους — διαγράφεται '
            'χωρίς άλλη ερώτηση. Θα μπορείτε να το αναιρέσετε.'
      : 'Τα $departmentCount τμήματα δεν έχουν τηλέφωνα, εξοπλισμό ή '
            'υπαλλήλους — διαγράφονται χωρίς άλλη ερώτηση. Θα μπορείτε να το '
            'αναιρέσετε.';
}

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
