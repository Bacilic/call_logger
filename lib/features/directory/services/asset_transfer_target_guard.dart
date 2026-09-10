// Φρουρός επιλογής τμήματος-προορισμού — καθαρή λογική, χωρίς widgets.

import '../../../core/utils/search_text_normalizer.dart';
import '../models/department_model.dart';

/// Μήνυμα εμποδίου όταν το πληκτρολογημένο [typedName] ταιριάζει με τμήμα που
/// διαγράφεται στην ίδια πράξη· `null` όταν ο προορισμός είναι θεμιτός.
///
/// Ο κατάλογος προτεινόμενων προορισμών εξαιρεί ήδη τα τμήματα που
/// διαγράφονται, αλλά η εξαίρεση αφορά μόνο την **επιλογή από λίστα**. Όποιος
/// γράψει το όνομα με το χέρι ζητά «δημιουργία νέου τμήματος», και ο επιλυτής
/// προορισμού είναι *get-or-create*: βρίσκει το υπάρχον ζωντανό τμήμα και
/// στέλνει εκεί τα στοιχεία — λίγο πριν αυτό διαγραφεί.
String? blockedTransferTargetMessage({
  required String typedName,
  required List<String> blockedNames,
}) {
  final typed = SearchTextNormalizer.normalizeForSearch(typedName.trim());
  if (typed.isEmpty) return null;

  for (final blocked in blockedNames) {
    final name = blocked.trim();
    if (name.isEmpty) continue;
    if (SearchTextNormalizer.normalizeForSearch(name) != typed) continue;
    return 'Το τμήμα «$name» διαγράφεται σε αυτή την πράξη — τα στοιχεία θα '
        'χάνονταν. Διαλέξτε άλλο προορισμό ή αφαιρέστε το από τη λίστα '
        'διαγραφής.';
  }
  return null;
}

/// Μήνυμα εμποδίου όταν ο πληκτρολογημένος προορισμός **δεν επιτρέπεται να
/// κρατά εξοπλισμό** (τμήμα με Είδος «Εταιρεία»).
///
/// Το φίλτρο της λίστας δεν αρκεί: ο χρήστης μπορεί να γράψει το όνομα με το
/// χέρι, και ο επιλυτής προορισμού είναι *get-or-create* — θα έστελνε σιωπηλά
/// το μηχάνημα στην εταιρεία που δεν του προσφέραμε ποτέ.
String? equipmentForbiddenTargetMessage({
  required String typedName,
  required bool involvesEquipment,
  required List<DepartmentModel> knownDepartments,
}) {
  if (!involvesEquipment) return null;
  final typed = SearchTextNormalizer.normalizeForSearch(typedName.trim());
  if (typed.isEmpty) return null;

  for (final d in knownDepartments) {
    if (d.kind.canOwnEquipment) continue;
    if (SearchTextNormalizer.normalizeForSearch(d.name) != typed) continue;
    return 'Το «${d.name.trim()}» είναι εταιρεία και δεν κρατά δικά μας '
        'μηχανήματα. Διαλέξτε τμήμα του νοσοκομείου ή εξωτερική μονάδα.';
  }
  return null;
}

/// Ερώτηση όταν το πληκτρολογημένο όνομα ταιριάζει με τμήμα που **υπάρχει
/// ήδη** αλλά δεν προσφέρεται στη λίστα (π.χ. είναι το τμήμα-πηγή).
///
/// Ο επιλυτής προορισμού είναι *get-or-create*: δεν θα δημιουργούσε τίποτα, θα
/// έστελνε σιωπηλά τα στοιχεία στο υπάρχον τμήμα — ενώ ο διάλογος υποσχόταν
/// «Θα δημιουργηθεί νέο τμήμα». Η συμπεριφορά ήταν σωστή, το μήνυμα ψευδές.
String existingTransferTargetQuestion(String departmentName) {
  return 'Υπάρχει ήδη τμήμα με αυτό το όνομα: $departmentName.\n\n'
      'Δεν θα δημιουργηθεί νέο — η μεταφορά θα γίνει στο υπάρχον τμήμα. '
      'Να συνεχίσουμε;';
}
