import 'package:flutter/material.dart';

import '../../../../../core/widgets/compact_tooltip.dart';
import '../services/floor_plan_drawing_preferences.dart';

/// Το γρανάζι της σχεδίασης: οι ρυθμίσεις συμπεριφοράς των εργαλείων. Το
/// μενού μένει ανοιχτό όσο αλλάζετε κουτάκια.
class FloorPlanDrawingSettingsButton extends StatelessWidget {
  const FloorPlanDrawingSettingsButton({
    super.key,
    required this.aids,
    required this.onChanged,
  });

  final FloorPlanDrawingAids aids;
  final ValueChanged<FloorPlanDrawingAids> onChanged;

  Widget _check({
    required String label,
    required String hint,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => CompactTooltip(
    message: hint,
    child: CheckboxMenuButton(
      closeOnActivate: false,
      value: value,
      onChanged: (v) => onChanged(v ?? false),
      child: Text(label),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        _check(
          label: 'Γραμμές-οδηγοί',
          hint:
              'Μοβ διακεκομμένες γραμμές στην προέκταση ή στην κάθετη από '
              'την άκρη ενός τοίχου· το σημείο κουμπώνει πάνω τους.',
          value: aids.guides,
          onChanged: (v) => onChanged(aids.copyWith(guides: v)),
        ),
        _check(
          label: 'Μοίρες τομής',
          hint:
              'Η γωνία ενός τοίχου με όσους συναντά, όσο τον σχεδιάζετε ή '
              'όταν είναι επιλεγμένος.',
          value: aids.angles,
          onChanged: (v) => onChanged(aids.copyWith(angles: v)),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: 'Ρυθμίσεις σχεδίασης',
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.settings_outlined),
      ),
    );
  }
}
