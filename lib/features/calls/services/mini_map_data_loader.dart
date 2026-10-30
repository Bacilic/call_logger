import '../../../core/database/building_map_repository.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/department_repository.dart';
import '../../../core/database/directory_support.dart';
import '../../../core/database/equipment_repository.dart';
import '../../../core/database/floor_plan_objects_repository.dart';
import '../../../core/database/floor_plan_placements_repository.dart';
import '../../../core/database/floor_plan_repository.dart';
import '../../../core/models/building_map_floor.dart';
import '../../../core/models/floor_plan_element.dart';
import '../../../core/models/floor_plan_object_kind.dart';
import '../../../core/models/floor_plan_placement.dart';
import '../../../core/services/lookup_service.dart';
import '../../directory/building_map/plan/floor_plan_objects.dart';
import '../../directory/models/department_model.dart';
import '../models/equipment_model.dart';
import '../models/user_model.dart';

/// Ποια οντότητα οδηγεί την προβολή του μικρού χάρτη.
enum MiniMapMode { department, equipment, phone, user }

/// Τα πεδία της φόρμας κλήσης που τροφοδοτούν τον μικρό χάρτη.
class MiniMapRequest {
  const MiniMapRequest({
    required this.equipment,
    required this.equipmentCodeText,
    required this.phoneText,
    required this.user,
    required this.departmentId,
  });

  final EquipmentModel? equipment;
  final String equipmentCodeText;
  final String phoneText;
  final UserModel? user;

  /// Επιλεγμένο τμήμα από την κεφαλίδα — πηγή με προτεραιότητα.
  final int? departmentId;
}

/// Τα τμήματα που προέκυψαν ανά πηγή, πριν την εφαρμογή προτεραιότητας.
class MiniMapCandidateDepartments {
  const MiniMapCandidateDepartments({
    required this.headerDepartmentId,
    required this.equipmentDepartmentId,
    required this.phoneDepartmentId,
    required this.userDepartmentId,
  });

  final int? headerDepartmentId;
  final int? equipmentDepartmentId;
  final int? phoneDepartmentId;
  final int? userDepartmentId;
}

/// Το αποτέλεσμα της προτεραιότητας: ποια όψη ανοίγει και ποιο τμήμα δείχνει.
class MiniMapSelection {
  const MiniMapSelection({
    required this.mode,
    required this.selectedDepartmentId,
    required this.hasPhoneEquipmentToggle,
  });

  final MiniMapMode mode;
  final int? selectedDepartmentId;

  /// Εξοπλισμός και τηλέφωνο δείχνουν σε **διαφορετικά** τμήματα — ο χρήστης
  /// μπορεί να εναλλάσσεται ανάμεσά τους.
  final bool hasPhoneEquipmentToggle;
}

/// Σειρά προτεραιότητας πηγών: Τμήμα → Εξοπλισμός → Τηλέφωνο → Καλών.
///
/// Μία και μοναδική σειρά — καθορίζει ΚΑΙ ποια όψη ανοίγει ΚΑΙ ποιο τμήμα
/// δείχνει ο χάρτης. Δύο χωριστές σειρές θα μπορούσαν να αποκλίνουν σιωπηλά.
const List<MiniMapMode> kMiniMapSourcePriority = [
  MiniMapMode.department,
  MiniMapMode.equipment,
  MiniMapMode.phone,
  MiniMapMode.user,
];

/// Όψη στην οποία ανοίγει άδεια φόρμα: ο εξοπλισμός, το πεδίο γύρω από το
/// οποίο περιστρέφεται η συνήθης καταγραφή.
const MiniMapMode _kEmptyFormMode = MiniMapMode.equipment;

/// Καθαρή λογική προτεραιότητας — χωρίς πρόσβαση σε βάση ή UI.
MiniMapSelection resolveMiniMapSelection(MiniMapCandidateDepartments c) {
  int? departmentOf(MiniMapMode mode) => switch (mode) {
    MiniMapMode.department => c.headerDepartmentId,
    MiniMapMode.equipment => c.equipmentDepartmentId,
    MiniMapMode.phone => c.phoneDepartmentId,
    MiniMapMode.user => c.userDepartmentId,
  };

  final mode = kMiniMapSourcePriority.firstWhere(
    (m) => departmentOf(m) != null,
    orElse: () => _kEmptyFormMode,
  );

  final equipmentDeptId = c.equipmentDepartmentId;
  final phoneDeptId = c.phoneDepartmentId;

  return MiniMapSelection(
    mode: mode,
    selectedDepartmentId: departmentOf(mode),
    hasPhoneEquipmentToggle:
        equipmentDeptId != null &&
        phoneDeptId != null &&
        equipmentDeptId != phoneDeptId,
  );
}

