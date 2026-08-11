import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/building_map_floor.dart';
import '../../../../core/services/lansweeper_department_accounts.dart';
import '../../../../core/services/lansweeper_identity_diagnosis.dart';
import '../../../../core/services/lookup_service.dart';
import '../../../../core/services/settings_service.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/database/building_map_repository.dart';
import '../../../../core/database/directory_support.dart';
import '../../../../core/widgets/compact_tooltip.dart';
import '../../../../core/widgets/draggable_dialog_shell.dart';
import '../../../../core/utils/search_text_normalizer.dart';
import '../../../../core/widgets/lexicon_spell_text_form_field.dart';
import '../../../../core/widgets/resizable_text_area.dart';
import '../../../../core/widgets/spell_check_controller.dart';
import '../../building_map/services/building_map_floor_ordering.dart';
import '../../models/department_model.dart';
import '../../providers/catalog_validation_provider.dart';
import '../../providers/department_directory_provider.dart';
import 'catalog_validation_hint_text.dart';
import 'department_color_palette.dart';
import 'department_color_picker_dialog.dart';
import 'department_form_dismiss_guard.dart';
import 'department_form_save.dart';
import 'department_form_shared_links.dart';
import 'department_palette_actions.dart';
import 'department_palette_host.dart';
import 'department_palette_store.dart';

