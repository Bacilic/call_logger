import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/database/database_helper.dart';
import '../../../../../core/database/floor_plan_objects_repository.dart';
import '../../../../../core/database/floor_plan_placements_repository.dart';
import '../../../../../core/database/floor_plan_ports_repository.dart';
import '../../../../../core/database/floor_plan_repository.dart';
import '../../../../../core/models/floor_plan_element.dart';
import '../../providers/building_map_providers.dart';
import '../../../../../core/models/floor_plan_object.dart';
import '../../../../../core/models/floor_plan_object_kind.dart';
import '../../../../../core/models/floor_plan_placement.dart';
import '../../../../../core/models/floor_plan_port.dart';
import '../floor_plan_objects.dart';

/// Αύξων αριθμός «κάτι άλλαξε στον νέο χάρτη» — από αυτόν τον σταθμό ή από
/// άλλον (τον εντοπίζει το [FloorPlanLiveRefresh]).
final floorPlanRevisionProvider =
    NotifierProvider<FloorPlanRevisionNotifier, int>(
      FloorPlanRevisionNotifier.new,
    );

class FloorPlanRevisionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state = state + 1;
}

/// Οι όροφοι που έχουν περάσει στον νέο χάρτη.
final activeFloorPlanIdsProvider = FutureProvider<Set<int>>((ref) async {
  ref.watch(buildingMapFloorReloadSeqProvider);
  ref.watch(floorPlanRevisionProvider);
  final db = await DatabaseHelper.instance.database;
  return FloorPlanRepository(db).activeFloorIds();
});

/// Τα στοιχεία του νέου χάρτη ενός ορόφου.
final floorPlanElementsProvider =
    FutureProvider.family<List<FloorPlanElement>, int>((ref, floorId) async {
      ref.watch(floorPlanRevisionProvider);
      final db = await DatabaseHelper.instance.database;
      return FloorPlanRepository(db).listElements(floorId);
    });

/// Ό,τι έχει ένας όροφος του νέου χάρτη πέρα από το σχέδιο: αντικείμενα,
/// είδη, θέσεις του Καταλόγου και οι εγγραφές τους.
class FloorPlanFloorItems {
  const FloorPlanFloorItems({
    required this.objects,
    required this.kinds,
    required this.placements,
    required this.catalog,
    this.ports = const [],
    this.occupiedPortIds = const {},
  });

  final List<FloorPlanObject> objects;
  final Map<int, FloorPlanObjectKind> kinds;
  final List<FloorPlanPlacement> placements;
  final Map<(FloorPlanPlacementType, int), FloorPlanCatalogEntry> catalog;

  /// Οι θύρες των αντικειμένων, και ποιες έχουν καλώδιο.
  final List<FloorPlanPort> ports;
  final Set<int> occupiedPortIds;

  /// Όλα έτοιμα για σχεδίαση: τα έπιπλα πρώτα, οι θέσεις τελευταίες.
  List<FloorPlanObjectView> get views => [
    ...buildFloorPlanObjectViews(objects, kinds),
    ...buildFloorPlanPlacementViews(placements, catalog),
  ];
}

final floorPlanFloorItemsProvider =
    FutureProvider.family<FloorPlanFloorItems, int>((ref, floorId) async {
      ref.watch(floorPlanRevisionProvider);
      final db = await DatabaseHelper.instance.database;
      final repo = FloorPlanObjectsRepository(db);
      final placements = FloorPlanPlacementsRepository(db);
      final portsRepo = FloorPlanPortsRepository(db);
      final ports = await portsRepo.listForFloor(floorId);
      return FloorPlanFloorItems(
        ports: ports,
        occupiedPortIds: await portsRepo.occupiedPortIds([
          for (final p in ports) p.id,
        ]),
        objects: await repo.listObjects(floorId),
        kinds: await repo.kinds(),
        placements: await placements.listPlacements(floorId),
        catalog: {for (final e in await placements.catalogEntries()) e.key: e},
      );
    });

/// Ελέγχει περιοδικά αν άλλος σταθμός άλλαξε τον νέο χάρτη (σχεδίαση ή
/// ενεργοποίηση ορόφου) και, μόνο τότε, ανανεώνει την προβολή.
///
/// Δικός του έλεγχος και όχι η γενική ανανέωση της κοινής βάσης: εκείνη
/// σταματά όσο είναι ανοιχτός ένας διάλογος — και ο χάρτης είναι διάλογος. Η
/// ανάγνωση είναι μία μικρή γραμμή ανά όροφο, χωρίς εικόνες.
class FloorPlanLiveRefresh extends ConsumerStatefulWidget {
  const FloorPlanLiveRefresh({
    super.key,
    this.interval = const Duration(seconds: 10),
  });

  final Duration interval;

  @override
  ConsumerState<FloorPlanLiveRefresh> createState() =>
      _FloorPlanLiveRefreshState();
}

class _FloorPlanLiveRefreshState extends ConsumerState<FloorPlanLiveRefresh> {
  Timer? _timer;
  Map<int, String>? _last;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.interval, (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      final db = await DatabaseHelper.instance.database;
      final stamps = await FloorPlanRepository(db).floorStamps();
      if (!mounted) return;
      final last = _last;
      _last = stamps;
      if (last != null && !_sameStamps(last, stamps)) {
        ref.read(floorPlanRevisionProvider.notifier).bump();
      }
    } catch (_) {
      // Η βάση δεν απάντησε αυτή τη φορά· ο επόμενος γύρος ξαναδοκιμάζει.
    } finally {
      _checking = false;
    }
  }

  static bool _sameStamps(Map<int, String> a, Map<int, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Τα τμήματα που έχουν χώρο στον νέο χάρτη του ορόφου [floorId] — ή `null`
/// όταν ο όροφος δεν έχει ενεργοποιηθεί (τότε ισχύουν τα κουτάκια του παλιού
/// χάρτη). Κενό σύνολο όσο τα στοιχεία δεν έχουν φορτώσει ακόμη.
Set<int>? newMapDepartmentIdsOnFloor(WidgetRef ref, int floorId) {
  final active = ref.watch(activeFloorPlanIdsProvider).value ?? const <int>{};
  if (!active.contains(floorId)) return null;
  final elements = ref.watch(floorPlanElementsProvider(floorId)).value;
  return {
    for (final e in elements ?? const <FloorPlanElement>[])
      if (e.kind == FloorPlanElementKind.room) ?e.departmentId,
  };
}
