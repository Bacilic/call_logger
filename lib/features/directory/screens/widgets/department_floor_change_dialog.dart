import 'package:flutter/material.dart';

/// Τι διάλεξε ο χρήστης για τη σχεδίαση τμήματος που αλλάζει όροφο.
enum DepartmentFloorChangeChoice {
  /// Η σχεδίαση ταξιδεύει αυτούσια στη νέα κάτοψη.
  movePlacement,

  /// Η σχεδίαση σβήνεται — το τμήμα μένει στον νέο όροφο ασχεδίαστο.
  clearPlacement,
}

/// «Αλλαγή ορόφου»: το τμήμα είναι σχεδιασμένο και ο χρήστης το μετακινεί σε
/// άλλη κάτοψη. Επιστρέφει `null` σε ακύρωση/κλείσιμο.
Future<DepartmentFloorChangeChoice?> showDepartmentFloorChangeDialog(
  BuildContext context, {
  required String departmentName,
  required String fromFloorLabel,
  required String toFloorLabel,
}) {
  return showDialog<DepartmentFloorChangeChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Το τμήμα είναι σχεδιασμένο στον χάρτη'),
      content: Text(
        'Το τμήμα «$departmentName» είναι σχεδιασμένο στην κάτοψη του ορόφου '
        '«$fromFloorLabel» και το μεταφέρεις στον όροφο «$toFloorLabel».\n\n'
        'Αν μεταφερθεί και η σχεδίαση, θα πάρει τις ίδιες ακριβώς διαστάσεις '
        'και θέση στη νέα κάτοψη — που μπορεί να μην ταιριάζουν εκεί. Αν '
        'διαγραφεί, το τμήμα μένει στον νέο όροφο χωρίς σχέδιο, έτοιμο να το '
        'σχεδιάσεις από τον χάρτη.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Άκυρο'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(ctx, DepartmentFloorChangeChoice.movePlacement),
          child: const Text('Μεταφορά σχεδίασης'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(ctx, DepartmentFloorChangeChoice.clearPlacement),
          child: const Text('Διαγραφή σχεδίασης'),
        ),
      ],
    ),
  );
}
