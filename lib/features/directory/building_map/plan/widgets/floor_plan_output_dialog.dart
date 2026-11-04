import 'package:flutter/material.dart';

import '../floor_plan_output.dart';

/// Ρωτά τι θα βγει: ολόκληρος ο όροφος ή ό,τι φαίνεται τώρα. Δείχνει και ποιες
/// στρώσεις λείπουν, για να μην εκπλαγεί κανείς από το αποτέλεσμα. Επιστρέφει
/// `null` στην ακύρωση.
Future<FloorPlanOutputScope?> showFloorPlanOutputDialog({
  required BuildContext context,
  required String title,
  required String confirmLabel,
  required List<String> hiddenLayerNames,
}) => showDialog<FloorPlanOutputScope>(
  context: context,
  builder: (_) => _FloorPlanOutputDialog(
    title: title,
    confirmLabel: confirmLabel,
    hiddenLayerNames: hiddenLayerNames,
  ),
);

class _FloorPlanOutputDialog extends StatefulWidget {
  const _FloorPlanOutputDialog({
    required this.title,
    required this.confirmLabel,
    required this.hiddenLayerNames,
  });

  final String title;
  final String confirmLabel;
  final List<String> hiddenLayerNames;

  @override
  State<_FloorPlanOutputDialog> createState() => _FloorPlanOutputDialogState();
}

class _FloorPlanOutputDialogState extends State<_FloorPlanOutputDialog> {
  FloorPlanOutputScope _scope = FloorPlanOutputScope.wholeFloor;

  @override
  Widget build(BuildContext context) {
    final names = widget.hiddenLayerNames;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RadioGroup<FloorPlanOutputScope>(
              groupValue: _scope,
              onChanged: (value) {
                if (value != null) setState(() => _scope = value);
              },
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<FloorPlanOutputScope>(
                    value: FloorPlanOutputScope.wholeFloor,
                    contentPadding: EdgeInsets.zero,
                    title: Text('Ολόκληρος ο όροφος'),
                  ),
                  RadioListTile<FloorPlanOutputScope>(
                    value: FloorPlanOutputScope.snapshot,
                    contentPadding: EdgeInsets.zero,
                    title: Text('Στιγμιότυπο: ό,τι φαίνεται τώρα'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              names.isEmpty
                  ? 'Φαίνονται όλες οι στρώσεις.'
                  : 'Κρυμμένες στρώσεις: ${names.join(', ')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Άκυρο'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_scope),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
