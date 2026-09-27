import '../../../../core/models/building_map_floor.dart';
import '../../models/department_model.dart';
import 'building_map_floor_ordering.dart';

/// Τι πρέπει να συμβεί όταν ο χρήστης διαλέγει τμήμα από τη λίστα «Επιλογή τμήματος».
enum BuildingMapDepartmentPickAction {
  /// Το τμήμα δεν έχει αποθηκευμένη θέση πουθενά — σχεδίαση στο τρέχον φύλλο.
  drawHere,

  /// Το τμήμα έχει ήδη θέση σε αυτό το φύλλο — επεξεργασία του υπάρχοντος σχήματος.
  editHere,

  /// Το τμήμα έχει θέση σε άλλο, υπαρκτό φύλλο — ο χρήστης διαλέγει μετάβαση ή μετακίνηση.
  askFloorChoice,

  /// Το τμήμα δείχνει σε φύλλο που δεν υπάρχει πια — σχεδίαση εδώ, με ενημέρωση.
  orphanedPlacement,
}

/// Η έκβαση της επιλογής, μαζί με το φύλλο στο οποίο ήδη βρίσκεται το τμήμα.
class BuildingMapDepartmentPick {
  const BuildingMapDepartmentPick({
    required this.action,
    this.otherFloorId,
    this.otherFloorLabel,
  });

  final BuildingMapDepartmentPickAction action;

  /// Το φύλλο όπου είναι ήδη σχεδιασμένο το τμήμα (μόνο στο [askFloorChoice]).
  final int? otherFloorId;

  /// Ετικέτα του [otherFloorId] για τα μηνύματα προς τον χρήστη.
  final String? otherFloorLabel;
}

/// Συμβόλαιο: η επιλογή τμήματος από τη λίστα δεν ξεκινά ποτέ νέα σχεδίαση όταν
/// το τμήμα έχει ήδη αποθηκευμένη θέση — πρώτα ο χρήστης μαθαίνει πού είναι.
BuildingMapDepartmentPick resolveBuildingMapDepartmentPick({
  required DepartmentModel department,
  required int currentSheetId,
  required List<BuildingMapFloor> floors,
}) {
  if (!department.isMapped) {
    return const BuildingMapDepartmentPick(
      action: BuildingMapDepartmentPickAction.drawHere,
    );
  }

  final placedOn = int.tryParse(department.mapFloor?.trim() ?? '');
  if (placedOn == null) {
    return const BuildingMapDepartmentPick(
      action: BuildingMapDepartmentPickAction.orphanedPlacement,
    );
  }
  if (placedOn == currentSheetId) {
    return const BuildingMapDepartmentPick(
      action: BuildingMapDepartmentPickAction.editHere,
    );
  }

  for (final f in floors) {
    if (f.id == placedOn) {
      return BuildingMapDepartmentPick(
        action: BuildingMapDepartmentPickAction.askFloorChoice,
        otherFloorId: placedOn,
        otherFloorLabel: buildingMapFloorDisplayLabel(f),
      );
    }
  }

  return const BuildingMapDepartmentPick(
    action: BuildingMapDepartmentPickAction.orphanedPlacement,
  );
}

/// Ετικέτα του φύλλου όπου είναι σχεδιασμένο το τμήμα — `null` όταν δεν έχει
/// θέση ή όταν το φύλλο δεν υπάρχει πια στον κατάλογο.
String? buildingMapPlacementFloorLabel({
  required DepartmentModel department,
  required Map<int, BuildingMapFloor> floorById,
}) {
  if (!department.isMapped) return null;
  final placedOn = int.tryParse(department.mapFloor?.trim() ?? '');
  if (placedOn == null) return null;
  final f = floorById[placedOn];
  if (f == null) return null;
  return buildingMapFloorDisplayLabel(f);
}
