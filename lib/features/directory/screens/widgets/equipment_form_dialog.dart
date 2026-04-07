import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/database/directory_repository.dart';
import '../../../../core/services/lookup_service.dart';
import '../../../../core/services/settings_service.dart';
import '../../../../core/utils/name_parser.dart';
import '../../../../core/utils/search_text_normalizer.dart';
import '../../../../core/utils/spell_check.dart';
import '../../../../core/widgets/lexicon_spell_text_form_field.dart';
import '../../../../core/widgets/spell_check_controller.dart';
import '../../../calls/models/equipment_model.dart';
import '../../../calls/models/user_model.dart';
import '../../../calls/provider/lookup_provider.dart';
import '../../../calls/provider/remote_paths_provider.dart';
import '../../../calls/utils/equipment_remote_param_key.dart';
import '../../../calls/utils/vnc_remote_target.dart';
import '../../providers/equipment_directory_provider.dart';

/// Διάλογος φόρμας για δημιουργία/επεξεργασία/αντίγραφο εξοπλισμού.
class EquipmentFormDialog extends StatefulWidget {
  const EquipmentFormDialog({
    super.key,
    this.initialEquipment,
    this.initialOwner,
    required this.notifier,
    required this.ref,
    this.isClone = false,
    this.focusedField,
    this.onSaved,
  });

  final EquipmentModel? initialEquipment;
  /// Κάτοχος για προσυμπλήρωση (από `user_equipment` / γραμμή καταλόγου).
  final UserModel? initialOwner;
  final EquipmentDirectoryNotifier notifier;
  final WidgetRef ref;
  final bool isClone;
  final String? focusedField;
  final VoidCallback? onSaved;

  @override
  State<EquipmentFormDialog> createState() => _EquipmentFormDialogState();
}

