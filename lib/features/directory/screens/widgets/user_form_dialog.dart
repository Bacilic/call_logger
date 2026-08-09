import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/draggable_dialog_shell.dart';
import '../../../../core/providers/settings_provider.dart';
import '../../../../core/providers/spell_check_provider.dart';
import '../../../../core/utils/search_text_normalizer.dart';
import '../../../../core/utils/user_similarity_finder.dart';
import '../../../../core/utils/user_identity_normalizer.dart';
import '../../../../core/utils/phone_list_parser.dart';
import '../../../../core/widgets/lexicon_spell_text_form_field.dart';
import '../../../../core/widgets/resizable_text_area.dart';
import '../../../../core/widgets/spell_check_controller.dart';
import '../../../../core/services/lookup_service.dart';
import '../../../calls/models/user_model.dart';
import '../../../calls/provider/lookup_provider.dart';
import '../../providers/directory_provider.dart';
import '../../models/full_location_breadcrumb.dart';
import 'full_location_line.dart';
import 'location_field_help_icon.dart';
import '../../providers/catalog_validation_provider.dart';
import 'catalog_validation_hint_text.dart';
import 'user_form_dismiss_guard.dart';
import 'user_form_equipment_chips.dart';
import 'user_form_equipment_link.dart';
import 'user_form_phone_policy.dart';
import 'user_form_save.dart';
import 'user_form_smart_text_field.dart';

/// Διάλογος φόρμας για δημιουργία/επεξεργασία/αντίγραφο χρήστη.
class UserFormDialog extends ConsumerStatefulWidget {
  const UserFormDialog({
    super.key,
    this.initialUser,
    required this.notifier,
    this.isClone = false,
    this.focusedField,
    this.onSaved,
  });

  final UserModel? initialUser;
  final DirectoryNotifier notifier;

  /// True = αντίγραφο: φόρμα προ-συμπληρωμένη, κουμπί «Προσθήκη».
  final bool isClone;
  final String? focusedField;
  final VoidCallback? onSaved;

  @override
  ConsumerState<UserFormDialog> createState() => UserFormDialogState();
}

/// Δημόσιο State: τα πεδία/στιγμιότυπα της φόρμας είναι ορατά στους
/// συνεργάτες της (φρουρός κλεισίματος, πολιτική τηλεφώνων, αποθήκευση).
class UserFormDialogState extends ConsumerState<UserFormDialog> {
  /// Φρουρός κλεισίματος (dirty έλεγχος + διάλογος αλλαγών).
  late final UserFormDismissGuard dismissGuard = UserFormDismissGuard(this);

  /// Πολιτική τηλεφώνων (συγκρούσεις τμήματος, αποκλειστικοί αριθμοί).
  late final UserFormPhonePolicy phonePolicy = UserFormPhonePolicy(this);

  /// Ροή αποθήκευσης (επιβεβαιώσεις + εγγραφή).
  late final UserFormSave saveFlow = UserFormSave(this);

  /// Ο εξοπλισμός που κουβαλά ο υπάλληλος (προβολή + άνοιγμα καρτέλας).
  late final UserFormEquipmentLink equipmentLink = UserFormEquipmentLink(this);

  /// Ξανασχεδιασμός της ενότητας εξοπλισμού μετά από αλλαγή στην καρτέλα του.
  void refreshEquipmentSection() {
    if (mounted) setState(() {});
  }

  final formKey = GlobalKey<FormState>();

  /// Αρχικό κείμενο τμήματος όπως στη βάση (εμφάνιση· επαναφορά στον διάλογο μεταφοράς).
  late final String initialDepartmentText;

  /// Κανονικοποιημένο κλειδί αρχικού τμήματος μόνο για σύγκριση dirty / διάλογο.
  late final String snapDepartmentNorm;
  late final String snapLastName;
  late final String snapFirstName;
  late final String snapPhone;
  late final String snapNotes;
  late final String snapLocation;
  late final TextEditingController lastNameController;
  late final SpellCheckController firstNameController;
  late final TextEditingController phoneController;
  late final SpellCheckController departmentController;

  /// Πού κάθεται ο υπάλληλος. Ο εξοπλισμός του την κληρονομεί όταν δεν έχει δική του.
  late final SpellCheckController locationController;
  late final SpellCheckController notesController;

