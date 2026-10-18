import 'package:flutter/material.dart';

/// Διάλογος «Διαγραφή ορόφου». `true` μόνο με ρητό «Διαγραφή».
///
/// Η εικόνα της κάτοψης ζει στη βάση και φεύγει μαζί με τον όροφο — δεν
/// υπάρχει πια χωριστό αρχείο στον δίσκο να ρωτηθεί αν θα κρατηθεί.
Future<bool> showBuildingMapFloorDeleteDialog(BuildContext context) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Διαγραφή ορόφου'),
      content: const Text(
        'Να διαγραφεί ο όροφος μαζί με την κάτοψή του;\n\n'
        'Ο σχεδιασμός στο χάρτη για τα τμήματα που δένονται σε αυτόν τον όροφο '
        'θα χαθεί: η θέση και η περιοχή στο χάρτη θα μηδενιστούν.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Άκυρο'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Διαγραφή'),
        ),
      ],
    ),
  );
  return go ?? false;
}