const _kDepartmentDistinctSuffixLetters = <String>[
  'Α',
  'Β',
  'Γ',
  'Δ',
  'Ε',
  'Ζ',
  'Η',
  'Θ',
  'Ι',
  'Κ',
  'Λ',
  'Μ',
  'Ν',
  'Ξ',
  'Ο',
  'Π',
  'Ρ',
  'Σ',
  'Τ',
  'Υ',
  'Φ',
  'Χ',
  'Ψ',
  'Ω',
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
class DepartmentFormDialog extends ConsumerStatefulWidget {
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
  ConsumerState<DepartmentFormDialog> createState() =>
      DepartmentFormDialogState();
}

/// Δημόσιο State: τα πεδία της φόρμας είναι ορατά στους συνεργάτες της
/// (φρουρός κλεισίματος, κοινόχρηστα στοιχεία, αποθήκευση).
class DepartmentFormDialogState extends ConsumerState<DepartmentFormDialog> {
  /// Φρουρός κλεισίματος (dirty έλεγχος + διάλογος αλλαγών).
  late final DepartmentFormDismissGuard dismissGuard =
      DepartmentFormDismissGuard(this);

  /// Κοινόχρηστα τηλέφωνα/εξοπλισμοί (είσοδος, συγκρούσεις, αφαιρέσεις).
  late final DepartmentFormSharedLinks sharedLinks = DepartmentFormSharedLinks(
    this,
  );

  /// Ροή αποθήκευσης (μοντέλο, εγγραφή, επαναφορά, μηνύματα).
  late final DepartmentFormSave saveFlow = DepartmentFormSave(this);

  final formKey = GlobalKey<FormState>();
  late final SpellCheckController nameController;
  late final SpellCheckController buildingController;
  late final SpellCheckController notesController;
  late final TextEditingController hexController;
  late final TextEditingController sharedPhoneInputController;
  late final TextEditingController sharedEquipmentInputController;

  /// Πεδίο εισαγωγής των γενικών λογαριασμών Lansweeper του τμήματος.
  late final TextEditingController lansweeperAccountInputController;

  /// Οι λογαριασμοί που θα αποθηκευτούν, με τη σειρά που τους έγραψε ο χρήστης.
  List<LansweeperAccount> lansweeperAccounts = const [];

  /// Ταυτότητα πράκτορα (Ρυθμίσεις API) — μέτρο σύγκρισης για τις ήπιες
  /// υποψίες τομέα (πορτοκαλί chip). Null όσο δεν έχει φορτωθεί/οριστεί.
  String? lansweeperAgentIdentity;

  late Color selectedColor;

  final FocusNode _nameFocus = FocusNode();
  final FocusNode _buildingFocus = FocusNode();
  final FocusNode _colorFocus = FocusNode();
  final FocusNode _lansweeperAccountsFocus = FocusNode();
  final FocusNode _notesFocus = FocusNode();
  final FocusNode sharedPhoneInputFocus = FocusNode();
  final FocusNode sharedEquipmentInputFocus = FocusNode();
  bool isNormalizingDelimitedInput = false;

  List<String> sharedPhones = [];
  List<String> sharedEquipmentCodes = [];
  final Set<String> _sharedPhonesPendingRemoval = {};
  final Set<String> _sharedEquipmentPendingRemoval = {};
  late final String snapName;
  late final String snapBuilding;
  late final String snapNotes;
  late final String snapColorHex;
  late final List<String> snapSharedPhones;
  late final List<String> snapSharedEquipmentCodes;
  late final String snapLansweeperAccounts;

  List<BuildingMapFloor> floors = const [];
  int? selectedFloorId;
  int? snapFloorId;

  /// True μετά την πρώτη ολοκλήρωση `_loadFloors` (ώστε το dropdown να μη δέχεται `value` πριν υπάρχουν items).
  bool _floorListLoadCompleted = false;

  bool get isEdit => widget.initialDepartment != null && !widget.isClone;

  /// Σηματοδοτεί αλλαγή φόρμας (rebuild) — χρησιμοποιείται και από συνεργάτες.
  void notifyFormChanged() {
    if (mounted) setState(() {});
  }

  /// Τιμή που επιτρέπεται στο `DropdownButtonFormField` χωρίς να σπάει το invariant των items.
  int? _effectiveFloorDropdownValue() {
    final sel = selectedFloorId;
    if (sel == null) return null;
    if (!_floorListLoadCompleted) return null;
    if (floors.any((f) => f.id == sel)) return sel;
    return sel;
  }

  List<DropdownMenuItem<int?>> _floorDropdownItems() {
    final sortedFloors = buildingMapFloorsSortedForDisplay(floors);
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
    final sel = selectedFloorId;
    if (_floorListLoadCompleted &&
        sel != null &&
        !floors.any((f) => f.id == sel)) {
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

  /// Υπογραφή των λογαριασμών για τον έλεγχο «άλλαξε κάτι;».
  String lansweeperAccountsSignature() =>
      lansweeperAccounts.map((a) => a.toInputText()).join('');

  /// Προσθέτει ό,τι έχει πληκτρολογηθεί ως λογαριασμούς και αδειάζει το πεδίο.
  ///
  /// Διπλά αναγνωριστικά αγνοούνται, ώστε ο επιλογέας του ticket να μη δείχνει
  /// δύο φορές τον ίδιο άνθρωπο.
  void commitLansweeperAccountInput() {
    final typed = lansweeperAccountInputController.text;
    if (typed.trim().isEmpty) return;
    final existing = {
      for (final a in lansweeperAccounts) a.username.toLowerCase(),
    };
    final added = [
      for (final account in parseLansweeperAccountsInput(typed))
        if (!existing.contains(account.username.toLowerCase())) account,
    ];
    setState(() {
      lansweeperAccounts = [...lansweeperAccounts, ...added];
      lansweeperAccountInputController.clear();
    });
  }

  /// Φορτώνει την ταυτότητα πράκτορα για τη σύγκριση τομέα. Αποτυχία =
  /// απλώς καμία πορτοκαλί υποψία — τα chips μένουν πράσινα/κόκκινα.
  Future<void> _loadLansweeperAgentIdentity() async {
    try {
      final value = await SettingsService().remoteLansweeper
          .getLansweeperAgentUsername();
      if (!mounted) return;
      setState(() => lansweeperAgentIdentity = value);
    } catch (_) {}
  }

  /// Ο τομέας αναφοράς για τα πορτοκαλί chips: του πράκτορα, ή —όταν εκείνος
  /// είναι email— ο πλειοψηφικός τομέας των αναγνωριστικών του καταλόγου.
  String? get lansweeperReferenceDomainForChips => lansweeperReferenceDomain(
    agentIdentity: lansweeperAgentIdentity,
    knownIdentities: [
      for (final user in LookupService.instance.users)
        user.lansweeperUsername ?? '',
      for (final department in LookupService.instance.departments)
        ...decodeLansweeperAccounts(
          department.lansweeperUsernames,
        ).map((account) => account.username),
      for (final account in lansweeperAccounts) account.username,
    ],
  );

  void removeLansweeperAccount(LansweeperAccount account) {
    setState(() {
      lansweeperAccounts = [
        for (final a in lansweeperAccounts)
          if (a != account) a,
      ];
    });
  }

  /// Φέρνει έναν λογαριασμό πίσω στο πεδίο για επεξεργασία: το chip φεύγει,
  /// το κείμενό του μπαίνει στο πεδίο και η εστίαση πάει εκεί — καμία
  /// επαναπληκτρολόγηση του «Ονομασία = τομέας\όνομα» από το μηδέν.
  ///
  /// Ό,τι μισογραμμένο υπάρχει ήδη στο πεδίο κατοχυρώνεται πρώτα ως
  /// λογαριασμός, ώστε να μη σβηστεί σιωπηλά από το κείμενο του chip.
  void editLansweeperAccount(LansweeperAccount account) {
    commitLansweeperAccountInput();
    final text = account.toInputText();
    setState(() {
      lansweeperAccounts = [
        for (final a in lansweeperAccounts)
          if (a != account) a,
      ];
      lansweeperAccountInputController.text = text;
      lansweeperAccountInputController.selection = TextSelection.collapsed(
        offset: text.length,
      );
    });
    _lansweeperAccountsFocus.requestFocus();
  }

  @override
  void initState() {
    super.initState();
    final d = widget.initialDepartment;
    nameController = SpellCheckController()..text = d?.name ?? '';
    buildingController = SpellCheckController()..text = d?.building ?? '';
    notesController = SpellCheckController()..text = (d?.notes ?? '');
    selectedColor = tryParseDepartmentHex(d?.color) ?? const Color(0xFF1976D2);
    hexController = TextEditingController(
      text: colorToDepartmentHex(selectedColor),
    );
    sharedPhoneInputController = TextEditingController();
    sharedEquipmentInputController = TextEditingController();
    lansweeperAccountInputController = TextEditingController();
    lansweeperAccounts = decodeLansweeperAccounts(d?.lansweeperUsernames);
    _loadLansweeperAgentIdentity();
    final did = d?.id;
    if (did != null) {
      sharedPhones = LookupService.instance.getDirectPhonesByDepartment(did);
      sharedEquipmentCodes = LookupService.instance
          .getSharedEquipmentCodesByDepartment(did);
    }
    snapName = nameController.text.trim();
    snapBuilding = buildingController.text.trim();
    snapNotes = notesController.text.trim();
    snapColorHex = colorToDepartmentHex(selectedColor);
    snapLansweeperAccounts = lansweeperAccountsSignature();
    snapSharedPhones =
        sharedPhones
            .map((v) => v.trim())
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.compareTo(b));
    snapSharedEquipmentCodes =
        sharedEquipmentCodes
            .map((v) => v.trim())
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.compareTo(b));
    final initDept = widget.initialDepartment;
    selectedFloorId = initDept?.floorId;
    snapFloorId = initDept?.floorId;
    nameController.addListener(notifyFormChanged);
    buildingController.addListener(notifyFormChanged);
    notesController.addListener(notifyFormChanged);
    hexController.addListener(notifyFormChanged);
    sharedPhoneInputFocus.addListener(sharedLinks.onSharedPhoneFocusChanged);
    sharedEquipmentInputFocus.addListener(
      sharedLinks.onSharedEquipmentFocusChanged,
    );
    if (widget.isClone) {
      nameController.text = '${d?.name ?? ''} (αντίγραφο)'.trim();
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
          sharedPhoneInputFocus.requestFocus();
          break;
        case 'equipment':
          sharedEquipmentInputFocus.requestFocus();
          break;
        case 'notes':
          _notesFocus.requestFocus();
          break;
        case 'lansweeperUsernames':
          _lansweeperAccountsFocus.requestFocus();
          break;
        case 'name':
        default:
          _nameFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    nameController.removeListener(notifyFormChanged);
    buildingController.removeListener(notifyFormChanged);
    notesController.removeListener(notifyFormChanged);
    hexController.removeListener(notifyFormChanged);
    sharedPhoneInputFocus.removeListener(sharedLinks.onSharedPhoneFocusChanged);
    sharedEquipmentInputFocus.removeListener(
      sharedLinks.onSharedEquipmentFocusChanged,
    );
    nameController.dispose();
    buildingController.dispose();
    hexController.dispose();
    sharedPhoneInputController.dispose();
    sharedEquipmentInputController.dispose();
    lansweeperAccountInputController.dispose();
    notesController.dispose();
    _nameFocus.dispose();
    _buildingFocus.dispose();
    _colorFocus.dispose();
    _notesFocus.dispose();
    _lansweeperAccountsFocus.dispose();
    sharedPhoneInputFocus.dispose();
    sharedEquipmentInputFocus.dispose();
    super.dispose();
  }

  Future<void> _loadFloors() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final list = await BuildingMapRepository(
        db,
        DirectorySupport(db),
      ).listBuildingMapFloors();
      if (!mounted) return;
      setState(() {
        floors = list;
        _floorListLoadCompleted = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        floors = const [];
        _floorListLoadCompleted = true;
      });
    }
  }

  String? _floorSubtitleText() {
    final sel = selectedFloorId;
    if (sel != null) {
      BuildingMapFloor? hit;
      for (final f in floors) {
        if (f.id == sel) {
          hit = f;
          break;
        }
      }
      if (hit != null) return buildingMapFloorDisplayLabel(hit);
    }
    final d = widget.initialDepartment;
    if (d == null) return null;
    final byId = {for (final f in floors) f.id: f};
    final mapSheetId = int.tryParse(d.mapFloor?.trim() ?? '');
    if (mapSheetId != null && byId.containsKey(mapSheetId)) {
      return 'Θέση στον χάρτη: ${buildingMapFloorDisplayLabel(byId[mapSheetId]!)}';
    }
    return null;
  }

  Future<void> _onFloorDropdownChanged(int? value) async {
    setState(() => selectedFloorId = value);
    if (!isEdit || widget.initialDepartment?.id == null) return;
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
        selectedColor = c;
        hexController.text = hex;
      });
    },
  );

  Future<void> _openColorPickerFromPreview() async {
    final initial =
        tryParseDepartmentHex(hexController.text.trim()) ?? selectedColor;
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
      selectedColor = applied;
      hexController.text = colorToDepartmentHex(applied);
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
    final excludeId = isEdit ? widget.initialDepartment?.id : null;
    final departments = LookupService.instance.searchDepartments(query);
    final names =
        departments
            .where((d) => excludeId == null || d.id != excludeId)
            .map((d) => d.name.trim())
            .where((n) => n.isNotEmpty)
            .toList()
          ..sort((a, b) => a.compareTo(b));
    return names;
  }

  @override
  Widget build(BuildContext context) {
    final title = isEdit
        ? 'Επεξεργασία τμήματος'
        : widget.isClone
        ? 'Νέο τμήμα (αντίγραφο)'
        : 'Νέο τμήμα';
    // Κανόνες επικύρωσης (υποδείξεις, όχι απαγορεύσεις) — όσο φορτώνουν,
    // απλώς δεν εμφανίζονται υποδείξεις.
    final validation = ref
        .watch(catalogValidationServiceProvider)
        .asData
        ?.value;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await dismissGuard.requestClose();
      },
      child: DraggableDialogShell(
        title: Text(title),
        builder: (titleHandle) => AlertDialog(
          title: titleHandle,
          // Το οριζόντιο περιθώριο περνά μέσα στο scrollable, ώστε η μπάρα
          // κύλησης να μένει στην άκρη του διαλόγου και όχι πάνω στα πεδία.
          contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 24),
          content: SizedBox(
            width: 468,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      RawAutocomplete<String>(
                        textEditingController: nameController,
                        focusNode: _nameFocus,
                        optionsBuilder: (value) =>
                            _departmentNameAutocompleteOptions(value.text),
                        displayStringForOption: (v) => v,
                        onSelected: (selection) {
                          nameController.text = selection;
                          notifyFormChanged();
                        },
                        fieldViewBuilder: (context, controller, focusNode, _) {
                          return LexiconSpellTextFormField(
                            controller: nameController,
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
                            onChanged: (_) => notifyFormChanged(),
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
                      CatalogValidationHintText(
                        hint: validation?.departmentNameHint(
                          nameController.text,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Κοινόχρηστα τηλέφωνα',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      RawAutocomplete<String>(
                        textEditingController: sharedPhoneInputController,
                        focusNode: sharedPhoneInputFocus,
                        optionsBuilder: (value) {
                          final q = SearchTextNormalizer.normalizeForSearch(
                            value.text,
                          );
                          final all = LookupService.instance
                              .getAllKnownPhones();
                          if (q.isEmpty) return all;
                          return all.where(
                            (v) => SearchTextNormalizer.matchesNormalizedQuery(
                              v,
                              q,
                            ),
                          );
                        },
                        displayStringForOption: (v) => v,
                        onSelected: (v) =>
                            sharedLinks.addSharedPhonesFromInput(v),
                        fieldViewBuilder: (context, controller, focusNode, _) {
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: const InputDecoration(
                              labelText: 'Προσθήκη τηλεφώνων (με κόμμα)',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => sharedLinks.commitDelimitedInput(
                              controller: sharedPhoneInputController,
                              target: sharedPhones,
                              keepLastIncomplete: true,
                            ),
                            onSubmitted: sharedLinks.addSharedPhonesFromInput,
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
                      // Ελέγχει και τα ήδη προστεθειμένα chips και ό,τι
                      // πληκτρολογείται τώρα στο πεδίο εισαγωγής.
                      CatalogValidationHintText(
                        hint: validation?.phonesFieldHint(
                          [
                            ...sharedPhones,
                            sharedPhoneInputController.text,
                          ].join(','),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final p in sharedPhones)
                            RemovableSharedChip(
                              label: p,
                              isNewlyAdded: !snapSharedPhones.contains(p),
                              isPendingRemoval: false,
                              onToggle: () => setState(() {
                                sharedPhones.remove(p);
                                if (snapSharedPhones.contains(p)) {
                                  _sharedPhonesPendingRemoval.add(p);
                                }
                              }),
                            ),
                          for (final p
                              in (_sharedPhonesPendingRemoval.toList()..sort())
                                  .where((x) => !sharedPhones.contains(x)))
                            RemovableSharedChip(
                              label: p,
                              isNewlyAdded: false,
                              isPendingRemoval: true,
                              onToggle: () => setState(() {
                                _sharedPhonesPendingRemoval.remove(p);
                                if (!sharedPhones.contains(p)) {
                                  sharedPhones.add(p);
                                  sharedPhones.sort();
                                }
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
                        textEditingController: sharedEquipmentInputController,
                        focusNode: sharedEquipmentInputFocus,
                        optionsBuilder: (value) {
                          final q = SearchTextNormalizer.normalizeForSearch(
                            value.text,
                          );
                          final all = LookupService.instance
                              .getAllKnownEquipmentCodes();
                          if (q.isEmpty) return all;
                          return all.where(
                            (v) => SearchTextNormalizer.matchesNormalizedQuery(
                              v,
                              q,
                            ),
                          );
                        },
                        displayStringForOption: (v) => v,
                        onSelected: (v) =>
                            sharedLinks.addSharedEquipmentFromInput(v),
                        fieldViewBuilder: (context, controller, focusNode, _) {
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: const InputDecoration(
                              labelText: 'Προσθήκη εξοπλισμού (με κόμμα)',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => sharedLinks.commitDelimitedInput(
                              controller: sharedEquipmentInputController,
                              target: sharedEquipmentCodes,
                              keepLastIncomplete: true,
                            ),
                            onSubmitted:
                                sharedLinks.addSharedEquipmentFromInput,
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
                          for (final code in sharedEquipmentCodes)
                            RemovableSharedChip(
                              label: code,
                              isNewlyAdded: !snapSharedEquipmentCodes.contains(
                                code,
                              ),
                              isPendingRemoval: false,
                              onToggle: () => setState(() {
                                sharedEquipmentCodes.remove(code);
                                if (snapSharedEquipmentCodes.contains(code)) {
                                  _sharedEquipmentPendingRemoval.add(code);
                                }
                              }),
                            ),
                          for (final code
                              in (_sharedEquipmentPendingRemoval.toList()
                                    ..sort())
                                  .where(
                                    (x) => !sharedEquipmentCodes.contains(x),
                                  ))
                            RemovableSharedChip(
                              label: code,
                              isNewlyAdded: false,
                              isPendingRemoval: true,
                              onToggle: () => setState(() {
                                _sharedEquipmentPendingRemoval.remove(code);
                                if (!sharedEquipmentCodes.contains(code)) {
                                  sharedEquipmentCodes.add(code);
                                  sharedEquipmentCodes.sort();
                                }
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
                            child: LexiconSpellTextFormField(
                              controller: buildingController,
                              focusNode: _buildingFocus,
                              decoration: const InputDecoration(
                                labelText: 'Κτίριο',
                                border: OutlineInputBorder(),
                              ),
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
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
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
                              selected: selectedColor,
                              onColorSelected: (c) {
                                setState(() {
                                  selectedColor = c;
                                  hexController.text = colorToDepartmentHex(c);
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 156,
                            child: Builder(
                              builder: (context) {
                                final rawHex = hexController.text.trim();
                                final parsedHex = tryParseDepartmentHex(rawHex);
                                final hasInvalidHex =
                                    rawHex.isNotEmpty && parsedHex == null;
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    TextFormField(
                                      controller: hexController,
                                      focusNode: _colorFocus,
                                      decoration: const InputDecoration(
                                        labelText: 'Δεκαεξαδικός (Hex)',
                                        hintText: '#RRGGBB',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                      style: TextStyle(
                                        color: hasInvalidHex
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.error
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
                                                  parsedHex ??
                                                  Colors.transparent,
                                              border: Border.all(
                                                color: hasInvalidHex
                                                    ? Theme.of(
                                                        context,
                                                      ).colorScheme.error
                                                    : Theme.of(context)
                                                          .colorScheme
                                                          .outlineVariant,
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
                                                    color:
                                                        (parsedHex ??
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
                      ResizableTextArea(
                        controller: notesController,
                        focusNode: _notesFocus,
                        decoration: const InputDecoration(
                          labelText: 'Σημειώσεις',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                        onChanged: (_) => notifyFormChanged(),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: lansweeperAccountInputController,
                        focusNode: _lansweeperAccountsFocus,
                        decoration: const InputDecoration(
                          labelText: 'Αναγνωριστικά Lansweeper (με κόμμα)',
                          hintText: r'Ονομασία = τομέας\όνομα, ή σκέτο email',
                          helperText:
                              'Ποιος χρεώνεται τα αιτήματα του τμήματος όταν ο '
                              'καλών είναι άγνωστος. Η ονομασία πριν το «=» '
                              'μένει στην εφαρμογή — στο Lansweeper φεύγει '
                              'μόνο το αναγνωριστικό.',
                          helperMaxLines: 3,
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => commitLansweeperAccountInput(),
                        onEditingComplete: commitLansweeperAccountInput,
                        onChanged: (value) {
                          if (value.endsWith(',')) {
                            commitLansweeperAccountInput();
                            return;
                          }
                          notifyFormChanged();
                        },
                      ),
                      if (lansweeperAccounts.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              for (final account in lansweeperAccounts)
                                LansweeperAccountChip(
                                  key: ValueKey(
                                    'lansweeper_account_${account.username}',
                                  ),
                                  account: account,
                                  referenceDomain:
                                      lansweeperReferenceDomainForChips,
                                  onEdit: () =>
                                      editLansweeperAccount(account),
                                  onRemove: () =>
                                      removeLansweeperAccount(account),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
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
              onPressed: (isEdit && !dismissGuard.isDirty)
                  ? null
                  : saveFlow.save,
              child: Text(isEdit ? 'Αποθήκευση' : 'Προσθήκη'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip κοινόχρηστου τηλεφώνου/εξοπλισμού: ενεργό, νεοπροστεθέν ή προς αφαίρεση.
/// Chip λογαριασμού Lansweeper με σήμανση εγκυρότητας:
/// 🟩 έγκυρο · 🟧 έγκυρο με ύποπτο τομέα (διαφέρει από του πράκτορα) ·
/// 🟥 άκυρο, με το ΣΤΟΧΕΥΜΕΝΟ λάθος στο tooltip (οικονομία χώρου — δεν
/// υπάρχει πια συγκεντρωτικό κόκκινο κείμενο κάτω από τα chips).
///
/// Κλικ στο σώμα = επεξεργασία (το κείμενο επιστρέφει στο πεδίο)· το X
/// παραμένει η αφαίρεση.
class LansweeperAccountChip extends StatelessWidget {
  const LansweeperAccountChip({
    super.key,
    required this.account,
    required this.referenceDomain,
    required this.onEdit,
    required this.onRemove,
  });

  final LansweeperAccount account;

  /// Τομέας αναφοράς για την πορτοκαλί υποψία (βλ.
  /// [lansweeperReferenceDomain]) — null = χωρίς μέτρο σύγκρισης.
  final String? referenceDomain;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final diagnosis = diagnoseLansweeperIdentity(account.username);
    final mismatch = diagnosis.isValid
        ? lansweeperDomainMismatchHint(account.username, referenceDomain)
        : null;

    final Color background;
    final String statusLine;
    if (!diagnosis.isValid) {
      background = Colors.red.shade100;
      statusLine = diagnosis.suggestion == null
          ? diagnosis.problem!
          : '${diagnosis.problem!}\n${diagnosis.suggestion!}';
    } else if (mismatch != null) {
      background = Colors.orange.shade100;
      statusLine = mismatch;
    } else {
      background = Colors.lightGreen.shade100;
      statusLine = diagnosis.kind == LansweeperIdentityKind.email
          ? 'Έγκυρο email'
          : 'Έγκυρο αναγνωριστικό τομέα';
    }

    return CompactTooltip(
      message: '$statusLine\n\nΚλικ για επεξεργασία — το κείμενο '
          'επιστρέφει στο πεδίο',
      waitDuration: const Duration(milliseconds: 350),
      child: InputChip(
        label: Text(account.toInputText()),
        backgroundColor: background,
        onPressed: onEdit,
        deleteIcon: const Icon(Icons.cancel),
        deleteButtonTooltipMessage: 'Διαγραφή',
        onDeleted: onRemove,
      ),
    );
  }
}

class RemovableSharedChip extends StatelessWidget {
  const RemovableSharedChip({
    super.key,
    required this.label,
    required this.isNewlyAdded,
    required this.isPendingRemoval,
    required this.onToggle,
    this.onPressed,
  });

  final String label;
  final bool isNewlyAdded;
  final bool isPendingRemoval;
  final VoidCallback onToggle;

  /// Προαιρετικό κλικ στο σώμα του chip (π.χ. «φέρε το προς επεξεργασία»).
  /// Το X παραμένει η διαγραφή/αναίρεση, ανεξάρτητα από αυτό.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      onPressed: onPressed,
      label: Text(
        label,
        style: isPendingRemoval
            ? const TextStyle(decoration: TextDecoration.lineThrough)
            : null,
      ),
      backgroundColor: isPendingRemoval
          ? Colors.red.shade100
          : (isNewlyAdded ? Colors.lightGreen.shade100 : null),
      deleteIcon: Icon(isPendingRemoval ? Icons.undo : Icons.cancel),
      deleteButtonTooltipMessage: isPendingRemoval
          ? 'Θα αφαιρεθεί στην αποθήκευση — κλικ για επαναφορά'
          : 'Διαγραφή',
      onDeleted: onToggle,
    );
  }
}
