import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/building_map_floor.dart';
import '../../../../core/models/floor_plan_placement.dart';
import '../../models/department_model.dart';
import '../../providers/department_directory_provider.dart';
import '../../providers/directory_provider.dart';
import '../../screens/widgets/user_form_dialog.dart';
import '../../services/equipment_form_launcher.dart';
import '../controllers/building_map_controller.dart';
import '../plan/floor_plan_item_info.dart';
import '../plan/floor_plan_layers.dart';
import '../plan/floor_plan_objects.dart';
import '../plan/services/floor_plan_layers_preference.dart';
import '../plan/widgets/floor_plan_layers_button.dart';
import '../plan/providers/floor_plan_providers.dart';
import '../plan/screens/floor_plan_editor_screen.dart';
import '../plan/widgets/floor_plan_map_view.dart';
import '../providers/building_map_providers.dart';
import '../services/building_map_department_eligibility.dart';

/// Ο καμβάς του κεντρικού χάρτη για όροφο που **πέρασε στον νέο χάρτη**: ο
/// σχεδιασμένος όροφος, με φωτισμένο το τμήμα που βρήκε η αναζήτηση.
///
/// Πέρασμα του ποντικιού πάνω από υπάλληλο, τηλέφωνο, εξοπλισμό ή
/// αντικείμενο δείχνει υπόδειξη· κλικ ανοίγει τα πλήρη στοιχεία. Οι
/// «Στρώσεις» κρύβουν ό,τι δεν χρειάζεται ο χρήστης, και τις θυμάται.
///
/// Το κουμπί «Μέτρηση» το βλέπουν όλοι: μετρά αποστάσεις (π.χ. μήκος
/// καλωδίου) χωρίς να αλλάζει τίποτα στον χάρτη. Στην «Επεξεργασία», όποιος
/// έχει το δικαίωμα βλέπει και το κουμπί «Σχεδίαση χάρτη».
class BuildingMapNewFloorCanvas extends ConsumerStatefulWidget {
  const BuildingMapNewFloorCanvas({
    super.key,
    required this.floor,
    required this.editMode,
  });

  final BuildingMapFloor floor;
  final bool editMode;

  @override
  ConsumerState<BuildingMapNewFloorCanvas> createState() =>
      _BuildingMapNewFloorCanvasState();
}

