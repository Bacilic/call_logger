import 'package:flutter/material.dart';

import 'floor_plan_text_editor.dart';

/// Το ύψος της μπάρας, για να μπει ακριβώς πάνω από το όνομα.
const double kFloorPlanRoomLabelBarHeight = 40;

/// Η μικρή μπάρα πάνω από το όνομα ενός επιλεγμένου χώρου: A− / μέγεθος /
/// A+, όπως στο ελεύθερο κείμενο, και επιστροφή του ονόματος στο κέντρο.
///
/// Κάθε πάτημα γράφεται αμέσως, ως μία κίνηση αναίρεσης.
class FloorPlanRoomLabelBar extends StatelessWidget {
  const FloorPlanRoomLabelBar({
    super.key,
    required this.sizeCm,
    required this.onSize,
    required this.onCenter,
  });

  final double sizeCm;
  final ValueChanged<double> onSize;

  /// `null` όταν το όνομα είναι ήδη στο κέντρο.
  final VoidCallback? onCenter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: kFloorPlanRoomLabelBarHeight,
      child: Material(
        elevation: 3,
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.surface,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Μικρότερο όνομα χώρου',
              onPressed: sizeCm > kFloorPlanTextSizeMinCm
                  ? () => onSize(stepFloorPlanTextSize(sizeCm, increase: false))
                  : null,
              icon: const Text('A−', style: TextStyle(fontSize: 14)),
            ),
            SizedBox(
              width: 52,
              child: Text(
                '${sizeCm.round()} εκ.',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium,
              ),
            ),
            IconButton(
              tooltip: 'Μεγαλύτερο όνομα χώρου',
              onPressed: sizeCm < kFloorPlanTextSizeMaxCm
                  ? () => onSize(stepFloorPlanTextSize(sizeCm, increase: true))
                  : null,
              icon: const Text('A+', style: TextStyle(fontSize: 17)),
            ),
            const SizedBox(height: 24, child: VerticalDivider(width: 9)),
            IconButton(
              tooltip: 'Το όνομα πίσω στο κέντρο του χώρου',
              onPressed: onCenter,
              icon: const Icon(Icons.filter_center_focus),
            ),
          ],
        ),
      ),
    );
  }
}