class _EquipmentFormDialogState extends State<EquipmentFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codeController;
  late final SpellCheckController _notesController;
  late final TextEditingController _ownerController;
  late final FocusNode _ownerFocusNode;
  bool _ownerTextInitialized = false;

  late final TextEditingController _departmentController;
  late final FocusNode _departmentFocusNode;
  bool _equipmentDepartmentTextInitialized = false;

  late final TextEditingController _locationController;

  int? _selectedUserId;
  /// Αποφυγή επανάληψης postFrame για συγχρονισμό τμήματος/τοποθεσίας από κάτοχο.
  int? _deptLocScheduledForUserId;

  /// Επιλογή τύπου εξοπλισμού· null = Κανένας.
  String? _selectedType;

  /// Επιλογή εργαλείου απομακρυσμένης· null ή κενό ή "Κανένα" = κανένα.
  String? _selectedRemoteTool;

  /// Τιμές παραμέτρων ανά κλειδί εργαλείου (συγχρονίζεται με `remote_params`).
  final Map<String, String> _remoteParamValues = {};
  /// Εργαλεία με ανοιχτό πεδίο επεξεργασίας (επιλεγμένο FilterChip).
  final Set<String> _expandedRemoteKeys = {};
  final Map<String, TextEditingController> _remoteParamControllers = {};

  bool get _isEdit => widget.initialEquipment != null && !widget.isClone;

  void _initRemoteParamsFromEquipment(EquipmentModel? e) {
    _remoteParamValues.clear();
    _expandedRemoteKeys.clear();
    if (e == null) return;
    for (final entry in e.remoteParams.entries) {
      final t = entry.value.trim();
      if (t.isNotEmpty) {
        _remoteParamValues[entry.key] = entry.value;
        _expandedRemoteKeys.add(entry.key);
      }
    }
    final ad = e.anydeskId?.trim();
    if (ad != null && ad.isNotEmpty) {
      final k = EquipmentRemoteParamKey.anydesk;
      if (!_remoteParamValues.containsKey(k) ||
          _remoteParamValues[k]!.trim().isEmpty) {
        _remoteParamValues[k] = ad;
      }
      _expandedRemoteKeys.add(k);
    }
    final ip = e.customIp?.trim();
    if (ip != null && ip.isNotEmpty) {
      final k = EquipmentRemoteParamKey.vnc;
      if (!_remoteParamValues.containsKey(k) ||
          _remoteParamValues[k]!.trim().isEmpty) {
        _remoteParamValues[k] = ip;
      }
      _expandedRemoteKeys.add(k);
    }
  }

  List<({String label, String key})> _toolLabelKeyPairs(List<String> labels) {
    final seen = <String>{};
    final out = <({String label, String key})>[];
    for (final l in labels) {
      final trimmed = l.trim();
      if (trimmed.isEmpty) continue;
      final k = EquipmentRemoteParamKey.forToolLabel(trimmed);
      if (seen.contains(k)) continue;
      seen.add(k);
      out.add((label: trimmed, key: k));
    }
    return out;
  }

  void _ensureRemoteController(String key) {
    if (_remoteParamControllers.containsKey(key)) return;
    _remoteParamControllers[key] = TextEditingController(
      text: _remoteParamValues[key] ?? '',
    );
  }

  void _disposeRemoteController(String key) {
    final c = _remoteParamControllers.remove(key);
    c?.dispose();
  }

  void _syncRemoteValueFromController(String key) {
    final c = _remoteParamControllers[key];
    if (c == null) return;
    final t = c.text.trim();
    if (t.isEmpty) {
      _remoteParamValues.remove(key);
    } else {
      _remoteParamValues[key] = c.text;
    }
  }

  Map<String, String> _remoteParamsForSave(List<String> toolLabels) {
    final pairs = _toolLabelKeyPairs(toolLabels);
    final out = <String, String>{};
    for (final p in pairs) {
      final c = _remoteParamControllers[p.key];
      final raw = (c?.text ?? _remoteParamValues[p.key] ?? '').trim();
      if (raw.isNotEmpty) {
        out[p.key] = p.key == EquipmentRemoteParamKey.vnc
            ? raw.replaceAll(',', '.')
            : raw;
      }
    }
    for (final entry in _remoteParamValues.entries) {
      final v = entry.value.trim();
      if (v.isEmpty) continue;
      if (out.containsKey(entry.key)) continue;
      out[entry.key] = entry.key == EquipmentRemoteParamKey.vnc
          ? v.replaceAll(',', '.')
          : v;
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    final e = widget.initialEquipment;
    _initRemoteParamsFromEquipment(e);
    _codeController = TextEditingController(text: e?.code ?? '');
    _notesController = SpellCheckController()..text = (e?.notes ?? '');
    _ownerController = TextEditingController();
    _ownerFocusNode = FocusNode();
    _departmentController = TextEditingController();
    _departmentFocusNode = FocusNode();
    final hasInitialOwner = widget.initialOwner?.id != null;
    _locationController = TextEditingController(
      text: hasInitialOwner ? '' : (e?.location ?? '').trim(),
    );
    _selectedUserId = widget.initialOwner?.id;
    final typeRaw = e?.type?.trim() ?? '';
    _selectedType = typeRaw.isEmpty ? null : typeRaw;
    final raw = e?.defaultRemoteTool?.trim() ?? '';
    _selectedRemoteTool = raw.isEmpty ? null : raw;
  }

  @override
  void dispose() {
    _codeController.dispose();
    _notesController.dispose();
    for (final c in _remoteParamControllers.values) {
      c.dispose();
    }
    _remoteParamControllers.clear();
    _ownerController.dispose();
    _ownerFocusNode.dispose();
    _departmentController.dispose();
    _departmentFocusNode.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _applyDepartmentLocationFromUser(UserModel u) {
    _departmentController.text = u.departmentName?.trim() ?? '';
    _locationController.text = (u.location ?? '').trim();
  }

  void _applyDepartmentLocationFromEquipment(EquipmentModel? e) {
    final did = e?.departmentId;
    if (did != null) {
      _departmentController.text =
          LookupService.instance.getDepartmentName(did)?.trim() ?? '';
    } else {
      _departmentController.text = '';
    }
    _locationController.text = (e?.location ?? '').trim();
  }

  Widget _departmentAutocompleteOptionsView(
    BuildContext context,
    void Function(String) onSelected,
    Iterable<String> options,
  ) {
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 4,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360, maxHeight: 220),
          child: ListView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            itemCount: options.length,
            itemBuilder: (context, index) {
              final option = options.elementAt(index);
              return ListTile(
                dense: true,
                title: Text(option),
                onTap: () => onSelected(option),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Επιλύει κείμενο κατόχου σε userId: κενό → null, match → id, αλλιώς insert νέο χρήστη.
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
    final dbOwn = await DatabaseHelper.instance.database;
    final newId = await DirectoryRepository(dbOwn).insertUser(
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
    for (final k in _expandedRemoteKeys.toList()) {
      _syncRemoteValueFromController(k);
    }
    final asyncLookup = widget.ref.read(lookupServiceProvider);
    final lookup = asyncLookup.value?.service;
    final ownerText = _ownerController.text.trim();
    final userId = await _resolveOwnerToUserId(ownerText, lookup);
    final code = _codeController.text.trim();
    final typeVal = _selectedType?.trim() ?? '';
    final deptText = _departmentController.text.trim();
    final int? equipmentDepartmentId;
    if (deptText.isEmpty) {
      equipmentDepartmentId = null;
    } else {
      final dbDept = await DatabaseHelper.instance.database;
      equipmentDepartmentId = await DirectoryRepository(dbDept)
          .getOrCreateDepartmentIdByName(deptText);
    }
    final locTrim = _locationController.text.trim();
    final toolsList = await SettingsService().getRemoteSurfaceAppsList();
    final remoteParams = _remoteParamsForSave(toolsList);
    final vncSaved = remoteParams[EquipmentRemoteParamKey.vnc]?.trim();
    final anydeskSaved = remoteParams[EquipmentRemoteParamKey.anydesk]?.trim();
    final equipment = EquipmentModel(
      id: _isEdit ? widget.initialEquipment?.id : null,
      code: code.isEmpty ? null : code,
      type: typeVal.isEmpty ? null : typeVal,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      customIp: vncSaved != null && vncSaved.isNotEmpty ? vncSaved : null,
      anydeskId: anydeskSaved != null && anydeskSaved.isNotEmpty
          ? anydeskSaved
          : null,
      remoteParams: remoteParams,
      defaultRemoteTool: _normalizedRemoteToolValue(_selectedRemoteTool),
      departmentId: equipmentDepartmentId,
      location: locTrim.isEmpty ? null : locTrim,
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
      await widget.notifier.updateEquipment(
        equipment,
        ownerUserId: userId,
      );
      if (!mounted) return;
      widget.ref.invalidate(lookupServiceProvider);
      widget.onSaved?.call();
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Αποθηκεύτηκε')));
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
    await widget.notifier.addEquipment(
      equipment,
      ownerUserId: userId,
    );
    if (!mounted) return;
    widget.ref.invalidate(lookupServiceProvider);
    widget.onSaved?.call();
    Navigator.of(context).pop(true);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Αποθηκεύτηκε')));
  }

  static const Duration _remoteAnimDuration = Duration(milliseconds: 240);

  Widget _buildRemoteParamsChipsSection(List<String> labels) {
    final pairs = _toolLabelKeyPairs(labels);
    final theme = Theme.of(context);
    if (pairs.isEmpty) {
      return Text(
        'Δεν ορίστηκαν εργαλεία απομακρυσμένης στις ρυθμίσεις.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    for (final k in _expandedRemoteKeys) {
      _ensureRemoteController(k);
    }
    final orderedExpanded = <String>[];
    final seen = <String>{};
    for (final p in pairs) {
      if (_expandedRemoteKeys.contains(p.key) && seen.add(p.key)) {
        orderedExpanded.add(p.key);
      }
    }
    for (final k in _expandedRemoteKeys) {
      if (!seen.contains(k)) {
        orderedExpanded.add(k);
        seen.add(k);
      }
    }
    String labelForKey(String key) {
      for (final p in pairs) {
        if (p.key == key) return p.label;
      }
      return key;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Παράμετροι απομακρυσμένης',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in pairs)
              FilterChip(
                label: Text(p.label),
                selected: _expandedRemoteKeys.contains(p.key),
                showCheckmark: true,
                onSelected: (sel) {
                  setState(() {
                    if (sel) {
                      _expandedRemoteKeys.add(p.key);
                      _ensureRemoteController(p.key);
                    } else {
                      _syncRemoteValueFromController(p.key);
                      _expandedRemoteKeys.remove(p.key);
                      _disposeRemoteController(p.key);
                      _remoteParamValues.remove(p.key);
                    }
                  });
                },
              ),
          ],
        ),
        AnimatedSize(
          duration: _remoteAnimDuration,
          curve: Curves.easeInOutCubic,
          alignment: Alignment.topCenter,
          child: orderedExpanded.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < orderedExpanded.length; i++) ...[
                        if (i > 0) const SizedBox(height: 10),
                        AnimatedSwitcher(
                          duration: _remoteAnimDuration,
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, -0.04),
                                end: Offset.zero,
                              ).animate(anim),
                              child: child,
                            ),
                          ),
                          child: KeyedSubtree(
                            key: ValueKey<String>(orderedExpanded[i]),
                            child: _buildRemoteParamField(
                              orderedExpanded[i],
                              labelForKey(orderedExpanded[i]),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildRemoteParamField(String paramKey, String toolLabel) {
    final c = _remoteParamControllers[paramKey];
    if (c == null) return const SizedBox.shrink();
    final isVnc = paramKey == EquipmentRemoteParamKey.vnc;
    return TextFormField(
      controller: c,
      decoration: InputDecoration(
        labelText: 'Παράμετρος · $toolLabel',
        border: const OutlineInputBorder(),
        hintText: isVnc ? 'IP ή hostname' : null,
      ),
      keyboardType: isVnc
          ? const TextInputType.numberWithOptions(decimal: true, signed: false)
          : TextInputType.text,
      inputFormatters:
          isVnc ? [CommaToDotDecimalSeparatorFormatter()] : null,
      onChanged: (_) => _syncRemoteValueFromController(paramKey),
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
                      ...options.map(
                        (o) =>
                            DropdownMenuItem<String?>(value: o, child: Text(o)),
                      ),
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
              LexiconSpellTextFormField(
                controller: _notesController,
                focusNode: null,
                decoration: const InputDecoration(
                  labelText: 'Σημειώσεις',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 3,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Consumer(
                builder: (context, ref, _) {
                  final asyncTools = ref.watch(remotePathsProvider);
                  return asyncTools.when(
                    data: (labels) => _buildRemoteParamsChipsSection(labels),
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                    error: (err, _) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Δεν φορτώθηκαν εργαλεία: $err',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  );
                },
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
                      ...options.map(
                        (o) =>
                            DropdownMenuItem<String?>(value: o, child: Text(o)),
                      ),
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
                    data: (bundle) {
                      final service = bundle.service;
                      final departmentNames = service.departments
                          .where((d) => !d.isDeleted)
                          .map((d) => d.name.trim())
                          .where((name) => name.isNotEmpty)
                          .toList();
                      if (!_equipmentDepartmentTextInitialized) {
                        final hasInitialHolder =
                            widget.initialOwner?.id != null;
                        if (hasInitialHolder) {
                          _equipmentDepartmentTextInitialized = true;
                        } else {
                          final did = widget.initialEquipment?.departmentId;
                          if (did != null) {
                            _equipmentDepartmentTextInitialized = true;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) return;
                              final name = LookupService.instance
                                      .getDepartmentName(did)
                                      ?.trim() ??
                                  '';
                              if (name.isNotEmpty) {
                                _departmentController.text = name;
                              }
                              setState(() {});
                            });
                          } else {
                            _equipmentDepartmentTextInitialized = true;
                          }
                        }
                      }
                      final holderLocksDeptLoc = _selectedUserId != null;
                      if (holderLocksDeptLoc) {
                        final uid = _selectedUserId!;
                        if (_deptLocScheduledForUserId != uid) {
                          final u = service.findUserById(uid);
                          if (u != null) {
                            _deptLocScheduledForUserId = uid;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted || _selectedUserId != uid) return;
                              _applyDepartmentLocationFromUser(u);
                              setState(() {});
                            });
                          }
                        }
                      } else {
                        _deptLocScheduledForUserId = null;
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: RawAutocomplete<String>(
                              textEditingController: _departmentController,
                              focusNode: _departmentFocusNode,
                              optionsBuilder: (textEditingValue) {
                                if (holderLocksDeptLoc) {
                                  return const Iterable<String>.empty();
                                }
                                final q = SearchTextNormalizer.normalizeForSearch(
                                  textEditingValue.text,
                                );
                                if (q.isEmpty) return departmentNames;
                                return departmentNames
                                    .where(
                                      (name) => SearchTextNormalizer
                                          .matchesNormalizedQuery(name, q),
                                    )
                                    .toList();
                              },
                              displayStringForOption: (option) => option,
                              onSelected: (selection) {
                                if (!holderLocksDeptLoc) {
                                  _departmentController.text = selection;
                                }
                              },
                              fieldViewBuilder:
                                  (context, controller, focusNode, _) {
                                return TextField(
                                  controller: controller,
                                  focusNode: focusNode,
                                  enabled: !holderLocksDeptLoc,
                                  decoration: InputDecoration(
                                    labelText: 'Τμήμα',
                                    border: const OutlineInputBorder(),
                                    helperText: holderLocksDeptLoc
                                        ? 'Καθορίζεται από τον κάτοχο'
                                        : null,
                                  ),
                                );
                              },
                              optionsViewBuilder:
                                  (context, onSelected, options) {
                                return _departmentAutocompleteOptionsView(
                                  context,
                                  onSelected,
                                  options,
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _locationController,
                              enabled: !holderLocksDeptLoc,
                              decoration: InputDecoration(
                                labelText: 'Τοποθεσία',
                                border: const OutlineInputBorder(),
                                helperText: holderLocksDeptLoc
                                    ? 'Καθορίζεται από τον κάτοχο'
                                    : null,
                              ),
                              spellCheckConfiguration:
                                  platformSpellCheckConfiguration,
                            ),
                          ),
                        ],
                      );
                    },
                    loading: () => const Row(
                      children: [
                        Expanded(
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Τμήμα',
                              border: OutlineInputBorder(),
                            ),
                            child: Text('Φόρτωση...'),
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Τοποθεσία',
                              border: OutlineInputBorder(),
                            ),
                            child: SizedBox.shrink(),
                          ),
                        ),
                      ],
                    ),
                    error: (_, _) => const Row(
                      children: [
                        Expanded(
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Τμήμα',
                              border: OutlineInputBorder(),
                            ),
                            child: Text('Σφάλμα φόρτωσης'),
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(child: SizedBox.shrink()),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              Consumer(
                builder: (context, ref, _) {
                  final async = ref.watch(lookupServiceProvider);
                  return async.when(
                    data: (bundle) {
                      final service = bundle.service;
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
                                    user.fullNameWithDepartment == selection,
                              )
                              .firstOrNull;
                          if (u != null && u.id != null) {
                            setState(() {
                              _selectedUserId = u.id;
                              _deptLocScheduledForUserId = u.id;
                              _ownerController.text =
                                  u.name ?? u.fullNameWithDepartment;
                              _applyDepartmentLocationFromUser(u);
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
                                  labelText: 'Κάτοχος',
                                  hintText:
                                      'Πληκτρολόγησε όνομα ή άφησε κενό (Άγνωστος κάτοχος)',
                                  hintStyle: theme.textTheme.bodyMedium
                                      ?.copyWith(
                                        color: theme
                                            .colorScheme
                                            .onSurfaceVariant
                                            .withValues(alpha: 0.7),
                                      ),
                                  border: const OutlineInputBorder(),
                                  suffixIcon: Semantics(
                                    label: 'Καθαρισμός Κατόχου',
                                    child: IconButton(
                                      icon: const Icon(Icons.close, size: 20),
                                      onPressed: () {
                                        textController.clear();
                                        setState(() {
                                          _selectedUserId = null;
                                          _deptLocScheduledForUserId = null;
                                          _applyDepartmentLocationFromEquipment(
                                            widget.initialEquipment,
                                          );
                                        });
                                      },
                                      tooltip: 'Καθαρισμός Κατόχου',
                                    ),
                                  ),
                                ),
                                onChanged: (value) {
                                  if (value.trim().isEmpty) {
                                    setState(() {
                                      _selectedUserId = null;
                                      _deptLocScheduledForUserId = null;
                                      _applyDepartmentLocationFromEquipment(
                                        widget.initialEquipment,
                                      );
                                    });
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
