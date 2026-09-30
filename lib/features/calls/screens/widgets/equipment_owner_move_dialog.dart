import 'package:flutter/material.dart';

/// Ρωτά αν ο εξοπλισμός που ανήκει σε υπάλληλο άλλου τμήματος θα μεταφερθεί
/// στον καλούντα.
///
/// `true` μόνο με ρητό «Ναι, μεταφορά». «Όχι», κλικ έξω και Esc επιστρέφουν
/// `false`/`null` — και ο καλών ακυρώνει ολόκληρη την καταχώρηση: τίποτα δεν
/// αλλάζει χωρίς ρητή απάντηση.
Future<bool?> showEquipmentOwnerMoveDialog({
  required BuildContext context,
  required String equipmentCode,
  required List<String> currentOwnerLabels,
  required String newOwnerName,
}) {
  final owners = currentOwnerLabels.join(', ');
  final who = newOwnerName.trim().isEmpty ? 'τον καλούντα' : newOwnerName;
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Εξοπλισμός άλλου τμήματος'),
      content: Text(
        'Ο εξοπλισμός $equipmentCode ανήκει σε: $owners.\n'
        'Να μεταφερθεί σε $who; Θα αφαιρεθεί από τον σημερινό κάτοχο.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Όχι'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Ναι, μεταφορά'),
        ),
      ],
    ),
  );
}
