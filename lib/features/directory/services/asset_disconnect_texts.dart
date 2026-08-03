// Τα κείμενα της ροής αποδέσμευσης: τίτλοι διαλόγων, σώματα και το μήνυμα
// επιβεβαίωσης κατάργησης με τις συνδέσεις του στοιχείου.
//
// Καθαρές συναρτήσεις χωρίς widgets και χωρίς βάση — ελέγχονται με unit tests.
// Οι φράσεις της συνεδρίας (μετρητής βημάτων, γραμμή στοιχείου, ακύρωση) ζουν
// στο asset_disconnect_session.dart, δίπλα στην κατάσταση που περιγράφουν.

import 'asset_disconnect_models.dart';

/// Τίτλος του κύριου διαλόγου: κοινόχρηστο ή προσωπικό στοιχείο.
String disconnectDialogTitle({
  required bool isPhone,
  required SharedAssetDisconnectMode mode,
}) {
  if (isPhone && mode == SharedAssetDisconnectMode.personalPhone) {
    return 'Αποδέσμευση προσωπικού τηλεφώνου';
  }
  if (!isPhone && mode == SharedAssetDisconnectMode.personalEquipment) {
    return 'Αποδέσμευση προσωπικού εξοπλισμού';
  }
  return isPhone
      ? 'Αποδέσμευση κοινόχρηστου τηλεφώνου'
      : 'Αποδέσμευση κοινόχρηστου εξοπλισμού';
}

/// Σώμα του κύριου διαλόγου αποδέσμευσης.
String disconnectDialogContent({
  required bool isPhone,
  required String value,
  required SharedAssetDisconnectMode mode,
  String? sourceDepartmentName,
  String? personalPhoneUserDisplayName,
}) {
  if (isPhone && mode == SharedAssetDisconnectMode.personalPhone) {
    final userPart = _personalEmployeeQuotedLabel(
      personalPhoneUserDisplayName: personalPhoneUserDisplayName,
      sourceDepartmentName: sourceDepartmentName,
    );
    return 'Ο αριθμός $value πρόκειται να αποσυνδεθεί από τον υπάλληλο$userPart.\n\nΕπιλέξτε ενέργεια:';
  }
  if (!isPhone && mode == SharedAssetDisconnectMode.personalEquipment) {
    final userPart = _personalEmployeeQuotedLabel(
      personalPhoneUserDisplayName: personalPhoneUserDisplayName,
      sourceDepartmentName: sourceDepartmentName,
    );
    return 'Ο εξοπλισμός $value πρόκειται να αποσυνδεθεί από τον υπάλληλο$userPart.\n\nΕπιλέξτε ενέργεια:';
  }
  final dept = sourceDepartmentName?.trim() ?? '';
  return isPhone
      ? 'Το κοινόχρηστο τηλέφωνο $value πρόκειται να αποδεσμευτεί από το τμήμα «$dept».\n\nΕπιλέξτε ενέργεια:'
      : 'Ο κοινόχρηστος εξοπλισμός $value πρόκειται να αποδεσμευτεί από το τμήμα «$dept».\n\nΕπιλέξτε ενέργεια:';
}

/// Ετικέτα της επιλογής «παραμονή», με το όνομα του τμήματος όταν υπάρχει.
String keepInDepartmentLabel(
  SharedAssetDisconnectMode mode, {
  String? sourceDepartmentName,
}) {
  final dept = sourceDepartmentName?.trim() ?? '';
  if (dept.isNotEmpty) {
    return 'Παραμονή στο $dept';
  }
  if (mode == SharedAssetDisconnectMode.personalEquipment) {
    return 'Παραμονή στο τμήμα του υπαλλήλου';
  }
  return 'Παραμονή στο ίδιο τμήμα';
}

// ── Υποδείξεις ενεργειών (hover) ─────────────────────────────────────────────
//
// Κάθε ενέργεια που ανοίγει άλλη ερώτηση ή αγγίζει πολλά στοιχεία μαζί λέει
// από πριν τι θα ακολουθήσει. Οι καθολικές δηλώνουν ρητά ότι μεσολαβεί
// προεπισκόπηση, ώστε το «όλα» να μη διαβάζεται ως άμεση εκτέλεση.

