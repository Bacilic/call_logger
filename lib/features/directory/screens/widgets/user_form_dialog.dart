import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/database/directory_repository.dart';
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
import '../../../../core/services/lookup_service.dart';
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

class _UserFormDialogState extends ConsumerState<UserFormDialog> {
  final _formKey = GlobalKey<FormState>();

  /// Αρχικό κείμενο τμήματος όπως στη βάση (εμφάνιση· επαναφορά στον διάλογο μεταφοράς).
  late final String _initialDepartmentText;

  /// Κανονικοποιημένο κλειδί αρχικού τμήματος μόνο για σύγκριση dirty / διάλογο.
  late final String _snapDepartmentNorm;
  late final String _snapLastName;
  late final String _snapFirstName;
  late final String _snapPhone;
  late final String _snapNotes;
  late final TextEditingController _lastNameController;
  late final SpellCheckController _firstNameController;
  late final TextEditingController _phoneController;
  late final SpellCheckController _departmentController;
  late final SpellCheckController _notesController;

  final FocusNode _lastNameFocusNode = FocusNode();
  final FocusNode _firstNameFocusNode = FocusNode();
  final FocusNode _phoneFocusNode = FocusNode();
  final FocusNode _departmentFocusNode = FocusNode();
  final FocusNode _notesFocusNode = FocusNode();

  bool get _isEdit => widget.initialUser != null && !widget.isClone;

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  bool get _isDirty {
    if (_lastNameController.text.trim() != _snapLastName) return true;
    if (_firstNameController.text.trim() != _snapFirstName) return true;
    if (_phoneController.text.trim() != _snapPhone) return true;
    if (_notesController.text.trim() != _snapNotes) return true;
    // Εμφανιζόμενο κείμενο (όχι μόνο κανονικοποίηση): τόνοι/κεφαλαία μετράνε ως αλλαγή.
    if (_departmentController.text.trim() != _initialDepartmentText) return true;
    return false;
  }

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

  String _buildUserDisplayName() {
    final f = _firstNameController.text.trim();
    final l = _lastNameController.text.trim();
    if (f.isEmpty && l.isEmpty) return '—';
    return '$f $l'.trim();
  }

  String _snapDisplayName() {
    final f = _snapFirstName.trim();
    final l = _snapLastName.trim();
    if (f.isEmpty && l.isEmpty) return '—';
    return '$f $l'.trim();
  }

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

  List<String> _removedPhonesFromField() {
    final before = PhoneListParser.splitPhones(_snapPhone);
    final after = PhoneListParser.splitPhones(_phoneController.text).toSet();
    return before.where((p) => !after.contains(p)).toList();
  }

  /// Τηλέφωνα που αφαιρούνται από το πεδίο και συνδέονται μόνο με τον τρέχοντα χρήστη.
  List<String> _exclusiveRemovedPhones() {
    final editingId = widget.initialUser?.id;
    if (!_isEdit || editingId == null) return const [];

    final removed = _removedPhonesFromField();
    if (removed.isEmpty) return const [];

    final exclusive = <String>[];
    for (final phone in removed) {
      final owners = widget.notifier.allUsersForUi.where((u) {
        if (u.isDeleted) return false;
        return u.phones.any((p) => p.trim() == phone.trim());
      }).toList();
      if (owners.length == 1 && owners.first.id == editingId) {
        exclusive.add(phone);
      }
    }
    return exclusive;
  }

  ({int? id, String? name}) _resolveSourceDepartmentForDisconnect() {
    final typed = _departmentController.text.trim();
    if (typed.isEmpty) return (id: null, name: null);

    final key = SearchTextNormalizer.normalizeForSearch(typed);
    if (key.isEmpty) return (id: null, name: null);

    for (final d in LookupService.instance.departments) {
      if (d.isDeleted) continue;
      if (SearchTextNormalizer.normalizeForSearch(d.name) == key) {
        return (id: d.id, name: d.name.trim());
      }
    }
    return (id: null, name: null);
  }

  List<String> _phonesToValidateForPolicy() {
    final current = PhoneListParser.splitPhones(_phoneController.text);
    if (!_isEdit || widget.isClone) return current;
    final deptChanged =
        SearchTextNormalizer.normalizeForSearch(_departmentController.text) !=
        _snapDepartmentNorm;
    if (deptChanged) return current;
    return PhoneDepartmentPolicy.addedPhones(
      beforePhones: PhoneListParser.splitPhones(_snapPhone),
      afterPhones: current,
    );
  }

  Future<({int? id, String name})> _resolveTargetDepartmentForSave() async {
    final name = _departmentController.text.trim();
    if (name.isEmpty) return (id: null, name: '');

    final id = await _resolveDepartmentIdForSave(
      DirectoryRepository(await DatabaseHelper.instance.database),
    );
    return (id: id, name: name);
  }

