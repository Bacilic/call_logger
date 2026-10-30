import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/building_map_floor.dart';
import '../../providers/department_directory_provider.dart';
import '../controllers/building_map_controller.dart';
import '../plan/providers/floor_plan_providers.dart';
import '../plan/screens/floor_plan_editor_screen.dart';
import '../services/building_map_floor_ordering.dart';

/// Μενού επιλογής / προσθήκης / επεξεργασίας / διαγραφής κατοψών (λειτουργία επεξεργασίας).
class BuildingMapFloorsMenuButton extends ConsumerWidget {
  const BuildingMapFloorsMenuButton({
    super.key,
    required this.floors,
    required this.onFloorsChanged,
  });

  final List<BuildingMapFloor> floors;
  final VoidCallback onFloorsChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(buildingMapControllerProvider);

    Future<void> selectFloor(int id) async {
      await controller.selectFloorFromList(id, floors);
      onFloorsChanged();
    }

    final sorted = buildingMapFloorsSortedForDisplay(floors);

    return PopupMenuButton<String>(
      tooltip: 'Κατόψεις ορόφων',
      child: const Padding(
        padding: EdgeInsets.all(8),
        child: Icon(Icons.layers_outlined),
      ),
      onSelected: (code) async {
        if (code == 'add') {
          await controller.addFloorSheet(context);
          onFloorsChanged();
          return;
        }
        if (code == 'upload') {
          await controller.uploadLocalFloorPlans(context);
          onFloorsChanged();
          return;
        }
        final parts = code.split(':');
        if (parts.length != 2) return;
        final cmd = parts[0];
        final id = int.tryParse(parts[1]);
        if (id == null) return;
        final floor = floors.cast<BuildingMapFloor?>().firstWhere(
          (fl) => fl?.id == id,
          orElse: () => null,
        );
        if (floor == null) return;
        switch (cmd) {
          case 'pick':
            await selectFloor(id);
          case 'plan':
            if (controller.canManageFloorPlans) {
              await openFloorPlanEditor(
                context,
                floor,
                afterDepartmentChange: () => ref
                    .read(departmentDirectoryProvider.notifier)
                    .loadDepartments(),
                onActivated: () =>
                    ref.read(floorPlanRevisionProvider.notifier).bump(),
              );
              ref.read(floorPlanRevisionProvider.notifier).bump();
              onFloorsChanged();
            }
          case 'edit':
            await controller.editFloorSheet(context, floor);
            onFloorsChanged();
          case 'revert':
            await controller.revertFloorImage(context, floor);
            onFloorsChanged();
          case 'delete':
            await controller.deleteFloorSheet(context, id);
            onFloorsChanged();
        }
      },
      itemBuilder: (ctx) {
        // Ρωτιέται σε κάθε άνοιγμα του μενού: η «Αλλαγή χρήστη» αλλάζει την
        // απάντηση ζωντανά. Χωρίς το δικαίωμα το μενού μένει μόνο επιλογέας
        // ορόφου — τα κουμπιά κρύβονται, δεν γκριζάρουν.
        final canManage = controller.canManageFloorPlans;
        // Όροφος στον νέο χάρτη δεν έχει πια εικόνα κάτοψης — και δεν θέλει.
        final newMapFloors =
            ref.read(activeFloorPlanIdsProvider).value ?? const <int>{};
        final anyNotUploaded = floors.any(
          (f) => !f.hasImage && !newMapFloors.contains(f.id),
        );
        return [
          if (canManage)
            _actionItem(
              ctx,
              value: 'add',
              icon: Icons.add_photo_alternate_outlined,
              label: 'Προσθήκη νέας κάτοψης',
            ),
          if (canManage && anyNotUploaded)
            _actionItem(
              ctx,
              value: 'upload',
              icon: Icons.cloud_upload_outlined,
              label: 'Ανέβασμα κατόψεων στη βάση',
            ),
          if (canManage && sorted.isNotEmpty) const PopupMenuDivider(),
          ...sorted.map((f) => _floorItem(ctx, f, canManage: canManage)),
        ];
      },
    );
  }

  PopupMenuItem<String> _actionItem(
    BuildContext ctx, {
    required String value,
    required IconData icon,
    required String label,
  }) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(ctx).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }

  PopupMenuItem<String> _floorItem(
    BuildContext ctx,
    BuildingMapFloor f, {
    required bool canManage,
  }) {
    final label = buildingMapFloorDisplayLabel(f);
    return PopupMenuItem<String>(
      value: 'pick:${f.id}',
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: () => Navigator.pop(ctx, 'pick:${f.id}'),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Text(label, overflow: TextOverflow.ellipsis),
              ),
            ),
            if (canManage) ...[
              IconButton(
                tooltip: 'Σχεδίαση νέου χάρτη',
                icon: const Icon(Icons.architecture, size: 20),
                onPressed: () => Navigator.pop(ctx, 'plan:${f.id}'),
              ),
              IconButton(
                tooltip: 'Επεξεργασία',
                icon: const Icon(Icons.edit_outlined, size: 20),
                onPressed: () => Navigator.pop(ctx, 'edit:${f.id}'),
              ),
              if (f.hasPreviousImage)
                IconButton(
                  tooltip: 'Επαναφορά προηγούμενης κάτοψης',
                  icon: const Icon(Icons.history, size: 20),
                  onPressed: () => Navigator.pop(ctx, 'revert:${f.id}'),
                ),
              IconButton(
                tooltip: 'Διαγραφή',
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () => Navigator.pop(ctx, 'delete:${f.id}'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
