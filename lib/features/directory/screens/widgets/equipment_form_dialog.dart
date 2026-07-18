import '../../../../core/widgets/dialog_snackbar_scope.dart' show DialogSnackbarHost;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/database/department_repository.dart';
import '../../../../core/database/user_repository.dart';
import '../../../../core/widgets/database_persistence_error_snackbar.dart';
import '../../../../core/widgets/draggable_dialog_shell.dart';
import '../../../../core/services/lookup_service.dart';
import '../../../../core/database/audit_diff_helper.dart';
import '../../../../core/database/audit_service.dart';
import '../../../../core/services/save_confirmation_summary.dart';
import '../../../../core/widgets/audit_summary_rich_text.dart';
import '../../../../core/services/settings_service.dart';
import '../../../../core/utils/name_parser.dart';
import '../../../../core/utils/search_text_normalizer.dart';
import '../../../../core/utils/spell_check.dart';
import '../../../../core/widgets/info_hint_icon.dart';
import '../../../../core/widgets/lexicon_spell_text_form_field.dart';
import '../../../../core/widgets/remote_tool_icon.dart';
import '../../../../core/widgets/spell_check_controller.dart';
import 'remote_param_help_text.dart';
import '../../../calls/models/equipment_model.dart';
import '../../../calls/models/user_model.dart';
import '../../../calls/provider/lookup_provider.dart';
import '../../../calls/provider/smart_entity_selector_provider.dart';
import '../../../calls/provider/remote_paths_provider.dart';
import '../../../../core/models/remote_tool.dart';
import '../../../../core/models/remote_tool_role.dart';
import '../../../calls/utils/equipment_remote_param_key.dart';
import '../../../calls/utils/remote_param_validator.dart';
import '../../../calls/utils/vnc_remote_target.dart';
import '../../providers/equipment_directory_provider.dart';


part 'equipment_form_dismiss_guard.dart';
part 'equipment_form_remote_params.dart';

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

/// Δηλώσεις πεδίων/μεθόδων του [_EquipmentFormDialogState] για τα θεματικά mixins.
mixin EquipmentFormDialogStateHost on State<EquipmentFormDialog> {
  TextEditingController get _codeController;
  SpellCheckController get _notesController;
  TextEditingController get _ownerController;
  TextEditingController get _departmentController;
  TextEditingController get _locationController;
  String? get _selectedType;
  int? get _selectedUserId;
  int? get _defaultRemoteToolId;
  int? get _exclusiveRemoteToolId;
  set _exclusiveRemoteToolId(int? value);
  Map<String, String> get _remoteParamValues;
  Set<String> get _expandedRemoteKeys;
  Map<String, TextEditingController> get _remoteParamControllers;
  bool get _ownerTextInitialized;
  bool get _equipmentDepartmentTextInitialized;
  bool get _didPruneUnknownRemoteKeys;
  set _didPruneUnknownRemoteKeys(bool value);
  bool get _formBaselineCaptured;
  set _formBaselineCaptured(bool value);
  String get _initialFormSignature;
  set _initialFormSignature(String value);
  bool get _isEdit;
  bool get _isDirty;
  Future<void> _save();
  void _tryCaptureFormBaseline();
}

