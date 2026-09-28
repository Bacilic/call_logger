import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/models/building_map_floor.dart';
import '../../../models/department_model.dart';
import '../../providers/building_map_providers.dart';
import '../../services/building_map_floor_ordering.dart';
import '../../services/building_map_placement_replacement.dart';
import '../building_map_edit_toolbar.dart';

/// Στήλη στοιχείων επεξεργασίας: μπάρα εργαλείων, επιλογή τμήματος.
DepartmentModel? _departmentById(List<DepartmentModel> departments, int id) {
  for (final d in departments) {
    if (d.id == id) return d;
  }
  return null;
}

/// Τι θα πάθει η αποθηκευμένη θέση αν σχεδιάσεις τώρα — `null` όταν δεν
/// υπάρχει τίποτα να αντικατασταθεί.
String? _placementWarning(
  DepartmentModel dept,
  int? currentSheetId,
  List<BuildingMapFloor> floors,
) {
  if (currentSheetId == null) return null;
  final replacement = resolveBuildingMapPlacementReplacement(
    department: dept,
    targetSheetId: currentSheetId,
  );
  if (replacement.replacesPlacementOnThisSheet) {
    return ' — έχει ήδη θέση εδώ· νέα σχεδίαση την αντικαθιστά';
  }
  if (!replacement.movesFromAnotherSheet) return null;
  for (final f in floors) {
    if (f.id == replacement.previousFloorId) {
      return ' — είναι σχεδιασμένο στον όροφο «${buildingMapFloorDisplayLabel(f)}»·'
          ' η σχεδίαση εδώ το μετακομίζει';
    }
  }
  return ' — δείχνει σε όροφο που δεν υπάρχει πια';
}

class BuildingMapEditLayout extends ConsumerWidget {
  const BuildingMapEditLayout({
    super.key,
    required this.floors,
    required this.hasActiveCanvas,
    required this.activeDepartments,
    required this.currentSheetId,
    required this.onFloorsChanged,
  });

  final List<BuildingMapFloor> floors;
  final bool hasActiveCanvas;
  final List<DepartmentModel> activeDepartments;
  final int? currentSheetId;
  final VoidCallback onFloorsChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deptToMap = ref.watch(buildingMapSelectedDepartmentIdToMapProvider);
    final selected = deptToMap == null
        ? null
        : _departmentById(activeDepartments, deptToMap);
    final warning = selected == null
        ? null
        : _placementWarning(selected, currentSheetId, floors);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: BuildingMapEditToolbar(
            floors: floors,
            hasActiveCanvas: hasActiveCanvas,
            onFloorsChanged: onFloorsChanged,
          ),
        ),
        AbsorbPointer(
          absorbing: !hasActiveCanvas,
          child: Opacity(
            opacity: hasActiveCanvas ? 1.0 : 0.42,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text.rich(
                    TextSpan(
                      style: Theme.of(context).textTheme.bodyMedium,
                      children: [
                        const TextSpan(text: 'Τμήμα για σχεδίαση: '),
                        TextSpan(
                          text: deptToMap == null
                              ? 'Κανένα'
                              : (selected?.name ?? 'Τμήμα #$deptToMap'),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (warning != null)
                          TextSpan(
                            text: warning,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