/// Ο σχεδιασμένος όροφος όπου ένα τμήμα έχει χώρο, για τον μικρό χάρτη.
class MiniMapNewFloor {
  const MiniMapNewFloor({
    required this.floor,
    required this.elements,
    this.objects = const [],
    this.callItems = const [],
  });

  final BuildingMapFloor floor;
  final List<FloorPlanElement> elements;

  /// Μόνο τα έπιπλα: δίνουν τον χώρο με μια ματιά. Τα σύμβολα του ορόφου
  /// (εκτυπωτές…) δεν μπαίνουν — ο μικρός χάρτης δείχνει ό,τι αφορά την κλήση.
  final List<FloorPlanObjectView> objects;

  /// Οι θέσεις του υπαλλήλου και του εξοπλισμού της κλήσης σε αυτόν τον
  /// όροφο: ο μικρός χάρτης κεντράρει εκεί και τις φωτίζει.
  final List<FloorPlanObjectView> callItems;
}

/// Έτοιμα δεδομένα προβολής για τον μικρό χάρτη.
class MiniMapCardData {
  const MiniMapCardData({
    required this.floors,
    required this.departmentsById,
    required this.selection,
    required this.equipmentEntity,
    required this.candidates,
    this.newMapByDepartment = const {},
    this.callFloors = const [],
  });

  /// Για κάθε υποψήφιο τμήμα που έχει χώρο σε όροφο του **νέου** χάρτη, ο
  /// όροφος αυτός με το σχέδιό του. Τα υπόλοιπα δείχνονται όπως πάντα.
  final Map<int, MiniMapNewFloor> newMapByDepartment;

  /// Οι ενεργοποιημένοι όροφοι όπου ο υπάλληλος ή ο εξοπλισμός της κλήσης
  /// έχει θέση — ο μικρός χάρτης τον εντοπίζει εκεί, ακόμη κι αν ο χώρος του
  /// τμήματος είναι σε άλλον όροφο. Κενό = όπως στη Φάση 1.
  final List<MiniMapNewFloor> callFloors;

  final List<BuildingMapFloor> floors;
  final Map<int, DepartmentModel> departmentsById;
  final MiniMapSelection selection;
  final EquipmentModel? equipmentEntity;
  final MiniMapCandidateDepartments candidates;

  int? get selectedDepartmentId => selection.selectedDepartmentId;
  bool get hasPhoneEquipmentToggle => selection.hasPhoneEquipmentToggle;
  MiniMapMode get initialMode => selection.mode;
  int? get equipmentDepartmentId => candidates.equipmentDepartmentId;
  int? get phoneDepartmentId => candidates.phoneDepartmentId;
  int? get userDepartmentId => candidates.userDepartmentId;
}

/// Υπογραφή φόρτωσης — injectable ώστε τα widget tests να μη χρειάζονται βάση.
typedef MiniMapDataLoad = Future<MiniMapCardData> Function(MiniMapRequest);

/// Συγκεντρώνει από τη βάση ό,τι χρειάζεται ο μικρός χάρτης της κλήσης.
///
/// Ζει εκτός widget: η κάρτα δηλώνει UI, τα ερωτήματα γίνονται εδώ.
class MiniMapDataLoader {
  const MiniMapDataLoader();

  Future<MiniMapCardData> load(MiniMapRequest request) async {
    final db = await DatabaseHelper.instance.database;
    final departmentsRepo = DepartmentRepository(db);
    final equipmentRepo = EquipmentRepository(db);

    final floors = await BuildingMapRepository(
      db,
      DirectorySupport(db),
    ).listBuildingMapFloors();
    final departmentRows = await departmentsRepo.getActiveDepartments();
    final departmentsById = <int, DepartmentModel>{};
    for (final row in departmentRows) {
      final dept = DepartmentModel.fromMap(row);
      if (dept.id != null) departmentsById[dept.id!] = dept;
    }

    final equipment = await _resolveEquipment(request);
    final equipmentDeptIds = equipment == null
        ? const <int>[]
        : await _departmentIdsForEquipment(
            departmentsRepo,
            equipmentRepo,
            equipment,
          );
    final phoneDeptIds = await departmentsRepo
        .resolveActiveDepartmentIdsForPhone(request.phoneText);

    final candidates = MiniMapCandidateDepartments(
      headerDepartmentId: request.departmentId,
      equipmentDepartmentId: equipmentDeptIds.isNotEmpty
          ? equipmentDeptIds.first
          : null,
      phoneDepartmentId: phoneDeptIds.isNotEmpty ? phoneDeptIds.first : null,
      userDepartmentId: request.user?.departmentId,
    );

    final callItems = await _callItems(
      FloorPlanPlacementsRepository(db),
      request.user,
      equipment,
    );
    final plans = FloorPlanRepository(db);
    final objectsRepo = FloorPlanObjectsRepository(db);
    final floorCache = <int, Future<MiniMapNewFloor?>>{};
    Map<int, FloorPlanObjectKind>? kinds;
    // Κάθε όροφος διαβάζεται μία φορά, όσα τμήματα κι αν δείχνουν σε αυτόν.
    Future<MiniMapNewFloor?> floorOf(int floorId) =>
        floorCache[floorId] ??= () async {
          final floor = floors.where((f) => f.id == floorId).firstOrNull;
          if (floor == null) return null;
          kinds ??= await objectsRepo.kinds();
          return MiniMapNewFloor(
            floor: floor,
            elements: await plans.listElements(floorId),
            objects: [
              for (final view in buildFloorPlanObjectViews(
                await objectsRepo.listObjects(floorId),
                kinds!,
              ))
                if (view.isVolume) view,
            ],
            callItems: callItems[floorId] ?? const [],
          );
        }();

    return MiniMapCardData(
      floors: floors,
      departmentsById: departmentsById,
      selection: resolveMiniMapSelection(candidates),
      equipmentEntity: equipment,
      candidates: candidates,
      newMapByDepartment: await _newMapFloors(
        plans,
        candidates,
        departmentsById,
        floorOf,
      ),
      callFloors: [
        for (final floorId in callItems.keys) ?await floorOf(floorId),
      ],
    );
  }

