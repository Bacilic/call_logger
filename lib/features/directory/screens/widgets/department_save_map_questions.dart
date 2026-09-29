import '../../models/department_model.dart';
import '../../services/building_map_placement_loss.dart';
import '../../services/department_floor_change_outcome.dart';
import 'bulk_user_action_pickers.dart';
import 'department_floor_change_dialog.dart';
import 'department_form_dialog.dart';

/// Τι αποφασίστηκε για τη θέση της καρτέλας στην κάτοψη.
///
/// Το [cancelled] είναι **η πρώτη ερώτηση κάθε καλούντα**: ο χρήστης μπορεί να
/// πατήσει «Άκυρο» σε οποιαδήποτε από τις δύο ερωτήσεις, και τότε η αποθήκευση
/// σταματά χωρίς να γραφτεί απολύτως τίποτα.
class DepartmentMapPlacementDecision {
  const DepartmentMapPlacementDecision({
    required this.cancelled,
    this.leavesTheBuildingMap = false,
    this.clearPlacement = false,
    this.movesPlacementToNewFloor = false,
    this.effectiveFloorId,
    this.placementFloorId,
  });

  const DepartmentMapPlacementDecision.cancelled() : this(cancelled: true);

  /// Ο χρήστης σταμάτησε τη ροή. Τίποτα δεν γράφεται.
  final bool cancelled;

  /// Το Είδος βγάζει την καρτέλα από την κάτοψη: κτίριο, όροφος και ομάδα
  /// παύουν να έχουν νόημα και δεν μένουν γραμμένα.
  final bool leavesTheBuildingMap;

  /// Η σχεδιασμένη θέση σβήνει.
  final bool clearPlacement;

  /// Η σχεδιασμένη θέση ταξιδεύει στον νέο όροφο.
  final bool movesPlacementToNewFloor;

  /// Ο όροφος που τελικά γράφεται· `null` όταν η καρτέλα φεύγει από την κάτοψη.
  final int? effectiveFloorId;

  /// Ο όροφος όπου ζει σήμερα το σχεδιασμένο ορθογώνιο.
  final int? placementFloorId;
}

/// Ρωτά ό,τι αφορά τη **θέση στην κάτοψη**, πριν γραφτεί οτιδήποτε.
///
/// Δύο ερωτήσεις με **αυστηρή σειρά**, και η σειρά είναι συμβόλαιο:
///
/// 1. **«Η καρτέλα φεύγει από την κάτοψη»** — όταν το Είδος δεν ανήκει στον
///    χάρτη και υπάρχει κάτι να χαθεί. Η θέση σχεδιάζεται με το χέρι, οπότε ο
///    χρήστης ρωτιέται πριν χαθεί η δουλειά του.
/// 2. **«Μεταφορά ή σβήσιμο;»** — όταν αλλάζει όροφος και υπάρχει σχεδιασμένο
///    ορθογώνιο. Χωρίς την ερώτηση, το ορθογώνιο θα ταξίδευε αυτούσιο σε σχέδιο
///    που ο χρήστης δεν είδε ποτέ.
///
/// **Καμία εγγραφή δεν γίνεται εδώ.** Η συνάρτηση μόνο ρωτά και επιστρέφει την
/// απόφαση· έτσι κάθε «Άκυρο» αφήνει τη βάση ανέπαφη εξ ορισμού, αντί να
/// εξαρτάται από το αν ο καλών θυμήθηκε να σταματήσει.
Future<DepartmentMapPlacementDecision> askDepartmentMapPlacement(
  DepartmentFormDialogState host, {
  required String name,
  required String building,
  required String group,
  required DepartmentModel? initial,
  required String? Function(int? floorId) floorLabel,
}) async {
  final leavesTheBuildingMap = !host.selectedKind.belongsOnBuildingMap;
  final placementLoss = judgeBuildingMapPlacementLoss(
    kindBelongsOnMap: host.selectedKind.belongsOnBuildingMap,
    building: building,
    floorLabel: floorLabel(host.selectedFloorId),
    mapWidth: initial?.mapWidth,
    mapHeight: initial?.mapHeight,
    group: group,
  );

  if (placementLoss.hasAnything) {
    final approved = await showBulkConfirmDialog(
      host.context,
      title: 'Η καρτέλα φεύγει από την κάτοψη',
      message: buildingMapPlacementLossMessage(
        departmentName: name,
        kindLabel: host.selectedKind.label,
        loss: placementLoss,
      ),
      confirmLabel: 'Συνέχεια και διαγραφή',
    );
    if (!approved || !host.mounted) {
      return const DepartmentMapPlacementDecision.cancelled();
    }
  }

  final effectiveFloorId = leavesTheBuildingMap ? null : host.selectedFloorId;
  final placementFloorId = int.tryParse(initial?.mapFloor?.trim() ?? '');
  final floorChange = resolveDepartmentFloorChange(
    isEdit: host.isEdit,
    leavesTheBuildingMap: leavesTheBuildingMap,
    selectedFloorId: host.selectedFloorId,
    snapshotFloorId: host.snapFloorId,
    initialFloorId: initial?.floorId,
    hasDrawnPlacement: initial?.isMapped ?? false,
    placementFloorId: placementFloorId,
    floorLoadState: host.floorLoadState,
  );

  var clearPlacement =
      floorChange == DepartmentFloorChangeAction.clearPlacement;
  var movesPlacementToNewFloor = false;

  if (floorChange == DepartmentFloorChangeAction.askMoveOrClear) {
    final choice = await showDepartmentFloorChangeDialog(
      host.context,
      departmentName: name,
      fromFloorLabel: floorLabel(placementFloorId) ?? 'άγνωστος',
      toFloorLabel: floorLabel(host.selectedFloorId) ?? 'άγνωστος',
    );
    if (choice == null || !host.mounted) {
      return const DepartmentMapPlacementDecision.cancelled();
    }
    clearPlacement = choice == DepartmentFloorChangeChoice.clearPlacement;
    movesPlacementToNewFloor = !clearPlacement;
  }

  return DepartmentMapPlacementDecision(
    cancelled: false,
    leavesTheBuildingMap: leavesTheBuildingMap,
    clearPlacement: clearPlacement,
    movesPlacementToNewFloor: movesPlacementToNewFloor,
    effectiveFloorId: effectiveFloorId,
    placementFloorId: placementFloorId,
  );
}
