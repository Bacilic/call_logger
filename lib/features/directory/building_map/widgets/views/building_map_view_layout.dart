import 'package:flutter/material.dart';

import '../building_map_floor_departments_dialog.dart';

/// Γραμμή επιλογής φύλλου, αναζήτησης τμήματος και πρόσβασης στη λίστα τμημάτων
/// του ορόφου (λειτουργία προβολής — read-only checkboxes).
class BuildingMapViewLayout extends StatelessWidget {
  const BuildingMapViewLayout({
    super.key,
    required this.sheetPicker,
    required this.globalSearchField,
    this.currentFloorLabel,
  });

  final Widget sheetPicker;
  final Widget globalSearchField;
  final String? currentFloorLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(flex: 2, child: sheetPicker),
          const SizedBox(width: 8),
          Expanded(flex: 4, child: globalSearchField),
          const SizedBox(width: 4),
          BuildingMapFloorDepartmentsButton(
            mode: BuildingMapFloorDepartmentsDialogMode.view,
            floorTitle: currentFloorLabel,
          ),
        ],
      ),
    );
  }
}