class _BuildingMapNewFloorCanvasState
    extends ConsumerState<BuildingMapNewFloorCanvas> {
  bool _measuring = false;

  /// Οι στρώσεις που ο χρήστης έχει κρύψει.
  Set<String> _hidden = const {};

  @override
  void initState() {
    super.initState();
    FloorPlanLayersPreference.read().then((hidden) {
      if (mounted) setState(() => _hidden = hidden);
    });
  }

  void _setHidden(Set<String> hidden) {
    setState(() => _hidden = hidden);
    FloorPlanLayersPreference.write(hidden);
  }

  /// «Άνοιγμα καρτέλας»: ο υπάλληλος και ο εξοπλισμός έχουν καρτέλα στον
  /// Κατάλογο· τα τηλέφωνα και τα αντικείμενα του χάρτη όχι.
  VoidCallback? _cardOpener(
    FloorPlanObjectView view,
    FloorPlanFloorItems items,
  ) {
    if (view.source != FloorPlanItemSource.placement) return null;
    final placement = items.placements
        .where((p) => p.id == view.id)
        .firstOrNull;
    if (placement == null) return null;
    switch (placement.type) {
      case FloorPlanPlacementType.user:
        return () => _openUser(placement.entityId);
      case FloorPlanPlacementType.equipment:
        return () =>
            EquipmentFormLauncher.openById(context, ref, placement.entityId);
      case FloorPlanPlacementType.phone:
        return null;
    }
  }

  Future<void> _openUser(int userId) async {
    final notifier = ref.read(directoryProvider.notifier);
    await notifier.loadUsers();
    if (!mounted) return;
    final user = ref
        .read(directoryProvider)
        .allUsers
        .where((u) => u.id == userId)
        .firstOrNull;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ο υπάλληλος δεν βρέθηκε στον Κατάλογο.')),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => UserFormDialog(initialUser: user, notifier: notifier),
    );
  }

  @override
  Widget build(BuildContext context) {
    final floor = widget.floor;
    final editMode = widget.editMode;
    final elements = ref.watch(floorPlanElementsProvider(floor.id));
    // Τα αντικείμενα δεν κρατούν τον χάρτη: ως να φορτώσουν, φαίνεται το
    // σχέδιο χωρίς αυτά.
    final items = ref.watch(floorPlanFloorItemsProvider(floor.id)).value;
    final departments = departmentsEligibleForBuildingMap(
      ref.watch(departmentDirectoryProvider).allDepartments,
    );
    final byId = <int, DepartmentModel>{
      for (final d in departments)
        if (d.id != null) d.id!: d,
    };
    final highlight = ref.watch(buildingMapSelectedDepartmentIdToMapProvider);
    final centerRequest = ref.watch(
      buildingMapViewportCenterRequestSeqProvider,
    );
    final controller = ref.read(buildingMapControllerProvider);
    final spot = ref.watch(buildingMapSearchFocusProvider);
    final focusItem = spot == null || spot.floorId != floor.id
        ? null
        : (
            source: spot.isPlacement
                ? FloorPlanItemSource.placement
                : FloorPlanItemSource.object,
            id: spot.itemId,
          );

    final Widget body = elements.when(
      data: (list) => FloorPlanMapView(
        elements: list,
        departments: byId,
        rotationDegrees: floor.rotationDegrees,
        highlightDepartmentId: highlight,
        centerRequest: centerRequest,
        measuring: _measuring,
        // Ό,τι βρήκε η αναζήτηση φαίνεται, ακόμη κι αν η στρώση του είναι
        // κρυμμένη.
        objects: items == null
            ? const []
            : visibleFloorPlanLayers(items.views, _hidden, keep: focusItem),
        focusItems: {?focusItem},
        infoSources: items == null
            ? null
            : FloorPlanInfoSources(
                objects: {for (final o in items.objects) o.id: o},
                kinds: items.kinds,
                catalog: items.catalog,
                placements: {for (final p in items.placements) p.id: p},
                departmentName: (id) => byId[id]?.name,
                roomAt: floorPlanRoomLookup(list),
                ports: items.ports,
                occupiedPortIds: items.occupiedPortIds,
              ),
        onOpenCard: items == null ? null : (view) => _cardOpener(view, items),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Ο χάρτης δεν διαβάστηκε: $e')),
    );

    final measureButton = _measuring
        ? FilledButton.icon(
            onPressed: () => setState(() => _measuring = false),
            icon: const Icon(Icons.close),
            label: const Text('Τέλος μέτρησης'),
          )
        : FilledButton.tonalIcon(
            onPressed: () => setState(() => _measuring = true),
            icon: const Icon(Icons.timeline),
            label: const Text('Μέτρηση'),
          );
    final canDraw = editMode && controller.canManageFloorPlans;
    return Stack(
      fit: StackFit.expand,
      children: [
        body,
        Positioned(
          left: 16,
          bottom: 16,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              measureButton,
              const SizedBox(width: 8),
              Material(
                shape: const CircleBorder(),
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: FloorPlanLayersButton(
                  kinds: items?.kinds.values.toList() ?? const [],
                  hidden: _hidden,
                  onChanged: _setHidden,
                ),
              ),
              if (canDraw) ...[
                const SizedBox(width: 8),
                _drawButton(context, floor),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _drawButton(BuildContext context, BuildingMapFloor floor) =>
      FilledButton.icon(
        onPressed: () async {
          await openFloorPlanEditor(
            context,
            floor,
            afterDepartmentChange: () => ref
                .read(departmentDirectoryProvider.notifier)
                .loadDepartments(),
            onActivated: () =>
                ref.read(floorPlanRevisionProvider.notifier).bump(),
          );
          // Ό,τι σχεδιάστηκε φαίνεται αμέσως, χωρίς να περιμένει τον
          // περιοδικό έλεγχο.
          ref.read(floorPlanRevisionProvider.notifier).bump();
        },
        icon: const Icon(Icons.architecture),
        label: const Text('Σχεδίαση χάρτη'),
      );
}
