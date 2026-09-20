import 'package:flutter/material.dart';

/// Τι δείχνει το κουτάκι της κεφαλίδας: `true` όλα, `false` κανένα, `null`
/// μερικά.
///
/// **Η ενδιάμεση κατάσταση δεν είναι στολίδι:** χωρίς αυτήν, τρεις επιλεγμένες
/// γραμμές σε δέκα δίνουν άδειο κουτάκι — που λέει «δεν έχεις επιλέξει τίποτα»
/// ενώ έχεις.
bool? catalogSelectAllValue({
  required List<int> visibleIds,
  required Set<int> selectedIds,
}) {
  if (visibleIds.isEmpty) return false;
  final selected = visibleIds.where(selectedIds.contains).length;
  if (selected == 0) return false;
  if (selected == visibleIds.length) return true;
  return null;
}

/// Ποιων γραμμών αλλάζει η κατάσταση με ένα πάτημα του κουτακιού.
///
/// **Το συμβόλαιο:** το κουτάκι της κεφαλίδας αφορά ΜΟΝΟ ό,τι δείχνει η λίστα
/// αυτή τη στιγμή. Ό,τι έχει φιλτραριστεί έξω δεν φαίνεται καν, άρα το κουτάκι
/// δεν έχει δικαίωμα πάνω του — ούτε για να το προσθέσει, ούτε για να το
/// σβήσει.
///
/// Από «όλα τα ορατά επιλεγμένα» αφαιρεί τα ορατά· από οτιδήποτε άλλο
/// (κανένα ή μερικά) **συμπληρώνει** τα ορατά που λείπουν.
List<int> catalogSelectAllToggleTargets({
  required List<int> visibleIds,
  required Set<int> selectedIds,
}) {
  if (visibleIds.isEmpty) return const <int>[];
  final allSelected = visibleIds.every(selectedIds.contains);
  if (allSelected) return List<int>.from(visibleIds);
  return visibleIds.where((id) => !selectedIds.contains(id)).toList();
}

/// Το κουτάκι «επιλογή όλων» στην κεφαλίδα ενός πίνακα του Καταλόγου.
///
/// **Γιατί δέχεται δεδομένα και όχι κλειστούρες:** ήταν γραμμένο τέσσερις φορές
/// —μία σε κάθε πίνακα— και και οι τέσσερις έγραφαν την ίδια λάθος κλειστούρα
/// αφαίρεσης: έσβηναν ολόκληρη την επιλογή, ορατή και κρυμμένη. Με αυτό το
/// σχήμα ο καλών δίνει μόνο «τι φαίνεται» και «τι είναι επιλεγμένο», και δεν
/// υπάρχει βήμα να ξεχάσει.
class CatalogSelectAllCheckbox extends StatelessWidget {
  const CatalogSelectAllCheckbox({
    super.key,
    required this.visibleIds,
    required this.selectedIds,
    required this.onToggleSelection,
    this.visualDensity,
  });

  /// Τα αναγνωριστικά των γραμμών που δείχνει ο πίνακας **τώρα**, μετά από
  /// αναζήτηση και φίλτρα.
  final List<int> visibleIds;

  final Set<int> selectedIds;

  /// Η ίδια συνάρτηση που χρησιμοποιεί και το κουτάκι της κάθε γραμμής.
  final void Function(int id) onToggleSelection;

  final VisualDensity? visualDensity;

  @override
  Widget build(BuildContext context) {
    final value = catalogSelectAllValue(
      visibleIds: visibleIds,
      selectedIds: selectedIds,
    );
    return Checkbox(
      tristate: true,
      visualDensity: visualDensity,
      value: value,
      onChanged: visibleIds.isEmpty
          ? null
          : (_) {
              for (final id in catalogSelectAllToggleTargets(
                visibleIds: visibleIds,
                selectedIds: selectedIds,
              )) {
                onToggleSelection(id);
              }
            },
    );
  }
}
