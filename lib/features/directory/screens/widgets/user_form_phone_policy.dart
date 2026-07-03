part of 'user_form_dialog.dart';

mixin UserFormPhonePolicyMixin on UserFormDialogStateHost {
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

  @override
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

  @override
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

  @override
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
}
