import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/search_text_normalizer.dart';
import '../../models/department_model.dart';
import '../../../calls/provider/smart_entity_selector_provider.dart';
import 'open_call_entity_guard.dart';

/// True όταν η ανοιχτή φόρμα κλήσης αναφέρεται σε κάποιο από τα
/// [selectedDepartments] — με επιλεγμένο τμήμα ή με γραμμένο το όνομά του.
///
/// **Και τα δύο σκέλη χρειάζονται.** Το τμήμα της κλήσης μπορεί να έχει
/// επιλεγεί από τη λίστα (οπότε υπάρχει αναγνωριστικό) ή να έχει πληκτρολογηθεί
/// και να μην έχει «κουμπώσει» ακόμη. Στη δεύτερη περίπτωση η κλήση αφορά
/// εξίσου το τμήμα, και η διαγραφή του θα περνούσε αθόρυβα.
bool openCallInvolvesSelectedDepartments(
  WidgetRef ref,
  List<DepartmentModel> selectedDepartments,
) {
  final smart = ref.read(callSmartEntityProvider);
  if (!smart.hasAnyContent) return false;

  final selectedIds = {
    for (final d in selectedDepartments)
      if (d.id != null) d.id!,
  };
  if (selectedIds.isEmpty) return false;

  final departmentId = smart.selectedDepartmentId;
  if (departmentId != null && selectedIds.contains(departmentId)) return true;

  // **Κανονικοποίηση, όχι σκέτο toLowerCase.** Τα ελληνικά κεφαλαία γράφονται
  // χωρίς τόνο: το «ΦΑΡΜΑΚΕΙΟ» πεζό γίνεται «φαρμακειο» και δεν ταιριάζει ποτέ
  // με το «φαρμακείο» του Καταλόγου. Ο ίδιος κανονικοποιητής που βρίσκει τα
  // τμήματα στην αναζήτηση βρίσκει και εδώ αυτό που ο χειριστής πληκτρολόγησε.
  final typed = SearchTextNormalizer.normalizeForSearch(
    smart.departmentText.trim(),
  );
  if (typed.isEmpty) return false;
  for (final d in selectedDepartments) {
    if (SearchTextNormalizer.normalizeForSearch(d.name.trim()) == typed) {
      return true;
    }
  }
  return false;
}

/// Φρουρός πριν από ενέργεια σε τμήματα: όταν η ανοιχτή κλήση αφορά επιλεγμένο
/// τμήμα, ο χρήστης αποφασίζει πρώτα για την κλήση.
///
/// Επιστρέφει true όταν η ενέργεια επιτρέπεται να προχωρήσει.
Future<bool> ensureBulkDepartmentActionAllowed(
  BuildContext context,
  WidgetRef ref,
  List<DepartmentModel> selectedDepartments,
) {
  return ensureOpenCallAllowsCatalogAction(
    context,
    ref,
    openCallInvolvesTarget: openCallInvolvesSelectedDepartments(
      ref,
      selectedDepartments,
    ),
    targetPhrase: 'επιλεγμένο τμήμα',
  );
}
