import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/database/department_repository.dart';
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
import '../../../../core/widgets/lexicon_spell_text_form_field.dart';
import '../../../../core/widgets/resizable_text_area.dart';
import '../../../../core/widgets/spell_check_controller.dart';
import '../../../calls/models/equipment_model.dart';
import '../../../calls/models/user_model.dart';
import '../../../calls/provider/lookup_provider.dart';
import '../../../calls/provider/smart_entity_selector_provider.dart';
import '../../../calls/provider/remote_paths_provider.dart';
import '../../../../core/models/remote_tool.dart';
import '../../../calls/utils/equipment_remote_param_key.dart';
import '../../models/equipment_column.dart';
import '../../models/equipment_location_field_state.dart';
import '../../models/full_location_breadcrumb.dart';
import '../../providers/catalog_validation_provider.dart';
import '../../providers/equipment_directory_provider.dart';
import 'catalog_validation_hint_text.dart';
import 'equipment_location_follow_row.dart';
import 'full_location_line.dart';
import 'location_field_help_icon.dart';
import 'equipment_form_dismiss_guard.dart';
import 'equipment_form_remote_params.dart';

/// Διάλογος φόρμας για δημιουργία/επεξεργασία/αντίγραφο εξοπλισμού.
class EquipmentFormDialog extends ConsumerStatefulWidget {
  const EquipmentFormDialog({
    super.key,
    this.initialEquipment,
    this.initialOwner,
    required this.notifier,
    this.isClone = false,
    this.focusedField,
    this.onSaved,
  });

  final EquipmentModel? initialEquipment;

  /// Κάτοχος για προσυμπλήρωση (από `user_equipment` / γραμμή καταλόγου).
  final UserModel? initialOwner;
  final EquipmentDirectoryNotifier notifier;
  final bool isClone;
  final String? focusedField;
  final VoidCallback? onSaved;

  @override
  ConsumerState<EquipmentFormDialog> createState() =>
      EquipmentFormDialogState();
}

