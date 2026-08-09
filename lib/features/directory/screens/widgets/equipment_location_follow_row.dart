import 'package:flutter/material.dart';

/// Διακόπτης «Ακολουθεί τη θέση του κατόχου».
///
/// Κάνει ρητή την πρόθεση: χωρίς αυτόν, η διαφορά ανάμεσα σε «είναι εκεί μαζί
/// με τον κάτοχο» και «είναι σκόπιμα αλλού» θα έπρεπε να μαντευτεί από ένα
/// κενό πεδίο. Η πορτοκαλί ένδειξη απόκλισης ζει στο helper του πεδίου
/// «Τοποθεσία», ώστε να αναδιπλώνεται μέσα στο πλάτος του.
class EquipmentLocationFollowRow extends StatelessWidget {
  const EquipmentLocationFollowRow({
    super.key,
    required this.followsOwner,
    required this.onChanged,
  });

  final bool followsOwner;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Transform.scale(
            scale: 0.85,
            child: Checkbox(
              value: followsOwner,
              onChanged: (v) => onChanged(v ?? false),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: InkWell(
              onTap: () => onChanged(!followsOwner),
              child: Text(
                'Ακολουθεί τη θέση του κατόχου',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
