import 'package:flutter/material.dart';

import '../../../../core/errors/department_exists_exception.dart';
import '../../../../core/services/lookup_service.dart';
import '../../../../core/services/save_confirmation_summary.dart';
import '../../../../core/widgets/database_persistence_error_snackbar.dart';
import 'department_form_dialog.dart';

/// Τι κάνει η αποθήκευση όταν το όνομα **υπάρχει ήδη**.
///
/// Δύο εντελώς διαφορετικές καταστάσεις πίσω από την ίδια εξαίρεση:
///
/// 1. **Διαγραμμένη καρτέλα** — προσφέρεται επαναφορά. Η παλιά εγγραφή ξυπνά
///    αντί να φτιαχτεί δεύτερη, ώστε να μη χαθεί ό,τι κρέμεται πάνω της.
/// 2. **Ζωντανή καρτέλα** — ο χρήστης ειδοποιείται και η φόρμα **μένει
///    ανοιχτή**: το λάθος διορθώνεται με μία λέξη, και ένα κλείσιμο εδώ θα
///    πετούσε ό,τι πληκτρολόγησε.
///
/// Ζει χωριστά από τη ροή αποθήκευσης γιατί απαντά σε δικό του ερώτημα και δεν
/// μοιράζεται τίποτα μαζί της παρά τα πεδία της φόρμας.
Future<void> handleDepartmentNameConflict(
  DepartmentFormDialogState host,
  DepartmentExistsException e, {
  required String name,
  required String building,
  required String color,
  required String notes,
}) async {
  if (!host.mounted) return;
  if (e.isDeleted) {
    await _offerRestore(
      host,
      e,
      name: name,
      building: building,
      color: color,
      notes: notes,
    );
    return;
  }
  await _reportNameInUse(host, name: name);
}

Future<void> _offerRestore(
  DepartmentFormDialogState host,
  DepartmentExistsException e, {
  required String name,
  required String building,
  required String color,
  required String notes,
}) async {
  final restore = await showDialog<bool>(
    context: host.context,
    builder: (ctx) => AlertDialog(
      title: Text(e.kind.deletedEntityTitle),
      content: const Text(
        'Υπάρχει ήδη καταχώρηση με αυτό το όνομα, σημειωμένη ως διαγραμμένη. '
        'Θέλετε να την επαναφέρετε;\n\n'
        'Τα πεδία κτίριο, χρώμα και σημειώσεις από τη φόρμα θα εφαρμοστούν μετά την επαναφορά. '
        'Αν δεν πρόκειται για το ίδιο τμήμα, πατήστε «Άκυρο» και δώστε νέο, διακριτό όνομα (π.χ. «Μαγειρείο 2026»).',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Άκυρο'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Επαναφορά'),
        ),
      ],
    ),
  );
  if (!host.mounted || restore != true) return;

  try {
    final restoredId = await host.widget.notifier.restoreDepartmentByName(
      name,
      building: building.isEmpty ? null : building,
      color: color,
      notes: notes.isEmpty ? null : notes,
    );
    if (!host.mounted) return;
    host.widget.onSaved?.call();
    host.closeForm(true);
    // Το Είδος είναι εκείνο της ΕΠΑΝΑΦΕΡΜΕΝΗΣ καρτέλας, όχι της επιλογής στη
    // φόρμα: η διαγραμμένη κρατά το δικό της.
    final restoredKind = LookupService.instance.departmentKindById(restoredId);
    final message = 'Επαναφέρθηκε ${restoredKind.entityWithArticle} «$name»';
    ScaffoldMessenger.of(host.context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: saveConfirmationSnackBarDuration(message),
      ),
    );
  } catch (err, st) {
    if (!host.mounted) return;
    showDatabasePersistenceErrorSnackBar(host.context, err, st);
  }
}

Future<void> _reportNameInUse(
  DepartmentFormDialogState host, {
  required String name,
}) async {
  await showDialog<void>(
    context: host.context,
    builder: (ctx) {
      final example = suggestDistinctDepartmentNameExample(name);
      final bodyStyle = Theme.of(ctx).textTheme.bodyMedium;
      return AlertDialog(
        title: const Text('Όνομα σε χρήση'),
        content: Text.rich(
          TextSpan(
            style: bodyStyle,
            children: [
              const TextSpan(text: 'Υπάρχει ήδη τμήμα με το όνομα '),
              TextSpan(
                text: name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const TextSpan(text: '. Δώστε νέο διακριτικό όνομα (π.χ. '),
              TextSpan(text: '«$example»'),
              const TextSpan(text: ').'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}
