part of 'user_form_dialog.dart';

const _kUserFormDuplicateSnack = SnackBar(
  content: Text(
    'Υπάρχει ήδη χρήστης με το ίδιο ονοματεπώνυμο (ισοδύναμη γραφή), το ίδιο τηλέφωνο και τους ίδιους κωδικούς εξοπλισμού. Διορθώστε τα δεδομένα.',
  ),
  backgroundColor: Colors.orange,
);

mixin UserFormSaveMixin on UserFormDialogStateHost {
  @override
  Future<({int? id, String name})> _resolveTargetDepartmentForSave() async {
    final name = _departmentController.text.trim();
    if (name.isEmpty) return (id: null, name: '');

    final id = await _resolveDepartmentIdForSave(
      DepartmentRepository(await DatabaseHelper.instance.database),
    );
    return (id: id, name: name);
  }

  /// Αν το πεδίο τμήματος δείχνει σε υπάρχον τμήμα (ίδιο name_key), επιστρέφει το id του·
  /// όταν αλλάζει μόνο η εμφάνιση (τόνοι/κεφαλαία), ενημερώνει και το `departments.name`.
  Future<int?> _resolveDepartmentIdForSave(DepartmentRepository dir) async {
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

  @override
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
            : await DepartmentRepository(await DatabaseHelper.instance.database)
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
    final dir = DepartmentRepository(db);
    final departmentId = await _resolveDepartmentIdForSave(dir);

    if (phoneConflictBatch != null && !phoneConflictBatch.isEmpty) {
      await PhoneDepartmentPolicy.applyUserPhoneConflictResolutions(
        phones: PhoneRepository(db),
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
        ScaffoldMessenger.of(context).showSnackBar(_kUserFormDuplicateSnack);
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
        ScaffoldMessenger.of(context).showSnackBar(_kUserFormDuplicateSnack);
        return;
      }
      await widget.notifier.updateUser(user);
      if (phoneDisconnectBatch != null) {
        final db = await DatabaseHelper.instance.database;
        await applyPersonalPhoneDisconnectBatch(
          db,
          phoneDisconnectBatch,
          sourceDepartmentId: departmentId,
        );
        await widget.notifier.loadUsers();
      }
      ref.invalidate(lookupServiceProvider);
      await ref.read(lookupServiceProvider.future);
      if (!mounted) return;
      final saveMessage = buildSaveConfirmationMessage(
        entityType: AuditEntityTypes.user,
        entityLabel: _buildUserDisplayName(),
        oldMap: _userMapForSaveConfirmation(
          widget.initialUser!.toMap(),
          departmentDisplayName:
              widget.initialUser!.departmentName?.trim() ??
              _initialDepartmentText.trim(),
        ),
        newMap: _userMapForSaveConfirmation(
          user.toMap(),
          departmentDisplayName: _departmentController.text.trim(),
        ),
        isNew: false,
      );
      widget.onSaved?.call();
      Navigator.of(context).pop(true);
      showSaveConfirmationSnackBar(context, saveMessage);
      return;
    }
    if (await widget.notifier.hasDuplicateUserFresh(user)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(_kUserFormDuplicateSnack);
      return;
    }
    await widget.notifier.addUser(user);
    ref.invalidate(lookupServiceProvider);
    await ref.read(lookupServiceProvider.future);
    if (!mounted) return;
    final saveMessage = buildSaveConfirmationMessage(
      entityType: AuditEntityTypes.user,
      entityLabel: _buildUserDisplayName(),
      oldMap: const {},
      newMap: user.toMap(),
      isNew: true,
    );
    widget.onSaved?.call();
    Navigator.of(context).pop(true);
    showSaveConfirmationSnackBar(context, saveMessage);
  }

  Map<String, dynamic> _userMapForSaveConfirmation(
    Map<String, dynamic> source, {
    required String departmentDisplayName,
  }) {
    final map = Map<String, dynamic>.from(source);
    if (map.containsKey('department_id')) {
      final name = departmentDisplayName.trim();
      map['department_id'] = name.isEmpty ? null : name;
    }
    return map;
  }
}
