import 'package:flutter/material.dart';

import '../../../calls/models/user_model.dart';
import '../../providers/directory_provider.dart';

/// Διάλογος μαζικής επεξεργασίας: εφαρμογή τιμών σε επιλεγμένους χρήστες.
class BulkUserEditDialog extends StatefulWidget {
  const BulkUserEditDialog({
    super.key,
    required this.selectedUsers,
    required this.notifier,
  });

  final List<UserModel> selectedUsers;
  final DirectoryNotifier notifier;

  @override
  State<BulkUserEditDialog> createState() => _BulkUserEditDialogState();
}

class _BulkUserEditDialogState extends State<BulkUserEditDialog> {
  static const _fieldKeys = ['lastName', 'firstName', 'phone', 'department', 'location', 'notes'];
  static const _dbKeys = ['last_name', 'first_name', 'phone', 'department', 'location', 'notes'];

  final Map<String, bool> _applyField = {
    'lastName': false,
    'firstName': false,
    'phone': false,
    'department': false,
    'location': false,
    'notes': false,
  };
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    for (final key in _fieldKeys) {
      _controllers[key] = TextEditingController(text: _commonValue(key));
    }
  }

  /// Κανονικοποίηση για σύγκριση: null και κενό string ως ίσα, trim κενά.
  static String _normalized(String? v) => v?.trim() ?? '';

  String _commonValue(String fieldKey) {
    final users = widget.selectedUsers;
    if (users.isEmpty) return '';
    final getter = _getterFor(fieldKey);
    final firstNorm = _normalized(getter(users.first));
    final allSame = users.every((u) => _normalized(getter(u)) == firstNorm);
    if (allSame) return firstNorm;
    return '';
  }

  String? Function(UserModel) _getterFor(String fieldKey) {
    switch (fieldKey) {
      case 'lastName':
        return (u) => u.lastName;
      case 'firstName':
        return (u) => u.firstName;
      case 'phone':
        return (u) => u.phone;
      case 'department':
        return (u) => u.department;
      case 'location':
        return (u) => u.location;
      case 'notes':
        return (u) => u.notes;
      default:
        return (u) => null;
    }
  }

  bool _hasDifferentValues(String fieldKey) {
    final users = widget.selectedUsers;
    if (users.length <= 1) return false;
    final getter = _getterFor(fieldKey);
    final firstNorm = _normalized(getter(users.first));
    return !users.every((u) => _normalized(getter(u)) == firstNorm);
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final ids = widget.selectedUsers
        .map((u) => u.id)
        .whereType<int>()
        .toList();
    if (ids.isEmpty) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final changes = <String, dynamic>{};
    for (var i = 0; i < _fieldKeys.length; i++) {
      final fieldKey = _fieldKeys[i];
      if (_applyField[fieldKey] != true) continue;
      final dbKey = _dbKeys[i];
      final value = _controllers[fieldKey]!.text.trim();
      changes[dbKey] = value.isEmpty ? null : value;
    }
    if (changes.isEmpty) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    await widget.notifier.bulkUpdate(ids, changes);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Ενημερώθηκαν ${ids.length} χρήστες.'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Αναίρεση',
          onPressed: () async {
            await widget.notifier.undoLastBulkUpdate();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final labels = {
      'lastName': 'Επώνυμο',
      'firstName': 'Όνομα',
      'phone': 'Τηλέφωνο',
      'department': 'Τμήμα',
      'location': 'Τοποθεσία',
      'notes': 'Σημειώσεις',
    };
    return AlertDialog(
      title: Text('Μαζική επεξεργασία (${widget.selectedUsers.length} χρήστες)'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < _fieldKeys.length; i++) ...[
              Row(
                children: [
                  SizedBox(
                    width: 200,
                    child: CheckboxListTile(
                      value: _applyField[_fieldKeys[i]]!,
                      onChanged: (v) => setState(() => _applyField[_fieldKeys[i]] = v ?? false),
                      title: Text(labels[_fieldKeys[i]]!),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  Expanded(
                    child: TextFormField(
                      controller: _controllers[_fieldKeys[i]],
                      decoration: InputDecoration(
                        hintText: _hasDifferentValues(_fieldKeys[i])
                            ? '(Διαφορετικές τιμές)'
                            : null,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Ακύρωση'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Αποθήκευση'),
        ),
      ],
    );
  }
}
