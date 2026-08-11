import 'package:flutter/material.dart';

import '../../../calls/utils/equipment_remote_param_key.dart';
import 'equipment_form_dialog.dart';

enum _EditDismissAction { save, discard, keepEditing }

/// Φρουρός κλεισίματος της φόρμας εξοπλισμού: υπογραφή κατάστασης, dirty
/// έλεγχος και διάλογοι «Μη αποθηκευμένες αλλαγές».
///
/// Συνεργάτης του [EquipmentFormDialogState] (Σύνθεση).
class EquipmentFormDismissGuard {
  EquipmentFormDismissGuard(this.host);

  final EquipmentFormDialogState host;

  bool get createHasRequiredFields =>
      host.codeController.text.trim().isNotEmpty;

  bool get isDirty =>
      host.formBaselineCaptured &&
      formStateSignature() != host.initialFormSignature;

  bool get _shouldConfirmDismissOnClose {
    if (!host.formBaselineCaptured) return false;
    if (host.isEdit) return isDirty;
    return createHasRequiredFields && isDirty;
  }

  String formStateSignature() {
    final sb = StringBuffer()
      ..write(host.codeController.text)
      ..write('\u001e')
      ..write(host.selectedType ?? '')
      ..write('\u001e')
      ..write(host.notesController.text)
      ..write('\u001e')
      ..write(host.selectedUserId ?? '')
      ..write('\u001e')
      ..write(host.ownerController.text)
      ..write('\u001e')
      ..write(host.departmentController.text)
      ..write('\u001e')
      ..write(host.locationController.text)
      ..write('\u001e')
      ..write(host.lansweeperAssetNameController.text)
      ..write('\u001e')
      ..write(host.defaultRemoteToolId ?? '');
    final remoteKeys = <String>{
      ...host.expandedRemoteKeys,
      ...host.remoteParamValues.keys,
    }.toList()..sort();
    for (final k in remoteKeys) {
      if (EquipmentRemoteParamKey.isReservedKey(k)) continue;
      sb
        ..write('\u001e')
        ..write(k)
        ..write('\u001f')
        ..write(host.remoteParamValues[k] ?? '')
        ..write('\u001f')
        ..write(host.expandedRemoteKeys.contains(k));
    }
    sb
      ..write('\u001e')
      ..write(host.exclusiveRemoteToolId ?? '');
    return sb.toString();
  }

  String _signatureExclusiveSegment(List<String> parts) =>
      parts.length > 9 ? parts.last : '';

  String _signatureRemoteTail(List<String> parts) {
    if (parts.length <= 10) return '';
    return parts.sublist(9, parts.length - 1).join('\u001e');
  }

  void tryCaptureFormBaseline() {
    if (host.formBaselineCaptured) return;
    if (host.widget.initialOwner?.id != null && !host.ownerTextInitialized) {
      return;
    }
    if (!host.equipmentDepartmentTextInitialized) return;
    if (!host.didPruneUnknownRemoteKeys) {
      return;
    }
    host.initialFormSignature = formStateSignature();
    host.formBaselineCaptured = true;
  }

  List<String> _buildChangedFieldLabels() {
    if (!host.formBaselineCaptured) return const [];
    final init = host.initialFormSignature.split('\u001e');
    String initAt(int i) => i < init.length ? init[i] : '';

    final labels = <String>[];
    if (host.codeController.text != initAt(0)) labels.add('Κωδικός');
    if ((host.selectedType ?? '') != initAt(1)) labels.add('Τύπος');
    if (host.notesController.text != initAt(2)) labels.add('Σημειώσεις');
    if ('${host.selectedUserId ?? ''}' != initAt(3) ||
        host.ownerController.text != initAt(4)) {
      labels.add('Κάτοχος');
    }
    if (host.departmentController.text != initAt(5)) labels.add('Τμήμα');
    if (host.locationController.text != initAt(6)) labels.add('Τοποθεσία');
    if (host.lansweeperAssetNameController.text != initAt(7)) {
      labels.add('Αναγνωριστικό Lansweeper');
    }
    if ('${host.defaultRemoteToolId ?? ''}' != initAt(8)) {
      labels.add('Προεπιλεγμένο εργαλείο');
    }
    final curParts = formStateSignature().split('\u001e');
    if (_signatureExclusiveSegment(init) !=
        _signatureExclusiveSegment(curParts)) {
      labels.add('Αποκλειστικό εργαλείο');
    }
    if (_signatureRemoteTail(init) != _signatureRemoteTail(curParts)) {
      labels.add('Απομακρυσμένη σύνδεση');
    }
    return labels;
  }

  Future<_EditDismissAction?> _showEditDismissDialog(
    List<String> changedLabels,
  ) {
    return showDialog<_EditDismissAction>(
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
                for (final label in changedLabels) Text('• $label'),
                const SizedBox(height: 12),
                const Text('Θέλεται να γίνει:'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_EditDismissAction.save),
            child: const Text('Διατήρηση'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(_EditDismissAction.discard),
            child: const Text('Ακύρωση Αλλαγών'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(_EditDismissAction.keepEditing),
            child: const Text('Επεξεργασία'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showNewDismissDialog() {
    return showDialog<bool>(
      context: host.context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Μη αποθηκευμένα στοιχεία'),
        content: const Text(
          'Έχετε συμπληρώσει κωδικό εξοπλισμού χωρίς αποθήκευση. '
          'Να κλείσει ο διάλογος;',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Επεξεργασία'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Ακύρωση Αλλαγών'),
          ),
        ],
      ),
    );
  }

  Future<void> requestClose() async {
    if (host.widget.initialEquipment != null &&
        !host.didPruneUnknownRemoteKeys) {
      return;
    }
    if (!_shouldConfirmDismissOnClose) {
      if (host.mounted) Navigator.of(host.context).pop();
      return;
    }

    if (host.isEdit) {
      final labels = _buildChangedFieldLabels();
      if (labels.isEmpty) {
        if (host.mounted) Navigator.of(host.context).pop();
        return;
      }
      final action = await _showEditDismissDialog(labels);
      switch (action) {
        case _EditDismissAction.save:
          await host.save();
        case _EditDismissAction.discard:
          if (host.mounted) Navigator.of(host.context).pop();
        case _EditDismissAction.keepEditing:
        case null:
          break;
      }
      return;
    }

    final discard = await _showNewDismissDialog();
    if (discard == true && host.mounted) {
      Navigator.of(host.context).pop();
    }
  }

  /// Κουμπί «Ακύρωση»: κλείσιμο χωρίς διάλογο επιβεβαίωσης (εκούσια απόρριψη).
  void cancelAndClose() {
    if (host.mounted) Navigator.of(host.context).pop();
  }
}
