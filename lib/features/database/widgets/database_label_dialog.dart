import 'package:flutter/material.dart';

import '../services/database_label.dart';

/// Το αποτέλεσμα του διαλόγου ονόματος βάσης.
///
/// Τυλιγμένο σε αντικείμενο επίτηδες: σκέτο `String?` δεν θα ξεχώριζε το
/// «ακύρωσα» από το «θέλω να σβήσω το όνομα» — δύο εντελώς διαφορετικές
/// προθέσεις που θα κατέληγαν στην ίδια τιμή.
class DatabaseLabelResult {
  const DatabaseLabelResult(this.value);

  /// Το νέο όνομα· `null` σημαίνει «χωρίς όνομα».
  final String? value;
}

/// Ζητά από τον χρήστη όνομα για την τρέχουσα βάση.
///
/// Επιστρέφει `null` όταν ο χρήστης ακύρωσε — τότε δεν αποθηκεύεται τίποτα.
Future<DatabaseLabelResult?> showDatabaseLabelDialog({
  required BuildContext context,
  required String? currentLabel,
}) {
  final controller = TextEditingController(text: currentLabel ?? '');
  return showDialog<DatabaseLabelResult>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('Όνομα βάσης'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Το όνομα αποθηκεύεται μέσα στη βάση και ταξιδεύει μαζί της. '
              'Βοηθά να ξεχωρίζετε ποιο αρχείο κοιτάτε — π.χ. «Παραγωγή ΓΝΚ» '
              'ή «Δοκιμαστική σπιτιού».',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: kDatabaseLabelMaxLength,
              decoration: const InputDecoration(
                labelText: 'Όνομα',
                hintText: 'Παραγωγή ΓΝΚ',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (value) => Navigator.of(
                ctx,
              ).pop(DatabaseLabelResult(normalizeDatabaseLabel(value))),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Ακύρωση'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              ctx,
            ).pop(DatabaseLabelResult(normalizeDatabaseLabel(controller.text))),
            child: const Text('Αποθήκευση'),
          ),
        ],
      );
    },
  ).whenComplete(controller.dispose);
}
