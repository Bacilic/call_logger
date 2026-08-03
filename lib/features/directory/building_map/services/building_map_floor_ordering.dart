// Σειρά εμφάνισης και ετικέτα των κατόψεων — καθαρή λογική, χωρίς widgets.
//
// Μία και μοναδική σειρά για ΚΑΘΕ λίστα ορόφων που βλέπει ο χρήστης: dropdown
// προβολής, μενού επεξεργασίας, φόρμα τμήματος, ομαδοποίηση στην επιλογή
// τμήματος. Η ωμή σειρά της βάσης δεν εμφανίζεται ποτέ.

import '../../../../core/models/building_map_floor.dart';
import '../../../../core/utils/natural_string_compare.dart';

/// Κείμενο εμφάνισης κατόψης: `ομάδα · ετικέτα`, ή σκέτη ετικέτα χωρίς ομάδα.
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
  final cmp = buildingMapFloorNumericSortKey(
    a,
  ).compareTo(buildingMapFloorNumericSortKey(b));
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
