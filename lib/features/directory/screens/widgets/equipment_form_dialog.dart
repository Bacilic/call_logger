import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/database/department_repository.dart';
import '../../../../core/database/user_repository.dart';
import '../../../../core/widgets/database_persistence_error_snackbar.dart';
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
import '../../../../core/database/remote_tools_repository.dart';
import '../../../../core/models/remote_tool.dart';
import '../../../../core/models/remote_tool_role.dart';
import '../../../calls/utils/equipment_remote_param_key.dart';
import '../../../calls/utils/vnc_remote_target.dart';
import '../../providers/equipment_directory_provider.dart';

enum _EditDismissAction { save, discard, keepEditing }

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

  /// Προεπιλεγμένο εργαλείο (id)· υπολογίζεται από τα επιλεγμένα chips κατά `sort_order`.
  int? _defaultRemoteToolId;

  /// Τιμές παραμέτρων ανά κλειδί εργαλείου (συγχρονίζεται με `remote_params`).
  final Map<String, String> _remoteParamValues = {};
  /// Εργαλεία με ανοιχτό πεδίο επεξεργασίας (επιλεγμένο FilterChip).
  final Set<String> _expandedRemoteKeys = {};
  final Map<String, TextEditingController> _remoteParamControllers = {};
  /// Μία φορά μετά φόρτωση καταλόγου: αφαίρεση κλειδιών που δεν αντιστοιχούν σε ενεργό εργαλείο.
  bool _didPruneUnknownRemoteKeys = false;

  bool get _isEdit => widget.initialEquipment != null && !widget.isClone;

  /// Στιγμιότυπο αρχικής κατάστασης μετά ολοκλήρωση bootstrap (prefill/async).
  late String _initialFormSignature;
  bool _formBaselineCaptured = false;

  bool get _isDirty =>
      _formBaselineCaptured && _formStateSignature() != _initialFormSignature;

  /// Νέος εξοπλισμός: υποχρεωτικός κωδικός πριν επιτραπεί αποθήκευση.
  bool get _createHasRequiredFields => _codeController.text.trim().isNotEmpty;

  bool get _canSubmitSave =>
      _isDirty && (_isEdit ? true : _createHasRequiredFields);

  bool get _shouldConfirmDismissOnClose {
    if (!_formBaselineCaptured) return false;
    if (_isEdit) return _isDirty;
    return _createHasRequiredFields && _isDirty;
  }

  void _markFormChanged() => setState(() {});

  String _formStateSignature() {
    final sb = StringBuffer()
      ..write(_codeController.text)
      ..write('\u001e')
      ..write(_selectedType ?? '')
      ..write('\u001e')
      ..write(_notesController.text)
      ..write('\u001e')
      ..write(_selectedUserId ?? '')
      ..write('\u001e')
      ..write(_ownerController.text)
      ..write('\u001e')
      ..write(_departmentController.text)
      ..write('\u001e')
      ..write(_locationController.text)
      ..write('\u001e')
      ..write(_defaultRemoteToolId ?? '');
    final remoteKeys = <String>{
      ..._expandedRemoteKeys,
      ..._remoteParamValues.keys,
    }.toList()
      ..sort();
    for (final k in remoteKeys) {
      sb
        ..write('\u001e')
        ..write(k)
        ..write('\u001f')
        ..write(_remoteParamValues[k] ?? '')
        ..write('\u001f')
        ..write(_expandedRemoteKeys.contains(k));
    }
    return sb.toString();
  }

  void _tryCaptureFormBaseline() {
    if (_formBaselineCaptured) return;
    if (widget.initialOwner?.id != null && !_ownerTextInitialized) return;
    if (!_equipmentDepartmentTextInitialized) return;
    if (widget.initialEquipment != null && !_didPruneUnknownRemoteKeys) {
      return;
    }
    _initialFormSignature = _formStateSignature();
    _formBaselineCaptured = true;
  }

  List<String> _buildChangedFieldLabels() {
    if (!_formBaselineCaptured) return const [];
    final init = _initialFormSignature.split('\u001e');
    String initAt(int i) => i < init.length ? init[i] : '';

    final labels = <String>[];
    if (_codeController.text != initAt(0)) labels.add('Κωδικός');
    if ((_selectedType ?? '') != initAt(1)) labels.add('Τύπος');
    if (_notesController.text != initAt(2)) labels.add('Σημειώσεις');
    if ('${_selectedUserId ?? ''}' != initAt(3) ||
        _ownerController.text != initAt(4)) {
      labels.add('Κάτοχος');
    }
    if (_departmentController.text != initAt(5)) labels.add('Τμήμα');
    if (_locationController.text != initAt(6)) labels.add('Τοποθεσία');
    if ('${_defaultRemoteToolId ?? ''}' != initAt(7)) {
      labels.add('Προεπιλεγμένο εργαλείο');
    }
    final initRemote = init.length > 8 ? init.sublist(8).join('\u001e') : '';
    final curRemote = _formStateSignature().split('\u001e');
    final curRemoteTail =
        curRemote.length > 8 ? curRemote.sublist(8).join('\u001e') : '';
    if (initRemote != curRemoteTail) {
      labels.add('Απομακρυσμένη σύνδεση');
    }
    return labels;
  }

  Future<_EditDismissAction?> _showEditDismissDialog(
    List<String> changedLabels,
  ) {
    return showDialog<_EditDismissAction>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Μη αποθηκευμένες αλλαγές'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Έχουν γίνει αλλαγές:'),
                const SizedBox(height: 8),
                for (final label in changedLabels) Text('• $label'),
                const SizedBox(height: 12),
                const Text('Θέλεται να γίνει:'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_EditDismissAction.save),
            child: const Text('Διατήρηση'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(_EditDismissAction.discard),
            child: const Text('Ακύρωση Αλλαγών'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(_EditDismissAction.keepEditing),
            child: const Text('Επεξεργασία'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showNewDismissDialog() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Μη αποθηκευμένα στοιχεία'),
        content: const Text(
          'Έχετε συμπληρώσει κωδικό εξοπλισμού χωρίς αποθήκευση. '
          'Να κλείσει ο διάλογος;',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Επεξεργασία'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Ακύρωση Αλλαγών'),
          ),
        ],
      ),
    );
  }

  Future<void> _requestClose() async {
    _tryCaptureFormBaseline();
    if (!_shouldConfirmDismissOnClose) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    if (_isEdit) {
      final labels = _buildChangedFieldLabels();
      if (labels.isEmpty) {
        if (mounted) Navigator.of(context).pop();
        return;
      }
      final action = await _showEditDismissDialog(labels);
      switch (action) {
        case _EditDismissAction.save:
          await _save();
        case _EditDismissAction.discard:
          if (mounted) Navigator.of(context).pop();
        case _EditDismissAction.keepEditing:
        case null:
          break;
      }
      return;
    }

    final discard = await _showNewDismissDialog();
    if (discard == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  /// Κουμπί «Ακύρωση»: κλείσιμο χωρίς διάλογο επιβεβαίωσης (εκούσια απόρριψη).
  void _cancelAndClose() {
    if (mounted) Navigator.of(context).pop();
  }

  void _initRemoteParamsFromEquipment(EquipmentModel? e) {
    _remoteParamValues.clear();
    _expandedRemoteKeys.clear();
    if (e == null) return;
    final nonStashEntries = <MapEntry<String, String>>[];
    final stashEntries = <MapEntry<String, String>>[];
    for (final entry in e.remoteParams.entries) {
      final t = entry.value.trim();
      if (t.isEmpty) continue;
      final real = EquipmentRemoteParamKey.remoteParamStashRealKeyOrNull(
        entry.key,
      );
      if (real != null) {
        stashEntries.add(MapEntry(real, entry.value));
      } else {
        nonStashEntries.add(entry);
      }
    }
    for (final entry in nonStashEntries) {
      _remoteParamValues[entry.key] = entry.value;
      _expandedRemoteKeys.add(entry.key);
    }
    for (final entry in stashEntries) {
      final k = entry.key;
      if (_expandedRemoteKeys.contains(k)) continue;
      _remoteParamValues[k] = entry.value;
    }
  }

  RemoteTool? _toolForParamKey(String key, List<RemoteTool> catalog) {
    final id = int.tryParse(key);
    if (id == null) return null;
    for (final t in catalog) {
      if (t.id == id) return t;
    }
    return null;
  }

  bool _isVncLikeParamKey(String key, List<RemoteTool> catalog) =>
      _toolForParamKey(key, catalog)?.role == ToolRole.vnc;

  void _pruneUnknownRemoteParamKeys(List<RemoteTool> catalog) {
    for (final k in _expandedRemoteKeys.toList()) {
      if (_toolForParamKey(k, catalog) == null) {
        _expandedRemoteKeys.remove(k);
        _remoteParamValues.remove(k);
        _disposeRemoteController(k);
      }
    }
    for (final k in _remoteParamValues.keys.toList()) {
      if (EquipmentRemoteParamKey.isRemoteParamStashKey(k)) continue;
      if (int.tryParse(k) == null) {
        _remoteParamValues.remove(k);
        _disposeRemoteController(k);
      }
    }
  }

  Future<void> _pruneRemoteParamsAfterCatalogLoad() async {
    if (!mounted || _didPruneUnknownRemoteKeys) return;
    final pairs = await widget.ref.read(remoteToolFormPairsProvider.future);
    final catalog = await widget.ref.read(remoteToolsCatalogProvider.future);
    if (!mounted || _didPruneUnknownRemoteKeys) return;
    _didPruneUnknownRemoteKeys = true;
    setState(() {
      _pruneUnknownRemoteParamKeys(catalog);
      _recomputeDefaultRemoteFromChips(pairs, catalog);
      _tryCaptureFormBaseline();
    });
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
      final norm = _isVncLikeParamKey(k, catalog)
          ? v.replaceAll(',', '.')
          : v;
      out[k] = norm;
    }
    for (final entry in _remoteParamValues.entries) {
      if (_expandedRemoteKeys.contains(entry.key)) continue;
      if (EquipmentRemoteParamKey.isRemoteParamStashKey(entry.key)) continue;
      final v = entry.value.trim();
      if (v.isEmpty) continue;
      final norm = _isVncLikeParamKey(entry.key, catalog)
          ? v.replaceAll(',', '.')
          : v;
      out[EquipmentRemoteParamKey.remoteParamStashKeyFor(entry.key)] = norm;
    }
    return out;
  }

  void _recomputeDefaultRemoteFromChips(
    List<RemoteToolFormPair> pairs,
    List<RemoteTool> catalog,
  ) {
    final selected = <RemoteTool>[];
    for (final p in pairs) {
      if (!_expandedRemoteKeys.contains(p.key)) continue;
      final id = int.tryParse(p.key);
      if (id == null) continue;
      for (final c in catalog) {
        if (c.id == id) {
          selected.add(c);
          break;
        }
      }
    }
    selected.sort((a, b) {
      final cmp = a.sortOrder.compareTo(b.sortOrder);
      if (cmp != 0) return cmp;
      return a.name.compareTo(b.name);
    });
    _defaultRemoteToolId = selected.isEmpty ? null : selected.first.id;
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
    _defaultRemoteToolId =
        RemoteToolsRepository.parseDefaultRemoteToolId(e?.defaultRemoteTool);
    if (e != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pruneRemoteParamsAfterCatalogLoad();
      });
    }
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
      defaultRemoteTool: RemoteToolsRepository.defaultRemoteToolIdToDbString(
        _defaultRemoteToolId,
      ),
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

  Widget _buildRemoteParamsChipsSection(
    List<RemoteToolFormPair> pairs,
    List<RemoteTool> catalog,
  ) {
    final theme = Theme.of(context);
    if (pairs.isEmpty) {
      return Text(
        'Δεν υπάρχουν ενεργά εργαλεία απομακρυσμένης — δεν μπορείτε να επιλέξετε παραμέτρους μέσω chips.',
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
    final defaultLabel = _defaultRemoteToolId == null
        ? 'Κανένα'
        : () {
            for (final c in catalog) {
              if (c.id == _defaultRemoteToolId) return c.name;
            }
            return '#$_defaultRemoteToolId';
          }();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Παράμετροι απομακρυσμένης',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          'Προεπιλεγμένο εργαλείο (πρώτο κατά σειρά ταξινόμησης μεταξύ επιλεγμένων): $defaultLabel',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
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
                    }
                    _recomputeDefaultRemoteFromChips(pairs, catalog);
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
                              pairs,
                              catalog,
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

  Widget _buildRemoteParamField(
    String paramKey,
    String toolLabel,
    List<RemoteToolFormPair> pairs,
    List<RemoteTool> catalog,
  ) {
    final c = _remoteParamControllers[paramKey];
    if (c == null) return const SizedBox.shrink();
    final isVnc = _isVncLikeParamKey(paramKey, catalog);
    final acceptsFileParam = _toolAcceptsFileParam(paramKey, pairs);
    return TextFormField(
      controller: c,
      decoration: InputDecoration(
        labelText: 'Παράμετρος · $toolLabel',
        border: const OutlineInputBorder(),
        hintText: acceptsFileParam
            ? 'Αρχείο παραμέτρων πχ .rdp'
            : (isVnc ? 'IP ή hostname' : null),
      ),
      keyboardType: isVnc
          ? const TextInputType.numberWithOptions(decimal: true, signed: false)
          : TextInputType.text,
      inputFormatters:
          isVnc ? [CommaToDotDecimalSeparatorFormatter()] : null,
      onChanged: (_) => _syncRemoteValueFromController(paramKey),
    );
  }

  bool _toolAcceptsFileParam(
    String key,
    List<RemoteToolFormPair> pairs,
  ) {
    for (final p in pairs) {
      if (p.key == key) return p.acceptsFileParam;
    }
    return false;
  }

  String get _title {
    if (_isEdit) return 'Επεξεργασία εξοπλισμού';
    if (widget.isClone) return 'Αντίγραφο εξοπλισμού';
    return 'Νέος εξοπλισμός';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _requestClose();
      },
      child: AlertDialog(
      title: Text(_title),
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
                          _buildRemoteParamsChipsSection(pairs, catalog),
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
    );
  }
}
