import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../calls/provider/lookup_provider.dart';
import '../../models/equipment_column.dart';
import '../../providers/equipment_directory_provider.dart';

/// Διάλογος μαζικής επεξεργασίας: εφαρμογή τιμών σε επιλεγμένο εξοπλισμό.
class BulkEquipmentEditDialog extends StatefulWidget {
  const BulkEquipmentEditDialog({
    super.key,
    required this.selectedRows,
    required this.notifier,
  });

  final List<EquipmentRow> selectedRows;
  final EquipmentDirectoryNotifier notifier;

  @override
  State<BulkEquipmentEditDialog> createState() =>
      _BulkEquipmentEditDialogState();
}

class _BulkEquipmentEditDialogState extends State<BulkEquipmentEditDialog> {
  static const _fieldKeys = [
    'type',
    'notes',
    'customIp',
    'anydeskId',
    'defaultRemoteTool',
    'owner',
  ];
  static const _dbKeys = [
    'type',
    'notes',
    'custom_ip',
    'anydesk_id',
    'default_remote_tool',
    'user_id',
  ];

  final Map<String, bool> _applyField = {
    'type': false,
    'notes': false,
    'customIp': false,
    'anydeskId': false,
    'defaultRemoteTool': false,
    'owner': false,
  };
  final Map<String, TextEditingController> _controllers = {};
  int? _selectedUserId;

  @override
  void initState() {
    super.initState();
    for (final key in _fieldKeys) {
      if (key == 'owner') continue;
      _controllers[key] = TextEditingController(text: _commonValue(key));
    }
    _selectedUserId = _commonOwnerId();
  }

  static String _normalized(String? v) => v?.trim() ?? '';

  String _commonValue(String fieldKey) {
    final rows = widget.selectedRows;
    if (rows.isEmpty) return '';
    final getter = _getterFor(fieldKey);
    final firstNorm = _normalized(getter(rows.first));
    final allSame = rows.every((r) => _normalized(getter(r)) == firstNorm);
    if (allSame) return firstNorm;
    return '';
  }

  String? Function(EquipmentRow) _getterFor(String fieldKey) {
    switch (fieldKey) {
      case 'type':
        return (r) => r.$1.type;
      case 'notes':
        return (r) => r.$1.notes;
      case 'customIp':
        return (r) => r.$1.customIp;
      case 'anydeskId':
        return (r) => r.$1.anydeskId;
      case 'defaultRemoteTool':
        return (r) => r.$1.defaultRemoteTool;
      default:
        return (r) => null;
    }
  }

  int? _commonOwnerId() {
    final rows = widget.selectedRows;
    if (rows.isEmpty) return null;
    final first = rows.first.$1.userId;
    final allSame = rows.every((r) => r.$1.userId == first);
    return allSame ? first : null;
  }

  bool _hasDifferentValues(String fieldKey) {
    final rows = widget.selectedRows;
    if (rows.length <= 1) return false;
    if (fieldKey == 'owner') {
      final first = rows.first.$1.userId;
      return !rows.every((r) => r.$1.userId == first);
    }
    final getter = _getterFor(fieldKey);
    final firstNorm = _normalized(getter(rows.first));
    return !rows.every((r) => _normalized(getter(r)) == firstNorm);
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final ids = widget.selectedRows
        .map((r) => r.$1.id)
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
      if (fieldKey == 'owner') {
        changes[dbKey] = _selectedUserId;
      } else {
        final value = _controllers[fieldKey]!.text.trim();
        changes[dbKey] = value.isEmpty ? null : value;
      }
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
        content: Text('Ενημερώθηκαν ${ids.length} εγγραφές εξοπλισμού.'),
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
      'type': 'Τύπος',
      'notes': 'Σημειώσεις',
      'customIp': 'Προσαρμοσμένη IP',
      'anydeskId': 'AnyDesk ID',
      'defaultRemoteTool': 'Εργαλείο απομακρυσμένης',
      'owner': 'Κάτοχος',
    };
    return AlertDialog(
      title: Text(
          'Μαζική επεξεργασία (${widget.selectedRows.length} εξοπλισμός)'),
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
                      onChanged: (v) => setState(
                          () => _applyField[_fieldKeys[i]] = v ?? false),
                      title: Text(labels[_fieldKeys[i]]!),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  Expanded(
                    child: _fieldKeys[i] == 'owner'
                        ? Consumer(
                            builder: (context, ref, _) {
                              final async = ref.watch(lookupServiceProvider);
                              return async.when(
                                data: (service) {
                                  final users = service.users;
                                  return DropdownButtonFormField<int?>(
                                    initialValue: _selectedUserId,
                                    decoration: InputDecoration(
                                      hintText: _hasDifferentValues('owner')
                                          ? '(Διαφορετικές τιμές)'
                                          : null,
                                      border: const OutlineInputBorder(),
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
                                              child: Text(
                                                  u.fullNameWithDepartment),
                                            ),
                                          ),
                                    ],
                                    onChanged: (v) =>
                                        setState(() => _selectedUserId = v),
                                  );
                                },
                                loading: () => const SizedBox(
                                    height: 48,
                                    child: Center(
                                        child: Text('Φόρτωση...'))),
                                error: (_, e) => const Text('Σφάλμα'),
                              );
                            },
                          )
                        : TextFormField(
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
