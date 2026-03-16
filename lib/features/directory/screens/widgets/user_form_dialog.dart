import 'package:flutter/material.dart';

import '../../../../core/utils/spell_check.dart';
import '../../../calls/models/user_model.dart';
import '../../providers/directory_provider.dart';

/// Διάλογος φόρμας για δημιουργία/επεξεργασία/αντίγραφο χρήστη.
class UserFormDialog extends StatefulWidget {
  const UserFormDialog({
    super.key,
    this.initialUser,
    required this.notifier,
    this.isClone = false,
    this.focusedField,
  });

  final UserModel? initialUser;
  final DirectoryNotifier notifier;
  /// True = αντίγραφο: φόρμα προ-συμπληρωμένη, κουμπί «Προσθήκη».
  final bool isClone;
  final String? focusedField;

  @override
  State<UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _lastNameController;
  late final TextEditingController _firstNameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _departmentController;
  late final TextEditingController _locationController;
  late final TextEditingController _notesController;
  
  final FocusNode _lastNameFocusNode = FocusNode();
  final FocusNode _firstNameFocusNode = FocusNode();
  final FocusNode _phoneFocusNode = FocusNode();
  final FocusNode _departmentFocusNode = FocusNode();
  final FocusNode _locationFocusNode = FocusNode();
  final FocusNode _notesFocusNode = FocusNode();

  bool get _isEdit => widget.initialUser != null && !widget.isClone;

  void _selectAll(TextEditingController c) {
    c.selection = TextSelection(
      baseOffset: 0,
      extentOffset: c.text.length,
    );
  }

  @override
  void initState() {
    super.initState();
    final u = widget.initialUser;
    _lastNameController = TextEditingController(text: u?.lastName ?? '');
    _firstNameController = TextEditingController(text: u?.firstName ?? '');
    _phoneController = TextEditingController(text: u?.phone ?? '');
    _departmentController = TextEditingController(text: u?.department ?? '');
    _locationController = TextEditingController(text: u?.location ?? '');
    _notesController = TextEditingController(text: u?.notes ?? '');
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (widget.focusedField) {
        case 'lastName':
          _lastNameFocusNode.requestFocus();
          _selectAll(_lastNameController);
          break;
        case 'phone':
          _phoneFocusNode.requestFocus();
          _selectAll(_phoneController);
          break;
        case 'department':
          _departmentFocusNode.requestFocus();
          _selectAll(_departmentController);
          break;
        case 'location':
          _locationFocusNode.requestFocus();
          _selectAll(_locationController);
          break;
        case 'notes':
          _notesFocusNode.requestFocus();
          _selectAll(_notesController);
          break;
        case 'firstName':
        default:
          _firstNameFocusNode.requestFocus();
          _selectAll(_firstNameController);
          break;
      }
    });
  }

  @override
  void dispose() {
    _lastNameFocusNode.dispose();
    _firstNameFocusNode.dispose();
    _phoneFocusNode.dispose();
    _departmentFocusNode.dispose();
    _locationFocusNode.dispose();
    _notesFocusNode.dispose();
    
    _lastNameController.dispose();
    _firstNameController.dispose();
    _phoneController.dispose();
    _departmentController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String? _requiredValidator(String? v) =>
      (v?.trim().isEmpty ?? true) ? 'Υποχρεωτικό' : null;

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final user = UserModel(
      id: _isEdit ? widget.initialUser?.id : null,
      lastName: _lastNameController.text.trim(),
      firstName: _firstNameController.text.trim(),
      phone: _phoneController.text.trim().isEmpty
          ? null
          : _phoneController.text.trim(),
      department: _departmentController.text.trim().isEmpty
          ? null
          : _departmentController.text.trim(),
      location: _locationController.text.trim().isEmpty
          ? null
          : _locationController.text.trim(),
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    );
    if (_isEdit) {
      if (user.id != null &&
          widget.notifier.hasDuplicateExcludingNotes(user, excludeId: user.id)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Υπάρχει ήδη χρήστης με τα ίδια στοιχεία (επώνυμο, όνομα, τηλέφωνο, τμήμα, τοποθεσία). Διορθώστε τα δεδομένα.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      await widget.notifier.updateUser(user);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Αποθηκεύτηκε')),
      );
      return;
    }
    if (widget.notifier.hasDuplicateExcludingNotes(user)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Υπάρχει ήδη χρήστης με τα ίδια στοιχεία (επώνυμο, όνομα, τηλέφωνο, τμήμα, τοποθεσία). Διορθώστε τα δεδομένα.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    await widget.notifier.addUser(user);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Αποθηκεύτηκε')),
    );
  }

  String get _title {
    if (_isEdit) return 'Επεξεργασία χρήστη';
    if (widget.isClone) return 'Αντίγραφο χρήστη';
    return 'Νέος χρήστης';
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
                controller: _lastNameController,
                focusNode: _lastNameFocusNode,
                decoration: const InputDecoration(
                  labelText: 'Επώνυμο',
                  border: OutlineInputBorder(),
                ),
                validator: _requiredValidator,
                textCapitalization: TextCapitalization.words,
                onTap: () => _selectAll(_lastNameController),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _firstNameController,
                focusNode: _firstNameFocusNode,
                decoration: const InputDecoration(
                  labelText: 'Όνομα',
                  border: OutlineInputBorder(),
                ),
                validator: _requiredValidator,
                textCapitalization: TextCapitalization.words,
                onTap: () => _selectAll(_firstNameController),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                focusNode: _phoneFocusNode,
                decoration: const InputDecoration(
                  labelText: 'Τηλέφωνο',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
                onTap: () => _selectAll(_phoneController),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _departmentController,
                focusNode: _departmentFocusNode,
                decoration: const InputDecoration(
                  labelText: 'Τμήμα',
                  border: OutlineInputBorder(),
                ),
                onTap: () => _selectAll(_departmentController),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _locationController,
                focusNode: _locationFocusNode,
                decoration: const InputDecoration(
                  labelText: 'Τοποθεσία',
                  border: OutlineInputBorder(),
                ),
                onTap: () => _selectAll(_locationController),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                focusNode: _notesFocusNode,
                decoration: const InputDecoration(
                  labelText: 'Σημειώσεις',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 3,
                spellCheckConfiguration: platformSpellCheckConfiguration,
                onTap: () => _selectAll(_notesController),
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
