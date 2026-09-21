// Καθαρή λογική μηνυμάτων διαγραφής τμήματος (χωρίς widgets/βάση).

import '../models/department_kind.dart';

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
String departmentFormSaveCancelScopeDescription(
  String? departmentName, {
  DepartmentKind kind = DepartmentKind.hospital,
}) {
  final entity = kind.entityGenitiveWithArticle;
  final name = departmentName?.trim() ?? '';
  if (name.isEmpty) return 'η αποθήκευση $entity';
  return 'η αποθήκευση $entity «$name»';
}

// ── Το snackbar μετά τη διαγραφή ─────────────────────────────────────────────

/// Ένας προορισμός μεταφοράς, όπως τον ονομάζει το μήνυμα.
///
/// Το [isNew] ξεχωρίζει το τμήμα που μόλις φτιάχτηκε από ένα που προϋπήρχε:
/// «στο νέο Γραμματεία ΤΕΠ» λέει στον χρήστη ότι η διαγραφή γέννησε τμήμα.
typedef DepartmentTransferTarget = ({String name, bool isNew});

/// Τα ονόματα των διαγραμμένων τμημάτων, κομμένα ώστε να χωρούν σε μία γραμμή.
///
/// Το snackbar είναι μία γραμμή· με δέκα τμήματα τα ονόματα θα την έσπρωχναν
/// έξω από την οθόνη. Επιστρέφεται και η πλήρης λίστα, για την υπόδειξη.
({String display, String? allNames}) departmentDeletionNames(
  List<String> departmentNames, {
  int maxLength = 70,
}) {
  final names = [
    for (final raw in departmentNames) raw.trim().isEmpty ? '?' : raw,
  ];
  if (names.isEmpty) return (display: '', allNames: null);

  var take = 0;
  var length = 0;
  for (; take < names.length; take++) {
    final addition = (take == 0 ? '' : ', ') + names[take];
    if (length + addition.length > maxLength) break;
    length += addition.length;
  }
  final display = take < names.length
      ? '${names.sublist(0, take).join(', ')}...'
      : names.join(', ');
  return (display: display, allNames: names.join(', '));
}

/// Το κείμενο του snackbar μετά τη διαγραφή τμημάτων.
///
/// Το [fallbackMessage] είναι το μήνυμα της πολιτικής αναίρεσης και μπαίνει
/// όταν δεν υπάρχει κανένα όνομα να αναφερθεί — τότε το «Το τμήμα Χ
/// διαγράφηκε» δεν έχει τι να πει.
///
/// Η μεταφορά ονομάζει τον προορισμό **μόνο όταν είναι ένας**. Με δύο και πάνω
/// το μήνυμα θα γινόταν κατάλογος, οπότε λέει μόνο ότι τα στοιχεία δεν χάθηκαν.
String departmentDeletionSummaryMessage({
  required String displayNames,
  required int deletedCount,
  required List<DepartmentTransferTarget> transferTargets,
  required bool transferredEmployees,
  required bool transferredEquipment,
  required bool transferredPhones,
  required String fallbackMessage,
}) {
  if (displayNames.isEmpty) return fallbackMessage;

  final deletedPart = deletedCount == 1
      ? 'Το τμήμα $displayNames διαγράφηκε.'
      : 'Τα τμήματα $displayNames διαγράφηκαν.';

  final movedCategories = <String>[
    if (transferredEmployees) 'υπαλλήλων',
    if (transferredEquipment) 'εξοπλισμού',
    if (transferredPhones) 'τηλεφώνων',
  ];
  if (movedCategories.isEmpty) return deletedPart;

  if (transferTargets.length == 1) {
    final target = transferTargets.first;
    final kind = target.isNew ? 'νέο' : 'υπάρχον';
    return '$deletedPart Επιτυχής μεταφορά '
        '${joinGreekGenitive(movedCategories)} στο $kind ${target.name}.';
  }
  return '$deletedPart Τα στοιχεία μεταφέρθηκαν σε άλλα τμήματα.';
}

/// «υπαλλήλων, εξοπλισμού και τηλεφώνων» — κόμματα ως το τελευταίο, μετά «και».
String joinGreekGenitive(List<String> items) {
  if (items.isEmpty) return '';
  if (items.length == 1) return items.first;
  if (items.length == 2) return '${items[0]} και ${items[1]}';
  return '${items.sublist(0, items.length - 1).join(', ')} και ${items.last}';
}
