import 'package:flutter/material.dart';

/// Διάλογος προειδοποίησης όταν το ονοματεπώνυμο ταιριάζει ήδη με εγγραφή στον κατάλογο
/// (πιθανή συνωνυμία — νέος υπάλληλος).
class HomonymWarningDialog extends StatelessWidget {
  const HomonymWarningDialog({
    super.key,
    required this.userDisplayName,
    required this.existingRecordDepartmentName,
  });

  /// Ονοματεπώνυμο όπως στη φόρμα αποθήκευσης (νέα/τρέχουσα εγγραφή).
  final String userDisplayName;

  /// Τμήμα της υπάρχουσας εγγραφής με ίδιο κανονικοποιημένο ονοματεπώνυμο.
  final String existingRecordDepartmentName;

  @override
  Widget build(BuildContext context) {
    final dept = existingRecordDepartmentName.trim().isEmpty
        ? '—'
        : existingRecordDepartmentName.trim();
    return AlertDialog(
      title: const Text('Ίδιο ονοματεπώνυμο'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Υπάρχει ήδη χρήστης «$userDisplayName» στο τμήμα «$dept».',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            Text(
              'Πρόκειται για συνωνυμία (νέος υπάλληλος με το ίδιο όνομα) ή θέλετε να ακυρώσετε και να διορθώσετε την υπάρχουσα εγγραφή;',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Ακύρωση'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Συνέχεια ως Συνωνυμία'),
        ),
      ],
    );
  }
}
