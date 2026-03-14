import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../calls/models/equipment_model.dart';
import '../../../calls/provider/lookup_provider.dart';
import '../../providers/equipment_directory_provider.dart';

/// Διάλογος φόρμας για δημιουργία/επεξεργασία/αντίγραφο εξοπλισμού.
class EquipmentFormDialog extends StatefulWidget {
  const EquipmentFormDialog({
    super.key,
    this.initialEquipment,
    required this.notifier,
    this.isClone = false,
    this.focusedField,
  });

  final EquipmentModel? initialEquipment;
  final EquipmentDirectoryNotifier notifier;
  final bool isClone;
  final String? focusedField;

  @override
  State<EquipmentFormDialog> createState() => _EquipmentFormDialogState();
}

class _EquipmentFormDialogState extends State<EquipmentFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codeController;
  late final TextEditingController _typeController;
  late final TextEditingController _notesController;
  late final TextEditingController _customIpController;
  late final TextEditingController _anydeskIdController;
  late final TextEditingController _defaultRemoteToolController;

  int? _selectedUserId;

  bool get _isEdit =>
      widget.initialEquipment != null && !widget.isClone;

  @override
  void initState() {
    super.initState();
    final e = widget.initialEquipment;
    _codeController = TextEditingController(text: e?.code ?? '');
    _typeController = TextEditingController(text: e?.type ?? '');
    _notesController = TextEditingController(text: e?.notes ?? '');
    _customIpController = TextEditingController(text: e?.customIp ?? '');
    _anydeskIdController = TextEditingController(text: e?.anydeskId ?? '');
    _defaultRemoteToolController =
        TextEditingController(text: e?.defaultRemoteTool ?? '');
    _selectedUserId = e?.userId;
  }

  @override
  void dispose() {
    _codeController.dispose();
    _typeController.dispose();
    _notesController.dispose();
    _customIpController.dispose();
    _anydeskIdController.dispose();
    _defaultRemoteToolController.dispose();
    super.dispose();
  }

  String? _requiredValidator(String? v) =>
      (v?.trim().isEmpty ?? true) ? 'Υποχρεωτικό' : null;

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final code = _codeController.text.trim();
    final equipment = EquipmentModel(
      id: _isEdit ? widget.initialEquipment?.id : null,
      code: code.isEmpty ? null : code,
      type: _typeController.text.trim().isEmpty
          ? null
          : _typeController.text.trim(),
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      userId: _selectedUserId,
      customIp: _customIpController.text.trim().isEmpty
          ? null
          : _customIpController.text.trim(),
      anydeskId: _anydeskIdController.text.trim().isEmpty
          ? null
          : _anydeskIdController.text.trim(),
      defaultRemoteTool:
          _defaultRemoteToolController.text.trim().isEmpty
              ? null
              : _defaultRemoteToolController.text.trim(),
    );
    if (_isEdit) {
      if (equipment.id != null &&
          widget.notifier.hasDuplicateCode(code, excludeId: equipment.id)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Υπάρχει ήδη εξοπλισμός με αυτόν τον κωδικό. Διορθώστε τα δεδομένα.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      await widget.notifier.updateEquipment(equipment);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Αποθηκεύτηκε')),
      );
      return;
    }
    if (widget.notifier.hasDuplicateCode(code)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Υπάρχει ήδη εξοπλισμός με αυτόν τον κωδικό. Διορθώστε τα δεδομένα.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    await widget.notifier.addEquipment(equipment);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Αποθηκεύτηκε')),
    );
  }

  String get _title {
    if (_isEdit) return 'Επεξεργασία εξοπλισμού';
    if (widget.isClone) return 'Αντίγραφο εξοπλισμού';
    return 'Νέος εξοπλισμός';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_title),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _codeController,
                decoration: const InputDecoration(
                  labelText: 'Κωδικός',
                  border: OutlineInputBorder(),
                ),
                validator: _requiredValidator,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _typeController,
                decoration: const InputDecoration(
                  labelText: 'Τύπος',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Σημειώσεις',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _customIpController,
                decoration: const InputDecoration(
                  labelText: 'Προσαρμοσμένη IP',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _anydeskIdController,
                decoration: const InputDecoration(
                  labelText: 'AnyDesk ID',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _defaultRemoteToolController,
                decoration: const InputDecoration(
                  labelText: 'Εργαλείο απομακρυσμένης',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Consumer(
                builder: (context, ref, _) {
                  final async = ref.watch(lookupServiceProvider);
                  return async.when(
                    data: (service) {
                      final users = service.users;
                      return DropdownButtonFormField<int?>(
                        initialValue: _selectedUserId,
                        decoration: const InputDecoration(
                          labelText: 'Κάτοχος',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('— Καμία —'),
                          ),
                          ...users
                              .where((u) => u.id != null)
                              .map(
                                (u) => DropdownMenuItem<int?>(
                                  value: u.id,
                                  child: Text(u.fullNameWithDepartment),
                                ),
                              ),
                        ],
                        onChanged: (v) => setState(() => _selectedUserId = v),
                      );
                    },
                    loading: () => const InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Κάτοχος',
                        border: OutlineInputBorder(),
                      ),
                      child: Text('Φόρτωση...'),
                    ),
                    error: (_, e) => const InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Κάτοχος',
                        border: OutlineInputBorder(),
                      ),
                      child: Text('Σφάλμα φόρτωσης'),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Ακύρωση'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(_isEdit ? 'Αποθήκευση' : 'Προσθήκη'),
        ),
      ],
    );
  }
}