  /// Αν το πεδίο τμήματος δείχνει σε υπάρχον τμήμα (ίδιο name_key), επιστρέφει το id του·
  /// όταν αλλάζει μόνο η εμφάνιση (τόνοι/κεφαλαία), ενημερώνει και το `departments.name`.
  Future<int?> _resolveDepartmentIdForSave(DirectoryRepository dir) async {
    final typed = _departmentController.text.trim();
    if (typed.isEmpty) return null;

    final matched = _resolveSourceDepartmentForDisconnect();
    if (matched.id != null) {
      final stored = (matched.name ?? '').trim();
      if (stored != typed) {
        await dir.updateDepartment(matched.id!, {'name': typed});
      }
      return matched.id;
    }

    return dir.getOrCreateDepartmentIdByName(typed);
  }

  Future<UserPhoneConflictBatchResult?> _confirmUserPhoneAssignmentConflicts({
    required int? editingUserId,
  }) async {
    final phones = _phonesToValidateForPolicy();
    if (phones.isEmpty) return const UserPhoneConflictBatchResult();

    final target = await _resolveTargetDepartmentForSave();
    final conflicts = PhoneDepartmentPolicy.findConflictsForUserAssignment(
      phones: phones,
      targetDepartmentId: target.id,
      editingUserId: editingUserId,
    );
    if (conflicts.isEmpty) return const UserPhoneConflictBatchResult();

    if (!mounted) return null;
    return showUserPhoneDepartmentConflictDialog(
      context,
      conflicts: conflicts,
      userDisplayName: _buildUserDisplayName(),
      targetDepartmentName: target.name,
      targetDepartmentId: target.id,
    );
  }

  Future<SharedAssetDisconnectBatchResult?>
  _confirmExclusiveRemovedPhonesDisconnect() async {
    final phones = _exclusiveRemovedPhones();
    if (phones.isEmpty) return const SharedAssetDisconnectBatchResult();

    final lookup = LookupService.instance;
    final source = _resolveSourceDepartmentForDisconnect();
    final departments = lookup.departments
        .where((d) => !d.isDeleted && d.name.trim().isNotEmpty)
        .toList();

    if (!mounted) return null;
    return showSharedAssetDisconnectFlow(
      context: context,
      sourceDepartmentId: source.id,
      sourceDepartmentName: source.name,
      phones: phones,
      availableDepartments: departments,
      mode: SharedAssetDisconnectMode.personalPhone,
      personalPhoneUserDisplayName: _buildUserDisplayName(),
    );
  }

  static const _duplicateSnack = SnackBar(
    content: Text(
      'Υπάρχει ήδη χρήστης με το ίδιο ονοματεπώνυμο (ισοδύναμη γραφή), το ίδιο τηλέφωνο και τους ίδιους κωδικούς εξοπλισμού. Διορθώστε τα δεδομένα.',
    ),
    backgroundColor: Colors.orange,
  );

