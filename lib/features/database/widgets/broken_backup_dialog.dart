import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// Ο διάλογος που εμφανίζεται όταν ένα αντίγραφο γράφτηκε αλλά δεν άνοιξε.
///
/// **Γιατί ερώτηση και όχι αυτόματη διαγραφή:** το χαλασμένο αρχείο έχει ήδη
/// σημαδευτεί στο όνομά του, άρα δεν κινδυνεύει να περάσει για υγιές. Το αν
/// θα μείνει για εξέταση ή θα φύγει από τη μέση είναι απόφαση του χειριστή —
/// και μόνο εδώ υπάρχει κάποιος να τη ρωτηθεί. Στο κλείσιμο της εφαρμογής η
/// ίδια κατάληξη σταματά στη μετονομασία, σιωπηλά.
Future<void> showBrokenBackupDialog({
  required BuildContext context,
  required String brokenFilePath,
  required String reason,
}) async {
  // Κρατιέται πριν από κάθε αναμονή: μετά το κλείσιμο του διαλόγου ο ίδιος
  // BuildContext μπορεί να μην ανήκει πια σε ζωντανό widget.
  final messenger = ScaffoldMessenger.maybeOf(context);

  final shouldDelete = await showDialog<bool>(
    context: context,
    // Απόφαση για αρχείο που υπάρχει στον δίσκο: το κλείσιμο με κλικ στο κενό
    // θα την άφηνε αναπάντητη χωρίς ο χρήστης να το καταλάβει.
    barrierDismissible: false,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        icon: Icon(
          Icons.report_gmailerrorred_outlined,
          color: theme.colorScheme.error,
        ),
        title: const Text('Το αντίγραφο δεν πέρασε τον έλεγχο'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(reason),
            const SizedBox(height: 12),
            Text(
              'Το αρχείο μετονομάστηκε ώστε να μην μπερδευτεί με υγιές '
              'αντίγραφο:',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              p.basename(brokenFilePath),
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontFamilyFallback: const ['Consolas', 'monospace'],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Να μείνει'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Διαγραφή'),
          ),
        ],
      );
    },
  );

  if (shouldDelete != true) return;

  try {
    await File(brokenFilePath).delete();
    messenger?.showSnackBar(
      const SnackBar(content: Text('Το χαλασμένο αντίγραφο διαγράφηκε.')),
    );
  } catch (e) {
    messenger?.showSnackBar(
      SnackBar(content: Text('Η διαγραφή δεν έγινε: $e')),
    );
  }
}