/// Υπόδειξη για την ατομική «Παραμονή» — το στοιχείο δεν αλλάζει τμήμα.
String keepInDepartmentTooltip(
  SharedAssetDisconnectMode mode, {
  String? sourceDepartmentName,
}) {
  final dept = sourceDepartmentName?.trim() ?? '';
  final where = dept.isEmpty ? 'στο τμήμα του' : 'στο «$dept»';
  return 'Το στοιχείο μένει $where ως κοινόχρηστο και δεν διαγράφεται. '
      'Καμία άλλη ερώτηση για αυτό.';
}

/// Υπόδειξη για την ατομική «Μεταφορά σε άλλο τμήμα».
String transferSingleTooltip() {
  return 'Θα επιλέξετε τμήμα προορισμού — υπάρχον ή νέο. '
      'Αφορά μόνο αυτό το στοιχείο· για τα υπόλοιπα θα ρωτηθείτε χωριστά.';
}

/// Υπόδειξη για την ατομική «Διαγραφή».
String deleteSingleTooltip({required bool isPhone}) {
  final what = isPhone ? 'Ο αριθμός' : 'Ο εξοπλισμός';
  return '$what καταργείται από τον κατάλογο. Αν συνδέεται με κλήσεις ή '
      'εκκρεμότητες, θα δείτε πρώτα με τι συνδέεται.';
}

/// Υπόδειξη για «Διαγραφή όλων» / «όλων των τηλεφώνων» / «όλου του εξοπλισμού».
///
/// Το [scope] περιγράφει τι καλύπτει η ενέργεια (π.χ. «τα τηλέφωνα»).
String deleteEverythingTooltip({required int count, required String scope}) {
  return 'Καταργούνται $count ${_itemWord(count)} — $scope. '
      'Θα δείτε πρώτα αναλυτική λίστα και θα επιβεβαιώσετε· '
      'δεν θα ερωτηθείτε ξανά ένα-ένα.';
}

/// Υπόδειξη για «Παραμονή — όλα».
String keepEverythingTooltip({
  required int count,
  required String departmentName,
}) {
  return 'Και τα $count ${_itemWord(count)} μένουν στο «$departmentName» ως '
      'κοινόχρηστα. Δεν διαγράφεται τίποτα και δεν θα ερωτηθείτε ξανά.';
}

/// Υπόδειξη για «Μεταφορά όλων σε ένα τμήμα».
String transferEverythingTooltip({required int count}) {
  return 'Θα επιλέξετε ένα μόνο τμήμα προορισμού και θα πάνε εκεί και τα '
      '$count ${_itemWord(count)}. Μία ερώτηση αντί για $count.';
}

/// «στοιχείο» ή «στοιχεία» — η υπόδειξη διαβάζεται δυνατά από τον χρήστη.
String _itemWord(int count) => count == 1 ? 'στοιχείο' : 'στοιχεία';

/// Μήνυμα επιβεβαίωσης κατάργησης με απαρίθμηση των συνδέσεων.
///
/// Δείχνονται έως 5 συνδέσεις· οι υπόλοιπες συνοψίζονται ως πλήθος, ώστε ένα
/// τηλέφωνο με τριάντα κλήσεις να μη γεμίσει την οθόνη.
String formatAssetReferenceDeleteMessage({
  required bool isPhone,
  required String value,
  required List<String> descriptions,
}) {
  if (descriptions.isEmpty) {
    return isPhone
        ? 'Ο αριθμός $value δεν συνδέεται με άλλες εγγραφές. Να καταργηθεί;'
        : 'Ο εξοπλισμός $value δεν συνδέεται με άλλες εγγραφές. Να καταργηθεί;';
  }

  final buf = StringBuffer(
    isPhone
        ? 'Ο αριθμός $value συνδέεται με:'
        : 'Ο εξοπλισμός $value συνδέεται με:',
  );
  final visibleCount = descriptions.length > 5 ? 5 : descriptions.length;
  for (var i = 0; i < visibleCount; i++) {
    buf.write('\n• ${descriptions[i]}');
  }
  if (descriptions.length > 5) {
    buf.write('\n…και ${descriptions.length - 5} ακόμα');
  }
  buf.write('\nΝα καταργηθεί;');
  return buf.toString();
}

String _personalEmployeeQuotedLabel({
  String? personalPhoneUserDisplayName,
  String? sourceDepartmentName,
}) {
  final user = personalPhoneUserDisplayName?.trim();
  if (user == null || user.isEmpty) return '';
  final dept = sourceDepartmentName?.trim();
  if (dept == null || dept.isEmpty) return ' «$user»';
  return ' «$user ($dept)»';
}
