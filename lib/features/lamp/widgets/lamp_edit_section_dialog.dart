import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/date_parser_util.dart';
import '../models/lamp_equipment_view_model.dart';

// Ο διάλογος «Επεξεργασία …» μιας ενότητας της κάρτας Λάμπας: παραλαμβάνει
// την ενότητα, επιστρέφει μόνο τα αλλαγμένα πεδία, έτοιμα για αποθήκευση.

class EditSectionDialog<T> extends StatefulWidget {
  const EditSectionDialog({
    super.key,
    required this.section,
    required this.onSave,
  });

  final InfoSectionData section;
  final Future<EquipmentSectionSaveResult> Function(
    Map<String, Object?> updatedFields,
  )
  onSave;

  @override
  State<EditSectionDialog<T>> createState() => _EditSectionDialogState<T>();
}

class _EditSectionDialogState<T> extends State<EditSectionDialog<T>> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};
  late final Map<String, Object?> originalData;
  late Map<String, Object?> currentData;
  bool _saving = false;

  bool get hasChanges => !mapEquals(originalData, currentData);

  @override
  void initState() {
    super.initState();
    originalData = {
      for (final field in widget.section.editableFields)
        field.fieldKey: field.value ?? '',
    };
    currentData = Map<String, Object?>.from(originalData);
    for (final field in widget.section.editableFields) {
      _controllers[field.fieldKey] =
          TextEditingController(text: field.value ?? '')..addListener(() {
            currentData = <String, Object?>{
              ...currentData,
              field.fieldKey: _controllers[field.fieldKey]!.text,
            };
            if (mounted) setState(() {});
          });
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.section.type.color;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _requestClose();
      },
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.escape): () {
            _requestClose();
          },
        },
        child: AlertDialog(
          title: Row(
            children: [
              Icon(widget.section.type.icon, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text('Επεξεργασία ${widget.section.type.title}')),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final field in widget.section.editableFields) ...[
                      _EditField(
                        field: field,
                        controller: _controllers[field.fieldKey]!,
                        changed:
                            currentData[field.fieldKey] !=
                            originalData[field.fieldKey],
                        validator: (value) => _validateField(field, value),
                        onPickDate: field.type == EditableFieldType.date
                            ? () => _pickDate(field)
                            : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _saving ? null : _requestClose,
              child: const Text('Άκυρο'),
            ),
            FilledButton.icon(
              onPressed: hasChanges && !_saving ? _save : null,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('Αποθήκευση'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _requestClose() async {
    if (_saving) return;
    if (!hasChanges) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Απόρριψη αλλαγών;'),
        content: const Text('Θέλεις να απορρίψεις αλλαγές;'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Συνέχεια επεξεργασίας'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Απόρριψη'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _pickDate(EditableInfoField field) async {
    final initial =
        _parseDate(_controllers[field.fieldKey]?.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1990),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    _controllers[field.fieldKey]?.text = _formatIsoDate(picked);
  }

  Future<void> _save() async {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;
    setState(() => _saving = true);
    final changedFields = _changedFields();
    final result = await widget.onSave(changedFields);
    if (!mounted) return;
    if (result.success) {
      Navigator.of(context).pop(changedFields);
      return;
    }
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message ?? 'Η αποθήκευση απέτυχε.')),
    );
  }

  Map<String, Object?> _changedFields() {
    final changed = <String, Object?>{};
    for (final field in widget.section.editableFields) {
      final current = currentData[field.fieldKey];
      if (current == originalData[field.fieldKey]) continue;
      changed[field.fieldKey] = _normalizeForStorage(field, current);
    }
    return changed;
  }

  Object? _normalizeForStorage(EditableInfoField field, Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    return switch (field.type) {
      EditableFieldType.code => int.tryParse(text),
      EditableFieldType.number when field.fieldKey == 'level' => int.tryParse(
        text,
      ),
      // Ο έλεγχος έχει ήδη αποκλείσει ό,τι δεν είναι ημερομηνία.
      EditableFieldType.date =>
        _parseDate(text) == null ? text : _formatIsoDate(_parseDate(text)!),
      _ => text,
    };
  }

  String? _validateField(EditableInfoField field, String? value) {
    final text = value?.trim() ?? '';
    if (_isPrimaryKeyField(field.fieldKey) && text.isEmpty) {
      return 'Ο κωδικός δεν μπορεί να είναι κενός.';
    }
    if (text.isEmpty) return null;
    switch (field.type) {
      case EditableFieldType.email:
        return null;
      case EditableFieldType.date:
        final (date, error) = DateParserUtil.parseSingleDate(text);
        if (error != null) return error;
        if (date != null && field.fieldKey == 'end_of_guarantee_date') {
          final start = _parseDate(currentData['receiving_date']);
          if (start != null && date.isBefore(start)) {
            return 'Η λήξη δεν μπορεί να προηγείται της παραλαβής.';
          }
        }
        return null;
      case EditableFieldType.number:
        return null;
      case EditableFieldType.phone:
        return null;
      case EditableFieldType.code:
        return int.tryParse(text) == null ? 'Μη έγκυρος κωδικός.' : null;
      case EditableFieldType.text:
        return null;
    }
  }

  bool _isPrimaryKeyField(String fieldKey) {
    return fieldKey == 'code' ||
        (widget.section.type == InfoSectionType.model &&
            fieldKey == 'model_id') ||
        (widget.section.type == InfoSectionType.contract &&
            fieldKey == 'contract_id') ||
        (widget.section.type == InfoSectionType.owner &&
            fieldKey == 'owner_id') ||
        (widget.section.type == InfoSectionType.department &&
            fieldKey == 'office_id');
  }

  /// Μία πηγή για «τι ημερομηνία είναι αυτό»: ο κοινός ελεγκτής της εφαρμογής.
  DateTime? _parseDate(Object? value) =>
      DateParserUtil.parseSingleDate(value?.toString() ?? '').$1;

  String _formatIsoDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}

class _EditField extends StatelessWidget {
  const _EditField({
    required this.field,
    required this.controller,
    required this.changed,
    required this.validator,
    this.onPickDate,
  });

  final EditableInfoField field;
  final TextEditingController controller;
  final bool changed;
  final String? Function(String?) validator;
  final VoidCallback? onPickDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: changed
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.22)
            : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextFormField(
        controller: controller,
        autofocus: field.autofocus,
        maxLines: field.maxLines,
        keyboardType: _keyboardType(field.type),
        validator: validator,
        decoration: InputDecoration(
          labelText: field.label,
          helperText: field.note,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
          suffixIcon: onPickDate == null
              ? null
              : IconButton(
                  tooltip: 'Επιλογή ημερομηνίας',
                  icon: const Icon(Icons.calendar_today_outlined),
                  onPressed: onPickDate,
                ),
        ),
      ),
    );
  }

  TextInputType _keyboardType(EditableFieldType type) {
    return switch (type) {
      EditableFieldType.email => TextInputType.emailAddress,
      EditableFieldType.date => TextInputType.datetime,
      EditableFieldType.number => TextInputType.number,
      EditableFieldType.phone => TextInputType.phone,
      EditableFieldType.code => TextInputType.number,
      EditableFieldType.text => TextInputType.text,
    };
  }
}
