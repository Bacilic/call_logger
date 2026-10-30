import 'package:flutter/material.dart';

import '../floor_plan_geometry.dart';

/// Ρωτά το πραγματικό μήκος (σε μέτρα) της γραμμής βαθμονόμησης· επιστρέφει
/// εκατοστά, ή `null` σε ακύρωση.
Future<double?> showFloorPlanCalibrationDialog(
  BuildContext context, {
  required bool hasWalls,
}) async {
  final controllerText = TextEditingController();
  try {
    return await showDialog<double>(
      context: context,
      builder: (ctx) {
        void submit() {
          final cm = parseMetersToCm(controllerText.text);
          if (cm != null) Navigator.pop(ctx, cm);
        }

        return AlertDialog(
          title: const Text('Βαθμονόμηση κλίμακας'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Πόσο είναι στην πραγματικότητα η γραμμή που σύρατε;'),
              const SizedBox(height: 12),
              TextField(
                controller: controllerText,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Πραγματικό μήκος',
                  suffixText: 'μέτρα',
                  hintText: 'π.χ. 4,20',
                ),
                onSubmitted: (_) => submit(),
              ),
              if (hasWalls) ...[
                const SizedBox(height: 12),
                Text(
                  'Οι τοίχοι που έχετε ήδη σχεδιάσει δεν αλλάζουν μέγεθος — '
                  'αλλάζει μόνο η εικόνα του πατρόν.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Άκυρο'),
            ),
            FilledButton(onPressed: submit, child: const Text('Εφαρμογή')),
          ],
        );
      },
    );
  } finally {
    controllerText.dispose();
  }
}
