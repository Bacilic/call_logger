import 'package:flutter/material.dart';

import 'department_color_palette.dart';
import 'department_form_dialog.dart';

enum _UnsavedChangesAction { save, discard, continueEditing }

/// Φρουρός κλεισίματος της φόρμας τμήματος: dirty έλεγχος + διάλογος
/// «Μη αποθηκευμένες αλλαγές».
///
/// Συνεργάτης του [DepartmentFormDialogState] (Σύνθεση).
class DepartmentFormDismissGuard {
  DepartmentFormDismissGuard(this.host);

  final DepartmentFormDialogState host;

  bool get isDirty {
    if (host.nameController.text.trim() != host.snapName) return true;
    if (host.buildingController.text.trim() != host.snapBuilding) return true;
    if (host.notesController.text.trim() != host.snapNotes) return true;
    final parsedHex = tryParseDepartmentHex(host.hexController.text.trim());
    final effectiveHex = colorToDepartmentHex(parsedHex ?? host.selectedColor);
    if (effectiveHex != host.snapColorHex) return true;

    final currentPhones =
        host.sharedPhones
            .map((v) => v.trim())
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.compareTo(b));
    final currentEquipment =
        host.sharedEquipmentCodes
            .map((v) => v.trim())
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.compareTo(b));
    if (currentPhones.join('|') != host.snapSharedPhones.join('|')) {
      return true;
    }
    if (currentEquipment.join('|') != host.snapSharedEquipmentCodes.join('|')) {
      return true;
    }
    if (host.selectedFloorId != host.snapFloorId) return true;
    return false;
  }

  bool _needsDismissConfirmation() {
    if (host.isEdit) return isDirty;
    return host.nameController.text.trim().isNotEmpty;
  }

  List<String> _buildChangedFieldLabels() {
    final labels = <String>[];
    if (host.nameController.text.trim() != host.snapName) labels.add('Όνομα');
    if (host.buildingController.text.trim() != host.snapBuilding) {
      labels.add('Κτίριο');
    }
    if (host.notesController.text.trim() != host.snapNotes) {
      labels.add('Σημειώσεις');
    }
    final parsedHex = tryParseDepartmentHex(host.hexController.text.trim());
    final effectiveHex = colorToDepartmentHex(parsedHex ?? host.selectedColor);
    if (effectiveHex != host.snapColorHex) labels.add('Χρώμα');

    final currentPhones =
        host.sharedPhones
            .map((v) => v.trim())
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.compareTo(b));
    final currentEquipment =
        host.sharedEquipmentCodes
            .map((v) => v.trim())
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.compareTo(b));
    if (currentPhones.join('|') != host.snapSharedPhones.join('|')) {
      labels.add('Κοινόχρηστα τηλέφωνα');
    }
    if (currentEquipment.join('|') != host.snapSharedEquipmentCodes.join('|')) {
      labels.add('Κοινόχρηστος εξοπλισμός');
    }
    if (host.selectedFloorId != host.snapFloorId) {
      labels.add('Όροφος (κατόψη)');
    }
    return labels;
  }

  String _unsavedChangesDialogMessage() {
    if (host.isEdit) {
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
      context: host.context,
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

  Future<void> requestClose() async {
    if (!_needsDismissConfirmation()) {
      if (host.mounted) Navigator.of(host.context).pop();
      return;
    }
    final action = await _showUnsavedChangesDialog();
    if (!host.mounted) return;
    switch (action) {
      case _UnsavedChangesAction.save:
        await host.saveFlow.save();
      case _UnsavedChangesAction.discard:
        Navigator.of(host.context).pop();
      case _UnsavedChangesAction.continueEditing:
      case null:
        break;
    }
  }

  /// Κουμπί «Ακύρωση»: κλείσιμο χωρίς διάλογο επιβεβαίωσης (εκούσια απόρριψη).
  void cancelAndClose() {
    if (host.mounted) Navigator.of(host.context).pop();
  }
}
