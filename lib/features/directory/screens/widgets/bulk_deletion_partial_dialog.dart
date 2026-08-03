import 'package:flutter/material.dart';

import '../../../../core/widgets/draggable_dialog_shell.dart';

/// Τι κάνουμε με τη μισοτελειωμένη σειρά διαγραφών.
enum BulkDeletionPartialChoice {
  /// Εφαρμογή όσων ολοκληρώθηκαν· τα υπόλοιπα μένουν ανέγγιχτα.
  applyCompleted,

  /// Τίποτα δεν γράφεται — όλες οι απαντήσεις πετιούνται.
  discardAll,
}

/// Ρωτά αν σώζονται οι απαντήσεις που δόθηκαν πριν την ακύρωση.
///
/// Χωρίς αυτό, η ακύρωση στο 21ο βήμα πετούσε και τις 20 προηγούμενες
/// απαντήσεις του χρήστη.
///
/// Η [question] έρχεται έτοιμη από τον καλούντα: η ελληνική γραμματική
/// διαφέρει ανά οντότητα («1 τμήμα από τα 30» / «1 υπάλληλο από τους 30»),
/// οπότε το κείμενο μένει δίπλα στην οντότητα και εδώ μένει μόνο ο διάλογος.
Future<BulkDeletionPartialChoice?> showBulkDeletionPartialDialog({
  required BuildContext context,
  required String question,
}) {
  return showDialog<BulkDeletionPartialChoice>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => DraggableDialogShell(
      title: const Text('Διακοπή στη μέση'),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
        content: SizedBox(width: 420, child: Text(question)),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(BulkDeletionPartialChoice.discardAll),
            child: const Text('Ακύρωση όλων'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(BulkDeletionPartialChoice.applyCompleted),
            child: const Text('Διαγραφή όσων ολοκληρώθηκαν'),
          ),
        ],
      ),
    ),
  );
}
