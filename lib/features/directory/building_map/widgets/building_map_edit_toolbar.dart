import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/building_map_floor.dart';
import '../providers/building_map_providers.dart';
import 'building_map_floor_menu_button.dart';

/// Εναλλαγή Επιλογή / Σχεδίαση. Η [MapToolMode.edit] (λαβές, περιστροφή) μπαίνει
/// αυτόματα μετά από σχεδίαση ή κλικ σε χαρτογραφημένο τμήμα· δεν εμφανίζεται
/// ξεχωριστό κουμπί.
class BuildingMapEditToolbar extends ConsumerWidget {
  const BuildingMapEditToolbar({
    super.key,
    required this.floors,
    required this.hasActiveCanvas,
    required this.onFloorsChanged,
  });

  final List<BuildingMapFloor> floors;
  final bool hasActiveCanvas;
  final VoidCallback onFloorsChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toolMode = ref.watch(buildingMapToolProvider);
    final deptToMap = ref.watch(buildingMapSelectedDepartmentIdToMapProvider);

    Widget toggles = ToggleButtons(
      isSelected: [
        toolMode == MapToolMode.select,
        toolMode == MapToolMode.draw || toolMode == MapToolMode.edit,
      ],
      onPressed: (index) {
        if (index == 0) {
          ref
              .read(buildingMapToolProvider.notifier)
              .setMode(MapToolMode.select);
          ref.read(buildingMapDraftShapeProvider.notifier).clear();
          ref.read(buildingMapEditFromSelectionTapProvider.notifier).clear();
        } else {
          if (deptToMap == null) {
            ref
                .read(buildingMapDeptSelectionHudVisibleProvider.notifier)
                .setVisible(true);
          }
          ref.read(buildingMapToolProvider.notifier).setMode(MapToolMode.draw);
        }
      },
      children: [
        Tooltip(
          message:
              'Μετακίνηση και εστίαση στον χάρτη. Το hover πάνω από την ετικέτα ονόματος επισημαίνει το τμήμα όπως πάνω από την περιοχή του. Κλικ σε χαρτογραφημένο τμήμα για επεξεργασία περιοχής (λαβές, περιστροφή).',
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(Icons.pan_tool_alt_outlined),
                SizedBox(width: 6),
                Text('Επιλογή'),
              ],
            ),
          ),
        ),
        Tooltip(
          message:
              'Σύρετε για νέο περίγραμμα τμήματος (χρειάζεται επιλεγμένο τμήμα). Αν δεν έχει επιλεγεί τμήμα, ανοίγει η λίστα επιλογής. Μετά το σχέδιο χρησιμοποιήστε τις λαβές για μέγεθος και περιστροφή.',
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(Icons.draw_outlined),
                SizedBox(width: 6),
                Text('Σχεδίαση'),
              ],
            ),
          ),
        ),
      ],
    );
    if (!hasActiveCanvas) {
      toggles = Opacity(opacity: 0.42, child: IgnorePointer(child: toggles));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
      child: Row(
        children: [
          toggles,
          IconButton(
            tooltip: 'Επιλογή τμήματος για σχεδίαση',
            onPressed: !hasActiveCanvas
                ? null
                : () => ref
                      .read(buildingMapDeptSelectionHudVisibleProvider.notifier)
                      .setVisible(true),
            icon: const Icon(Icons.grid_view_rounded),
          ),
          BuildingMapFloorsMenuButton(
            floors: floors,
            onFloorsChanged: onFloorsChanged,
          ),
        ],
      ),
    );
  }
}
