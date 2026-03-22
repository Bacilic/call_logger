import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/services/lookup_service.dart';
import '../../../../core/services/settings_service.dart';
import '../../../../core/utils/name_parser.dart';
import '../../../../core/utils/search_text_normalizer.dart';
import '../../../../core/utils/spell_check.dart';
import '../../../calls/provider/lookup_provider.dart';
import '../../models/equipment_column.dart';
import '../../providers/equipment_directory_provider.dart';

/// Διάλογος μαζικής επεξεργασίας: εφαρμογή τιμών σε επιλεγμένο εξοπλισμό.
class BulkEquipmentEditDialog extends StatefulWidget {
  const BulkEquipmentEditDialog({
    super.key,
    required this.selectedRows,
    required this.notifier,
    required this.ref,
  });

  final List<EquipmentRow> selectedRows;
  final EquipmentDirectoryNotifier notifier;
  final WidgetRef ref;

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
  late final TextEditingController _ownerController;
  late final FocusNode _ownerFocusNode;
  bool _ownerTextInitialized = false;
  int? _selectedUserId;
  String? _selectedType;
  String? _selectedRemoteTool;

  @override
  void initState() {
    super.initState();
    for (final key in _fieldKeys) {
      if (key == 'owner' || key == 'defaultRemoteTool' || key == 'type') {
        continue;
      }
      _controllers[key] = TextEditingController(text: _commonValue(key));
    }
    _ownerController = TextEditingController();
    _ownerFocusNode = FocusNode();
    _selectedUserId = _commonOwnerId();
    final typeRaw = _commonValue('type').trim();
    _selectedType = typeRaw.isEmpty ? null : typeRaw;
    final raw = _commonValue('defaultRemoteTool').trim();
    _selectedRemoteTool = raw.isEmpty ? null : raw;
  }

