import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/services/lookup_service.dart';
import '../../../../core/services/settings_service.dart';
import '../../../../core/utils/name_parser.dart';
import '../../../../core/utils/search_text_normalizer.dart';
import '../../../../core/utils/spell_check.dart';
import '../../../calls/models/equipment_model.dart';
import '../../../calls/provider/lookup_provider.dart';
import '../../providers/equipment_directory_provider.dart';

/// Διάλογος φόρμας για δημιουργία/επεξεργασία/αντίγραφο εξοπλισμού.
class EquipmentFormDialog extends StatefulWidget {
  const EquipmentFormDialog({
    super.key,
    this.initialEquipment,
    required this.notifier,
    required this.ref,
    this.isClone = false,
    this.focusedField,
  });

  final EquipmentModel? initialEquipment;
  final EquipmentDirectoryNotifier notifier;
  final WidgetRef ref;
  final bool isClone;
  final String? focusedField;

  @override
  State<EquipmentFormDialog> createState() => _EquipmentFormDialogState();
}

class _EquipmentFormDialogState extends State<EquipmentFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codeController;
  late final TextEditingController _notesController;
  late final TextEditingController _customIpController;
  late final TextEditingController _anydeskIdController;
  late final TextEditingController _ownerController;
  late final FocusNode _ownerFocusNode;
  bool _ownerTextInitialized = false;

  int? _selectedUserId;
  /// Επιλογή τύπου εξοπλισμού· null = Κανένας.
  String? _selectedType;
  /// Επιλογή εργαλείου απομακρυσμένης· null ή κενό ή "Κανένα" = κανένα.
  String? _selectedRemoteTool;

  bool get _isEdit =>
      widget.initialEquipment != null && !widget.isClone;

  @override
  void initState() {
    super.initState();
    final e = widget.initialEquipment;
    _codeController = TextEditingController(text: e?.code ?? '');
    _notesController = TextEditingController(text: e?.notes ?? '');
    _customIpController = TextEditingController(text: e?.customIp ?? '');
    _anydeskIdController = TextEditingController(text: e?.anydeskId ?? '');
    _ownerController = TextEditingController();
    _ownerFocusNode = FocusNode();
    _selectedUserId = e?.userId;
    final typeRaw = e?.type?.trim() ?? '';
    _selectedType = typeRaw.isEmpty ? null : typeRaw;
    final raw = e?.defaultRemoteTool?.trim() ?? '';
    _selectedRemoteTool = raw.isEmpty ? null : raw;
  }

  @override
  void dispose() {
    _codeController.dispose();
    _notesController.dispose();
    _customIpController.dispose();
    _anydeskIdController.dispose();
    _ownerController.dispose();
    _ownerFocusNode.dispose();
    super.dispose();
  }

  /// Επιλύει κείμενο κατόχου σε userId: κενό → null, match → id, αλλιώς insert νέο χρήστη.
  Future<int?> _resolveOwnerToUserId(String ownerText, LookupService? lookupService) async {
    final text = ownerText.trim();
    if (text.isEmpty) return null;
    if (lookupService == null) return null;
    final textForSearch = NameParserUtility.stripParentheticalSuffix(text);
    final users = lookupService.searchUsersByQuery(textForSearch);
    if (users.isNotEmpty) {
      final exact = users.where((u) =>
          (u.fullNameWithDepartment == text) || (u.name?.trim() == textForSearch)).toList();
      if (exact.isNotEmpty && exact.first.id != null) return exact.first.id;
      if (users.first.id != null) return users.first.id;
    }
    final parsed = NameParserUtility.parse(textForSearch);
    final newId = await DatabaseHelper.instance.insertUser(
      firstName: parsed.firstName,
      lastName: parsed.lastName,
    );
    return newId;
  }

  /// null, κενό ή "Κανένα" → null· αλλιώς επιστρέφει το trim string.
  static String? _normalizedRemoteToolValue(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty || t == 'Κανένα') return null;
    return t;
  }

  String? _requiredValidator(String? v) =>
      (v?.trim().isEmpty ?? true) ? 'Υποχρεωτικό' : null;

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final asyncLookup = widget.ref.read(lookupServiceProvider);
    final lookup = asyncLookup.hasValue ? asyncLookup.value : null;
    final ownerText = _ownerController.text.trim();
    final userId = await _resolveOwnerToUserId(ownerText, lookup);
    final code = _codeController.text.trim();
    final typeVal = _selectedType?.trim() ?? '';
    final equipment = EquipmentModel(
      id: _isEdit ? widget.initialEquipment?.id : null,
      code: code.isEmpty ? null : code,
      type: typeVal.isEmpty ? null : typeVal,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      userId: userId,
      customIp: _customIpController.text.trim().isEmpty
          ? null
          : _customIpController.text.trim(),
      anydeskId: _anydeskIdController.text.trim().isEmpty
          ? null
          : _anydeskIdController.text.trim(),
      defaultRemoteTool: _normalizedRemoteToolValue(_selectedRemoteTool),
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
      widget.ref.invalidate(lookupServiceProvider);
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
    widget.ref.invalidate(lookupServiceProvider);
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
              FutureBuilder<List<String>>(
                future: SettingsService().getEquipmentTypesList(),
                builder: (context, snapshot) {
                  var options = snapshot.data ?? ['Υπολογιστής', 'Εκτυπωτής'];
                  if (_selectedType != null &&
                      _selectedType!.trim().isNotEmpty &&
                      !options.contains(_selectedType)) {
                    options = [_selectedType!, ...options];
                  }
                  return DropdownButtonFormField<String?>(
                    initialValue: _selectedType,
                    decoration: const InputDecoration(
                      labelText: 'Τύπος',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      ...options.map((o) => DropdownMenuItem<String?>(
                            value: o,
                            child: Text(o),
                          )),
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Κανένας'),
                      ),
                    ],
                    onChanged: (v) => setState(() => _selectedType = v),
                  );
                },
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
                spellCheckConfiguration: platformSpellCheckConfiguration,
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
              FutureBuilder<List<String>>(
                future: SettingsService().getRemoteSurfaceAppsList(),
                builder: (context, snapshot) {
                  final options = snapshot.data ?? ['AnyDesk', 'VNC'];
                  return DropdownButtonFormField<String?>(
                    initialValue: _selectedRemoteTool,
                    decoration: const InputDecoration(
                      labelText: 'Εργαλείο απομακρυσμένης',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      ...options.map((o) => DropdownMenuItem<String?>(
                            value: o,
                            child: Text(o),
                          )),
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Κανένα'),
                      ),
                    ],
                    onChanged: (v) => setState(() => _selectedRemoteTool = v),
                  );
                },
              ),
              const SizedBox(height: 12),
              Consumer(
                builder: (context, ref, _) {
                  final async = ref.watch(lookupServiceProvider);
                  return async.when(
                    data: (service) {
                      if (_selectedUserId != null && !_ownerTextInitialized) {
                        final u = service.users
                            .where((u) => u.id == _selectedUserId)
                            .firstOrNull;
                        if (u != null) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              _ownerController.text = u.fullNameWithDepartment;
                              setState(() => _ownerTextInitialized = true);
                            }
                          });
                        } else {
                          _ownerTextInitialized = true;
                        }
                      }
                      final theme = Theme.of(context);
                      return Autocomplete<String>(
                        displayStringForOption: (String option) => option,
                        focusNode: _ownerFocusNode,
                        textEditingController: _ownerController,
                        optionsBuilder: (TextEditingValue value) {
                          final q = SearchTextNormalizer.normalizeForSearch(
                            value.text,
                          );
                          final users = q.isEmpty
                              ? service.users
                              : service.searchUsersByQuery(value.text.trim());
                          return users
                              .where((u) => u.id != null)
                              .map((u) => u.fullNameWithDepartment)
                              .where((option) =>
                                  SearchTextNormalizer.matchesNormalizedQuery(
                                      option, q))
                              .toList();
                        },
                        onSelected: (String selection) {
                          final u = service.users.where((user) =>
                              user.fullNameWithDepartment == selection).firstOrNull;
                          if (u != null && u.id != null) {
                            setState(() {
                              _selectedUserId = u.id;
                              _ownerController.text = u.name ?? u.fullNameWithDepartment;
                            });
                          }
                        },
                        fieldViewBuilder: (
                          context,
                          textController,
                          focusNode,
                          onFieldSubmitted,
                        ) {
                          return TextField(
                            controller: textController,
                            focusNode: focusNode,
                            decoration: InputDecoration(
                              labelText: 'Κάτοχος',
                              hintText:
                                  'Πληκτρολόγησε όνομα ή άφησε κενό (Άγνωστος κάτοχος)',
                              hintStyle: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.7),
                              ),
                              border: const OutlineInputBorder(),
                              suffixIcon: Semantics(
                                label: 'Καθαρισμός Κατόχου',
                                child: IconButton(
                                  icon: const Icon(Icons.close, size: 20),
                                  onPressed: () {
                                    textController.clear();
                                    setState(() => _selectedUserId = null);
                                  },
                                  tooltip: 'Καθαρισμός Κατόχου',
                                ),
                              ),
                            ),
                            onChanged: (value) {
                              if (value.trim().isEmpty) {
                                setState(() => _selectedUserId = null);
                              }
                            },
                          );
                        },
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
