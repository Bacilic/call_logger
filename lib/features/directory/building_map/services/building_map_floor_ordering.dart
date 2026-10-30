// Σειρά εμφάνισης και ετικέτα των κατόψεων — καθαρή λογική, χωρίς widgets.
//
// Μία και μοναδική σειρά για ΚΑΘΕ λίστα ορόφων που βλέπει ο χρήστης: dropdown
// προβολής, μενού επεξεργασίας, φόρμα τμήματος, ομαδοποίηση στην επιλογή
// τμήματος. Η ωμή σειρά της βάσης δεν εμφανίζεται ποτέ.

import '../../../../core/models/building_map_floor.dart';
import '../../../../core/utils/natural_string_compare.dart';
import '../../../../core/utils/search_text_normalizer.dart';

/// Κείμενο εμφάνισης κάτοψης: `ομάδα · ετικέτα`, ή σκέτη ετικέτα χωρίς ομάδα.
String buildingMapFloorDisplayLabel(BuildingMapFloor f) {
  final g = f.floorGroup?.trim();
  return (g != null && g.isNotEmpty) ? '$g · ${f.label}' : f.label;
}

/// Αριθμός ορόφου από την ετικέτα: «-2» → −2, «0 - Ισόγειο» → 0, «1ος …» → 1.
///
/// Χωρίς αριθμό στην αρχή (π.χ. «Πατάρι») πέφτει πίσω στο `sort_order` της
/// βάσης, ώστε ο χρήστης να μπορεί να ορίσει τη θέση με σύρσιμο.
int buildingMapFloorNumericSortKey(BuildingMapFloor f) {
  final match = RegExp(r'^(-?\d+)').firstMatch(f.label.trim());
  if (match != null) {
    return int.tryParse(match.group(1)!) ?? f.sortOrder;
  }
  return f.sortOrder;
}

/// Σύγκριση δύο κατόψεων για εμφάνιση: αριθμητικά κατά όροφο, και σε ισοπαλία
/// φυσικά κατά ετικέτα.
///
/// Η σύγκριση **δεν** γίνεται με σκέτο [naturalCompareStrings] πάνω στην
/// ετικέτα: εκείνη αγνοεί το πρόσημο, οπότε το «−1» θα προηγούνταν του «−2».
int compareBuildingMapFloorsForDisplay(BuildingMapFloor a, BuildingMapFloor b) {
  final cmp = buildingMapFloorNumericSortKey(a)
      .compareTo(buildingMapFloorNumericSortKey(b));
  if (cmp != 0) return cmp;
  return naturalCompareStrings(
    buildingMapFloorDisplayLabel(a),
    buildingMapFloorDisplayLabel(b),
  );
}

/// Νέα ταξινομημένη λίστα — η αρχική μένει ανέγγιχτη.
List<BuildingMapFloor> buildingMapFloorsSortedForDisplay(
  List<BuildingMapFloor> floors,
) {
  return List<BuildingMapFloor>.from(floors)
    ..sort(compareBuildingMapFloorsForDisplay);
}

/// Σε ποιον όροφο ανοίγει ο χάρτης όταν δεν έχει διαλεχτεί ακόμη κανένας σε
/// αυτή τη συνεδρία (απόφαση Διευθυντή 30/10/2026):
///
/// 1. ο τελευταίος που είδε ο χρήστης ([rememberedId]), αν υπάρχει ακόμη·
/// 2. την πρώτη φορά, ο όροφος του τμήματος πληροφορικής ([itFloorIds])·
/// 3. αλλιώς ένας όροφος με κάτοψη — εικόνα ή νέο χάρτη ([newMapFloorIds])·
/// 4. αλλιώς οποιοσδήποτε.
///
/// «Οποιοσδήποτε» είναι πάντα ο πρώτος κατά τη σειρά εμφάνισης, ώστε ο ίδιος
/// χρήστης να βλέπει κάθε φορά τον ίδιο. `null` μόνο χωρίς ορόφους.
int? chooseInitialBuildingMapFloor({
  required List<BuildingMapFloor> floors,
  int? rememberedId,
  Set<int> itFloorIds = const {},
  Set<int> newMapFloorIds = const {},
}) {
  if (floors.isEmpty) return null;
  final sorted = buildingMapFloorsSortedForDisplay(floors);
  if (rememberedId != null && sorted.any((f) => f.id == rememberedId)) {
    return rememberedId;
  }
  for (final f in sorted) {
    if (itFloorIds.contains(f.id)) return f.id;
  }
  for (final f in sorted) {
    if (f.hasImage || newMapFloorIds.contains(f.id)) return f.id;
  }
  return sorted.first.id;
}

/// Είναι το [departmentName] το τμήμα πληροφορικής; Από το όνομα, χωρίς
/// τόνους και κεφαλαία (απόφαση Διευθυντή 30/10/2026: η εφαρμογή δεν το
/// κρατά πουθενά αλλού).
bool isItDepartmentName(String departmentName) =>
    SearchTextNormalizer.normalizeForSearch(departmentName)
        .contains(SearchTextNormalizer.normalizeForSearch('πληροφορικ'));