  /// Χρήστης με συνωνυμία (όνομα / επώνυμο / και τα δύο), εκτός τρέχουσας/πηγής αντίγραφου.
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

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_isDirty) return;

    final homonym = _findSoftHomonymUser();
    if (homonym != null) {
      if (!mounted) return;
      final existingDept = homonym.departmentName?.trim() ?? '';
      final choice = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => HomonymWarningDialog(
          userDisplayName: _buildUserDisplayName(),
          existingRecordDepartmentName: existingDept,
        ),
      );
      if (!mounted) return;
      if (choice != true) return;
    }

    var cloneAsNewEmployee = false;

    if (_isEdit && _nameIdentityChanged()) {
      if (!mounted) return;
      final nameChoice = await showUserNameChangeConfirmDialog(
        context: context,
        oldDisplayName: _snapDisplayName(),
        newDisplayName: _buildUserDisplayName(),
      );
      if (!mounted) return;
      if (nameChoice == null) return;
      if (nameChoice == UserNameChangeDialogChoice.newEmployee) {
        cloneAsNewEmployee = true;
      }
    }

    try {
      final initialDeptNorm = SearchTextNormalizer.normalizeForSearch(
        _initialDepartmentText,
      );
      final currentDeptNorm = SearchTextNormalizer.normalizeForSearch(
        _departmentController.text,
      );
      if (initialDeptNorm != currentDeptNorm) {
        final existsInOrg = currentDeptNorm.isEmpty
            ? true
            : await DirectoryRepository(await DatabaseHelper.instance.database)
                .departmentNameExists(
                _departmentController.text,
              );
        if (!mounted) return;
        final useAddToDepartmentMessage =
            !_isEdit || widget.isClone || _initialDepartmentText.trim().isEmpty;
        final result = await showDepartmentTransferConfirmDialog(
          context: context,
          userDisplayName: _buildUserDisplayName(),
          oldDepartment: _initialDepartmentText,
          newDepartment: _departmentController.text,
          newDepartmentExistsInOrg: existsInOrg,
          useAddToDepartmentMessage: useAddToDepartmentMessage,
        );
        final effective =
            result ?? DepartmentTransferDialogResult.cancelTransfer;
        if (effective == DepartmentTransferDialogResult.cancelTransfer) {
          _departmentController.text = _initialDepartmentText;
          return;
        }
      }

      SharedAssetDisconnectBatchResult? phoneDisconnectBatch;
      if (_isEdit && !cloneAsNewEmployee) {
        phoneDisconnectBatch = await _confirmExclusiveRemovedPhonesDisconnect();
        if (!mounted) return;
        if (phoneDisconnectBatch == null) return;
      }

      final editingUserId =
          _isEdit && !cloneAsNewEmployee && !widget.isClone
          ? widget.initialUser?.id
          : null;
      final phoneConflictBatch = await _confirmUserPhoneAssignmentConflicts(
        editingUserId: editingUserId,
      );
      if (!mounted) return;
      if (phoneConflictBatch == null) return;

      await _persistUser(
        cloneAsNewEmployee: cloneAsNewEmployee,
        phoneDisconnectBatch: phoneDisconnectBatch,
        phoneConflictBatch: phoneConflictBatch,
      );
    } on PhoneDepartmentPolicyException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Απορρίφθηκε η αποθήκευση: το(α) τηλέφωνο(α) '
            '${e.conflicts.map((c) => c.phone).join(', ')} '
            'συγκρούεται με τμήμα άλλου καταλόγου.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e, st) {
      if (!mounted) return;
      showDatabasePersistenceErrorSnackBar(context, e, st);
    }
  }

  Future<void> _persistUser({
    bool cloneAsNewEmployee = false,
    SharedAssetDisconnectBatchResult? phoneDisconnectBatch,
    UserPhoneConflictBatchResult? phoneConflictBatch,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final dir = DirectoryRepository(db);
    final departmentId = await _resolveDepartmentIdForSave(dir);

    if (phoneConflictBatch != null && !phoneConflictBatch.isEmpty) {
      await PhoneDepartmentPolicy.applyUserPhoneConflictResolutions(
        dir: dir,
        resolutions: phoneConflictBatch,
        targetDepartmentId: departmentId,
      );
      LookupService.instance.resetForReload();
      await LookupService.instance.loadFromDatabase();
    }

    final user = UserModel(
      id: (_isEdit && !cloneAsNewEmployee) ? widget.initialUser?.id : null,
      lastName: _lastNameController.text.trim(),
      firstName: _firstNameController.text.trim(),
      phones: PhoneListParser.splitPhones(_phoneController.text),
      departmentId: departmentId,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    );

    if (_isEdit && cloneAsNewEmployee) {
      final sourceId = widget.initialUser?.id;
      if (sourceId == null) return;
      if (await widget.notifier.hasDuplicateUserFresh(
        user,
        mirrorEquipmentFromUserId: sourceId,
      )) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(_duplicateSnack);
        return;
      }
      await widget.notifier.addUserCloningEquipmentFrom(user, sourceId);
      ref.invalidate(lookupServiceProvider);
      await ref.read(lookupServiceProvider.future);
      if (!mounted) return;
      widget.onSaved?.call();
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Δημιουργήθηκε νέος υπάλληλος· αντιγράφηκαν οι συνδέσεις εξοπλισμού.',
          ),
        ),
      );
      return;
    }

    if (_isEdit) {
      if (user.id != null &&
          await widget.notifier.hasDuplicateUserFresh(
            user,
            excludeId: user.id,
          )) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(_duplicateSnack);
        return;
      }
      await widget.notifier.updateUser(user);
      if (phoneDisconnectBatch != null) {
        final db = await DatabaseHelper.instance.database;
        await applyPersonalPhoneDisconnectBatch(
          DirectoryRepository(db),
          phoneDisconnectBatch,
          sourceDepartmentId: departmentId,
        );
        await widget.notifier.loadUsers();
      }
      ref.invalidate(lookupServiceProvider);
      await ref.read(lookupServiceProvider.future);
      if (!mounted) return;
      widget.onSaved?.call();
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Αποθηκεύτηκε')));
      return;
    }
    if (await widget.notifier.hasDuplicateUserFresh(user)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(_duplicateSnack);
      return;
    }
    await widget.notifier.addUser(user);
    ref.invalidate(lookupServiceProvider);
    await ref.read(lookupServiceProvider.future);
    if (!mounted) return;
    widget.onSaved?.call();
    Navigator.of(context).pop(true);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Αποθηκεύτηκε')));
  }

  String get _title {
    if (_isEdit) return 'Επεξεργασία χρήστη';
    if (widget.isClone) return 'Αντίγραφο χρήστη';
    return 'Νέος χρήστης';
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
    return AlertDialog(
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
              UserFormSmartTextField(
                controller: _phoneController,
                focusNode: _phoneFocusNode,
                decoration: const InputDecoration(
                  labelText: 'Τηλέφωνο',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Ακύρωση'),
        ),
        FilledButton(
          onPressed: _isDirty ? _save : null,
          child: Text(_isEdit ? 'Αποθήκευση' : 'Προσθήκη'),
        ),
      ],
    );
  }
}
