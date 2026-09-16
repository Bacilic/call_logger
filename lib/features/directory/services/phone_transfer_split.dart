import '../models/catalog_validation_rules.dart';
import '../models/department_kind.dart';

/// Πώς χωρίζονται τα τηλέφωνα ενός υπαλλήλου όταν αλλάζει τμήμα.
///
/// **Δεν είναι όλα διαπραγματεύσιμα.** Ένα εσωτερικό του δικού μας κέντρου
/// είναι γραμμή καρφωμένη σε αυτό το κτίριο: δεν μπορεί να «ακολουθήσει» τον
/// άνθρωπο σε εταιρεία ή σε εξωτερική μονάδα, όπου χτυπούν δεκαψήφια. Η
/// ερώτηση «ακολουθούν ή μένουν;» έχει νόημα μόνο για τα υπόλοιπα.
///
/// Ίδια οικογένεια με τον εξοπλισμό που δεν ακολουθεί σε εταιρεία — το
/// συμβόλαιο είναι κοινό: **ό,τι ανήκει στο νοσοκομείο δεν ακολουθεί άνθρωπο
/// που φεύγει από το νοσοκομείο.** Το κριτήριο όμως είναι διαφορετικό: η
/// εξωτερική μονάδα κρατά δικά μας μηχανήματα, αλλά ποτέ δικό μας εσωτερικό.
///
/// Καθαρή κρίση: καμία πρόσβαση σε βάση, κανένα widget.
class PhoneTransferSplit {
  const PhoneTransferSplit({
    this.forcedToStay = const [],
    this.negotiable = const [],
  });

  /// Εσωτερικά που **μένουν πίσω ό,τι κι αν απαντηθεί** — ο προορισμός δεν
  /// μπορεί να τα κρατά.
  final List<String> forcedToStay;

  /// Τα τηλέφωνα για τα οποία η ερώτηση έχει νόημα.
  final List<String> negotiable;

  /// Υπάρχει λόγος να ανοίξει ο διάλογος;
  bool get asksAnything => negotiable.isNotEmpty;

  /// Υπάρχει κάτι να αναγγελθεί ως αναγκαστικό;
  bool get hasForced => forcedToStay.isNotEmpty;
}

/// Χωρίζει τα τηλέφωνα σε «αναγκαστικά μένουν» και «ρωτιούνται».
///
/// Όταν ο προορισμός κρατά κανονικά εσωτερικά — δηλαδή είναι τμήμα του
/// νοσοκομείου — τίποτα δεν είναι αναγκαστικό και όλα ρωτιούνται, ακριβώς
/// όπως πριν.
PhoneTransferSplit splitPhonesForDepartmentChange({
  required Iterable<String> phones,
  required DepartmentKind targetKind,
  required CatalogValidationRules rules,
}) {
  final cleaned = [
    for (final p in phones)
      if (p.trim().isNotEmpty) p.trim(),
  ];
  if (targetKind.canHoldHospitalInternalPhone) {
    return PhoneTransferSplit(negotiable: cleaned);
  }

  final forced = <String>[];
  final negotiable = <String>[];
  for (final phone in cleaned) {
    if (rules.looksLikeHospitalInternalPhone(phone)) {
      forced.add(phone);
    } else {
      negotiable.add(phone);
    }
  }
  return PhoneTransferSplit(forcedToStay: forced, negotiable: negotiable);
}

/// Η γραμμή που αναγγέλλει τα αναγκαστικά — `null` όταν δεν υπάρχουν.
///
/// Λέγεται **πάντα**, ακόμη κι όταν δεν ανοίγει καθόλου ερώτηση: ο χρήστης δεν
/// πρέπει να ανακαλύψει αργότερα ότι ένα τηλέφωνο άλλαξε χέρια χωρίς να
/// ρωτηθεί. Απαριθμεί τους αριθμούς — σε τόσο λίγα, το «2 τηλέφωνα» θα έκρυβε
/// ακριβώς την πληροφορία που χρειάζεται.
String? forcedPhoneStayMessage({
  required PhoneTransferSplit split,
  required DepartmentKind targetKind,
  String? sourceDepartmentName,
}) {
  if (!split.hasForced) return null;

  final numbers = split.forcedToStay.join(', ');
  final single = split.forcedToStay.length == 1;
  final subject = single
      ? 'Το $numbers είναι εσωτερικό του νοσοκομείου και δεν ακολουθεί'
      : 'Τα $numbers είναι εσωτερικά του νοσοκομείου και δεν ακολουθούν';
  return '$subject ${targetKind.entityWhere} — '
      '${_whereItStays(sourceDepartmentName, single: single)}';
}

/// «μένει στο τμήμα «Γραφείο Κίνησης»» ή, χωρίς όνομα, «μένει στο τμήμα που
/// αφήνει» — με το ρήμα να συμφωνεί με το πλήθος.
///
/// Το όνομα λείπει στη μαζική μεταφορά: οι επιλεγμένοι μπορεί να προέρχονται
/// από διαφορετικά τμήματα, και ένα όνομα θα ήταν ψέμα για τους μισούς.
String _whereItStays(String? sourceDepartmentName, {required bool single}) {
  final verb = single ? 'μένει' : 'μένουν';
  final name = sourceDepartmentName?.trim() ?? '';
  return name.isEmpty
      ? '$verb στο τμήμα που αφήνει'
      : '$verb στο τμήμα «$name»';
}
