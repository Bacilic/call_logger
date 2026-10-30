import 'package:flutter/material.dart';

import '../floor_plan_editor_controller.dart';
import 'floor_plan_symbol_painter.dart';

/// Η κατακόρυφη στήλη εργαλείων της οθόνης σχεδίασης.
class FloorPlanToolRail extends StatelessWidget {
  const FloorPlanToolRail({super.key, required this.controller});

  final FloorPlanEditorController controller;

  @override
  Widget build(BuildContext context) {
    Widget tool(FloorPlanTool t, IconData icon, String label) {
      final selected = controller.tool == t;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: IconButton(
          tooltip: label,
          isSelected: selected,
          style: IconButton.styleFrom(
            backgroundColor: selected
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
          ),
          onPressed: () => controller.setTool(t),
          icon: Icon(icon),
        ),
      );
    }

    return SizedBox(
      width: 60,
      child: Column(
        children: [
          const SizedBox(height: 8),
          tool(FloorPlanTool.select, Icons.near_me_outlined, 'Επιλογή'),
          tool(FloorPlanTool.wall, Icons.horizontal_rule, 'Τοίχος'),
          tool(
            FloorPlanTool.opening,
            Icons.door_front_door_outlined,
            'Άνοιγμα (πόρτα)',
          ),
          tool(FloorPlanTool.room, Icons.crop_square, 'Χώρος'),
          tool(FloorPlanTool.text, Icons.text_fields, 'Κείμενο'),
          tool(FloorPlanTool.dimension, Icons.straighten, 'Διάσταση'),
          tool(FloorPlanTool.measure, Icons.timeline, 'Μέτρηση απόστασης'),
          const Divider(indent: 12, endIndent: 12),
          _objectTool(context),
          tool(
            FloorPlanTool.place,
            Icons.person_pin_circle_outlined,
            'Τοποθέτηση υπαλλήλων, τηλεφώνων, εξοπλισμού',
          ),
        ],
      ),
    );
  }

  /// «Αντικείμενο»: ανοίγει τη λίστα με τα είδη· το είδος που διαλέγετε
  /// τοποθετείται με κάθε κλικ.
  Widget _objectTool(BuildContext context) {
    final selected = controller.tool == FloorPlanTool.object;
    final current = controller.objectKind;
    final kinds = controller.kinds.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: PopupMenuButton<int>(
        tooltip: selected && current != null
            ? 'Αντικείμενο: ${current.name}'
            : 'Αντικείμενο',
        position: PopupMenuPosition.over,
        offset: const Offset(56, 0),
        onSelected: controller.setObjectTool,
        itemBuilder: (_) => kinds.isEmpty
            ? const [
                PopupMenuItem<int>(
                  enabled: false,
                  child: Text(
                    'Δεν υπάρχει ακόμη κανένα είδος.\n'
                    'Ορίστε είδη από το κουμπί «Είδη αντικειμένων».',
                  ),
                ),
              ]
            : [
                for (final kind in kinds)
                  PopupMenuItem<int>(
                    value: kind.id,
                    child: Row(
                      children: [
                        FloorPlanSymbolIcon(kind.symbol, size: 24),
                        const SizedBox(width: 12),
                        Text(kind.name),
                      ],
                    ),
                  ),
              ],
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
            borderRadius: BorderRadius.circular(20),
          ),
          alignment: Alignment.center,
          child: selected && current != null
              ? FloorPlanSymbolIcon(current.symbol, size: 26)
              : const Icon(Icons.print_outlined),
        ),
      ),
    );
  }
}

/// Η γραμμή στο κάτω μέρος του καμβά: τι κάνει τώρα το εργαλείο.
class FloorPlanStatusBar extends StatelessWidget {
  const FloorPlanStatusBar({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(text, style: theme.textTheme.bodySmall),
    );
  }
}
