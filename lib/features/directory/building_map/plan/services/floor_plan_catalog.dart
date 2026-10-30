import '../../../../../core/database/building_map_repository.dart';
import '../../../../../core/database/department_repository.dart';
import '../../../../../core/models/building_map_floor.dart';
import '../../../../../core/utils/department_floor_sync.dart';
import '../../../models/department_model.dart';
import '../../services/building_map_department_eligibility.dart';

/// Ό,τι χρειάζεται η σχεδίαση από τον Κατάλογο: τα τμήματα, τα ονόματα των
/// ορόφων, και η μεταφορά τμήματος σε άλλον όροφο.
abstract class FloorPlanCatalog {
  /// Τα τμήματα που δικαιούνται θέση στον χάρτη (όχι εταιρείες, όχι
  /// διαγραμμένα).
  Future<List<DepartmentModel>> departments();

  Future<List<BuildingMapFloor>> floors();

  /// Γράφει στον Κατάλογο ότι το τμήμα βρίσκεται στον όροφο [floorId].
  Future<void> moveDepartmentToFloor(int departmentId, int floorId);

  /// Σβήνει οριστικά τον **παλιό** χάρτη του ορόφου: τα κουτάκια των
  /// τμημάτων πάνω του και την εικόνα κάτοψης.
  Future<void> retireOldMap(int floorId);
}

/// Ο Κατάλογος της βάσης.
class DatabaseFloorPlanCatalog implements FloorPlanCatalog {
  DatabaseFloorPlanCatalog({
    required this.departmentRepository,
    required this.buildingMapRepository,
    required this.afterDepartmentChange,
  });

  final DepartmentRepository departmentRepository;
  final BuildingMapRepository buildingMapRepository;

  /// Ανανέωση όσων οθονών δείχνουν τμήματα, μετά από αλλαγή ορόφου.
  final Future<void> Function() afterDepartmentChange;

  @override
  Future<List<DepartmentModel>> departments() async {
    final rows = await departmentRepository.getActiveDepartments();
    final all = rows.map(DepartmentModel.fromMap);
    final eligible = departmentsEligibleForBuildingMap(all).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return eligible;
  }

  @override
  Future<List<BuildingMapFloor>> floors() =>
      buildingMapRepository.listBuildingMapFloors();

  /// Ο όροφος αλλάζει, και αν το τμήμα είχε κουτάκι στον παλιό χάρτη
  /// **άλλου** ορόφου, το κουτάκι φεύγει: θα έδειχνε το τμήμα σε όροφο που ο
  /// Κατάλογος πια δεν γράφει.
  @override
  Future<void> moveDepartmentToFloor(int departmentId, int floorId) async {
    final current = await buildingMapRepository.readDepartmentColumns(
      departmentId,
      const ['map_floor'],
    );
    final oldSheet = (current['map_floor'] as String?)?.trim();
    final drawnElsewhere =
        oldSheet != null && oldSheet.isNotEmpty && oldSheet != '$floorId';
    await departmentRepository.updateDepartment(
      departmentId,
      DepartmentFloorSync.mergeFloorContext({
        if (drawnElsewhere) ..._oldMapBoxCleared,
      }, manualFloorId: floorId),
      expected: null,
    );
    await afterDepartmentChange();
  }

  /// Το κουτάκι του παλιού χάρτη σβήνεται, ο όροφος χάρτη (`map_floor`) όχι.
  ///
  /// Η καρτέλα τμήματος γράφει πάντα `map_floor` ίσο με τον όροφο του
  /// Καταλόγου και συγκρίνει με αυτό στην επόμενη αποθήκευση· ένα κενό
  /// `map_floor` δίπλα σε συμπληρωμένο όροφο θα διαβαζόταν ως αλλαγή άλλου
  /// σταθμού («Κάποιος πρόλαβε»).
  static final Map<String, dynamic> _oldMapBoxCleared = {
    ...BuildingMapRepository.clearedBuildingMapPlacementColumns(),
  }..remove('map_floor');

  /// Ο όροφος του τμήματος στον Κατάλογο **δεν** αλλάζει — φεύγει μόνο η θέση
  /// του στον παλιό χάρτη.
  @override
  Future<void> retireOldMap(int floorId) async {
    final ids = await buildingMapRepository.departmentIdsDrawnOnOldFloor(
      floorId,
    );
    for (final id in ids) {
      await departmentRepository.updateDepartment(
        id,
        _oldMapBoxCleared,
        expected: null,
      );
    }
    await buildingMapRepository.deleteFloorImage(floorId);
    await afterDepartmentChange();
  }
}