/// Δημόσιο State: τα πεδία της φόρμας είναι ορατά στους συνεργάτες της
/// (φρουρός κλεισίματος, παράμετροι απομακρυσμένης σύνδεσης).
///
/// Διαβάζει providers με το δικό του `ref` — ποτέ με του καλούντος, που
/// μπορεί να πάψει να υπάρχει όσο τρέχει μια αποθήκευση.
class EquipmentFormDialogState extends ConsumerState<EquipmentFormDialog> {
  /// Μήνυμα απόρριψης αποθήκευσης (διπλότυπος κωδικός, άγνωστος κάτοχος).
  ///
  /// Πάει στον **ριζικό** messenger επίτηδες: ο διάλογος ζει μέσα σε
  /// [DraggableDialogShell], που απαγορεύει ρητά τοπικό `Scaffold` — χωρίς
  /// αυτόν ένας τοπικός `ScaffoldMessenger` δεν έχει πού να δείξει και
  /// σκάει με «no descendant Scaffolds».
  void _showRejectionSnackBar(SnackBar snackBar) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(snackBar);
  }

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

  /// Εστίαση από τον πίνακα: διπλό κλικ σε κελί ανοίγει τη φόρμα στο πεδίο
  /// εκείνης της στήλης.
  late final FocusNode _codeFocusNode;
  late final FocusNode _typeFocusNode;
  late final FocusNode _locationFocusNode;
  late final FocusNode _notesFocusNode;

  late final SpellCheckController locationController;

  /// Η κατάσταση του πεδίου τοποθεσίας (διακόπτης + δική του τιμή + του κατόχου).
  late EquipmentLocationFieldState locationState;

  bool get locationFollowsOwner => locationState.followsOwner;

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
      final norm = remoteParams.isHostAddressParamKey(entry.key, catalog, pairs)
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
    _codeFocusNode = FocusNode();
    _typeFocusNode = FocusNode();
    _locationFocusNode = FocusNode();
    _notesFocusNode = FocusNode();
    locationState = EquipmentLocationFieldState.fromStored(
      storedLocation: e?.location,
      ownerLocation: widget.initialOwner?.location,
    );
    locationController = SpellCheckController()
      ..text = locationState.displayText;
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
      _applyRequestedFocus();
    });
  }

  /// Εστίαση στο πεδίο που ζήτησε ο καλών (διπλό κλικ σε κελί του πίνακα).
  ///
  /// Τα κλειδιά είναι τα `key` των στηλών του καταλόγου εξοπλισμού. Στήλες
  /// χωρίς αντίστοιχο επεξεργάσιμο πεδίο (`id`, `phone`, παράμετροι και κύριο
  /// εργαλείο) δεν εστιάζουν πουθενά: το `null` αφήνει τη φόρμα όπως ανοίγει,
  /// αντί να στείλει τον κέρσορα σε άσχετο πεδίο.
  void _applyRequestedFocus() {
    final target = switch (widget.focusedField) {
      'code' => _codeFocusNode,
      'type' => _typeFocusNode,
      'owner' => _ownerFocusNode,
      'department' => _departmentFocusNode,
      'location' => _locationFocusNode,
      'notes' => _notesFocusNode,
      _ => null,
    };
    if (target == null) return;
    target.requestFocus();
    // Το κείμενο επιλέγεται ολόκληρο ώστε η πληκτρολόγηση να το αντικαθιστά —
    // ίδια συμπεριφορά με τις φόρμες υπαλλήλου και τμήματος.
    final controller = switch (widget.focusedField) {
      'code' => codeController,
      'department' => departmentController,
      'location' => locationController,
      'notes' => notesController,
      _ => null,
    };
    if (controller == null) return;
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
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
    _codeFocusNode.dispose();
    _typeFocusNode.dispose();
    _locationFocusNode.dispose();
    _notesFocusNode.dispose();
    super.dispose();
  }

  /// Εναλλαγή του διακόπτη «Ακολουθεί τη θέση του κατόχου».
  ///
  /// Η απόφαση ανήκει στο [EquipmentLocationFieldState]· εδώ μένει μόνο ο
  /// συγχρονισμός του ορατού κειμένου.
  void setLocationFollowsOwner(bool follows) {
    setState(() {
      locationState = follows
          ? locationState.follow()
          : locationState.unfollow();
      locationController.text = locationState.displayText;
    });
  }

  /// Η κατάσταση με ενσωματωμένο ό,τι έχει πληκτρολογηθεί.
  ///
  /// Όσο ο διακόπτης είναι αναμμένος το πεδίο είναι μη επεξεργάσιμο, οπότε το
  /// κείμενό του δεν εκφράζει πρόθεση του χρήστη και αγνοείται.
  EquipmentLocationFieldState get effectiveLocationState =>
      locationState.followsOwner
      ? locationState
      : locationState.typed(locationController.text);

  /// Ο κάτοχος άλλαξε — η αναφορά ανανεώνεται, η δική του θέση μένει.
  void syncLocationOwner(String? ownerLocation) {
    final next = locationState.withOwnerLocation(ownerLocation);
    if (next.displayText == locationState.displayText) {
      locationState = next;
      return;
    }
    locationState = next;
    locationController.text = next.displayText;
  }

  /// Το τμήμα ακολουθεί τον κάτοχο — η τοποθεσία **όχι**.
  ///
  /// Αν αντιγραφόταν, θα γινόταν ρητή τιμή του εξοπλισμού: ο εξοπλισμός θα
  /// κρατούσε για πάντα το γραφείο που είχε ο κάτοχος τη στιγμή της σύνδεσης,
  /// και μια μετακόμιση του ανθρώπου δεν θα τον ακολουθούσε.
  void _applyDepartmentFromUser(UserModel u) {
    departmentController.text = u.departmentName?.trim() ?? '';
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

  /// Κανονικοποιημένο πλήρες όνομα, χωρίς το «(Τμήμα)» που προστίθεται για
  /// εμφάνιση σε λίστες.
  static String _ownerNameKey(String raw) {
    return SearchTextNormalizer.normalizeForSearch(
      NameParserUtility.stripParentheticalSuffix(raw),
    );
  }

  /// Δένει τον κάτοχο ΜΟΝΟ σε υπαρκτό υπάλληλο: επιλογή από τη λίστα ή
  /// μονοσήμαντη ακριβής αντιστοίχιση ονόματος.
  ///
  /// Ποτέ δεν δημιουργεί υπάλληλο και ποτέ δεν μαντεύει «το πρώτο αποτέλεσμα
  /// της αναζήτησης» — ένα τυπογραφικό λάθος πρέπει να σταματά την αποθήκευση,
  /// όχι να γεννά οντότητα-φάντασμα ή να αναθέτει τον εξοπλισμό σε άλλον.
  ///
  /// Επιστρέφει `error != null` όταν το κείμενο δεν δένει σε κανέναν.
  ({int? userId, String? error}) resolveOwnerBinding(
    String ownerText,
    LookupService? lookupService,
  ) {
    final text = ownerText.trim();
    if (text.isEmpty) return (userId: null, error: null);
    if (lookupService == null) {
      return (
        userId: null,
        error: 'Ο κατάλογος υπαλλήλων δεν έχει φορτώσει ακόμη.',
      );
    }

    final key = _ownerNameKey(text);
    final matches = lookupService.users
        .where(
          (u) =>
              u.id != null &&
              _ownerNameKey(u.name ?? u.fullNameWithDepartment) == key,
        )
        .toList();

    if (matches.isEmpty) {
      return (
        userId: null,
        error:
            'Δεν υπάρχει υπάλληλος «$text». Επιλέξτε υπάλληλο από τη λίστα ή '
            'δημιουργήστε τον πρώτα στην καρτέλα Υπάλληλοι.',
      );
    }
    if (matches.length > 1) {
      // Συνωνυμία: μόνο η ρητή επιλογή από τη λίστα ξεχωρίζει ποιον εννοεί.
      final picked = matches.where((u) => u.id == selectedUserId).firstOrNull;
      if (picked != null) return (userId: picked.id, error: null);
      return (
        userId: null,
        error:
            'Υπάρχουν ${matches.length} υπάλληλοι με το όνομα «$text». '
            'Επιλέξτε τον σωστό από τη λίστα.',
      );
    }
    return (userId: matches.first.id, error: null);
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
    final asyncLookup = ref.read(lookupServiceProvider);
    final lookup = asyncLookup.value?.service;
    final ownerText = ownerController.text.trim();
    final ownerBinding = resolveOwnerBinding(ownerText, lookup);
    if (ownerBinding.error != null) {
      if (!mounted) return;
      _showRejectionSnackBar(
        SnackBar(
          content: Text(ownerBinding.error!),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 6),
        ),
      );
      return;
    }
    final userId = ownerBinding.userId;
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
    // Χωρίς κάτοχο δεν υπάρχει τι να ακολουθήσει: ισχύει ό,τι γράφτηκε.
    final locTrim = userId == null
        ? locationController.text.trim()
        : (effectiveLocationState.valueToStore ?? '');
    final pairs = await ref.read(remoteToolFormPairsProvider.future);
    final catalog = await ref.read(remoteToolsCatalogProvider.future);
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
        _showRejectionSnackBar(
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
        ref.invalidate(lookupServiceProvider);
        await refreshSelectedEquipmentInAllSelectors(ref);
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
      _showRejectionSnackBar(
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
      ref.invalidate(lookupServiceProvider);
      await refreshSelectedEquipmentInAllSelectors(ref);
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
    // Κανόνες επικύρωσης (υποδείξεις, όχι απαγορεύσεις) — όσο φορτώνουν,
    // απλώς δεν εμφανίζονται υποδείξεις.
    final validation = ref
        .watch(catalogValidationServiceProvider)
        .asData
        ?.value;
    // ΧΩΡΙΣ τοπικό ScaffoldMessenger: το DraggableDialogShell απαγορεύει
    // Scaffold μέσα στον διάλογο (σκοτώνει το barrier-dismiss), οπότε ένας
    // τοπικός messenger θα ήταν νεκρός — τα μηνύματα πάνε στον ριζικό.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await dismissGuard.requestClose();
      },
      child: DraggableDialogShell(
        title: Text(_title),
        builder: (titleHandle) => AlertDialog(
          title: titleHandle,
          // Το οριζόντιο περιθώριο περνά μέσα στο scrollable, ώστε η μπάρα
          // κύλησης να μένει στην άκρη του διαλόγου και όχι πάνω στα πεδία.
          contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 24),
          content: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextFormField(
                                controller: codeController,
                                focusNode: _codeFocusNode,
                                decoration: const InputDecoration(
                                  labelText: 'Κωδικός',
                                  border: OutlineInputBorder(),
                                ),
                                validator: _requiredValidator,
                                onChanged: (_) => setState(() {}),
                              ),
                              CatalogValidationHintText(
                                hint: validation?.equipmentCodeHint(
                                  codeController.text,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FutureBuilder<List<String>>(
                            future: SettingsService().catalogs
                                .getEquipmentTypesList(),
                            builder: (context, snapshot) {
                              var options =
                                  snapshot.data ?? ['Υπολογιστής', 'Εκτυπωτής'];
                              if (selectedType != null &&
                                  selectedType!.trim().isNotEmpty &&
                                  !options.contains(selectedType)) {
                                options = [selectedType!, ...options];
                              }
                              return DropdownButtonFormField<String?>(
                                initialValue: selectedType,
                                focusNode: _typeFocusNode,
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
                    ResizableTextArea(
                      controller: notesController,
                      focusNode: _notesFocusNode,
                      decoration: const InputDecoration(
                        labelText: 'Σημειώσεις',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      minLines: 2,
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
                            if (!equipmentDepartmentTextInitialized) {
                              final hasInitialHolder =
                                  widget.initialOwner?.id != null;
                              if (hasInitialHolder) {
                                equipmentDepartmentTextInitialized = true;
                              } else {
                                final did =
                                    widget.initialEquipment?.departmentId;
                                if (did != null) {
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
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
                                      equipmentDepartmentTextInitialized = true;
                                    });
                                    dismissGuard.tryCaptureFormBaseline();
                                  });
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
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    if (!mounted || selectedUserId != uid) {
                                      return;
                                    }
                                    _applyDepartmentFromUser(u);
                                    setState(() {});
                                  });
                                }
                              }
                            } else {
                              _deptLocScheduledForUserId = null;
                            }
                            final owner = selectedUserId == null
                                ? null
                                : service.findUserById(selectedUserId!);
                            if (holderLocksDeptLoc &&
                                locationState.ownerLocation !=
                                    (owner?.location ?? '').trim()) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!mounted) return;
                                setState(
                                  () => syncLocationOwner(owner?.location),
                                );
                              });
                            }
                            final breadcrumbDeptId =
                                owner?.departmentId ??
                                service
                                    .findDepartmentByName(
                                      departmentController.text,
                                    )
                                    ?.id;
                            final fullLocation = fullLocationBreadcrumb(
                              building: service.getDepartmentBuilding(
                                breadcrumbDeptId,
                              ),
                              floor: service.getDepartmentFloor(
                                breadcrumbDeptId,
                              ),
                              department: departmentController.text,
                              location: holderLocksDeptLoc
                                  ? effectiveLocationState.displayText
                                  : locationController.text,
                            );
                            // Δύο ανεξάρτητες στήλες: ο διακόπτης ζει κάτω
                            // από το Τμήμα και η ένδειξη απόκλισης κάτω από
                            // την Τοποθεσία, ώστε η αναδίπλωσή της να
                            // απλώνεται στον κενό χώρο χωρίς να σπρώχνει
                            // τον διακόπτη.
                            final fieldsRow = Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      RawAutocomplete<String>(
                                        textEditingController:
                                            departmentController,
                                        focusNode: _departmentFocusNode,
                                        optionsBuilder: (textEditingValue) {
                                          if (holderLocksDeptLoc) {
                                            return const Iterable<
                                              String
                                            >.empty();
                                          }
                                          final q =
                                              SearchTextNormalizer.normalizeForSearch(
                                                textEditingValue.text,
                                              );
                                          if (q.isEmpty) {
                                            return departmentNames;
                                          }
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
                                            departmentController.text =
                                                selection;
                                          }
                                        },
                                        fieldViewBuilder:
                                            (
                                              context,
                                              controller,
                                              focusNode,
                                              _,
                                            ) {
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
                                      if (holderLocksDeptLoc)
                                        EquipmentLocationFollowRow(
                                          followsOwner: locationFollowsOwner,
                                          onChanged: setLocationFollowsOwner,
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  // Η ένδειξη απόκλισης ζει στο helper του
                                  // πεδίου: αναδιπλώνεται μέσα στο πλάτος του
                                  // χωρίς να τεντώνει τον διάλογο, όπως θα
                                  // έκανε ένα ελεύθερο Text.
                                  child: LexiconSpellTextFormField(
                                    controller: locationController,
                                    focusNode: _locationFocusNode,
                                    readOnly:
                                        holderLocksDeptLoc &&
                                        locationFollowsOwner,
                                    style:
                                        holderLocksDeptLoc &&
                                            locationFollowsOwner
                                        ? TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).disabledColor,
                                          )
                                        : null,
                                    decoration: InputDecoration(
                                      labelText: 'Τοποθεσία',
                                      border: const OutlineInputBorder(),
                                      suffixIcon: const LocationFieldHelpIcon(),
                                      helperText:
                                          holderLocksDeptLoc &&
                                              effectiveLocationState.diverges
                                          ? '⚠ ${equipmentLocationDivergenceNotice(ownerName: owner?.name ?? '', ownerLocation: owner?.location)}'
                                          : null,
                                      helperMaxLines: 3,
                                      helperStyle: const TextStyle(
                                        color: Color(0xFFE65100),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                fieldsRow,
                                FullLocationLine(text: fullLocation),
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
                                    setState(() => ownerTextInitialized = true);
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
                              displayStringForOption: (String option) => option,
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
                                    _applyDepartmentFromUser(u);
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
                                            'Επίλεξε υπάλληλο από τη λίστα ή άφησε κενό (Άγνωστος κάτοχος)',
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
                                          return;
                                        }
                                        // Πληκτρολόγηση πάνω σε επιλεγμένο
                                        // υπάλληλο σπάει το δέσιμο: αλλιώς
                                        // το τμήμα/τοποθεσία θα έμεναν
                                        // κλειδωμένα σε άσχετο πρόσωπο.
                                        final bound = selectedUserId;
                                        if (bound == null) return;
                                        final u = service.users
                                            .where((x) => x.id == bound)
                                            .firstOrNull;
                                        if (u == null) return;
                                        final stillMatches =
                                            _ownerNameKey(value) ==
                                            _ownerNameKey(
                                              u.name ??
                                                  u.fullNameWithDepartment,
                                            );
                                        if (!stillMatches) {
                                          setState(() {
                                            selectedUserId = null;
                                            _deptLocScheduledForUserId = null;
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
    );
  }
}
