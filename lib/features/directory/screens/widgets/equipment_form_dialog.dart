import '../../../../core/widgets/dialog_snackbar_scope.dart'
    show DialogSnackbarHost;
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
import '../../../../core/widgets/lexicon_spell_text_form_field.dart';
import '../../../../core/widgets/spell_check_controller.dart';
import '../../../calls/models/equipment_model.dart';
import '../../../calls/models/user_model.dart';
import '../../../calls/provider/lookup_provider.dart';
import '../../../calls/provider/smart_entity_selector_provider.dart';
import '../../../calls/provider/remote_paths_provider.dart';
import '../../../../core/models/remote_tool.dart';
import '../../../calls/utils/equipment_remote_param_key.dart';
import '../../providers/equipment_directory_provider.dart';
import 'equipment_form_dismiss_guard.dart';
import 'equipment_form_remote_params.dart';

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
  State<EquipmentFormDialog> createState() => EquipmentFormDialogState();
}

/// Δημόσιο State: τα πεδία της φόρμας είναι ορατά στους συνεργάτες της
/// (φρουρός κλεισίματος, παράμετροι απομακρυσμένης σύνδεσης).
class EquipmentFormDialogState extends State<EquipmentFormDialog>
    with DialogSnackbarHost {
  /// Φρουρός κλεισίματος (υπογραφή/dirty + διάλογοι αλλαγών).
  late final EquipmentFormDismissGuard dismissGuard = EquipmentFormDismissGuard(
    this,
  );

  /// Παράμετροι απομακρυσμένης σύνδεσης (Ζώνες Α/Β).
  late final EquipmentFormRemoteParams remoteParams = EquipmentFormRemoteParams(
    this,
  );

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController codeController;
  late final SpellCheckController notesController;
  late final TextEditingController ownerController;
  late final FocusNode _ownerFocusNode;
  bool ownerTextInitialized = false;

  late final TextEditingController departmentController;
  late final FocusNode _departmentFocusNode;
  bool equipmentDepartmentTextInitialized = false;

  late final TextEditingController locationController;

  int? selectedUserId;

  /// Αποφυγή επανάληψης postFrame για συγχρονισμό τμήματος/τοποθεσίας από κάτοχο.
  int? _deptLocScheduledForUserId;

  /// Επιλογή τύπου εξοπλισμού· null = Κανένας.
  String? selectedType;

  /// Προεπιλεγμένο εργαλείο (id)· υπολογίζεται από τα επιλεγμένα chips κατά `sort_order`.
  int? defaultRemoteToolId;

  /// Αποκλειστικό εργαλείο για κλήση (id)· αποθηκεύεται στο `remote_params`.
  int? exclusiveRemoteToolId;

  /// Τιμές παραμέτρων ανά κλειδί εργαλείου (συγχρονίζεται με `remote_params`).
  final Map<String, String> remoteParamValues = {};

  /// Εργαλεία με ανοιχτό πεδίο επεξεργασίας (επιλεγμένο FilterChip).
  final Set<String> expandedRemoteKeys = {};
  final Map<String, TextEditingController> remoteParamControllers = {};

  /// Μία φορά μετά φόρτωση καταλόγου: αφαίρεση κλειδιών που δεν αντιστοιχούν σε ενεργό εργαλείο.
  bool didPruneUnknownRemoteKeys = false;

  bool get isEdit => widget.initialEquipment != null && !widget.isClone;

  /// Στιγμιότυπο αρχικής κατάστασης μετά ολοκλήρωση bootstrap (prefill/async).
  late String initialFormSignature;
  bool formBaselineCaptured = false;

  bool get _canSubmitSave =>
      dismissGuard.isDirty &&
      (isEdit ? true : dismissGuard.createHasRequiredFields);

  /// Σηματοδοτεί αλλαγή φόρμας (rebuild) — χρησιμοποιείται και από συνεργάτες.
  void markFormChanged() => setState(() {});

  Map<String, String> _remoteParamsForSave(
    List<RemoteToolFormPair> pairs,
    List<RemoteTool> catalog,
  ) {
    for (final k in expandedRemoteKeys.toList()) {
      remoteParams.syncValueFromController(k);
    }
    final out = <String, String>{};
    for (final k in expandedRemoteKeys) {
      final v = (remoteParamValues[k] ?? '').trim();
      if (v.isEmpty) continue;
      final norm = remoteParams.isHostAddressParamKey(k, catalog, pairs)
          ? v.replaceAll(',', '.')
          : v;
      out[k] = norm;
    }
    for (final entry in remoteParamValues.entries) {
      if (expandedRemoteKeys.contains(entry.key)) continue;
      if (EquipmentRemoteParamKey.isReservedKey(entry.key)) continue;
      final v = entry.value.trim();
      if (v.isEmpty) continue;
      final norm =
          remoteParams.isHostAddressParamKey(entry.key, catalog, pairs)
          ? v.replaceAll(',', '.')
          : v;
      out[EquipmentRemoteParamKey.remoteParamStashKeyFor(entry.key)] = norm;
    }
    final effectiveId =
        (exclusiveRemoteToolId != null &&
            expandedRemoteKeys.contains('$exclusiveRemoteToolId'))
        ? exclusiveRemoteToolId
        : null;
    return EquipmentRemoteParamKey.withExclusiveToolId(out, effectiveId);
  }

  @override
  void initState() {
    super.initState();
    final e = widget.initialEquipment;
    remoteParams.initFromEquipment(e);
    codeController = TextEditingController(text: e?.code ?? '');
    notesController = SpellCheckController()..text = (e?.notes ?? '');
    ownerController = TextEditingController();
    _ownerFocusNode = FocusNode();
    departmentController = TextEditingController();
    _departmentFocusNode = FocusNode();
    final hasInitialOwner = widget.initialOwner?.id != null;
    locationController = TextEditingController(
      text: hasInitialOwner ? '' : (e?.location ?? '').trim(),
    );
    selectedUserId = widget.initialOwner?.id;
    final typeRaw = e?.type?.trim() ?? '';
    selectedType = typeRaw.isEmpty ? null : typeRaw;
    // Το «κύριο» εργαλείο είναι πλέον υπολογιζόμενο (σειρά προτεραιότητας) — δεν
    // αποθηκεύεται. Κρατιέται null ώστε το `default_remote_tool` να καθαρίζει.
    defaultRemoteToolId = null;
    // Πάντα (και σε νέο εξοπλισμό): γεμίζει τα πεδία παραμέτρων ανά εργαλείο από
    // τον κατάλογο ώστε να αποδοθούν όλες οι Ζώνες.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      remoteParams.pruneAfterCatalogLoad();
    });
    if (selectedUserId == null) {
      ownerTextInitialized = true;
    }
    for (final c in [
      codeController,
      ownerController,
      departmentController,
      locationController,
    ]) {
      c.addListener(markFormChanged);
    }
    notesController.addListener(markFormChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      dismissGuard.tryCaptureFormBaseline();
    });
  }

  @override
  void dispose() {
    for (final c in [
      codeController,
      ownerController,
      departmentController,
      locationController,
    ]) {
      c.removeListener(markFormChanged);
    }
    notesController.removeListener(markFormChanged);
    codeController.dispose();
    notesController.dispose();
    for (final c in remoteParamControllers.values) {
      c.dispose();
    }
    remoteParamControllers.clear();
    ownerController.dispose();
    _ownerFocusNode.dispose();
    departmentController.dispose();
    _departmentFocusNode.dispose();
    locationController.dispose();
    super.dispose();
  }

  void _applyDepartmentLocationFromUser(UserModel u) {
    departmentController.text = u.departmentName?.trim() ?? '';
    locationController.text = (u.location ?? '').trim();
  }

  void _applyDepartmentLocationFromEquipment(EquipmentModel? e) {
    final did = e?.departmentId;
    if (did != null) {
      departmentController.text =
          LookupService.instance.getDepartmentName(did)?.trim() ?? '';
    } else {
      departmentController.text = '';
    }
    locationController.text = (e?.location ?? '').trim();
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
    final newId = await UserRepository(
      dbOwn,
    ).insertUser(firstName: parsed.firstName, lastName: parsed.lastName);
    return newId;
  }

  /// null, κενό ή "Κανένα" → null· αλλιώς επιστρέφει το trim string.
  String? _requiredValidator(String? v) =>
      (v?.trim().isEmpty ?? true) ? 'Υποχρεωτικό' : null;

  Future<void> save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    for (final k in expandedRemoteKeys.toList()) {
      remoteParams.syncValueFromController(k);
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
    final ownerText = ownerController.text.trim();
    final userId = await _resolveOwnerToUserId(ownerText, lookup);
    final code = codeController.text.trim();
    final typeVal = selectedType?.trim() ?? '';
    final deptText = departmentController.text.trim();
    final int? equipmentDepartmentId;
    if (deptText.isEmpty) {
      equipmentDepartmentId = null;
    } else {
      final dbDept = await DatabaseHelper.instance.database;
      equipmentDepartmentId = await DepartmentRepository(
        dbDept,
      ).getOrCreateDepartmentIdByName(deptText);
    }
    final locTrim = locationController.text.trim();
    final pairs = await widget.ref.read(remoteToolFormPairsProvider.future);
    final catalog = await widget.ref.read(remoteToolsCatalogProvider.future);
    final remoteParamsMap = _remoteParamsForSave(pairs, catalog);
    final equipment = EquipmentModel(
      id: isEdit ? widget.initialEquipment?.id : null,
      code: code.isEmpty ? null : code,
      type: typeVal.isEmpty ? null : typeVal,
      notes: notesController.text.trim().isEmpty
          ? null
          : notesController.text.trim(),
      remoteParams: remoteParamsMap,
      defaultRemoteTool: null,
      departmentId: equipmentDepartmentId,
      location: locTrim.isEmpty ? null : locTrim,
    );
    if (isEdit) {
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
      await widget.notifier.updateEquipment(equipment, ownerUserId: userId);
      if (!mounted) return;
      final savedMessage = await _buildEditSaveConfirmationMessage(
        equipment: equipment,
        catalog: catalog,
        newRemoteParams: remoteParamsMap,
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
    await widget.notifier.addEquipment(equipment, ownerUserId: userId);
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
    if (isEdit) return 'Επεξεργασία εξοπλισμού';
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
          await dismissGuard.requestClose();
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
                              controller: codeController,
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
                              future: SettingsService().catalogs.getEquipmentTypesList(),
                              builder: (context, snapshot) {
                                var options =
                                    snapshot.data ??
                                    ['Υπολογιστής', 'Εκτυπωτής'];
                                if (selectedType != null &&
                                    selectedType!.trim().isNotEmpty &&
                                    !options.contains(selectedType)) {
                                  options = [selectedType!, ...options];
                                }
                                return DropdownButtonFormField<String?>(
                                  initialValue: selectedType,
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
                                      setState(() => selectedType = v),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      LexiconSpellTextFormField(
                        controller: notesController,
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
                          final pairsAsync = ref.watch(
                            remoteToolFormPairsProvider,
                          );
                          final catalogAsync = ref.watch(
                            remoteToolsCatalogProvider,
                          );
                          return pairsAsync.when(
                            data: (pairs) => catalogAsync.when(
                              data: (catalog) =>
                                  remoteParams.buildSection(pairs, catalog),
                              loading: () => const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: LinearProgressIndicator(minHeight: 2),
                              ),
                              error: (err, _) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
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
                              if (!equipmentDepartmentTextInitialized) {
                                final hasInitialHolder =
                                    widget.initialOwner?.id != null;
                                if (hasInitialHolder) {
                                  equipmentDepartmentTextInitialized = true;
                                } else {
                                  final did =
                                      widget.initialEquipment?.departmentId;
                                  if (did != null) {
                                    WidgetsBinding.instance.addPostFrameCallback(
                                      (_) {
                                        if (!mounted) return;
                                        final name =
                                            LookupService.instance
                                                .getDepartmentName(did)
                                                ?.trim() ??
                                            '';
                                        if (name.isNotEmpty) {
                                          departmentController.text = name;
                                        }
                                        setState(() {
                                          equipmentDepartmentTextInitialized =
                                              true;
                                        });
                                        dismissGuard.tryCaptureFormBaseline();
                                      },
                                    );
                                  } else {
                                    equipmentDepartmentTextInitialized = true;
                                  }
                                }
                              }
                              final holderLocksDeptLoc = selectedUserId != null;
                              if (holderLocksDeptLoc) {
                                final uid = selectedUserId!;
                                if (_deptLocScheduledForUserId != uid) {
                                  final u = service.findUserById(uid);
                                  if (u != null) {
                                    _deptLocScheduledForUserId = uid;
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          if (!mounted ||
                                              selectedUserId != uid) {
                                            return;
                                          }
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
                                      textEditingController:
                                          departmentController,
                                      focusNode: _departmentFocusNode,
                                      optionsBuilder: (textEditingValue) {
                                        if (holderLocksDeptLoc) {
                                          return const Iterable<String>.empty();
                                        }
                                        final q =
                                            SearchTextNormalizer.normalizeForSearch(
                                              textEditingValue.text,
                                            );
                                        if (q.isEmpty) return departmentNames;
                                        return departmentNames
                                            .where(
                                              (name) =>
                                                  SearchTextNormalizer.matchesNormalizedQuery(
                                                    name,
                                                    q,
                                                  ),
                                            )
                                            .toList();
                                      },
                                      displayStringForOption: (option) =>
                                          option,
                                      onSelected: (selection) {
                                        if (!holderLocksDeptLoc) {
                                          departmentController.text = selection;
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
                                                border:
                                                    const OutlineInputBorder(),
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
                                      controller: locationController,
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
                              if (selectedUserId != null &&
                                  !ownerTextInitialized) {
                                final u = service.users
                                    .where((u) => u.id == selectedUserId)
                                    .firstOrNull;
                                if (u != null) {
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    if (mounted) {
                                      ownerController.text =
                                          u.fullNameWithDepartment;
                                      setState(
                                        () => ownerTextInitialized = true,
                                      );
                                      dismissGuard.tryCaptureFormBaseline();
                                    }
                                  });
                                } else {
                                  ownerTextInitialized = true;
                                  dismissGuard.tryCaptureFormBaseline();
                                }
                              }
                              final theme = Theme.of(context);
                              return Autocomplete<String>(
                                displayStringForOption: (String option) =>
                                    option,
                                focusNode: _ownerFocusNode,
                                textEditingController: ownerController,
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
                                      selectedUserId = u.id;
                                      _deptLocScheduledForUserId = u.id;
                                      ownerController.text =
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
                                              icon: const Icon(
                                                Icons.close,
                                                size: 20,
                                              ),
                                              onPressed: () {
                                                textController.clear();
                                                setState(() {
                                                  selectedUserId = null;
                                                  _deptLocScheduledForUserId =
                                                      null;
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
                                              selectedUserId = null;
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
                onPressed: dismissGuard.cancelAndClose,
                child: const Text('Ακύρωση'),
              ),
              FilledButton(
                onPressed: _canSubmitSave ? save : null,
                child: Text(isEdit ? 'Αποθήκευση' : 'Προσθήκη'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
