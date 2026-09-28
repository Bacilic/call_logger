import 'building_map_floor_load_state.dart';

/// Τι πρέπει να απογίνει η σχεδίαση ενός τμήματος όταν αποθηκεύεται η καρτέλα του.
enum DepartmentFloorChangeAction {
  /// Τίποτα δεν αλλάζει — ο όροφος έμεινε ίδιος, ή δεν υπάρχει σχέδιο.
  keepPlacement,

  /// Η σχεδίαση σβήνεται χωρίς ερώτηση: ο χρήστης αφαίρεσε τον όροφο, ή το
  /// Είδος έβγαλε την καρτέλα από την κάτοψη. Και στις δύο περιπτώσεις έχει
  /// ήδη ρωτηθεί αλλού.
  clearPlacement,

  /// Ο όροφος άλλαξε σε άλλον ΚΑΙ υπάρχει σχέδιο — ο χρήστης αποφασίζει αν
  /// θα ταξιδέψει μαζί ή θα σβηστεί.
  askMoveOrClear,
}

/// Συμβόλαιο: καμία σχεδίαση δεν αλλάζει κάτοψη χωρίς ο χρήστης να το
/// αποφασίσει ρητά.
///
/// Η αλλαγή ορόφου από την καρτέλα δεν δείχνει κάτοψη, άρα ο χρήστης δεν έχει
/// κανέναν τρόπο να δει πού θα πέσει το ορθογώνιο στη νέα — γι' αυτό ρωτάει
/// εδώ, σε αντίθεση με τον χάρτη, όπου βλέπει και την παλιά και τη νέα θέση.
DepartmentFloorChangeAction resolveDepartmentFloorChange({
  required bool isEdit,
  required bool leavesTheBuildingMap,
  required int? selectedFloorId,
  required int? snapshotFloorId,
  required int? initialFloorId,
  required bool hasDrawnPlacement,
  required int? placementFloorId,
  required BuildingMapFloorLoadState floorLoadState,
}) {
  // Το Είδος βγάζει την καρτέλα από την κάτοψη — ο χρήστης το ενέκρινε ήδη.
  if (leavesTheBuildingMap) return DepartmentFloorChangeAction.clearPlacement;

  if (!isEdit) return DepartmentFloorChangeAction.keepPlacement;

  // Δεύτερη γραμμή άμυνας: με άγνωστες κατόψεις το κενό πεδίο δεν είναι
  // επιλογή του χρήστη αλλά συνέπεια της αποτυχίας ανάγνωσης.
  if (!floorLoadState.isLoaded) {
    return DepartmentFloorChangeAction.keepPlacement;
  }

  // Ηθελημένη αφαίρεση ορόφου από καρτέλα που τον είχε.
  if (selectedFloorId == null) {
    return (snapshotFloorId != null || initialFloorId != null)
        ? DepartmentFloorChangeAction.clearPlacement
        : DepartmentFloorChangeAction.keepPlacement;
  }

  // Χωρίς σχέδιο δεν υπάρχει τίποτα να χαθεί ή να ταξιδέψει.
  if (!hasDrawnPlacement) return DepartmentFloorChangeAction.keepPlacement;
  if (placementFloorId == null || placementFloorId == selectedFloorId) {
    return DepartmentFloorChangeAction.keepPlacement;
  }

  return DepartmentFloorChangeAction.askMoveOrClear;
}
