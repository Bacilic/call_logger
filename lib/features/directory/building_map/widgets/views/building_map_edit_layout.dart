import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/models/building_map_floor.dart';
import '../../../models/department_model.dart';
import '../../providers/building_map_providers.dart';
import '../building_map_edit_toolbar.dart';

/// Στήλη στοιχείων επεξεργασίας: μπάρα εργαλείων, επιλογή τμήματος.
String _departmentName(List<DepartmentModel> departments, int id) {
  for (final d in departments) {
    if (d.id == id) return d.name;
  }
  return 'Τμήμα #$id';
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
                              : _departmentName(
                                  activeDepartments,
                                  deptToMap,
                                ),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
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
