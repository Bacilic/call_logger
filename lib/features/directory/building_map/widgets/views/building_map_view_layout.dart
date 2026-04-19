import 'package:flutter/material.dart';

/// Γραμμή επιλογής φύλλου και αναζήτησης τμήματος (λειτουργία προβολής).
class BuildingMapViewLayout extends StatelessWidget {
  const BuildingMapViewLayout({
    super.key,
    required this.sheetPicker,
    required this.globalSearchField,
  });

  final Widget sheetPicker;
  final Widget globalSearchField;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: sheetPicker),
          const SizedBox(width: 8),
          Expanded(child: globalSearchField),
        ],
      ),
    );
  }
}
