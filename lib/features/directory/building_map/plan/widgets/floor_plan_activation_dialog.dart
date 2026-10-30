import 'package:flutter/material.dart';

import '../../../../../core/models/floor_plan_element.dart';
import '../../../models/department_model.dart';

/// Τα τμήματα που ο Κατάλογος βάζει στον όροφο [floorId] αλλά δεν έχουν
/// ακόμη χώρο στον νέο χάρτη του — θα έλειπαν μετά την ενεργοποίηση.
List<DepartmentModel> departmentsMissingFromFloorPlan({
  required int floorId,
  required Iterable<DepartmentModel> departments,
  required Iterable<FloorPlanElement> elements,
}) {
  final drawn = {
    for (final e in elements)
      if (e.kind == FloorPlanElementKind.room) e.departmentId,
  };
  return [
    for (final d in departments)
      if (d.floorId == floorId && !drawn.contains(d.id)) d,
  ];
}

/// Επιβεβαίωση της «Ενεργοποίησης νέου χάρτη». `true` μόνο με ρητό «ναι».
Future<bool> confirmFloorPlanActivation(
  BuildContext context, {
  required String floorLabel,
  required List<DepartmentModel> missing,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return AlertDialog(
        title: Text('Ενεργοποίηση νέου χάρτη — $floorLabel'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Από τη στιγμή της ενεργοποίησης όλοι οι σταθμοί βλέπουν τον '
                'νέο χάρτη, και στον μικρό χάρτη των κλήσεων.',
              ),
              const SizedBox(height: 12),
              Text(
                'Τα κουτάκια των τμημάτων και η εικόνα κάτοψης του ορόφου '
                'σβήνονται οριστικά. Το πατρόν μένει στη σχεδίαση.',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              const SizedBox(height: 16),
              if (missing.isEmpty)
                const Text('Όλα τα τμήματα του ορόφου έχουν χώρο.')
              else ...[
                Text(
                  'Χωρίς χώρο ακόμη — θα έλειπαν από τον νέο χάρτη '
                  '(${missing.length}):',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final d in missing)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text('• ${d.name}'),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Άκυρο'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ενεργοποίηση'),
          ),
        ],
      );
    },
  );
  return ok == true;
}