  /// Οι θέσεις του υπαλλήλου και του εξοπλισμού της κλήσης σε ενεργοποιημένους
  /// ορόφους, ανά όροφο — πρώτα ο υπάλληλος. Υπάλληλος με δύο θέσεις δίνει
  /// και τις δύο.
  Future<Map<int, List<FloorPlanObjectView>>> _callItems(
    FloorPlanPlacementsRepository placements,
    UserModel? user,
    EquipmentModel? equipment,
  ) async {
    final entries = [
      if (user?.id case final id?)
        FloorPlanCatalogEntry(
          type: FloorPlanPlacementType.user,
          entityId: id,
          label: '${user!.lastName ?? ''} ${user.firstName ?? ''}'.trim(),
        ),
      if (equipment?.id case final id?)
        FloorPlanCatalogEntry(
          type: FloorPlanPlacementType.equipment,
          entityId: id,
          label: equipment!.code?.trim().isNotEmpty == true
              ? equipment.code!.trim()
              : 'Εξοπλισμός $id',
        ),
    ];
    final result = <int, List<FloorPlanObjectView>>{};
    for (final entry in entries) {
      for (final p in await placements.activePlacementsOf(
        entry.type,
        entry.entityId,
      )) {
        (result[p.floorId] ??= []).addAll(
          buildFloorPlanPlacementViews([p], {entry.key: entry}),
        );
      }
    }
    return result;
  }

  /// Ο σχεδιασμένος όροφος κάθε υποψήφιου τμήματος — ο όροφος του Καταλόγου
  /// όταν έχει χώρο εκεί, αλλιώς ο πρώτος όπου έχει.
  Future<Map<int, MiniMapNewFloor>> _newMapFloors(
    FloorPlanRepository plans,
    MiniMapCandidateDepartments candidates,
    Map<int, DepartmentModel> departmentsById,
    Future<MiniMapNewFloor?> Function(int floorId) floorOf,
  ) async {
    final ids = {
      ?candidates.headerDepartmentId,
      ?candidates.equipmentDepartmentId,
      ?candidates.phoneDepartmentId,
      ?candidates.userDepartmentId,
    };
    final roomFloors = await plans.activeFloorsWithRoomsOf(ids);
    final result = <int, MiniMapNewFloor>{};
    for (final entry in roomFloors.entries) {
      final catalogFloor = departmentsById[entry.key]?.floorId;
      final floorId = entry.value.contains(catalogFloor)
          ? catalogFloor!
          : entry.value.first;
      final floor = await floorOf(floorId);
      if (floor != null) result[entry.key] = floor;
    }
    return result;
  }

  Future<EquipmentModel?> _resolveEquipment(MiniMapRequest request) async {
    if (request.equipment != null) return request.equipment;
    final query = request.equipmentCodeText.trim();
    if (query.isEmpty) return null;
    final lookup = LookupService.instance;
    await lookup.loadFromDatabase();
    final found = lookup.findEquipmentsByCode(query);
    if (found.length == 1) return found.first;
    return null;
  }

  Future<List<int>> _departmentIdsForEquipment(
    DepartmentRepository departments,
    EquipmentRepository equipmentRepo,
    EquipmentModel equipment,
  ) async {
    final direct = equipment.departmentId;
    if (direct != null) return [direct];
    final equipmentId = equipment.id;
    if (equipmentId == null) return const [];
    final linkedUsers = await equipmentRepo.getUserIdsLinkedToEquipment(
      equipmentId,
    );
    final ids = <int>{};
    for (final uid in linkedUsers) {
      ids.addAll(await departments.resolveActiveDepartmentIdsForUserId(uid));
    }
    return ids.toList()..sort();
  }
}
