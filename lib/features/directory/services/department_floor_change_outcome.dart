import 'building_map_floor_load_state.dart';

/// Τι πρέπει να απογίνει η σχεδίαση ενός τμήματος όταν αποθηκεύεται η καρτέλα του.
enum DepartmentFloorChangeAction {
  /// Τίποτα δεν αλλάζει — ο όροφος έμεινε ίδιος, ή δεν υπάρχει σχέδιο.
  keepPlacement,

  /// Η θέση σβήνεται χωρίς ερώτηση: το Είδος έβγαλε την καρτέλα από την
  /// κάτοψη (ο χρήστης έχει ήδη ρωτηθεί), ή ο όροφος αφαιρέθηκε από τμήμα που
  /// δεν είχε σχεδίαση — δεν χάνεται τίποτα ορατό.
  clearPlacement,

  /// Ο όροφος αφαιρέθηκε από **σχεδιασμένο** τμήμα: η σχεδίαση χάνεται
  /// οριστικά, άρα ο χρήστης επιβεβαιώνει πριν γραφτεί οτιδήποτε.
  confirmClearPlacement,

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
    if (snapshotFloorId == null && initialFloorId == null) {
      return DepartmentFloorChangeAction.keepPlacement;
    }
    return hasDrawnPlacement
        ? DepartmentFloorChangeAction.confirmClearPlacement
        : DepartmentFloorChangeAction.clearPlacement;
  }

  // Χωρίς σχέδιο δεν υπάρχει τίποτα να χαθεί ή να ταξιδέψει.
  if (!hasDrawnPlacement) return DepartmentFloorChangeAction.keepPlacement;
  if (placementFloorId == null || placementFloorId == selectedFloorId) {
    return DepartmentFloorChangeAction.keepPlacement;
  }

  return DepartmentFloorChangeAction.askMoveOrClear;
}

/// Το κείμενο της επιβεβαίωσης όταν σχεδιασμένο τμήμα μένει χωρίς όροφο.
///
/// Λέει ρητά και τα δύο: ότι η θέση χάνεται, και ότι **δεν** επανέρχεται αν
/// ξαναδηλωθεί ο όροφος — η εφαρμογή δεν την κρατά πουθενά.
String departmentFloorRemovalMessage({
  required String departmentName,
  required String? floorLabel,
}) {
  final where = floorLabel == null
      ? 'στον χάρτη του νοσοκομείου'
      : 'στην κάτοψη του ορόφου «$floorLabel»';
  return 'Το τμήμα «$departmentName» είναι σχεδιασμένο $where και μένει '
      'χωρίς όροφο.\n\n'
      'Με την αποθήκευση η σχεδίασή του στον χάρτη θα διαγραφεί οριστικά.\n\n'
      'Αν αργότερα ξαναδηλώσετε όροφο, η παλιά θέση δεν θα επανέλθει· το '
      'τμήμα θα χρειαστεί να σχεδιαστεί ξανά από τον χάρτη.';
}
