import 'package:flutter/material.dart';

import 'user_form_dialog.dart';

enum _UserFormDismissChoice { keep, discard, continueEditing }

/// Φρουρός κλεισίματος της φόρμας υπαλλήλου: dirty έλεγχος + διάλογος
/// «Μη αποθηκευμένες αλλαγές».
///
/// Συνεργάτης του [UserFormDialogState] (Σύνθεση) — δουλεύει πάνω στα πεδία
/// της φόρμας μέσω του host, χωρίς δική του κατάσταση.
class UserFormDismissGuard {
  UserFormDismissGuard(this.host);

  final UserFormDialogState host;

  bool get isDirty {
    if (host.lastNameController.text.trim() != host.snapLastName) return true;
    if (host.firstNameController.text.trim() != host.snapFirstName) {
      return true;
    }
    if (host.phoneController.text.trim() != host.snapPhone) return true;
    if (host.notesController.text.trim() != host.snapNotes) return true;
    // Εμφανιζόμενο κείμενο (όχι μόνο κανονικοποίηση): τόνοι/κεφαλαία μετράνε ως αλλαγή.
    if (host.departmentController.text.trim() != host.initialDepartmentText) {
      return true;
    }
    return false;
  }

  /// Νέος/αντίγραφο χρήστη: υποχρεωτικά όνομα και επώνυμο πριν εμφανιστεί προειδοποίηση.
  bool get _createHasRequiredFields =>
      host.lastNameController.text.trim().isNotEmpty &&
      host.firstNameController.text.trim().isNotEmpty;

  bool get _shouldConfirmDismiss =>
      host.isEdit ? isDirty : _createHasRequiredFields;

  List<String> _changedFieldLabels() {
    final changes = <String>[];
    if (host.lastNameController.text.trim() != host.snapLastName) {
      changes.add('Επώνυμο');
    }
    if (host.firstNameController.text.trim() != host.snapFirstName) {
      changes.add('Όνομα');
    }
    if (host.phoneController.text.trim() != host.snapPhone) {
      changes.add('Τηλέφωνο');
    }
    if (host.departmentController.text.trim() != host.initialDepartmentText) {
      changes.add('Τμήμα');
    }
    if (host.notesController.text.trim() != host.snapNotes) {
      changes.add('Σημειώσεις');
    }
    return changes;
  }

  Future<_UserFormDismissChoice?> _showDismissConfirmationDialog() async {
    final changes = _changedFieldLabels();
    return showDialog<_UserFormDismissChoice>(
      context: host.context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Μη αποθηκευμένες αλλαγές'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Έχουν γίνει αλλαγές:'),
                const SizedBox(height: 8),
                for (final label in changes) Text('• $label'),
                const SizedBox(height: 12),
                const Text('Θέλεται να γίνει:'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(_UserFormDismissChoice.continueEditing),
            child: const Text('Επεξεργασία'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(_UserFormDismissChoice.discard),
            child: const Text('Ακύρωση Αλλαγών'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(_UserFormDismissChoice.keep),
            child: const Text('Διατήρηση'),
          ),
        ],
      ),
    );
  }

  Future<void> requestClose() async {
    if (!_shouldConfirmDismiss) {
      if (host.mounted) Navigator.of(host.context).pop();
      return;
    }
    final choice = await _showDismissConfirmationDialog();
    if (!host.mounted ||
        choice == null ||
        choice == _UserFormDismissChoice.continueEditing) {
      return;
    }
    if (choice == _UserFormDismissChoice.discard) {
      Navigator.of(host.context).pop();
      return;
    }
    await host.saveFlow.save();
  }

  /// Κουμπί «Ακύρωση»: κλείσιμο χωρίς διάλογο επιβεβαίωσης (εκούσια απόρριψη).
  void cancelAndClose() {
    if (host.mounted) Navigator.of(host.context).pop();
  }
}