class _EquipmentFormDialogState extends State<EquipmentFormDialog>
    with
        DialogSnackbarHost,
        EquipmentFormDialogStateHost,
        EquipmentFormDismissGuardMixin,
        EquipmentFormRemoteParamsMixin {
  final _formKey = GlobalKey<FormState>();
  @override
  late final TextEditingController _codeController;
  @override
  late final SpellCheckController _notesController;
  @override
  late final TextEditingController _ownerController;
  late final FocusNode _ownerFocusNode;
  @override
  bool _ownerTextInitialized = false;

  @override
  late final TextEditingController _departmentController;
  late final FocusNode _departmentFocusNode;
  @override
  bool _equipmentDepartmentTextInitialized = false;

  @override
  late final TextEditingController _locationController;

  @override
  int? _selectedUserId;
  /// Αποφυγή επανάληψης postFrame για συγχρονισμό τμήματος/τοποθεσίας από κάτοχο.
  int? _deptLocScheduledForUserId;

  /// Επιλογή τύπου εξοπλισμού· null = Κανένας.
  @override
  String? _selectedType;

  /// Προεπιλεγμένο εργαλείο (id)· υπολογίζεται από τα επιλεγμένα chips κατά `sort_order`.
  @override
  int? _defaultRemoteToolId;

  /// Αποκλειστικό εργαλείο για κλήση (id)· αποθηκεύεται στο `remote_params`.
  @override
  int? _exclusiveRemoteToolId;

  /// Τιμές παραμέτρων ανά κλειδί εργαλείου (συγχρονίζεται με `remote_params`).
  @override
  final Map<String, String> _remoteParamValues = {};
  /// Εργαλεία με ανοιχτό πεδίο επεξεργασίας (επιλεγμένο FilterChip).
  @override
  final Set<String> _expandedRemoteKeys = {};
  @override
  final Map<String, TextEditingController> _remoteParamControllers = {};
  /// Μία φορά μετά φόρτωση καταλόγου: αφαίρεση κλειδιών που δεν αντιστοιχούν σε ενεργό εργαλείο.
  @override
  bool _didPruneUnknownRemoteKeys = false;

  @override
  bool get _isEdit => widget.initialEquipment != null && !widget.isClone;

  /// Στιγμιότυπο αρχικής κατάστασης μετά ολοκλήρωση bootstrap (prefill/async).
  @override
  late String _initialFormSignature;
  @override
  bool _formBaselineCaptured = false;

  @override
  bool get _isDirty =>
      _formBaselineCaptured && _formStateSignature() != _initialFormSignature;

  bool get _canSubmitSave =>
      _isDirty && (_isEdit ? true : _createHasRequiredFields);

  void _markFormChanged() => setState(() {});
  Map<String, String> _remoteParamsForSave(
    List<RemoteToolFormPair> pairs,
    List<RemoteTool> catalog,
  ) {
    for (final k in _expandedRemoteKeys.toList()) {
      _syncRemoteValueFromController(k);
    }
    final out = <String, String>{};
    for (final k in _expandedRemoteKeys) {
      final v = (_remoteParamValues[k] ?? '').trim();
      if (v.isEmpty) continue;
      final norm = _isHostAddressParamKey(k, catalog, pairs)
          ? v.replaceAll(',', '.')
          : v;
      out[k] = norm;
    }
    for (final entry in _remoteParamValues.entries) {
      if (_expandedRemoteKeys.contains(entry.key)) continue;
      if (EquipmentRemoteParamKey.isReservedKey(entry.key)) continue;
      final v = entry.value.trim();
      if (v.isEmpty) continue;
      final norm = _isHostAddressParamKey(entry.key, catalog, pairs)
          ? v.replaceAll(',', '.')
          : v;
      out[EquipmentRemoteParamKey.remoteParamStashKeyFor(entry.key)] = norm;
    }
    final effectiveId = (_exclusiveRemoteToolId != null &&
            _expandedRemoteKeys.contains('$_exclusiveRemoteToolId'))
        ? _exclusiveRemoteToolId
        : null;
    return EquipmentRemoteParamKey.withExclusiveToolId(out, effectiveId);
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
    // Το «κύριο» εργαλείο είναι πλέον υπολογιζόμενο (σειρά προτεραιότητας) — δεν
    // αποθηκεύεται. Κρατιέται null ώστε το `default_remote_tool` να καθαρίζει.
    _defaultRemoteToolId = null;
    // Πάντα (και σε νέο εξοπλισμό): γεμίζει τα πεδία παραμέτρων ανά εργαλείο από
    // τον κατάλογο ώστε να αποδοθούν όλες οι Ζώνες.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pruneRemoteParamsAfterCatalogLoad();
    });
    if (_selectedUserId == null) {
      _ownerTextInitialized = true;
    }
    for (final c in [
      _codeController,
      _ownerController,
      _departmentController,
      _locationController,
    ]) {
      c.addListener(_markFormChanged);
    }
    _notesController.addListener(_markFormChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _tryCaptureFormBaseline();
    });
  }

  @override
  void dispose() {
    for (final c in [
      _codeController,
      _ownerController,
      _departmentController,
      _locationController,
    ]) {
      c.removeListener(_markFormChanged);
    }
    _notesController.removeListener(_markFormChanged);
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
    final newId = await UserRepository(dbOwn).insertUser(
      firstName: parsed.firstName,
      lastName: parsed.lastName,
    );
    return newId;
  }

  /// null, κενό ή "Κανένα" → null· αλλιώς επιστρέφει το trim string.
  String? _requiredValidator(String? v) =>
      (v?.trim().isEmpty ?? true) ? 'Υποχρεωτικό' : null;

  @override
  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    for (final k in _expandedRemoteKeys.toList()) {
      _syncRemoteValueFromController(k);
    }
    try {
      await _savePersist();
    } catch (e, st) {
      if (!mounted) return;
      showDatabasePersistenceErrorSnackBar(context, e, st);
    }
  }

  Future<void> _savePersist() async {
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
      equipmentDepartmentId = await DepartmentRepository(dbDept)
          .getOrCreateDepartmentIdByName(deptText);
    }
    final locTrim = _locationController.text.trim();
    final pairs = await widget.ref.read(remoteToolFormPairsProvider.future);
    final catalog = await widget.ref.read(remoteToolsCatalogProvider.future);
    final remoteParams = _remoteParamsForSave(pairs, catalog);
    final equipment = EquipmentModel(
      id: _isEdit ? widget.initialEquipment?.id : null,
      code: code.isEmpty ? null : code,
      type: typeVal.isEmpty ? null : typeVal,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      remoteParams: remoteParams,
      defaultRemoteTool: null,
      departmentId: equipmentDepartmentId,
      location: locTrim.isEmpty ? null : locTrim,
    );
    if (_isEdit) {
      if (equipment.id != null &&
          widget.notifier.hasDuplicateCode(code, excludeId: equipment.id)) {
        if (!mounted) return;
        showDialogSnackBar(
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
      final savedMessage = await _buildEditSaveConfirmationMessage(
        equipment: equipment,
        catalog: catalog,
        newRemoteParams: remoteParams,
      );
      try {
        widget.ref.invalidate(lookupServiceProvider);
        await refreshSelectedEquipmentInAllSelectors(widget.ref);
      } catch (_) {
        if (!mounted) return;
        widget.onSaved?.call();
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Αποθηκεύτηκε, αλλά η οθόνη κλήσεων ίσως δείχνει παλιές τιμές — επιλέξτε ξανά τον εξοπλισμό.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      if (!mounted) return;
      widget.onSaved?.call();
      Navigator.of(context).pop(true);
      showSaveConfirmationSnackBar(context, savedMessage);
      return;
    }
    if (widget.notifier.hasDuplicateCode(code)) {
      if (!mounted) return;
      showDialogSnackBar(
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
    try {
      widget.ref.invalidate(lookupServiceProvider);
      await refreshSelectedEquipmentInAllSelectors(widget.ref);
    } catch (_) {
      if (!mounted) return;
      widget.onSaved?.call();
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Αποθηκεύτηκε, αλλά η οθόνη κλήσεων ίσως δείχνει παλιές τιμές — επιλέξτε ξανά τον εξοπλισμό.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (!mounted) return;
    widget.onSaved?.call();
    Navigator.of(context).pop(true);
    final createMessage = 'Δημιουργήθηκε εξοπλισμός «$code»';
    showSaveConfirmationSnackBar(context, createMessage);
  }

  Future<String> _buildEditSaveConfirmationMessage({
    required EquipmentModel equipment,
    required List<RemoteTool> catalog,
    required Map<String, String> newRemoteParams,
  }) async {
    final oldMap = Map<String, dynamic>.from(widget.initialEquipment!.toMap())
      ..remove('remote_params');
    final newMap = Map<String, dynamic>.from(equipment.toMap())
      ..remove('remote_params');
    final fieldMessage = buildSaveConfirmationMessage(
      entityType: AuditEntityTypes.equipment,
      entityLabel: equipment.code ?? '',
      oldMap: oldMap,
      newMap: newMap,
      isNew: false,
    );

    final initial = widget.initialEquipment?.remoteParams ?? const {};
    final toolNames = {for (final tool in catalog) tool.id: tool.name};
    final remoteLines = AuditDiffHelper.describeRemoteParamsDiffLines(
      oldValue: initial,
      newValue: newRemoteParams,
      toolNames: toolNames,
    );

    if (remoteLines.isEmpty) return fieldMessage;

    if (fieldMessage == kSaveConfirmationNoChangesMessage) {
      return 'Αποθηκεύτηκε — εξοπλισμός «${equipment.code}»\n'
          '${remoteLines.join('\n')}';
    }
    return '$fieldMessage\n${remoteLines.join('\n')}';
  }
  String get _title {
    if (_isEdit) return 'Επεξεργασία εξοπλισμού';
    if (widget.isClone) return 'Αντίγραφο εξοπλισμού';
    return 'Νέος εξοπλισμός';
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: dialogMessengerKey,
      child: PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _requestClose();
      },
      child: DraggableDialogShell(
        title: Text(_title),
        builder: (titleHandle) => AlertDialog(
      title: titleHandle,
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _codeController,
                      decoration: const InputDecoration(
                        labelText: 'Κωδικός',
                        border: OutlineInputBorder(),
                      ),
                      validator: _requiredValidator,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FutureBuilder<List<String>>(
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
                          decoration: const InputDecoration(
                            labelText: 'Τύπος',
                            border: OutlineInputBorder(),
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
                    ),
                  ),
                ],
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
                minLines: 2,
                maxLines: null,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Consumer(
                builder: (context, ref, _) {
                  final pairsAsync = ref.watch(remoteToolFormPairsProvider);
                  final catalogAsync = ref.watch(remoteToolsCatalogProvider);
                  return pairsAsync.when(
                    data: (pairs) => catalogAsync.when(
                      data: (catalog) =>
                          _buildRemoteParamsSection(pairs, catalog),
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                      error: (err, _) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Κατάλογος εργαλείων: $err',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
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
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) return;
                              final name = LookupService.instance
                                      .getDepartmentName(did)
                                      ?.trim() ??
                                  '';
                              if (name.isNotEmpty) {
                                _departmentController.text = name;
                              }
                              setState(() {
                                _equipmentDepartmentTextInitialized = true;
                              });
                              _tryCaptureFormBaseline();
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
                              _tryCaptureFormBaseline();
                            }
                          });
                        } else {
                          _ownerTextInitialized = true;
                          _tryCaptureFormBaseline();
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
      ),
      actions: [
        TextButton(
          onPressed: _cancelAndClose,
          child: const Text('Ακύρωση'),
        ),
        FilledButton(
          onPressed: _canSubmitSave ? _save : null,
          child: Text(_isEdit ? 'Αποθήκευση' : 'Προσθήκη'),
        ),
      ],
      ),
      ),
      ),
    );
  }
}
