part of 'equipment_form_dialog.dart';

enum _EditDismissAction { save, discard, keepEditing }

mixin EquipmentFormDismissGuardMixin on EquipmentFormDialogStateHost {
  bool get _createHasRequiredFields => _codeController.text.trim().isNotEmpty;
  bool get _shouldConfirmDismissOnClose {
    if (!_formBaselineCaptured) return false;
    if (_isEdit) return _isDirty;
    return _createHasRequiredFields && _isDirty;
  }
  String _formStateSignature() {
    final sb = StringBuffer()
      ..write(_codeController.text)
      ..write('\u001e')
      ..write(_selectedType ?? '')
      ..write('\u001e')
      ..write(_notesController.text)
      ..write('\u001e')
      ..write(_selectedUserId ?? '')
      ..write('\u001e')
      ..write(_ownerController.text)
      ..write('\u001e')
      ..write(_departmentController.text)
      ..write('\u001e')
      ..write(_locationController.text)
      ..write('\u001e')
      ..write(_defaultRemoteToolId ?? '');
    final remoteKeys = <String>{
      ..._expandedRemoteKeys,
      ..._remoteParamValues.keys,
    }.toList()
      ..sort();
    for (final k in remoteKeys) {
      if (EquipmentRemoteParamKey.isReservedKey(k)) continue;
      sb
        ..write('\u001e')
        ..write(k)
        ..write('\u001f')
        ..write(_remoteParamValues[k] ?? '')
        ..write('\u001f')
        ..write(_expandedRemoteKeys.contains(k));
    }
    sb
      ..write('\u001e')
      ..write(_exclusiveRemoteToolId ?? '');
    return sb.toString();
  }

  String _signatureExclusiveSegment(List<String> parts) =>
      parts.length > 8 ? parts.last : '';

  String _signatureRemoteTail(List<String> parts) {
    if (parts.length <= 9) return '';
    return parts.sublist(8, parts.length - 1).join('\u001e');
  }

  @override
  void _tryCaptureFormBaseline() {
    if (_formBaselineCaptured) return;
    if (widget.initialOwner?.id != null && !_ownerTextInitialized) return;
    if (!_equipmentDepartmentTextInitialized) return;
    if (!_didPruneUnknownRemoteKeys) {
      return;
    }
    _initialFormSignature = _formStateSignature();
    _formBaselineCaptured = true;
  }

  List<String> _buildChangedFieldLabels() {
    if (!_formBaselineCaptured) return const [];
    final init = _initialFormSignature.split('\u001e');
    String initAt(int i) => i < init.length ? init[i] : '';

    final labels = <String>[];
    if (_codeController.text != initAt(0)) labels.add('Κωδικός');
    if ((_selectedType ?? '') != initAt(1)) labels.add('Τύπος');
    if (_notesController.text != initAt(2)) labels.add('Σημειώσεις');
    if ('${_selectedUserId ?? ''}' != initAt(3) ||
        _ownerController.text != initAt(4)) {
      labels.add('Κάτοχος');
    }
    if (_departmentController.text != initAt(5)) labels.add('Τμήμα');
    if (_locationController.text != initAt(6)) labels.add('Τοποθεσία');
    if ('${_defaultRemoteToolId ?? ''}' != initAt(7)) {
      labels.add('Προεπιλεγμένο εργαλείο');
    }
    final curParts = _formStateSignature().split('\u001e');
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
      context: context,
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

  Future<void> _requestClose() async {
    if (widget.initialEquipment != null && !_didPruneUnknownRemoteKeys) {
      return;
    }
    if (!_shouldConfirmDismissOnClose) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    if (_isEdit) {
      final labels = _buildChangedFieldLabels();
      if (labels.isEmpty) {
        if (mounted) Navigator.of(context).pop();
        return;
      }
      final action = await _showEditDismissDialog(labels);
      switch (action) {
        case _EditDismissAction.save:
          await _save();
        case _EditDismissAction.discard:
          if (mounted) Navigator.of(context).pop();
        case _EditDismissAction.keepEditing:
        case null:
          break;
      }
      return;
    }

    final discard = await _showNewDismissDialog();
    if (discard == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  /// Κουμπί «Ακύρωση»: κλείσιμο χωρίς διάλογο επιβεβαίωσης (εκούσια απόρριψη).
  void _cancelAndClose() {
    if (mounted) Navigator.of(context).pop();
  }
}
