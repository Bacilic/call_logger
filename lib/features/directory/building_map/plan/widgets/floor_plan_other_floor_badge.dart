import 'package:flutter/material.dart';

import '../floor_plan_item_info.dart';

/// Τα σήματα «↑ RC6 · 1ος» μιας διαδρομής προς άλλον όροφο, πάνω από τον χάρτη:
/// δίπλα στη σκάλα ή στον αγωγό, ή δίπλα στην πρίζα αν δεν έχει σχεδιαστεί.
///
/// Με [onOpen] το κλικ πηγαίνει στον όροφο της καμπίνας.
List<Widget> floorPlanOtherFloorBadges({
  required List<FloorPlanOtherFloorTarget> targets,
  required Offset? anchor,
  required Size bounds,
  void Function(FloorPlanOtherFloorTarget target)? onOpen,
}) {
  if (anchor == null) return const [];
  const width = 200.0;
  return [
    for (final (i, target) in targets.indexed)
      Positioned(
        left: (anchor.dx + 18).clamp(
          0.0,
          (bounds.width - width).clamp(0.0, double.infinity),
        ),
        top: (anchor.dy - 16 - i * 36).clamp(
          0.0,
          (bounds.height - 36).clamp(0.0, double.infinity),
        ),
        // Χωρίς [onOpen] σκέτο σήμα: ένα ανενεργό κουμπί θα ήταν αχνό, και το
        // σήμα πρέπει να διαβάζεται.
        child: onOpen == null
            ? Chip(
                avatar: const Icon(Icons.stairs_outlined, size: 18),
                label: Text(target.badge),
              )
            : ActionChip(
                avatar: const Icon(Icons.stairs_outlined, size: 18),
                label: Text(target.badge),
                onPressed: () => onOpen(target),
              ),
      ),
  ];
}