  final FocusNode _lastNameFocusNode = FocusNode();
  final FocusNode _firstNameFocusNode = FocusNode();
  final FocusNode _phoneFocusNode = FocusNode();
  final FocusNode _departmentFocusNode = FocusNode();
  final FocusNode _locationFocusNode = FocusNode();
  final FocusNode _notesFocusNode = FocusNode();

  bool get isEdit => widget.initialUser != null && !widget.isClone;

  void _selectAll(TextEditingController c) {
    c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
  }

  @override
  void initState() {
    super.initState();
    final u = widget.initialUser;
    snapLastName = (u?.lastName ?? '').trim();
    snapFirstName = (u?.firstName ?? '').trim();
    snapPhone = PhoneListParser.joinPhones(u?.phones ?? const []);
    snapNotes = (u?.notes ?? '').trim();
    snapLocation = (u?.location ?? '').trim();
    initialDepartmentText = (u?.departmentName ?? '').trim();
    snapDepartmentNorm = SearchTextNormalizer.normalizeForSearch(
      initialDepartmentText,
    );

    lastNameController = TextEditingController(text: u?.lastName ?? '');
    firstNameController = SpellCheckController()..text = u?.firstName ?? '';
    phoneController = TextEditingController(
      text: PhoneListParser.joinPhones(u?.phones ?? const []),
    );
    departmentController = SpellCheckController()..text = initialDepartmentText;
    locationController = SpellCheckController()..text = (u?.location ?? '');
    notesController = SpellCheckController()..text = (u?.notes ?? '');

    lastNameController.addListener(_onFieldChanged);
    firstNameController.addListener(_onFieldChanged);
    phoneController.addListener(_onFieldChanged);
    departmentController.addListener(_onFieldChanged);
    locationController.addListener(_onFieldChanged);
    notesController.addListener(_onFieldChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (widget.focusedField) {
        case 'lastName':
          _lastNameFocusNode.requestFocus();
          _selectAll(lastNameController);
          break;
        case 'phone':
          _phoneFocusNode.requestFocus();
          _selectAll(phoneController);
          break;
        case 'department':
          _departmentFocusNode.requestFocus();
          _selectAll(departmentController);
          break;
        case 'notes':
          _notesFocusNode.requestFocus();
          _selectAll(notesController);
          break;
        case 'firstName':
        default:
          _firstNameFocusNode.requestFocus();
          _selectAll(firstNameController);
          break;
      }
    });
  }

  @override
  void dispose() {
    lastNameController.removeListener(_onFieldChanged);
    firstNameController.removeListener(_onFieldChanged);
    phoneController.removeListener(_onFieldChanged);
    departmentController.removeListener(_onFieldChanged);
    locationController.removeListener(_onFieldChanged);
    notesController.removeListener(_onFieldChanged);

    _lastNameFocusNode.dispose();
    _firstNameFocusNode.dispose();
    _phoneFocusNode.dispose();
    _departmentFocusNode.dispose();
    _locationFocusNode.dispose();
    _notesFocusNode.dispose();

    lastNameController.dispose();
    firstNameController.dispose();
    phoneController.dispose();
    departmentController.dispose();
    locationController.dispose();
    notesController.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  String? _requiredValidator(String? v) =>
      (v?.trim().isEmpty ?? true) ? 'Υποχρεωτικό' : null;

  String buildUserDisplayName() {
    final f = firstNameController.text.trim();
    final l = lastNameController.text.trim();
    if (f.isEmpty && l.isEmpty) return '—';
    return '$f $l'.trim();
  }

  String snapDisplayName() {
    final f = snapFirstName.trim();
    final l = snapLastName.trim();
    if (f.isEmpty && l.isEmpty) return '—';
    return '$f $l'.trim();
  }

  bool nameIdentityChanged() {
    return UserIdentityNormalizer.identityKeyForPerson(
          snapFirstName,
          snapLastName,
        ) !=
        UserIdentityNormalizer.identityKeyForPerson(
          firstNameController.text,
          lastNameController.text,
        );
  }

  /// Υπάρχουσες εγγραφές καταλόγου με ίδιο ή παρόμοιο ονοματεπώνυμο,
  /// εκτός τρέχουσας/πηγής αντίγραφου.
  List<UserSimilarityMatch> findSimilarUsers() {
    final int? excludeId =
        widget.initialUser != null && (isEdit || widget.isClone)
        ? widget.initialUser!.id
        : null;
    return UserSimilarityFinder.findSimilarUsers(
      users: widget.notifier.allUsersForUi,
      firstName: firstNameController.text,
      lastName: lastNameController.text,
      excludeUserId: excludeId,
    );
  }

  /// «Κτίριο › Όροφος › Τμήμα › Τοποθεσία» για τον υπάλληλο που επεξεργάζεται.
  ///
  /// Το κτίριο και ο όροφος προκύπτουν από το τμήμα που γράφεται εκείνη τη
  /// στιγμή στη φόρμα, οπότε η γραμμή ακολουθεί την πληκτρολόγηση.
  String _fullLocationText() {
    final lookup = LookupService.instance;
    final deptId = lookup.findDepartmentByName(departmentController.text)?.id;
    return fullLocationBreadcrumb(
      building: lookup.getDepartmentBuilding(deptId),
      floor: lookup.getDepartmentFloor(deptId),
      department: departmentController.text,
      location: locationController.text,
    );
  }

  String get _title {
    if (isEdit) return 'Επεξεργασία Υπαλλήλου';
    if (widget.isClone) return 'Αντίγραφο Υπαλλήλου';
    return 'Νέος Υπάλληλος';
  }

  /// Μοναδικά επώνυμα από κατάλογο· ίδιο [UserIdentityNormalizer] κλειδί επωνύμου → μία πρόταση.
  List<String> _catalogLastNameOptionsSorted() {
    final byKey = <String, String>{};
    for (final u in widget.notifier.allUsersForUi) {
      if (u.isDeleted) continue;
      final last = u.lastName?.trim() ?? '';
      if (last.isEmpty) continue;
      final key = UserIdentityNormalizer.identityKeyForPerson('', last);
      if (key.isEmpty) continue;
      byKey.putIfAbsent(key, () => last);
    }
    final list = byKey.values.toList();
    list.sort(
      (a, b) => SearchTextNormalizer.normalizeForSearch(
        a,
      ).compareTo(SearchTextNormalizer.normalizeForSearch(b)),
    );
    return list;
  }

  /// Μοναδικά ονόματα μόνο από χρήστες με ίδιο κανονικοποιημένο επώνυμο με το πεδίο επωνύμου.
  List<String> _catalogFirstNameOptionsSortedForLast(String lastFieldText) {
    final lastKey = UserIdentityNormalizer.identityKeyForPerson(
      '',
      lastFieldText,
    );
    if (lastKey.isEmpty) return const [];
    final byKey = <String, String>{};
    for (final u in widget.notifier.allUsersForUi) {
      if (u.isDeleted) continue;
      if (UserIdentityNormalizer.identityKeyForPerson('', u.lastName) !=
          lastKey) {
        continue;
      }
      final first = u.firstName?.trim() ?? '';
      if (first.isEmpty) continue;
      final fk = UserIdentityNormalizer.identityKeyForPerson(first, '');
      if (fk.isEmpty) continue;
      byKey.putIfAbsent(fk, () => first);
    }
    final list = byKey.values.toList();
    list.sort(
      (a, b) => SearchTextNormalizer.normalizeForSearch(
        a,
      ).compareTo(SearchTextNormalizer.normalizeForSearch(b)),
    );
    return list;
  }

  Widget _nameAutocompleteOptionsView(
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

  /// Ετικέτα λίστας προτάσεων: «2914 (Φαρμακείο - Βασίλης Πρόβος)».
  /// Μόνο για εμφάνιση — η επιλογή γράφει σκέτο τον αριθμό.
  String _phoneAutocompleteListLabel(String phone) {
    final lookup = LookupService.instance;
    final owners = lookup
        .findUsersByPhone(phone)
        .where((u) => !u.isDeleted)
        .toList();
    final names = owners
        .map((u) => (u.name ?? '').trim())
        .where((n) => n.isNotEmpty)
        .toList();
    String? dept;
    final ownerDeptIds = owners
        .map((u) => u.departmentId)
        .whereType<int>()
        .toSet();
    if (ownerDeptIds.length == 1) {
      dept = lookup.departmentIdToName[ownerDeptIds.single]?.trim();
    } else if (owners.length == 1) {
      dept = (owners.first.departmentName ?? '').trim();
    }
    if (dept == null || dept.isEmpty) {
      final usage = lookup.checkPhoneUsage(phone);
      dept = usage.departmentName?.trim();
    }
    if ((dept == null || dept.isEmpty) && names.isEmpty) {
      return phone;
    }
    if (names.isEmpty) {
      return '$phone ($dept)';
    }
    if (dept == null || dept.isEmpty) {
      return '$phone (${names.join(', ')})';
    }
    return '$phone ($dept - ${names.join(', ')})';
  }

  String _phoneDisplayStringForAutocompleteOption(String option) {
    final text = phoneController.text;
    final offset = phoneController.selection.isValid
        ? phoneController.selection.extentOffset
        : text.length;
    return PhoneListParser.replaceActiveSegment(
      text: text,
      cursor: offset,
      replacement: option,
    ).text;
  }

  Iterable<String> _phoneAutocompleteOptions(TextEditingValue value) {
    final offset = value.selection.isValid
        ? value.selection.extentOffset
        : value.text.length;
    final segment = PhoneListParser.activeSegmentBounds(
      value.text,
      offset,
    ).segmentIn(value.text);
    return PhoneListParser.autocompletePhonesForSegment(
      allKnownPhones: LookupService.instance.getAllKnownPhones(),
      segmentQuery: segment,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref
        .watch(spellCheckServiceProvider)
        .whenData(firstNameController.attachSpellService);
    ref
        .watch(enableSpellCheckProvider)
        .whenData(firstNameController.setSpellCheckEnabled);
    ref
        .watch(spellCheckServiceProvider)
        .whenData(departmentController.attachSpellService);
    ref
        .watch(enableSpellCheckProvider)
        .whenData(departmentController.setSpellCheckEnabled);

    final lookupAsync = ref.watch(lookupServiceProvider);
    final departmentNames = lookupAsync.maybeWhen(
      data: (bundle) => bundle.service.departments
          .map((d) => d.name.trim())
          .where((name) => name.isNotEmpty)
          .toList(),
      orElse: () => const <String>[],
    );
    final lastNameOptions = _catalogLastNameOptionsSorted();
    final firstNameOptions = _catalogFirstNameOptionsSortedForLast(
      lastNameController.text,
    );
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
        title: Text(_title),
        builder: (titleHandle) => AlertDialog(
          title: titleHandle,
          // Το οριζόντιο περιθώριο περνά μέσα στο scrollable, ώστε η μπάρα
          // κύλησης να μένει στην άκρη του διαλόγου και όχι πάνω στα πεδία.
          contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 24),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RawAutocomplete<String>(
                    textEditingController: lastNameController,
                    focusNode: _lastNameFocusNode,
                    optionsBuilder: (textEditingValue) {
                      final q = SearchTextNormalizer.normalizeForSearch(
                        textEditingValue.text,
                      );
                      if (q.isEmpty) return lastNameOptions;
                      return lastNameOptions.where(
                        (name) => SearchTextNormalizer.matchesNormalizedQuery(
                          name,
                          q,
                        ),
                      );
                    },
                    displayStringForOption: (option) => option,
                    onSelected: (selection) {
                      lastNameController.text = selection;
                      _onFieldChanged();
                    },
                    fieldViewBuilder: (context, controller, focusNode, _) {
                      return UserFormSmartTextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: const InputDecoration(
                          labelText: 'Επώνυμο',
                          border: OutlineInputBorder(),
                        ),
                        validator: _requiredValidator,
                        textCapitalization: TextCapitalization.words,
                        onChanged: (_) => _onFieldChanged(),
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      return _nameAutocompleteOptionsView(
                        context,
                        onSelected,
                        options,
                      );
                    },
                  ),
                  CatalogValidationHintText(
                    hint: validation?.personNameHint(lastNameController.text),
                  ),
                  const SizedBox(height: 12),
                  RawAutocomplete<String>(
                    textEditingController: firstNameController,
                    focusNode: _firstNameFocusNode,
                    optionsBuilder: (textEditingValue) {
                      if (firstNameOptions.isEmpty) {
                        return const Iterable<String>.empty();
                      }
                      final q = SearchTextNormalizer.normalizeForSearch(
                        textEditingValue.text,
                      );
                      if (q.isEmpty) return firstNameOptions;
                      return firstNameOptions.where(
                        (name) => SearchTextNormalizer.matchesNormalizedQuery(
                          name,
                          q,
                        ),
                      );
                    },
                    displayStringForOption: (option) => option,
                    onSelected: (selection) {
                      firstNameController.text = selection;
                      _onFieldChanged();
                    },
                    fieldViewBuilder: (context, controller, focusNode, _) {
                      return UserFormSmartTextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: const InputDecoration(
                          labelText: 'Όνομα',
                          border: OutlineInputBorder(),
                        ),
                        validator: _requiredValidator,
                        textCapitalization: TextCapitalization.words,
                        lexiconSpellAssist: true,
                        onChanged: (_) => _onFieldChanged(),
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      return _nameAutocompleteOptionsView(
                        context,
                        onSelected,
                        options,
                      );
                    },
                  ),
                  CatalogValidationHintText(
                    hint: validation?.personNameHint(firstNameController.text),
                  ),
                  const SizedBox(height: 12),
                  RawAutocomplete<String>(
                    textEditingController: phoneController,
                    focusNode: _phoneFocusNode,
                    optionsBuilder: _phoneAutocompleteOptions,
                    displayStringForOption:
                        _phoneDisplayStringForAutocompleteOption,
                    onSelected: (option) {
                      final offset = phoneController.selection.isValid
                          ? phoneController.selection.extentOffset
                          : phoneController.text.length;
                      final updated = PhoneListParser.replaceActiveSegment(
                        text: phoneController.text,
                        cursor: offset,
                        replacement: option,
                      );
                      final cursorPos = updated.cursor;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        phoneController.selection = TextSelection.collapsed(
                          offset: cursorPos.clamp(
                            0,
                            phoneController.text.length,
                          ),
                        );
                      });
                      _onFieldChanged();
                    },
                    fieldViewBuilder: (context, controller, focusNode, _) {
                      return UserFormSmartTextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: const InputDecoration(
                          labelText: 'Τηλέφωνο',
                          border: OutlineInputBorder(),
                          hintText: 'Πολλαπλά τηλέφωνα χωρισμένα με κόμμα',
                        ),
                        keyboardType: TextInputType.phone,
                        onChanged: (_) => _onFieldChanged(),
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 4,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: 420,
                              maxHeight: 220,
                            ),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (context, index) {
                                final option = options.elementAt(index);
                                return ListTile(
                                  dense: true,
                                  title: Text(
                                    _phoneAutocompleteListLabel(option),
                                  ),
                                  onTap: () => onSelected(option),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  CatalogValidationHintText(
                    hint: validation?.phonesFieldHint(phoneController.text),
                  ),
                  const SizedBox(height: 12),
                  RawAutocomplete<String>(
                    textEditingController: departmentController,
                    focusNode: _departmentFocusNode,
                    optionsBuilder: (textEditingValue) {
                      final q = SearchTextNormalizer.normalizeForSearch(
                        textEditingValue.text,
                      );
                      if (q.isEmpty) return departmentNames;
                      return departmentNames.where(
                        (name) => SearchTextNormalizer.matchesNormalizedQuery(
                          name,
                          q,
                        ),
                      );
                    },
                    displayStringForOption: (option) => option,
                    onSelected: (selection) {
                      departmentController.text = selection;
                      _onFieldChanged();
                    },
                    fieldViewBuilder: (context, controller, focusNode, _) {
                      return UserFormSmartTextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: const InputDecoration(
                          labelText: 'Τμήμα',
                          border: OutlineInputBorder(),
                        ),
                        textCapitalization: TextCapitalization.none,
                        lexiconSpellAssist: true,
                        onChanged: (_) => _onFieldChanged(),
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      return _nameAutocompleteOptionsView(
                        context,
                        onSelected,
                        options,
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  LexiconSpellTextFormField(
                    controller: locationController,
                    focusNode: _locationFocusNode,
                    decoration: const InputDecoration(
                      labelText: 'Τοποθεσία',
                      border: OutlineInputBorder(),
                      suffixIcon: LocationFieldHelpIcon(),
                    ),
                    onChanged: (_) => _onFieldChanged(),
                  ),
                  FullLocationLine(text: _fullLocationText()),
                  const SizedBox(height: 12),
                  ResizableTextArea(
                    controller: notesController,
                    focusNode: _notesFocusNode,
                    decoration: const InputDecoration(
                      labelText: 'Σημειώσεις',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                    onChanged: (_) => _onFieldChanged(),
                  ),
                  if (equipmentLink.isVisible)
                    UserFormEquipmentChips(
                      entries: equipmentLink.entries,
                      onTapEquipment: equipmentLink.openEquipment,
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: dismissGuard.cancelAndClose,
              child: const Text('Ακύρωση'),
            ),
            FilledButton(
              onPressed: dismissGuard.isDirty ? saveFlow.save : null,
              child: Text(isEdit ? 'Αποθήκευση' : 'Προσθήκη'),
            ),
          ],
        ),
      ),
    );
  }
}
