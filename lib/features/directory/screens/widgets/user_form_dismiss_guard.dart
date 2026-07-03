part of 'user_form_dialog.dart';

enum _UserFormDismissChoice { keep, discard, continueEditing }

mixin UserFormDismissGuardMixin on UserFormDialogStateHost {
  @override
  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  bool get _isDirty {
    if (_lastNameController.text.trim() != _snapLastName) return true;
    if (_firstNameController.text.trim() != _snapFirstName) return true;
    if (_phoneController.text.trim() != _snapPhone) return true;
    if (_notesController.text.trim() != _snapNotes) return true;
    // Εμφανιζόμενο κείμενο (όχι μόνο κανονικοποίηση): τόνοι/κεφαλαία μετράνε ως αλλαγή.
    if (_departmentController.text.trim() != _initialDepartmentText) return true;
    return false;
  }

  /// Νέος/αντίγραφο χρήστη: υποχρεωτικά όνομα και επώνυμο πριν εμφανιστεί προειδοποίηση.
  bool get _createHasRequiredFields =>
      _lastNameController.text.trim().isNotEmpty &&
      _firstNameController.text.trim().isNotEmpty;

  bool get _shouldConfirmDismiss =>
      _isEdit ? _isDirty : _createHasRequiredFields;

  List<String> _changedFieldLabels() {
    final changes = <String>[];
    if (_lastNameController.text.trim() != _snapLastName) {
      changes.add('Επώνυμο');
    }
    if (_firstNameController.text.trim() != _snapFirstName) {
      changes.add('Όνομα');
    }
    if (_phoneController.text.trim() != _snapPhone) {
      changes.add('Τηλέφωνο');
    }
    if (_departmentController.text.trim() != _initialDepartmentText) {
      changes.add('Τμήμα');
    }
    if (_notesController.text.trim() != _snapNotes) {
      changes.add('Σημειώσεις');
    }
    return changes;
  }

  Future<_UserFormDismissChoice?> _showDismissConfirmationDialog() async {
    final changes = _changedFieldLabels();
    return showDialog<_UserFormDismissChoice>(
      context: context,
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
            onPressed: () => Navigator.of(
              ctx,
            ).pop(_UserFormDismissChoice.continueEditing),
            child: const Text('Επεξεργασία'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_UserFormDismissChoice.discard),
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

  Future<void> _requestClose() async {
    if (!_shouldConfirmDismiss) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final choice = await _showDismissConfirmationDialog();
    if (!mounted ||
        choice == null ||
        choice == _UserFormDismissChoice.continueEditing) {
      return;
    }
    if (choice == _UserFormDismissChoice.discard) {
      Navigator.of(context).pop();
      return;
    }
    await _save();
  }

  /// Κουμπί «Ακύρωση»: κλείσιμο χωρίς διάλογο επιβεβαίωσης (εκούσια απόρριψη).
  void _cancelAndClose() {
    if (mounted) Navigator.of(context).pop();
  }
}
