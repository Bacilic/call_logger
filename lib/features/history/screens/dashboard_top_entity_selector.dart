import 'package:flutter/material.dart';

/// Οι τρεις όψεις της κάρτας «Κορυφαίο …» του Πίνακα Ελέγχου.
enum TopEntityMode { department, caller, issue }

/// Επιλογέας όψης, πάνω στην ίδια την κάρτα.
///
/// Αντικατέστησε το φύλλο που ανέβαινε από τον πάτο της οθόνης: εκεί χρειάζονταν
/// δύο κλικ, ο πάτος ήταν μακριά από το ποντίκι και τίποτα δεν πρόδιδε ότι η
/// κάρτα κρύβει άλλες δύο όψεις. Τα τρία εικονίδια είναι μόνιμα ορατά και κάθε
/// όψη απέχει ένα κλικ — το ίδιο μοτίβο με την κάρτα χρόνου και την Κατανομή
/// Βλαβών. Τα πλήρη ονόματα δίνονται ως υποδείξεις, αφού ο τίτλος της κάρτας
/// ανακοινώνει ούτως ή άλλως την ενεργή όψη.
class TopEntityModeSelector extends StatelessWidget {
  const TopEntityModeSelector({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  final TopEntityMode mode;
  final ValueChanged<TopEntityMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<TopEntityMode>(
      segments: const [
        ButtonSegment(
          value: TopEntityMode.department,
          icon: Icon(Icons.apartment_outlined, size: 17),
          tooltip: 'Κορυφαίο Τμήμα',
        ),
        ButtonSegment(
          value: TopEntityMode.caller,
          icon: Icon(Icons.person_outline_rounded, size: 17),
          tooltip: 'Κορυφαίος Καλών',
        ),
        ButtonSegment(
          value: TopEntityMode.issue,
          icon: Icon(Icons.build_outlined, size: 17),
          tooltip: 'Κορυφαία Κατηγορία',
        ),
      ],
      selected: {mode},
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
        minimumSize: WidgetStatePropertyAll(Size(0, 30)),
      ),
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}
