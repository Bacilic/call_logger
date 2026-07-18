import 'package:flutter/material.dart';

import '../../../../core/errors/department_exists_exception.dart';
import '../../../../core/models/building_map_floor.dart';
import '../../../../core/services/lookup_service.dart';
import '../../../../core/database/audit_service.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/services/save_confirmation_summary.dart';
import '../../../../core/widgets/audit_summary_rich_text.dart';
import '../../../../core/database/building_map_repository.dart';
import '../../../../core/database/department_repository.dart';
import '../../../../core/database/directory_support.dart';
import '../../../../core/widgets/database_persistence_error_snackbar.dart';
import '../../../../core/widgets/draggable_dialog_shell.dart';
import '../../../../core/utils/search_text_normalizer.dart';
import '../../../../core/utils/spell_check.dart';
import '../../../../core/widgets/lexicon_spell_text_form_field.dart';
import '../../../../core/widgets/spell_check_controller.dart';
import '../../building_map/widgets/building_map_floor_menu_button.dart';
import '../../models/department_model.dart';
import '../../providers/department_directory_provider.dart';
import '../../../floor_map/services/floor_color_assignment_service.dart';
import 'department_color_palette.dart';
import 'department_color_picker_dialog.dart';
import 'department_palette_actions.dart';
import 'department_palette_host.dart';
import 'department_palette_store.dart';
import 'shared_asset_disconnect_dialog.dart';

part 'department_form_dismiss_guard.dart';
part 'department_form_shared_links.dart';
part 'department_form_save.dart';

const _kDepartmentDistinctSuffixLetters = <String>[
  'Α', 'Β', 'Γ', 'Δ', 'Ε', 'Ζ', 'Η', 'Θ', 'Ι', 'Κ', 'Λ', 'Μ',
  'Ν', 'Ξ', 'Ο', 'Π', 'Ρ', 'Σ', 'Τ', 'Υ', 'Φ', 'Χ', 'Ψ', 'Ω',
];

/// Παράδειγμα διακριτού ονόματος τμήματος (π.χ. «Μαγειρείο Α») όταν υπάρχει σύγκρουση.
String suggestDistinctDepartmentNameExample(String name) {
  final base = name.trim();
  if (base.isEmpty) return 'Τμήμα Α';
  final lookup = LookupService.instance;
  for (final letter in _kDepartmentDistinctSuffixLetters) {
    final candidate = '$base $letter';
    if (lookup.findDepartmentByName(candidate) == null) {
      return candidate;
    }
  }
  for (var i = 2; i <= 99; i++) {
    final candidate = '$base $i';
    if (lookup.findDepartmentByName(candidate) == null) {
      return candidate;
    }
  }
  return '$base Α';
}

/// Διάλογος προσθήκης / επεξεργασίας / αντιγράφου τμήματος.
class DepartmentFormDialog extends StatefulWidget {
  const DepartmentFormDialog({
    super.key,
    this.initialDepartment,
    required this.notifier,
    this.isClone = false,
    this.focusedField,
    this.onSaved,
  });

  final DepartmentModel? initialDepartment;
  final DepartmentDirectoryNotifier notifier;
  final bool isClone;
  final String? focusedField;
  final VoidCallback? onSaved;

  @override
  State<DepartmentFormDialog> createState() => _DepartmentFormDialogState();
}

