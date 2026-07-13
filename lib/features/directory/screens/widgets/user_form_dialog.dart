import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/database/department_repository.dart';
import '../../../../core/database/phone_repository.dart';
import '../../../../core/directory/phone_department_policy.dart';
import '../../../../core/widgets/database_persistence_error_snackbar.dart';
import '../../../../core/providers/settings_provider.dart';
import '../../../../core/providers/spell_check_provider.dart';
import '../../../../core/utils/search_text_normalizer.dart';
import '../../../../core/utils/user_homonym_finder.dart';
import '../../../../core/utils/user_identity_normalizer.dart';
import '../../../../core/utils/phone_list_parser.dart';
import '../../../../core/widgets/lexicon_spell_text_form_field.dart';
import '../../../../core/widgets/spell_check_controller.dart';
import '../../../../core/database/audit_service.dart';
import '../../../../core/services/lookup_service.dart';
import '../../../../core/services/save_confirmation_summary.dart';
import '../../../../core/widgets/audit_summary_rich_text.dart';
import '../../../calls/models/user_model.dart';
import '../../../calls/provider/lookup_provider.dart';
import '../../providers/directory_provider.dart';
import '../../services/shared_asset_disconnect_apply.dart';
import 'department_transfer_confirm_dialog.dart';
import 'homonym_warning_dialog.dart';
import 'shared_asset_disconnect_dialog.dart';
import 'user_name_change_confirm_dialog.dart';
import 'user_phone_department_conflict_dialog.dart';
import 'user_form_smart_text_field.dart';

part 'user_form_dismiss_guard.dart';
part 'user_form_phone_policy.dart';
part 'user_form_save.dart';

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
  ConsumerState<UserFormDialog> createState() => _UserFormDialogState();
}

mixin UserFormDialogStateHost on ConsumerState<UserFormDialog> {
  GlobalKey<FormState> get _formKey;
  TextEditingController get _lastNameController;
  SpellCheckController get _firstNameController;
  TextEditingController get _phoneController;
  SpellCheckController get _departmentController;
  SpellCheckController get _notesController;

  String get _initialDepartmentText;
  String get _snapDepartmentNorm;
  String get _snapLastName;
  String get _snapFirstName;
  String get _snapPhone;
  String get _snapNotes;

  bool get _isEdit;

  // ignore: unused_element — απαιτείται από part mixins· ο analyzer δεν το ανιχνεύει.
  void _onFieldChanged();

  // ignore: unused_element
  bool get _isDirty;

  String _buildUserDisplayName();
  String _snapDisplayName();
  bool _nameIdentityChanged();
  UserModel? _findSoftHomonymUser();

  Future<void> _save();

  ({int? id, String? name}) _resolveSourceDepartmentForDisconnect();

  Future<({int? id, String name})> _resolveTargetDepartmentForSave();

  Future<UserPhoneConflictBatchResult?> _confirmUserPhoneAssignmentConflicts({
    required int? editingUserId,
  });

  Future<SharedAssetDisconnectBatchResult?>
  _confirmExclusiveRemovedPhonesDisconnect();
}

