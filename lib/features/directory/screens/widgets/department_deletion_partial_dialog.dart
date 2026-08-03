import 'package:flutter/material.dart';

import 'bulk_deletion_partial_dialog.dart';

/// Μήνυμα διεξόδου όταν ο χρήστης ακυρώνει στη μέση της σειριακής συλλογής.
///
/// Καθαρή λογική — χωρίς widgets, ώστε οι ενικοί/πληθυντικοί να δοκιμάζονται
/// χωρίς δέντρο.
String departmentDeletionPartialQuestion({
  required int completed,
  required int total,
}) {
  final done = completed == 1
      ? 'Ολοκληρώσατε 1 τμήμα από τα $total'
      : 'Ολοκληρώσατε $completed τμήματα από τα $total';
  final apply = completed == 1
      ? 'Να διαγραφεί αυτό που ολοκληρώθηκε;'
      : 'Να διαγραφούν αυτά που ολοκληρώθηκαν;';
  return '$done. $apply';
}

/// Τι έχει ολοκληρωθεί μέχρι στιγμής — πρώτη γραμμή του διαλόγου διακοπής.
String departmentDeletionCompletedSummary({
  required int completed,
  required int total,
}) {
  return completed == 1
      ? 'Ολοκληρώσατε 1 τμήμα από τα $total.'
      : 'Ολοκληρώσατε $completed τμήματα από τα $total.';
}

/// Υπόδειξη του κουμπιού «Εφαρμογή απαντήσεων» — αυτοτελής πρόταση.
String departmentDeletionApplyCompletedHint(int completed) {
  return completed == 1
      ? 'Κλείνει ο οδηγός και διαγράφεται το 1 τμήμα που ολοκληρώσατε. Τα '
            'υπόλοιπα μένουν ανέγγιχτα και επιλεγμένα.'
      : 'Κλείνει ο οδηγός και διαγράφονται τα $completed τμήματα που '
            'ολοκληρώσατε. Τα υπόλοιπα μένουν ανέγγιχτα και επιλεγμένα.';
}

/// Η διέξοδος για τα τμήματα — ο διάλογος είναι ο κοινός.
Future<BulkDeletionPartialChoice?> showDepartmentDeletionPartialDialog({
  required BuildContext context,
  required int completed,
  required int total,
}) {
  return showBulkDeletionPartialDialog(
    context: context,
    question: departmentDeletionPartialQuestion(
      completed: completed,
      total: total,
    ),
  );
}