mixin DepartmentFormDialogStateHost on State<DepartmentFormDialog> {
  GlobalKey<FormState> get _formKey;
  SpellCheckController get _nameController;
  TextEditingController get _buildingController;
  SpellCheckController get _notesController;
  TextEditingController get _hexController;
  TextEditingController get _sharedPhoneInputController;
  TextEditingController get _sharedEquipmentInputController;

  // ignore: unused_element — απαιτείται από part mixins· ο analyzer δεν το ανιχνεύει.
  Color get _selectedColor;
  // ignore: unused_element
  set _selectedColor(Color value);

  FocusNode get _sharedPhoneInputFocus;
  FocusNode get _sharedEquipmentInputFocus;

  bool get _isNormalizingDelimitedInput;
  set _isNormalizingDelimitedInput(bool value);

  List<String> get _sharedPhones;
  set _sharedPhones(List<String> value);

  List<String> get _sharedEquipmentCodes;
  set _sharedEquipmentCodes(List<String> value);

  String get _snapName;
  String get _snapBuilding;
  String get _snapNotes;
  String get _snapColorHex;
  List<String> get _snapSharedPhones;
  List<String> get _snapSharedEquipmentCodes;

  // ignore: unused_element — απαιτείται από part mixins· ο analyzer δεν το ανιχνεύει.
  int? get _selectedFloorId;
  // ignore: unused_element
  set _selectedFloorId(int? value);

  int? get _snapFloorId;

  List<BuildingMapFloor> get _floors;

  bool get _isEdit;

  Future<void> _save();

  Future<
    ({
      List<String> acceptedPhones,
      List<String> acceptedEquipmentCodes,
      Set<String> phonesToMoveFromUsers,
      Set<String> equipmentToMoveFromUsers,
    })?
  >
  _resolveCrossUsageConflicts(
    int? departmentId,
    String targetDepartmentName,
    List<String> sharedPhones,
    List<String> sharedEquipmentCodes,
  );

  Future<
    ({
      List<String> sharedPhones,
      List<String> sharedEquipmentCodes,
      Map<String, int> phoneTransfers,
      Map<String, int> equipmentTransfers,
      List<String> phonesToDelete,
      List<String> equipmentToDelete,
    })?
  >
  _applySharedOnlyRemovalConfirmations({
    required int departmentId,
    required String departmentName,
    required List<String> sharedPhones,
    required List<String> sharedEquipmentCodes,
  });
}