  static String? _normalizedRemoteToolValue(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty || t == 'Κανένα') return null;
    return t;
  }

  Future<int?> _resolveOwnerToUserId(
    String ownerText,
    LookupService? lookupService,
  ) async {
    final text = ownerText.trim();
    if (text.isEmpty) return null;
    if (lookupService == null) return null;
    final textForSearch = NameParserUtility.stripParentheticalSuffix(text);
    final users = lookupService.searchUsersByQuery(textForSearch);
    if (users.isNotEmpty) {
      final exact = users
          .where(
            (u) =>
                (u.fullNameWithDepartment == text) ||
                (u.name?.trim() == textForSearch),
          )
          .toList();
      if (exact.isNotEmpty && exact.first.id != null) return exact.first.id;
      if (users.first.id != null) return users.first.id;
    }
    final parsed = NameParserUtility.parse(textForSearch);
    return DatabaseHelper.instance.insertUser(
      firstName: parsed.firstName,
      lastName: parsed.lastName,
    );
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
    final first = rows.first.$2?.id;
    final allSame = rows.every((r) => r.$2?.id == first);
    return allSame ? first : null;
  }

  bool _hasDifferentValues(String fieldKey) {
    final rows = widget.selectedRows;
    if (rows.length <= 1) return false;
    if (fieldKey == 'owner') {
      final first = rows.first.$2?.id;
      return !rows.every((r) => r.$2?.id == first);
    }
    final getter = _getterFor(fieldKey);
    final firstNorm = _normalized(getter(rows.first));
    return !rows.every((r) => _normalized(getter(r)) == firstNorm);
  }

  @override
  void dispose() {
    _ownerController.dispose();
    _ownerFocusNode.dispose();
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
    final asyncLookup = widget.ref.read(lookupServiceProvider);
    final lookup = asyncLookup.value?.service;
    for (var i = 0; i < _fieldKeys.length; i++) {
      final fieldKey = _fieldKeys[i];
      if (_applyField[fieldKey] != true) continue;
      final dbKey = _dbKeys[i];
      if (fieldKey == 'owner') {
        changes[dbKey] = await _resolveOwnerToUserId(
          _ownerController.text.trim(),
          lookup,
        );
      } else if (fieldKey == 'defaultRemoteTool') {
        changes[dbKey] = _normalizedRemoteToolValue(_selectedRemoteTool);
      } else if (fieldKey == 'type') {
        final v = _selectedType?.trim() ?? '';
        changes[dbKey] = v.isEmpty ? null : v;
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
    widget.ref.invalidate(lookupServiceProvider);
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
        'Μαζική επεξεργασία (${widget.selectedRows.length} εξοπλισμός)',
      ),
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
                        () => _applyField[_fieldKeys[i]] = v ?? false,
                      ),
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
                                data: (bundle) {
                                  final service = bundle.service;
                                  if (_selectedUserId != null &&
                                      !_ownerTextInitialized) {
                                    final u = service.users
                                        .where((u) => u.id == _selectedUserId)
                                        .firstOrNull;
                                    if (u != null) {
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                            if (mounted) {
                                              _ownerController.text =
                                                  u.fullNameWithDepartment;
                                              setState(
                                                () => _ownerTextInitialized =
                                                    true,
                                              );
                                            }
                                          });
                                    } else {
                                      _ownerTextInitialized = true;
                                    }
                                  }
                                  final theme = Theme.of(context);
                                  return Autocomplete<String>(
                                    displayStringForOption: (String o) => o,
                                    focusNode: _ownerFocusNode,
                                    textEditingController: _ownerController,
                                    optionsBuilder: (TextEditingValue value) {
                                      final q =
                                          SearchTextNormalizer.normalizeForSearch(
                                            value.text,
                                          );
                                      final users = q.isEmpty
                                          ? service.users
                                          : service.searchUsersByQuery(
                                              value.text.trim(),
                                            );
                                      return users
                                          .where((u) => u.id != null)
                                          .map((u) => u.fullNameWithDepartment)
                                          .where(
                                            (option) =>
                                                SearchTextNormalizer.matchesNormalizedQuery(
                                                  option,
                                                  q,
                                                ),
                                          )
                                          .toList();
                                    },
                                    onSelected: (String selection) {
                                      final u = service.users
                                          .where(
                                            (user) =>
                                                user.fullNameWithDepartment ==
                                                selection,
                                          )
                                          .firstOrNull;
                                      if (u != null && u.id != null) {
                                        setState(() {
                                          _selectedUserId = u.id;
                                          _ownerController.text =
                                              u.name ??
                                              u.fullNameWithDepartment;
                                        });
                                      }
                                    },
                                    fieldViewBuilder:
                                        (
                                          context,
                                          textController,
                                          focusNode,
                                          onFieldSubmitted,
                                        ) {
                                          return TextField(
                                            controller: textController,
                                            focusNode: focusNode,
                                            decoration: InputDecoration(
                                              hintText:
                                                  _hasDifferentValues('owner')
                                                  ? '(Διαφορετικές τιμές)'
                                                  : 'Πληκτρολόγησε όνομα ή άφησε κενό (Άγνωστος κάτοχος)',
                                              hintStyle: theme
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.copyWith(
                                                    color: theme
                                                        .colorScheme
                                                        .onSurfaceVariant
                                                        .withValues(alpha: 0.7),
                                                  ),
                                              border:
                                                  const OutlineInputBorder(),
                                              suffixIcon: Semantics(
                                                label: 'Καθαρισμός Κατόχου',
                                                child: IconButton(
                                                  icon: const Icon(
                                                    Icons.close,
                                                    size: 20,
                                                  ),
                                                  onPressed: () {
                                                    textController.clear();
                                                    setState(
                                                      () => _selectedUserId =
                                                          null,
                                                    );
                                                  },
                                                  tooltip: 'Καθαρισμός Κατόχου',
                                                ),
                                              ),
                                            ),
                                            onChanged: (value) {
                                              if (value.trim().isEmpty) {
                                                setState(
                                                  () => _selectedUserId = null,
                                                );
                                              }
                                            },
                                          );
                                        },
                                  );
                                },
                                loading: () => const SizedBox(
                                  height: 48,
                                  child: Center(child: Text('Φόρτωση...')),
                                ),
                                error: (_, e) => const Text('Σφάλμα'),
                              );
                            },
                          )
                        : _fieldKeys[i] == 'type'
                        ? FutureBuilder<List<String>>(
                            future: SettingsService().getEquipmentTypesList(),
                            builder: (context, snapshot) {
                              var options =
                                  snapshot.data ?? ['Υπολογιστής', 'Εκτυπωτής'];
                              if (_selectedType != null &&
                                  _selectedType!.trim().isNotEmpty &&
                                  !options.contains(_selectedType)) {
                                options = [_selectedType!, ...options];
                              }
                              return DropdownButtonFormField<String?>(
                                initialValue: _selectedType,
                                decoration: InputDecoration(
                                  hintText: _hasDifferentValues('type')
                                      ? '(Διαφορετικές τιμές)'
                                      : null,
                                  border: const OutlineInputBorder(),
                                ),
                                items: [
                                  ...options.map(
                                    (o) => DropdownMenuItem<String?>(
                                      value: o,
                                      child: Text(o),
                                    ),
                                  ),
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('Κανένας'),
                                  ),
                                ],
                                onChanged: (v) =>
                                    setState(() => _selectedType = v),
                              );
                            },
                          )
                        : _fieldKeys[i] == 'defaultRemoteTool'
                        ? FutureBuilder<List<String>>(
                            future: SettingsService()
                                .getRemoteSurfaceAppsList(),
                            builder: (context, snapshot) {
                              final options =
                                  snapshot.data ?? ['AnyDesk', 'VNC'];
                              return DropdownButtonFormField<String?>(
                                initialValue: _selectedRemoteTool,
                                decoration: InputDecoration(
                                  hintText:
                                      _hasDifferentValues('defaultRemoteTool')
                                      ? '(Διαφορετικές τιμές)'
                                      : null,
                                  border: const OutlineInputBorder(),
                                ),
                                items: [
                                  ...options.map(
                                    (o) => DropdownMenuItem<String?>(
                                      value: o,
                                      child: Text(o),
                                    ),
                                  ),
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('Κανένα'),
                                  ),
                                ],
                                onChanged: (v) =>
                                    setState(() => _selectedRemoteTool = v),
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
                            spellCheckConfiguration:
                                platformSpellCheckConfiguration,
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
        FilledButton(onPressed: _save, child: const Text('Αποθήκευση')),
      ],
    );
  }
}
