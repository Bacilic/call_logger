import '../../models/department_model.dart';

/// Τι αντικαθιστά η Επιβεβαίωση (✓) όταν το τμήμα έχει ήδη αποθηκευμένη θέση.
class BuildingMapPlacementReplacement {
  const BuildingMapPlacementReplacement({
    required this.replacesPlacementOnThisSheet,
    required this.movesFromAnotherSheet,
    this.previousFloorId,
  });

  /// Το τμήμα έχει ήδη θέση στο ΙΔΙΟ φύλλο — η αποθήκευση τη διορθώνει.
  final bool replacesPlacementOnThisSheet;

  /// Το τμήμα έχει θέση σε ΑΛΛΟ φύλλο — η αποθήκευση το μετακομίζει.
  final bool movesFromAnotherSheet;

  /// Το φύλλο από το οποίο φεύγει (μόνο στο [movesFromAnotherSheet]).
  final int? previousFloorId;

  /// Δεν υπάρχει τίποτα να αντικατασταθεί — πρώτη σχεδίαση.
  bool get isFirstPlacement =>
      !replacesPlacementOnThisSheet && !movesFromAnotherSheet;
}

/// Συμβόλαιο: καμία αποθηκευμένη θέση δεν αντικαθίσταται χωρίς ο χρήστης να το
/// ξέρει τη στιγμή που συμβαίνει. Η μετακόμιση σε άλλο φύλλο ρωτά πάντα, γιατί
/// η παλιά θέση δεν φαίνεται στην οθόνη.
BuildingMapPlacementReplacement resolveBuildingMapPlacementReplacement({
  required DepartmentModel department,
  required int targetSheetId,
}) {
  if (!department.isMapped) {
    return const BuildingMapPlacementReplacement(
      replacesPlacementOnThisSheet: false,
      movesFromAnotherSheet: false,
    );
  }
  final placedOn = int.tryParse(department.mapFloor?.trim() ?? '');
  if (placedOn == null) {
    return const BuildingMapPlacementReplacement(
      replacesPlacementOnThisSheet: false,
      movesFromAnotherSheet: false,
    );
  }
  if (placedOn == targetSheetId) {
    return const BuildingMapPlacementReplacement(
      replacesPlacementOnThisSheet: true,
      movesFromAnotherSheet: false,
    );
  }
  return BuildingMapPlacementReplacement(
    replacesPlacementOnThisSheet: false,
    movesFromAnotherSheet: true,
    previousFloorId: placedOn,
  );
}