class _DepartmentFormDialogState extends State<DepartmentFormDialog>
    with
        DepartmentFormDialogStateHost,
        DepartmentFormDismissGuardMixin,
        DepartmentFormSharedLinksMixin,
        DepartmentFormSaveMixin {
  @override
  final _formKey = GlobalKey<FormState>();
  @override
  late final SpellCheckController _nameController;
  @override
  late final TextEditingController _buildingController;
  @override
  late final SpellCheckController _notesController;
  @override
  late final TextEditingController _hexController;
  @override
  late final TextEditingController _sharedPhoneInputController;
  @override
  late final TextEditingController _sharedEquipmentInputController;

  @override
  late Color _selectedColor;

  final FocusNode _nameFocus = FocusNode();
  final FocusNode _buildingFocus = FocusNode();
  final FocusNode _colorFocus = FocusNode();
  final FocusNode _notesFocus = FocusNode();
  @override
  final FocusNode _sharedPhoneInputFocus = FocusNode();
  @override
  final FocusNode _sharedEquipmentInputFocus = FocusNode();
  @override
  bool _isNormalizingDelimitedInput = false;

  @override
  List<String> _sharedPhones = [];
  @override
  List<String> _sharedEquipmentCodes = [];
  @override
  late final String _snapName;
  @override
  late final String _snapBuilding;
  @override
  late final String _snapNotes;
  @override
  late final String _snapColorHex;
  @override
  late final List<String> _snapSharedPhones;
  @override
  late final List<String> _snapSharedEquipmentCodes;

  @override
  List<BuildingMapFloor> _floors = const [];
  @override
  int? _selectedFloorId;
  @override
  int? _snapFloorId;

  /// True μετά την πρώτη ολοκλήρωση `_loadFloors` (ώστε το dropdown να μη δέχεται `value` πριν υπάρχουν items).
  bool _floorListLoadCompleted = false;

  @override
  bool get _isEdit => widget.initialDepartment != null && !widget.isClone;

  /// Τιμή που επιτρέπεται στο `DropdownButtonFormField` χωρίς να σπάει το invariant των items.
  int? _effectiveFloorDropdownValue() {
    final sel = _selectedFloorId;
    if (sel == null) return null;
    if (!_floorListLoadCompleted) return null;
    if (_floors.any((f) => f.id == sel)) return sel;
    return sel;
  }

  List<DropdownMenuItem<int?>> _floorDropdownItems() {
    final sortedFloors = buildingMapFloorsSortedByDisplayLabel(_floors);
    final items = <DropdownMenuItem<int?>>[
      const DropdownMenuItem<int?>(value: null, child: Text('— χωρίς —')),
      for (final f in sortedFloors)
        DropdownMenuItem<int?>(
          value: f.id,
          child: Text(
            buildingMapFloorDisplayLabel(f),
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ];
    final sel = _selectedFloorId;
    if (_floorListLoadCompleted &&
        sel != null &&
        !_floors.any((f) => f.id == sel)) {
      items.add(
        DropdownMenuItem<int?>(
          value: sel,
          child: Text(
            'Όροφος #$sel (δεν βρέθηκε κατόψη)',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
    return items;
  }

  @override
  void initState() {
    super.initState();
    final d = widget.initialDepartment;
    _nameController = SpellCheckController()..text = d?.name ?? '';
    _buildingController = TextEditingController(text: d?.building ?? '');
    _notesController = SpellCheckController()..text = (d?.notes ?? '');
    _selectedColor = tryParseDepartmentHex(d?.color) ?? const Color(0xFF1976D2);
    _hexController = TextEditingController(
      text: colorToDepartmentHex(_selectedColor),
    );
    _sharedPhoneInputController = TextEditingController();
    _sharedEquipmentInputController = TextEditingController();
    final did = d?.id;
    if (did != null) {
      _sharedPhones = LookupService.instance.getDirectPhonesByDepartment(did);
      _sharedEquipmentCodes = LookupService.instance
          .getSharedEquipmentCodesByDepartment(did);
    }
    _snapName = _nameController.text.trim();
    _snapBuilding = _buildingController.text.trim();
    _snapNotes = _notesController.text.trim();
    _snapColorHex = colorToDepartmentHex(_selectedColor);
    _snapSharedPhones =
        _sharedPhones
            .map((v) => v.trim())
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.compareTo(b));
    _snapSharedEquipmentCodes =
        _sharedEquipmentCodes
            .map((v) => v.trim())
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.compareTo(b));
    final initDept = widget.initialDepartment;
    _selectedFloorId = initDept?.floorId;
    _snapFloorId = initDept?.floorId;
    _nameController.addListener(_onFieldChanged);
    _buildingController.addListener(_onFieldChanged);
    _notesController.addListener(_onFieldChanged);
    _hexController.addListener(_onFieldChanged);
    _sharedPhoneInputFocus.addListener(_onSharedPhoneFocusChanged);
    _sharedEquipmentInputFocus.addListener(_onSharedEquipmentFocusChanged);
    if (widget.isClone) {
      _nameController.text = '${d?.name ?? ''} (αντίγραφο)'.trim();
    }
    DepartmentPaletteStore.instance.ensureLoaded();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _loadFloors();
      if (!mounted) return;
      switch (widget.focusedField) {
        case 'building':
          _buildingFocus.requestFocus();
          break;
        case 'color':
          _colorFocus.requestFocus();
          break;
        case 'phones':
          _sharedPhoneInputFocus.requestFocus();
          break;
        case 'equipment':
          _sharedEquipmentInputFocus.requestFocus();
          break;
        case 'notes':
          _notesFocus.requestFocus();
          break;
        case 'name':
        default:
          _nameFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _nameController.removeListener(_onFieldChanged);
    _buildingController.removeListener(_onFieldChanged);
    _notesController.removeListener(_onFieldChanged);
    _hexController.removeListener(_onFieldChanged);
    _sharedPhoneInputFocus.removeListener(_onSharedPhoneFocusChanged);
    _sharedEquipmentInputFocus.removeListener(_onSharedEquipmentFocusChanged);
    _nameController.dispose();
    _buildingController.dispose();
    _hexController.dispose();
    _sharedPhoneInputController.dispose();
    _sharedEquipmentInputController.dispose();
    _notesController.dispose();
    _nameFocus.dispose();
    _buildingFocus.dispose();
    _colorFocus.dispose();
    _notesFocus.dispose();
    _sharedPhoneInputFocus.dispose();
    _sharedEquipmentInputFocus.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadFloors() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final list =
          await BuildingMapRepository(db, DirectorySupport(db)).listBuildingMapFloors();
      if (!mounted) return;
      setState(() {
        _floors = list;
        _floorListLoadCompleted = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _floors = const [];
        _floorListLoadCompleted = true;
      });
    }
  }

  String? _floorSubtitleText() {
    final sel = _selectedFloorId;
    if (sel != null) {
      BuildingMapFloor? hit;
      for (final f in _floors) {
        if (f.id == sel) {
          hit = f;
          break;
        }
      }
      if (hit != null) return buildingMapFloorDisplayLabel(hit);
    }
    final d = widget.initialDepartment;
    if (d == null) return null;
    final byId = {for (final f in _floors) f.id: f};
    final mapSheetId = int.tryParse(d.mapFloor?.trim() ?? '');
    if (mapSheetId != null && byId.containsKey(mapSheetId)) {
      return 'Θέση στον χάρτη: ${buildingMapFloorDisplayLabel(byId[mapSheetId]!)}';
    }
    return null;
  }

  Future<void> _onFloorDropdownChanged(int? value) async {
    setState(() => _selectedFloorId = value);
    if (!_isEdit || widget.initialDepartment?.id == null) return;
    final manualFromMap = int.tryParse(
      widget.initialDepartment?.mapFloor?.trim() ?? '',
    );
    if (value != null && manualFromMap != null && manualFromMap != value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Ο όροφος στη φόρμα διαφέρει από τη θέση στο χάρτη — '
            'η αποθήκευση από τον χάρτη παραμένει η κύρια για το σχήμα.',
          ),
        ),
      );
    }
  }

  DepartmentPaletteHost get _paletteHost => DepartmentPaletteHost(
    editingDepartmentId: widget.initialDepartment?.id,
    directoryNotifier: widget.notifier,
    onEditingDepartmentColorChanged: (hex) {
      if (!mounted) return;
      final c = tryParseDepartmentHex(hex);
      if (c == null) return;
      setState(() {
        _selectedColor = c;
        _hexController.text = hex;
      });
    },
  );

  Future<void> _openColorPickerFromPreview() async {
    final initial =
        tryParseDepartmentHex(_hexController.text.trim()) ?? _selectedColor;
    final picked = await showDepartmentColorPickerDialog(
      context,
      initialColor: initial,
    );
    if (picked == null || !mounted) return;
    final applied = await DepartmentPaletteActions.applyPickedColorForPreview(
      context,
      picked: picked,
      previousColor: initial,
      host: _paletteHost,
    );
    if (applied == null || !mounted) return;
    setState(() {
      _selectedColor = applied;
      _hexController.text = colorToDepartmentHex(applied);
    });
  }

  Widget _buildReadOnlyLegend({
    required BuildContext context,
    required String title,
    required Map<String, List<String>> byValueToOwners,
    required IconData avatarIcon,
  }) {
    if (byValueToOwners.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final key in byValueToOwners.keys)
              Tooltip(
                message: byValueToOwners[key]!.join(', '),
                child: Chip(
                  label: Text(key),
                  avatar: Icon(avatarIcon, size: 14),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _departmentNameAutocompleteOptionsView(
    BuildContext context,
    void Function(String) onSelected,
    Iterable<String> options,
  ) {
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 4,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380, maxHeight: 200),
          child: ListView(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            children: [
              for (final opt in options)
                ListTile(
                  dense: true,
                  title: Text(opt),
                  onTap: () => onSelected(opt),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Iterable<String> _departmentNameAutocompleteOptions(String query) {
    final excludeId = _isEdit ? widget.initialDepartment?.id : null;
    final departments = LookupService.instance.searchDepartments(query);
    final names = departments
        .where((d) => excludeId == null || d.id != excludeId)
        .map((d) => d.name.trim())
        .where((n) => n.isNotEmpty)
        .toList()
      ..sort((a, b) => a.compareTo(b));
    return names;
  }

  @override
  Widget build(BuildContext context) {
    final title = _isEdit
        ? 'Επεξεργασία τμήματος'
        : widget.isClone
        ? 'Νέο τμήμα (αντίγραφο)'
        : 'Νέο τμήμα';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _requestClose();
      },
      child: DraggableDialogShell(
        title: Text(title),
        builder: (titleHandle) => AlertDialog(
      title: titleHandle,
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RawAutocomplete<String>(
                    textEditingController: _nameController,
                    focusNode: _nameFocus,
                    optionsBuilder: (value) =>
                        _departmentNameAutocompleteOptions(value.text),
                    displayStringForOption: (v) => v,
                    onSelected: (selection) {
                      _nameController.text = selection;
                      _onFieldChanged();
                    },
                    fieldViewBuilder: (context, controller, focusNode, _) {
                      return LexiconSpellTextFormField(
                        controller: _nameController,
                        focusNode: focusNode,
                        decoration: const InputDecoration(
                          labelText: 'Όνομα',
                          border: OutlineInputBorder(),
                        ),
                        textCapitalization: TextCapitalization.words,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Απαιτείται όνομα';
                          }
                          return null;
                        },
                        onChanged: (_) => _onFieldChanged(),
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      return _departmentNameAutocompleteOptionsView(
                        context,
                        onSelected,
                        options,
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Κοινόχρηστα τηλέφωνα',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  RawAutocomplete<String>(
                    textEditingController: _sharedPhoneInputController,
                    focusNode: _sharedPhoneInputFocus,
                    optionsBuilder: (value) {
                      final q = SearchTextNormalizer.normalizeForSearch(
                        value.text,
                      );
                      final all = LookupService.instance.getAllKnownPhones();
                      if (q.isEmpty) return all;
                      return all.where(
                        (v) =>
                            SearchTextNormalizer.matchesNormalizedQuery(v, q),
                      );
                    },
                    displayStringForOption: (v) => v,
                    onSelected: (v) => _addSharedPhonesFromInput(v),
                    fieldViewBuilder: (context, controller, focusNode, _) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: const InputDecoration(
                          labelText: 'Προσθήκη τηλεφώνων (με κόμμα)',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => _commitDelimitedInput(
                          controller: _sharedPhoneInputController,
                          target: _sharedPhones,
                          keepLastIncomplete: true,
                        ),
                        onSubmitted: _addSharedPhonesFromInput,
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 4,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: 380,
                              maxHeight: 200,
                            ),
                            child: ListView(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              children: [
                                for (final opt in options)
                                  ListTile(
                                    dense: true,
                                    title: Text(opt),
                                    onTap: () => onSelected(opt),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final p in _sharedPhones)
                        InputChip(
                          label: Text(p),
                          backgroundColor: _snapSharedPhones.contains(p)
                              ? null
                              : Colors.lightGreen.shade100,
                          onDeleted: () => setState(() {
                            _sharedPhones.remove(p);
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (widget.initialDepartment?.id != null)
                    _buildReadOnlyLegend(
                      context: context,
                      title:
                          'Τηλέφωνα Τμήματος (Πέρασμα του ποντικιού για προβολή υπαλλήλου)',
                      byValueToOwners: LookupService.instance
                          .getCallerOwnedPhonesByDepartment(
                            widget.initialDepartment!.id!,
                          ),
                      avatarIcon: Icons.phone_outlined,
                    ),
                  const SizedBox(height: 12),
                  Text(
                    'Κοινόχρηστος εξοπλισμός',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  RawAutocomplete<String>(
                    textEditingController: _sharedEquipmentInputController,
                    focusNode: _sharedEquipmentInputFocus,
                    optionsBuilder: (value) {
                      final q = SearchTextNormalizer.normalizeForSearch(
                        value.text,
                      );
                      final all = LookupService.instance
                          .getAllKnownEquipmentCodes();
                      if (q.isEmpty) return all;
                      return all.where(
                        (v) =>
                            SearchTextNormalizer.matchesNormalizedQuery(v, q),
                      );
                    },
                    displayStringForOption: (v) => v,
                    onSelected: (v) => _addSharedEquipmentFromInput(v),
                    fieldViewBuilder: (context, controller, focusNode, _) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: const InputDecoration(
                          labelText: 'Προσθήκη εξοπλισμού (με κόμμα)',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => _commitDelimitedInput(
                          controller: _sharedEquipmentInputController,
                          target: _sharedEquipmentCodes,
                          keepLastIncomplete: true,
                        ),
                        onSubmitted: _addSharedEquipmentFromInput,
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 4,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: 380,
                              maxHeight: 200,
                            ),
                            child: ListView(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              children: [
                                for (final opt in options)
                                  ListTile(
                                    dense: true,
                                    title: Text(opt),
                                    onTap: () => onSelected(opt),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final code in _sharedEquipmentCodes)
                        InputChip(
                          label: Text(code),
                          backgroundColor:
                              _snapSharedEquipmentCodes.contains(code)
                              ? null
                              : Colors.lightGreen.shade100,
                          onDeleted: () => setState(() {
                            _sharedEquipmentCodes.remove(code);
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (widget.initialDepartment?.id != null)
                    _buildReadOnlyLegend(
                      context: context,
                      title:
                          'Εξοπλισμός Τμήματος (Πέρασμα του ποντικιού για προβολή υπαλλήλου)',
                      byValueToOwners: LookupService.instance
                          .getCallerOwnedEquipmentByDepartment(
                            widget.initialDepartment!.id!,
                          ),
                      avatarIcon: Icons.computer_outlined,
                    ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _buildingController,
                          focusNode: _buildingFocus,
                          decoration: const InputDecoration(
                            labelText: 'Κτίριο',
                            border: OutlineInputBorder(),
                          ),
                          spellCheckConfiguration:
                              platformSpellCheckConfiguration,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int?>(
                          // ignore: deprecated_member_use — controlled selection (Flutter 3.33+ προτείνει initialValue μόνο για uncontrolled)
                          value: _effectiveFloorDropdownValue(),
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Όροφος (κατόψη)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: _floorDropdownItems(),
                          onChanged: (v) => _onFloorDropdownChanged(v),
                        ),
                      ),
                    ],
                  ),
                  if (_floorSubtitleText() != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _floorSubtitleText()!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'Χρώμα',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: DepartmentColorPalette(
                          compact: true,
                          showHeading: false,
                          host: _paletteHost,
                          selected: _selectedColor,
                          onColorSelected: (c) {
                            setState(() {
                              _selectedColor = c;
                              _hexController.text = colorToDepartmentHex(c);
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 156,
                        child: Builder(
                          builder: (context) {
                            final rawHex = _hexController.text.trim();
                            final parsedHex = tryParseDepartmentHex(rawHex);
                            final hasInvalidHex =
                                rawHex.isNotEmpty && parsedHex == null;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextFormField(
                                  controller: _hexController,
                                  focusNode: _colorFocus,
                                  decoration: const InputDecoration(
                                    labelText: 'Δεκαεξαδικός (Hex)',
                                    hintText: '#RRGGBB',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  style: TextStyle(
                                    color: hasInvalidHex
                                        ? Theme.of(context).colorScheme.error
                                        : null,
                                  ),
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  onChanged: (_) => setState(() {}),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'Εισάγετε hex χρώματος';
                                    }
                                    if (tryParseDepartmentHex(v.trim()) ==
                                        null) {
                                      return 'Μη έγκυρο (π.χ. #1976D2)';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 6),
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: hasInvalidHex
                                        ? null
                                        : _openColorPickerFromPreview,
                                    borderRadius: BorderRadius.circular(4),
                                    child: Tooltip(
                                      message: hasInvalidHex
                                          ? 'Διορθώστε το hex'
                                          : 'Επιλογέας χρώματος',
                                      child: Container(
                                        height: 22,
                                        decoration: BoxDecoration(
                                          color:
                                              parsedHex ?? Colors.transparent,
                                          border: Border.all(
                                            color: hasInvalidHex
                                                ? Theme.of(
                                                    context,
                                                  ).colorScheme.error
                                                : Theme.of(
                                                    context,
                                                  ).colorScheme.outlineVariant,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        alignment: Alignment.center,
                                        child: hasInvalidHex
                                            ? Icon(
                                                Icons.error_outline,
                                                size: 14,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.error,
                                              )
                                            : Icon(
                                                Icons.palette_outlined,
                                                size: 14,
                                                color: (parsedHex ??
                                                            Colors.grey)
                                                        .computeLuminance() >
                                                    0.55
                                                    ? Colors.black54
                                                    : Colors.white70,
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LexiconSpellTextFormField(
                    controller: _notesController,
                    focusNode: _notesFocus,
                    decoration: const InputDecoration(
                      labelText: 'Σημειώσεις',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                    onChanged: (_) => _onFieldChanged(),
                  ),
                ],
              ),
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
          onPressed: (_isEdit && !_isDirty) ? null : _save,
          child: Text(_isEdit ? 'Αποθήκευση' : 'Προσθήκη'),
        ),
      ],
    ),
      ),
    );
  }
}
