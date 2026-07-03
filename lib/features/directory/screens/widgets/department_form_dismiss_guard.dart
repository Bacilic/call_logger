part of 'department_form_dialog.dart';

enum _UnsavedChangesAction { save, discard, continueEditing }

mixin DepartmentFormDismissGuardMixin on DepartmentFormDialogStateHost {
  bool get _isDirty {
    if (_nameController.text.trim() != _snapName) return true;
    if (_buildingController.text.trim() != _snapBuilding) return true;
    if (_notesController.text.trim() != _snapNotes) return true;
    final parsedHex = tryParseDepartmentHex(_hexController.text.trim());
    final effectiveHex = colorToDepartmentHex(parsedHex ?? _selectedColor);
    if (effectiveHex != _snapColorHex) return true;

    final currentPhones =
        _sharedPhones
            .map((v) => v.trim())
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.compareTo(b));
    final currentEquipment =
        _sharedEquipmentCodes
            .map((v) => v.trim())
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.compareTo(b));
    if (currentPhones.join('|') != _snapSharedPhones.join('|')) return true;
    if (currentEquipment.join('|') != _snapSharedEquipmentCodes.join('|')) {
      return true;
    }
    if (_selectedFloorId != _snapFloorId) return true;
    return false;
  }

  bool _needsDismissConfirmation() {
    if (_isEdit) return _isDirty;
    return _nameController.text.trim().isNotEmpty;
  }

  List<String> _buildChangedFieldLabels() {
    final labels = <String>[];
    if (_nameController.text.trim() != _snapName) labels.add('Όνομα');
    if (_buildingController.text.trim() != _snapBuilding) labels.add('Κτίριο');
    if (_notesController.text.trim() != _snapNotes) labels.add('Σημειώσεις');
    final parsedHex = tryParseDepartmentHex(_hexController.text.trim());
    final effectiveHex = colorToDepartmentHex(parsedHex ?? _selectedColor);
    if (effectiveHex != _snapColorHex) labels.add('Χρώμα');

    final currentPhones =
        _sharedPhones
            .map((v) => v.trim())
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.compareTo(b));
    final currentEquipment =
        _sharedEquipmentCodes
            .map((v) => v.trim())
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.compareTo(b));
    if (currentPhones.join('|') != _snapSharedPhones.join('|')) {
      labels.add('Κοινόχρηστα τηλέφωνα');
    }
    if (currentEquipment.join('|') != _snapSharedEquipmentCodes.join('|')) {
      labels.add('Κοινόχρηστος εξοπλισμός');
    }
    if (_selectedFloorId != _snapFloorId) labels.add('Όροφος (κατόψη)');
    return labels;
  }

  String _unsavedChangesDialogMessage() {
    if (_isEdit) {
      final labels = _buildChangedFieldLabels();
      final buf = StringBuffer('Έχουν γίνει αλλαγές:');
      for (final label in labels) {
        buf.write('\n- $label');
      }
      buf.write('\n\nΘέλεται να γίνει:');
      return buf.toString();
    }
    return 'Το τμήμα δεν έχει αποθηκευτεί.\n\nΘέλεται να γίνει:';
  }

  Future<_UnsavedChangesAction?> _showUnsavedChangesDialog() {
    return showDialog<_UnsavedChangesAction>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Text(_unsavedChangesDialogMessage()),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(_UnsavedChangesAction.save),
            child: const Text('Διατήρηση'),
          ),
          FilledButton.tonal(
            onPressed: () =>
                Navigator.of(ctx).pop(_UnsavedChangesAction.discard),
            child: const Text('Ακύρωση Αλλαγών'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(_UnsavedChangesAction.continueEditing),
            child: const Text('Επεξεργασία'),
          ),
        ],
      ),
    );
  }

  Future<void> _requestClose() async {
    if (!_needsDismissConfirmation()) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final action = await _showUnsavedChangesDialog();
    if (!mounted) return;
    switch (action) {
      case _UnsavedChangesAction.save:
        await _save();
      case _UnsavedChangesAction.discard:
        Navigator.of(context).pop();
      case _UnsavedChangesAction.continueEditing:
      case null:
        break;
    }
  }

  /// Κουμπί «Ακύρωση»: κλείσιμο χωρίς διάλογο επιβεβαίωσης (εκούσια απόρριψη).
  void _cancelAndClose() {
    if (mounted) Navigator.of(context).pop();
  }
}
