import 'dart:async';

import 'package:flutter/material.dart';

import '../database/database_init_result.dart';

/// Τρέχει μια αποθήκευση ρύθμισης **χωρίς να μπλοκάρει τη διεπαφή** και **χωρίς
/// να καταπίνει την αποτυχία**.
///
/// Οι ρυθμίσεις σώζονται τη στιγμή που αλλάζει ο διακόπτης, οπότε η οθόνη δεν
/// επιτρέπεται να παγώσει όσο γράφει η δικτυακή βάση. Το σκέτο `unawaited`
/// όμως πετούσε την αποτυχία στο κενό: η ρύθμιση δεν γραφόταν, κανένα μήνυμα
/// δεν εμφανιζόταν, και η οθόνη συνέχιζε να δείχνει τη νέα τιμή σαν να
/// αποθηκεύτηκε — ώσπου η επόμενη εκκίνηση επανέφερε την παλιά.
///
/// Χρησιμοποίησέ την **αντί για `unawaited`** σε κάθε εγγραφή ρύθμισης.
void persistSettingInBackground(BuildContext context, Future<void> write) {
  unawaited(
    write.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        // Η εγγραφή τελειώνει μετά από await: η οθόνη μπορεί να έχει κλείσει
        // στο μεταξύ, οπότε δεν υπάρχει κανείς να ακούσει.
        if (!context.mounted) return;
        showDatabasePersistenceErrorSnackBar(context, error, stackTrace);
      },
    ),
  );
}

/// SnackBar + προαιρετικός διάλογος αναφοράς για αποτυχία εγγραφής/ανάγνωσης SQLite.
void showDatabasePersistenceErrorSnackBar(
  BuildContext context,
  Object error,
  StackTrace stackTrace,
) {
  final result = DatabaseInitResult.fromException(error, null, stackTrace);
  final scheme = Theme.of(context).colorScheme;
  // Ο navigator κρατιέται ΤΩΡΑ: το «Αναφορά» πατιέται δευτερόλεπτα αργότερα,
  // όταν ο διάλογος που προκάλεσε το σφάλμα έχει συνήθως ήδη κλείσει και ο
  // [context] του είναι νεκρός.
  final navigator = Navigator.maybeOf(context, rootNavigator: true);
  final summary = (result.message ?? 'Αποτυχία εγγραφής στη βάση δεδομένων.')
      .trim();
  final details = result.details?.trim();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            summary,
            style: TextStyle(
              color: scheme.onError,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (details != null && details.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              details,
              style: TextStyle(
                color: scheme.onError.withValues(alpha: 0.92),
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
      backgroundColor: scheme.error,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 12),
      // Ρητή δήλωση: από το Flutter 3.47 κάθε μήνυμα με κουμπί ενέργειας
      // βαφτίζεται αυτόματα «μόνιμο» και δεν φεύγει ποτέ μόνο του — μπλοκάροντας
      // και την ουρά των επόμενων μηνυμάτων. Δεν αφήνουμε σιωπηλή προεπιλογή
      // του framework να αποφασίζει για τη διεπαφή μας.
      persist: false,
      showCloseIcon: true,
      closeIconColor: scheme.onError,
      action: SnackBarAction(
        textColor: scheme.onError,
        label: 'Αναφορά',
        onPressed: () {
          if (navigator == null || !navigator.mounted) return;
          showDialog<void>(
            context: navigator.context,
            builder: (ctx) => AlertDialog(
              title: const Text('Λεπτομέρειες σφάλματος'),
              content: SingleChildScrollView(
                child: SelectableText(
                  result.buildClipboardReport(),
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Κλείσιμο'),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}
