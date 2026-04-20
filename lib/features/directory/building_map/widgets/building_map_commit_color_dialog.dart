import 'package:flutter/material.dart';

import '../../screens/widgets/department_color_palette.dart';

/// Ερώτηση πριν την αποθήκευση χαρτογράφησης: κατάλογος χρώμα vs προτεινόμενο διαφοροποίησης.
///
/// Επιστρέφει `true` αν επιλεγεί αλλαγή στο προτεινόμενο, `false` αν κρατηθεί το υπάρχον,
/// `null` αν κλείσει ο διάλογος χωρίς επιλογή (ακύρωση commit).
Future<bool?> showBuildingMapCommitColorDialog(
  BuildContext context, {
  required String departmentName,
  required Color currentColor,
  required Color suggestedColor,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('Χρώμα τμήματος στο χάρτη'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Το τμήμα «$departmentName» έχει προεπιλεγμένο χρώμα:',
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              const SizedBox(height: 10),
              _ColorRow(color: currentColor, hexLabel: colorToDepartmentHex(currentColor)),
              const SizedBox(height: 18),
              Text(
                'Θέλετε να αλλάξει σε (για διαφοροποίηση από τα άλλα);',
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              const SizedBox(height: 10),
              _ColorRow(
                color: suggestedColor,
                hexLabel: colorToDepartmentHex(suggestedColor),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Όχι — κράτα το τρέχον'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ναι — χρήση προτεινόμενου'),
          ),
        ],
      );
    },
  );
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({required this.color, required this.hexLabel});

  final Color color;
  final String hexLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black26),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            hexLabel,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
      ],
    );
  }
}
