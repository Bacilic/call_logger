import 'package:flutter/material.dart';

import '../models/owner_filter.dart';

/// Το φίλτρο «ποιανού εγγραφές» — μενού πάνω σε chip.
///
/// Ίδια εμφάνιση παντού (Εκκρεμότητες, Ιστορικό Κλήσεων, αναφορά Lansweeper):
/// τρία σημεία που κάνουν το ίδιο πράγμα δεν επιτρέπεται να δείχνουν
/// διαφορετικά, αλλιώς ο χρήστης μαθαίνει τρεις φορές το ίδιο μάθημα.
///
/// Όσο δεν έχουν φορτώσει οι [options], το chip δείχνει την τρέχουσα τιμή
/// αλλά δεν ανοίγει: μενού με μία μόνο επιλογή μοιάζει με σφάλμα.
class OwnerFilterChip extends StatelessWidget {
  const OwnerFilterChip({
    super.key,
    required this.options,
    required this.current,
    required this.onSelected,
    this.tooltip = 'Ποιανού εγγραφές',
    this.enabled = true,
  });

  final List<OwnerFilterOption> options;
  final OwnerFilter current;
  final ValueChanged<OwnerFilter> onSelected;
  final String tooltip;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    var label = 'Όλοι';
    for (final option in options) {
      if (option.value == current) {
        label = option.label;
        break;
      }
    }

    final chip = Chip(
      avatar: Icon(
        current.isEveryone ? Icons.groups_outlined : Icons.person_outline,
        size: 18,
      ),
      label: Text(label),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );

    if (!enabled || options.isEmpty) return chip;

    return PopupMenuButton<OwnerFilter>(
      tooltip: tooltip,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final option in options)
          PopupMenuItem<OwnerFilter>(
            value: option.value,
            child: Text(option.label),
          ),
      ],
      child: chip,
    );
  }
}
