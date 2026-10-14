import 'dart:ui';

import '../../models/department_model.dart';
import '../../screens/widgets/department_color_palette.dart';

/// Τι γίνεται με το χρώμα του τμήματος όταν πατηθεί η Επιβεβαίωση (✓).
enum BuildingMapCommitColorAction {
  /// Θέση στο ίδιο φύλλο με έγκυρο χρώμα — το χρώμα μένει, χωρίς ερώτηση.
  keepCurrent,

  /// Χωρίς χρώμα ή με χρώμα που δεν διαβάζεται — δίνεται το επόμενο ελεύθερο.
  assignNew,

  /// Έχει χρώμα, αλλά έρχεται από αλλού ή πρώτη φορά εδώ — ερώτηση στον χρήστη.
  askUser,
}

class BuildingMapCommitColorPlan {
  const BuildingMapCommitColorPlan({
    required this.action,
    required this.currentColor,
    required this.releaseFromFloorId,
  });

  final BuildingMapCommitColorAction action;

  /// Το σημερινό χρώμα του τμήματος, αν διαβάζεται.
  final Color? currentColor;

  /// Το φύλλο από το οποίο φεύγει το τμήμα — εκεί το παλιό χρώμα ελευθερώνεται
  /// όταν αλλάξει ή μετακομίσει. `null` όταν δεν μετακομίζει.
  final int? releaseFromFloorId;
}

/// Συμβόλαιο: το χρώμα ενός τμήματος που ήδη κάθεται σε αυτό το φύλλο δεν
/// αλλάζει ποτέ σιωπηλά· ό,τι δεν έχει χρώμα παίρνει ένα που ξεχωρίζει.
BuildingMapCommitColorPlan resolveBuildingMapCommitColorPlan({
  required DepartmentModel dept,
  required String sheetStr,
}) {
  final previousFloorStr = dept.mapFloor?.trim();
  final previousFloorId = int.tryParse(previousFloorStr ?? '');
  final movingToNewFloor =
      previousFloorStr != null && previousFloorStr != sheetStr;
  final existingColor = dept.color?.trim();
  final currentColor = tryParseDepartmentHex(existingColor);
  final releaseFromFloorId = movingToNewFloor ? previousFloorId : null;

  final shouldKeepCurrentColor =
      previousFloorStr == sheetStr &&
      dept.isMapped &&
      existingColor != null &&
      existingColor.isNotEmpty;

  final BuildingMapCommitColorAction action;
  if (shouldKeepCurrentColor) {
    action = BuildingMapCommitColorAction.keepCurrent;
  } else if (existingColor == null || existingColor.isEmpty) {
    action = BuildingMapCommitColorAction.assignNew;
  } else if (currentColor == null) {
    action = BuildingMapCommitColorAction.assignNew;
  } else {
    action = BuildingMapCommitColorAction.askUser;
  }
  return BuildingMapCommitColorPlan(
    action: action,
    currentColor: currentColor,
    releaseFromFloorId: releaseFromFloorId,
  );
}