class _UserFormDialogState extends ConsumerState<UserFormDialog>
    with
        UserFormDialogStateHost,
        UserFormDismissGuardMixin,
        UserFormPhonePolicyMixin,
        UserFormSaveMixin {
  @override
  final _formKey = GlobalKey<FormState>();

  /// Αρχικό κείμενο τμήματος όπως στη βάση (εμφάνιση· επαναφορά στον διάλογο μεταφοράς).
  @override
  late final String _initialDepartmentText;

  /// Κανονικοποιημένο κλειδί αρχικού τμήματος μόνο για σύγκριση dirty / διάλογο.
  @override
  late final String _snapDepartmentNorm;
  @override
  late final String _snapLastName;
  @override
  late final String _snapFirstName;
  @override
  late final String _snapPhone;
  @override
  late final String _snapNotes;
  @override
  late final TextEditingController _lastNameController;
  @override
  late final SpellCheckController _firstNameController;
  @override
  late final TextEditingController _phoneController;
  @override
  late final SpellCheckController _departmentController;
  @override
  late final SpellCheckController _notesController;

  final FocusNode _lastNameFocusNode = FocusNode();
  final FocusNode _firstNameFocusNode = FocusNode();
  final FocusNode _phoneFocusNode = FocusNode();
  final FocusNode _departmentFocusNode = FocusNode();
  final FocusNode _notesFocusNode = FocusNode();

  @override
  bool get _isEdit => widget.initialUser != null && !widget.isClone;

  void _selectAll(TextEditingController c) {
    c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
  }

  @override
  void initState() {
    super.initState();
    final u = widget.initialUser;
    _snapLastName = (u?.lastName ?? '').trim();
    _snapFirstName = (u?.firstName ?? '').trim();
    _snapPhone = PhoneListParser.joinPhones(u?.phones ?? const []);
    _snapNotes = (u?.notes ?? '').trim();
    _initialDepartmentText = (u?.departmentName ?? '').trim();
    _snapDepartmentNorm = SearchTextNormalizer.normalizeForSearch(
      _initialDepartmentText,
    );

    _lastNameController = TextEditingController(text: u?.lastName ?? '');
    _firstNameController = SpellCheckController()..text = u?.firstName ?? '';
    _phoneController = TextEditingController(
      text: PhoneListParser.joinPhones(u?.phones ?? const []),
    );
    _departmentController = SpellCheckController()
      ..text = _initialDepartmentText;
    _notesController = SpellCheckController()..text = (u?.notes ?? '');

    _lastNameController.addListener(_onFieldChanged);
    _firstNameController.addListener(_onFieldChanged);
    _phoneController.addListener(_onFieldChanged);
    _departmentController.addListener(_onFieldChanged);
    _notesController.addListener(_onFieldChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (widget.focusedField) {
        case 'lastName':
          _lastNameFocusNode.requestFocus();
          _selectAll(_lastNameController);
          break;
        case 'phone':
          _phoneFocusNode.requestFocus();
          _selectAll(_phoneController);
          break;
        case 'department':
          _departmentFocusNode.requestFocus();
          _selectAll(_departmentController);
          break;
        case 'notes':
          _notesFocusNode.requestFocus();
          _selectAll(_notesController);
          break;
        case 'firstName':
        default:
          _firstNameFocusNode.requestFocus();
          _selectAll(_firstNameController);
          break;
      }
    });
  }

  @override
  void dispose() {
    _lastNameController.removeListener(_onFieldChanged);
    _firstNameController.removeListener(_onFieldChanged);
    _phoneController.removeListener(_onFieldChanged);
    _departmentController.removeListener(_onFieldChanged);
    _notesController.removeListener(_onFieldChanged);

    _lastNameFocusNode.dispose();
    _firstNameFocusNode.dispose();
    _phoneFocusNode.dispose();
    _departmentFocusNode.dispose();
    _notesFocusNode.dispose();

    _lastNameController.dispose();
    _firstNameController.dispose();
    _phoneController.dispose();
    _departmentController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String? _requiredValidator(String? v) =>
      (v?.trim().isEmpty ?? true) ? 'Υποχρεωτικό' : null;

  @override
  String _buildUserDisplayName() {
    final f = _firstNameController.text.trim();
    final l = _lastNameController.text.trim();
    if (f.isEmpty && l.isEmpty) return '—';
    return '$f $l'.trim();
  }

  @override
  String _snapDisplayName() {
    final f = _snapFirstName.trim();
    final l = _snapLastName.trim();
    if (f.isEmpty && l.isEmpty) return '—';
    return '$f $l'.trim();
  }

  @override
  bool _nameIdentityChanged() {
    return UserIdentityNormalizer.identityKeyForPerson(
          _snapFirstName,
          _snapLastName,
        ) !=
        UserIdentityNormalizer.identityKeyForPerson(
          _firstNameController.text,
          _lastNameController.text,
        );
  }

  /// Χρήστης με συνωνυμία (όνομα / επώνυμο / και τα δύο), εκτός τρέχουσας/πηγής αντίγραφου.
  @override
  UserModel? _findSoftHomonymUser() {
    final int? excludeId =
        widget.initialUser != null && (_isEdit || widget.isClone)
        ? widget.initialUser!.id
        : null;
    return UserHomonymFinder.findHomonymUser(
      users: widget.notifier.allUsersForUi,
      firstName: _firstNameController.text,
      lastName: _lastNameController.text,
      excludeUserId: excludeId,
    );
  }

  String get _title {
    if (_isEdit) return 'Επεξεργασία Υπαλλήλου';
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

  String _phoneDisplayStringForAutocompleteOption(String option) {
    final text = _phoneController.text;
    final offset = _phoneController.selection.isValid
        ? _phoneController.selection.extentOffset
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
        .whenData(_firstNameController.attachSpellService);
    ref
        .watch(enableSpellCheckProvider)
        .whenData(_firstNameController.setSpellCheckEnabled);
    ref
        .watch(spellCheckServiceProvider)
        .whenData(_departmentController.attachSpellService);
    ref
        .watch(enableSpellCheckProvider)
        .whenData(_departmentController.setSpellCheckEnabled);

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
      _lastNameController.text,
    );
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RawAutocomplete<String>(
                textEditingController: _lastNameController,
                focusNode: _lastNameFocusNode,
                optionsBuilder: (textEditingValue) {
                  final q = SearchTextNormalizer.normalizeForSearch(
                    textEditingValue.text,
                  );
                  if (q.isEmpty) return lastNameOptions;
                  return lastNameOptions.where(
                    (name) =>
                        SearchTextNormalizer.matchesNormalizedQuery(name, q),
                  );
                },
                displayStringForOption: (option) => option,
                onSelected: (selection) {
                  _lastNameController.text = selection;
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
              RawAutocomplete<String>(
                textEditingController: _firstNameController,
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
                    (name) =>
                        SearchTextNormalizer.matchesNormalizedQuery(name, q),
                  );
                },
                displayStringForOption: (option) => option,
                onSelected: (selection) {
                  _firstNameController.text = selection;
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
              const SizedBox(height: 12),
              RawAutocomplete<String>(
                textEditingController: _phoneController,
                focusNode: _phoneFocusNode,
                optionsBuilder: _phoneAutocompleteOptions,
                displayStringForOption: _phoneDisplayStringForAutocompleteOption,
                onSelected: (option) {
                  final offset = _phoneController.selection.isValid
                      ? _phoneController.selection.extentOffset
                      : _phoneController.text.length;
                  final updated = PhoneListParser.replaceActiveSegment(
                    text: _phoneController.text,
                    cursor: offset,
                    replacement: option,
                  );
                  final cursorPos = updated.cursor;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _phoneController.selection = TextSelection.collapsed(
                      offset: cursorPos.clamp(0, _phoneController.text.length),
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
                  return _nameAutocompleteOptionsView(
                    context,
                    onSelected,
                    options,
                  );
                },
              ),
              const SizedBox(height: 12),
              RawAutocomplete<String>(
                textEditingController: _departmentController,
                focusNode: _departmentFocusNode,
                optionsBuilder: (textEditingValue) {
                  final q = SearchTextNormalizer.normalizeForSearch(
                    textEditingValue.text,
                  );
                  if (q.isEmpty) return departmentNames;
                  return departmentNames.where(
                    (name) =>
                        SearchTextNormalizer.matchesNormalizedQuery(name, q),
                  );
                },
                displayStringForOption: (option) => option,
                onSelected: (selection) {
                  _departmentController.text = selection;
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
                controller: _notesController,
                focusNode: _notesFocusNode,
                decoration: const InputDecoration(
                  labelText: 'Σημειώσεις',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 3,
                onChanged: (_) => _onFieldChanged(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _cancelAndClose,
          child: const Text('Ακύρωση'),
        ),
        FilledButton(
          onPressed: _isDirty ? _save : null,
          child: Text(_isEdit ? 'Αποθήκευση' : 'Προσθήκη'),
        ),
      ],
    ),
    );
  }
}
