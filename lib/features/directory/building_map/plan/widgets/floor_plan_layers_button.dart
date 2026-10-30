import 'package:flutter/material.dart';

import '../../../../../core/models/floor_plan_object_kind.dart';
import '../../../../../core/models/floor_plan_placement.dart';
import '../floor_plan_layers.dart';
import 'floor_plan_symbol_painter.dart';

/// Το κουμπί «Στρώσεις»: ένα κουτάκι για υπαλλήλους, τηλέφωνα, εξοπλισμό
/// του Καταλόγου και κάθε είδος αντικειμένου, συν «όλα» / «κανένα». Το μενού
/// μένει ανοιχτό όσο αλλάζετε κουτάκια.
class FloorPlanLayersButton extends StatelessWidget {
  const FloorPlanLayersButton({
    super.key,
    required this.kinds,
    required this.hidden,
    required this.onChanged,
  });

  final List<FloorPlanObjectKind> kinds;
  final Set<String> hidden;
  final ValueChanged<Set<String>> onChanged;

  List<String> get _allLayers => [
    for (final t in FloorPlanPlacementType.values) floorPlanPlacementLayer(t),
    for (final k in kinds) floorPlanKindLayer(k.id),
  ];

  void _toggle(String layer, bool visible) {
    final next = {...hidden};
    if (visible) {
      next.remove(layer);
    } else {
      next.add(layer);
    }
    onChanged(next);
  }

  Widget _check(String layer, String label, Widget icon) => CheckboxMenuButton(
    closeOnActivate: false,
    value: !hidden.contains(layer),
    onChanged: (v) => _toggle(layer, v ?? false),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [icon, const SizedBox(width: 8), Text(label)],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final sortedKinds = [...kinds]..sort((a, b) => a.name.compareTo(b.name));
    return MenuAnchor(
      menuChildren: [
        _check(
          floorPlanPlacementLayer(FloorPlanPlacementType.user),
          'Υπάλληλοι',
          const FloorPlanSymbolIcon(FloorPlanSymbol.person, size: 20),
        ),
        _check(
          floorPlanPlacementLayer(FloorPlanPlacementType.phone),
          'Τηλέφωνα',
          const FloorPlanSymbolIcon(FloorPlanSymbol.phone, size: 20),
        ),
        _check(
          floorPlanPlacementLayer(FloorPlanPlacementType.equipment),
          'Εξοπλισμός Καταλόγου',
          const FloorPlanSymbolIcon(FloorPlanSymbol.computer, size: 20),
        ),
        if (sortedKinds.isNotEmpty) const Divider(height: 8),
        for (final kind in sortedKinds)
          _check(
            floorPlanKindLayer(kind.id),
            kind.name,
            FloorPlanSymbolIcon(kind.symbol, size: 20),
          ),
        const Divider(height: 8),
        MenuItemButton(
          closeOnActivate: false,
          onPressed: hidden.isEmpty ? null : () => onChanged(const {}),
          child: const Text('Όλα'),
        ),
        MenuItemButton(
          closeOnActivate: false,
          onPressed: () => onChanged(_allLayers.toSet()),
          child: const Text('Κανένα'),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: hidden.isEmpty ? 'Στρώσεις' : 'Στρώσεις (κάποιες κρυμμένες)',
        isSelected: hidden.isNotEmpty,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.layers_outlined),
      ),
    );
  }
}
