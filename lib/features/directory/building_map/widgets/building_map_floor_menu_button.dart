import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/building_map_floor.dart';
import '../controllers/building_map_controller.dart';

/// Κείμενο εμφάνισης όπως στο dropdown · χρησιμοποιείται και για ταξινόμηση.
String buildingMapFloorDisplayLabel(BuildingMapFloor f) {
  final g = f.floorGroup?.trim();
  return (g != null && g.isNotEmpty) ? '$g · ${f.label}' : f.label;
}

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

    final sorted = List<BuildingMapFloor>.from(floors)
      ..sort(
        (a, b) => buildingMapFloorDisplayLabel(a).toLowerCase().compareTo(
              buildingMapFloorDisplayLabel(b).toLowerCase(),
            ),
      );

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
        final parts = code.split(':');
        if (parts.length != 2) return;
        final cmd = parts[0];
        final id = int.tryParse(parts[1]);
        if (id == null) return;
        final floor = floors
            .cast<BuildingMapFloor?>()
            .firstWhere((fl) => fl?.id == id, orElse: () => null);
        if (floor == null) return;
        switch (cmd) {
          case 'pick':
            await selectFloor(id);
          case 'edit':
            await controller.editFloorSheet(context, floor);
            onFloorsChanged();
          case 'delete':
            await controller.deleteFloorSheet(context, id, floor.imagePath);
            onFloorsChanged();
        }
      },
      itemBuilder: (ctx) => [
        PopupMenuItem<String>(
          value: 'add',
          child: Row(
            children: [
              Icon(
                Icons.add_photo_alternate_outlined,
                size: 20,
                color: Theme.of(ctx).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Προσθήκη νέας κάτοψης'),
              ),
            ],
          ),
        ),
        if (sorted.isNotEmpty) const PopupMenuDivider(),
        ...sorted.map((f) {
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
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Επεξεργασία',
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    onPressed: () => Navigator.pop(ctx, 'edit:${f.id}'),
                  ),
                  IconButton(
                    tooltip: 'Διαγραφή',
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => Navigator.pop(ctx, 'delete:${f.id}'),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
