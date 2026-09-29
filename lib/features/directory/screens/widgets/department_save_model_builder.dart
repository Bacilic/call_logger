import '../../../../core/services/lansweeper_department_accounts.dart';
import '../../models/department_model.dart';
import 'department_form_dialog.dart';
import 'department_save_map_questions.dart';

/// Χτίζει την καρτέλα που πρόκειται να γραφτεί, από τη φόρμα και τις αποφάσεις
/// της κάτοψης.
///
/// **Καθαρή μετατροπή, καμία ερώτηση και καμία εγγραφή.** Ζει χωριστά επειδή
/// είναι το μόνο σημείο όπου αποφασίζεται *τι ακριβώς αποθηκεύεται* — και ήταν
/// χαμένο στη μέση μιας μεθόδου τετρακοσίων γραμμών, ανάμεσα σε διαλόγους.
///
/// **Ό,τι κρύβει η φόρμα δεν γράφεται.** Όταν το Είδος βγάζει την καρτέλα από
/// την κάτοψη, το κτίριο, ο όροφος και η ομάδα μηδενίζονται αντί να μείνουν
/// γραμμένα: η φόρμα τα έκρυβε, αλλά η λίστα του Καταλόγου τα έδειχνε — και η
/// καρτέλα έλεγε «εκτός κάτοψης» ενώ ο κατάλογος έδειχνε όροφο.
DepartmentModel buildDepartmentModelToSave(
  DepartmentFormDialogState host, {
  required String name,
  required String building,
  required String group,
  required String color,
  required String notes,
  required DepartmentModel? initial,
  required DepartmentMapPlacementDecision placement,
}) {
  final leaves = placement.leavesTheBuildingMap;
  final clear = placement.clearPlacement;
  final floorId = placement.effectiveFloorId;

  return DepartmentModel(
    id: host.isEdit ? initial?.id : null,
    name: name,
    building: (leaves || building.isEmpty) ? null : building,
    color: color,
    notes: notes.isEmpty ? null : notes,
    lansweeperUsernames: encodeLansweeperAccounts(host.lansweeperAccounts),
    floorId: floorId,
    // Η ομάδα οργανώνει τον επιλογέα του χάρτη: φεύγει μαζί με το κτίριο και
    // τον όροφο όταν το Είδος βγάζει την καρτέλα από την κάτοψη.
    groupName: (leaves || group.isEmpty) ? null : group,
    mapFloor: floorId != null
        ? floorId.toString()
        : (clear ? null : initial?.mapFloor),
    mapX: clear ? null : initial?.mapX,
    mapY: clear ? null : initial?.mapY,
    mapWidth: clear ? null : initial?.mapWidth,
    mapHeight: clear ? null : initial?.mapHeight,
    mapRotation: clear ? 0.0 : (initial?.mapRotation ?? 0.0),
    mapLabelOffsetX: clear ? null : initial?.mapLabelOffsetX,
    mapLabelOffsetY: clear ? null : initial?.mapLabelOffsetY,
    mapAnchorOffsetX: clear ? null : initial?.mapAnchorOffsetX,
    mapAnchorOffsetY: clear ? null : initial?.mapAnchorOffsetY,
    mapCustomName: clear ? null : initial?.mapCustomName,
    directPhones: initial?.directPhones,
    isDeleted: initial?.isDeleted ?? false,
    isHiddenOnMap: initial?.isHiddenOnMap ?? false,
    kind: host.selectedKind,
  );
}
