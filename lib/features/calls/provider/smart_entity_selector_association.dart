part of 'smart_entity_selector_provider.dart';

/// Συσχετίσεις, quick-add orphan και γρήγορες εκκρεμότητες.
mixin SmartEntitySelectorAssociationMixin on Notifier<SmartEntitySelectorState> {
  SmartEntitySelectorNotifier get _host => this as SmartEntitySelectorNotifier;

  /// Εμφανίζει τον υπάρχοντα διάλογο σύγκρουσης αν χρειάζεται· επιστρέφει το
  /// τηλέφωνο προς σύνδεση ή null αν ο χρήστης ακύρωσε / δεν υπάρχει context.
  Future<String?> _confirmAndPreparePhoneAssociation({
    required BuildContext? context,
    required PhoneRepository phonesRepo,
    required String phone,
    required int? targetDepartmentId,
    required int? editingUserId,
    required String userDisplayName,
    required String targetDepartmentName,
  }) async {
    final trimmed = phone.trim();
    if (trimmed.isEmpty) return null;

    final conflicts = PhoneDepartmentPolicy.findConflictsForUserAssignment(
      phones: [trimmed],
      targetDepartmentId: targetDepartmentId,
      editingUserId: editingUserId,
    );
    if (conflicts.isEmpty) return trimmed;

    if (context == null || !context.mounted) {
      return null;
    }

    final result = await showUserPhoneDepartmentConflictDialog(
      context,
      conflicts: conflicts,
      userDisplayName: userDisplayName,
      targetDepartmentName: targetDepartmentName,
      targetDepartmentId: targetDepartmentId,
    );
    if (result == null) return null;

    await PhoneDepartmentPolicy.applyUserPhoneConflictResolutions(
      phones: phonesRepo,
      resolutions: result,
      targetDepartmentId: targetDepartmentId,
    );
    ref.invalidate(lookupServiceProvider);
    await ref.read(lookupServiceProvider.future);
    return trimmed;
  }

  void _resetAssociationQuickTaskCycle() {
    _host._associationQuickTaskId = null;
    _host._callerAwaitingPhoneAssociation = false;
    _host.clearPendingAuditOrigins();
  }

  Future<OrphanQuickAddResult?> quickAddOrphanToDepartment({
    bool forceSharedOnConflict = false,
  }) async {
    final s = state;
    if (!s.needsOrphanDepartmentQuickAdd) return null;
    final lookup = (await ref.read(lookupServiceProvider.future)).service;
    final deptText = s.departmentText.trim();
    var departmentId = s.selectedDepartmentId;
    DepartmentModel? selectedDepartment;
    if (departmentId != null) {
      for (final d in lookup.departments) {
        if (d.id == departmentId && !d.isDeleted) {
          selectedDepartment = d;
          break;
        }
      }
    } else {
      selectedDepartment = lookup.findDepartmentByName(deptText);
      departmentId = selectedDepartment?.id;
    }
    final phone = s.selectedPhone?.trim();
    final equipmentCode = s.equipmentText.trim().isEmpty
        ? null
        : s.equipmentText.trim();

    final dbOrphan = await DatabaseHelper.instance.database;
    final departmentsOrphan = DepartmentRepository(dbOrphan);
    final phonesOrphan = PhoneRepository(dbOrphan);
    final equipmentOrphan = EquipmentRepository(dbOrphan);
    final deptExistedBefore =
        deptText.isNotEmpty && await departmentsOrphan.departmentNameExists(deptText);
    final phoneExistedBefore = (phone != null && phone.isNotEmpty)
        ? await phonesOrphan.phoneNumberExists(phone)
        : true;
    final equipmentExistedBefore = (equipmentCode != null)
        ? await equipmentOrphan.equipmentCodeExists(equipmentCode)
        : true;

    final phoneUsage = (phone != null && phone.isNotEmpty)
        ? lookup.checkPhoneUsage(phone)
        : null;
    final equipmentUsage = (equipmentCode != null)
        ? lookup.checkEquipmentUsage(equipmentCode)
        : null;

    final phoneConflict =
        phoneUsage != null &&
        (phoneUsage.hasUserOwners ||
            (phoneUsage.departmentId != null &&
                departmentId != null &&
                phoneUsage.departmentId != departmentId));
    final equipmentConflict =
        equipmentUsage != null &&
        (equipmentUsage.hasUserOwners ||
            (equipmentUsage.departmentId != null &&
                departmentId != null &&
                equipmentUsage.departmentId != departmentId));
    final hasConflict = phoneConflict || equipmentConflict;
    final phoneNeedsShared =
        phone != null &&
        phone.isNotEmpty &&
        (phoneUsage == null ||
            phoneUsage.hasUserOwners ||
            departmentId == null ||
            phoneUsage.departmentId != departmentId);
    final equipmentNeedsShared =
        equipmentCode != null &&
        (equipmentUsage == null ||
            equipmentUsage.hasUserOwners ||
            departmentId == null ||
            equipmentUsage.departmentId != departmentId);
    if (hasConflict && !forceSharedOnConflict) {
      final lines = <String>[
        'Εντοπίστηκαν πιθανές συγκρούσεις για Shared Policy.',
      ];
      if (phoneConflict) {
        if (phoneUsage.hasUserOwners) {
          lines.add(
            'Το τηλέφωνο ${phoneUsage.phone} ανήκει ήδη στους: ${phoneUsage.userNames.join(', ')}.',
          );
        }
        if (phoneUsage.departmentId != null &&
            phoneUsage.departmentName != null) {
          lines.add(
            'Το τηλέφωνο ${phoneUsage.phone} έχει ήδη τοποθεσία τμήμα: ${phoneUsage.departmentName}.',
          );
        }
      }
      if (equipmentConflict) {
        if (equipmentUsage.hasUserOwners) {
          lines.add(
            'Ο εξοπλισμός ${equipmentUsage.code} ανήκει ήδη στους: ${equipmentUsage.userNames.join(', ')}.',
          );
        }
        if (equipmentUsage.departmentId != null &&
            equipmentUsage.departmentName != null) {
          lines.add(
            'Ο εξοπλισμός ${equipmentUsage.code} έχει ήδη τοποθεσία τμήμα: ${equipmentUsage.departmentName}.',
          );
        }
      }
      lines.add(
        'Θέλετε να καταχωρηθούν ΚΑΙ ως κοινόχρηστα στο τμήμα ${deptText.isEmpty ? '—' : deptText};',
      );
      return OrphanQuickAddResult(
        requiresConfirmation: true,
        message: lines.join('\n'),
      );
    }

    departmentId ??= await departmentsOrphan.getOrCreateDepartmentIdByName(deptText);
    if (departmentId == null) {
      return const OrphanQuickAddResult(
        requiresConfirmation: false,
        message: 'Δεν βρέθηκε/δημιουργήθηκε τμήμα.',
      );
    }

    if (phoneNeedsShared) {
      await phonesOrphan.updatePhoneDepartment(phone, departmentId);
    }
    if (equipmentNeedsShared) {
      await equipmentOrphan.updateEquipmentDepartment(equipmentCode, departmentId);
    }

    await refreshDirectoryCaches(
      ref,
      users: phoneNeedsShared,
      equipment: equipmentNeedsShared,
      departments: true,
    );
    if (!ref.mounted) {
      return const OrphanQuickAddResult(
        requiresConfirmation: false,
        message: 'Η συσχέτιση ολοκληρώθηκε αλλά το container δεν είναι ενεργό.',
      );
    }
    final refreshed = (await ref.read(lookupServiceProvider.future)).service;
    final finalDepartment = refreshed.findDepartmentByName(deptText);
    state = state.copyWith(
      selectedDepartmentId: finalDepartment?.id ?? departmentId,
      departmentText: finalDepartment?.name ?? deptText,
      callerNoMatch: false,
      equipmentNoMatch: false,
    );

    final added = <String>[];
    if (phoneNeedsShared) added.add('τηλέφωνο');
    if (equipmentNeedsShared) added.add('εξοπλισμός');
    final associationWorkDone = added.isNotEmpty;
    final success = added.isEmpty
        ? 'Δεν υπήρχε στοιχείο προς καταχώρηση.'
        : 'Καταχωρήθηκε ${added.join(' και ')} ως κοινόχρηστο στο τμήμα ${state.departmentText.trim()}.';

    final newEntityEligible =
        (deptText.isNotEmpty && !deptExistedBefore) ||
        (phone != null && phone.isNotEmpty && !phoneExistedBefore) ||
        (equipmentCode != null && !equipmentExistedBefore);

    final resolvedDeptId = finalDepartment?.id ?? departmentId;
    final equipResolved = (equipmentCode != null && equipmentCode.isNotEmpty)
        ? refreshed.findEquipmentsByCode(equipmentCode)
        : const <EquipmentModel>[];
    final resolvedEquipmentId = equipResolved.isNotEmpty
        ? equipResolved.first.id
        : null;

    if (newEntityEligible || _host._associationQuickTaskId != null) {
      try {
        await _syncAssociationQuickTask(
          newEntityEligible: newEntityEligible,
          associationWorkDone: associationWorkDone,
          summaryText: success,
          callerName: null,
          callerId: null,
          departmentId: resolvedDeptId,
          equipmentId: resolvedEquipmentId,
          phoneText: phone,
          userText: null,
          equipmentText: equipmentCode,
          departmentText: state.departmentText.trim().isEmpty
              ? null
              : state.departmentText.trim(),
        );
      } catch (e, st) {
        developer.log(
          'orphan quick add task sync failed',
          name: 'SmartEntitySelectorNotifier',
          error: e,
          stackTrace: st,
        );
      }
    }

    return OrphanQuickAddResult(
      requiresConfirmation: false,
      message: success,
      successMessage: success,
    );
  }

  Future<String?> associateCurrentIfNeeded({
    bool updatePrimaryDepartment = false,
    BuildContext? context,
  }) async {
    final lookupForAssoc = ref.read(lookupServiceProvider).value?.service;
    if (!state.needsAssociation(lookupForAssoc)) return null;

    final msg = state.associationTooltip(lookupForAssoc);
    final dbAssoc = await DatabaseHelper.instance.database;
    final auditSince = await _host.maxAuditLogId(dbAssoc);
    final departments = DepartmentRepository(dbAssoc);
    final phones = PhoneRepository(dbAssoc);
    final equipmentRepo = EquipmentRepository(dbAssoc);
    final users = UserRepository(dbAssoc);
    if (state.needsNewCallerCreation) {
      final name = NameParserUtility.stripParentheticalSuffix(
        state.normalizedCallerDisplayText,
      );
      final phone = state.selectedPhone?.trim();
      final equipmentCode = state.equipmentText.trim();
      final parsed = NameParserUtility.parse(name);
      final deptTextRaw = state.departmentText.trim();
      final departmentExistedBefore =
          deptTextRaw.isNotEmpty &&
          await departments.departmentNameExists(deptTextRaw);
      final phoneExistedBefore = (phone != null && phone.isNotEmpty)
          ? await phones.phoneNumberExists(phone)
          : false;
      final equipmentExistedBefore = equipmentCode.isNotEmpty
          ? await equipmentRepo.equipmentCodeExists(equipmentCode)
          : false;

      final lookup = ref.read(lookupServiceProvider).value?.service;
      var departmentId =
          state.selectedDepartmentId ??
          (state.departmentText.trim().isNotEmpty && lookup != null
              ? lookup.findDepartmentByName(state.departmentText)?.id
              : null);
      if (departmentId == null && state.departmentText.trim().isNotEmpty) {
        departmentId = await departments.getOrCreateDepartmentIdByName(
          state.departmentText.trim(),
        );
      }
      try {
        var parsedPhones = PhoneListParser.splitPhones(phone);
        String? phoneForAssociation = phone;
        if (parsedPhones.isNotEmpty) {
          final dialogContext = context;
          if (dialogContext != null && !dialogContext.mounted) {
            parsedPhones = <String>[];
            phoneForAssociation = null;
          } else {
            final prepared = await _confirmAndPreparePhoneAssociation(
              context: dialogContext,
              phonesRepo: phones,
              phone: parsedPhones.first,
              targetDepartmentId: departmentId,
              editingUserId: null,
              userDisplayName: name,
              targetDepartmentName: departmentId != null
                  ? (lookup?.departmentIdToName[departmentId] ??
                        deptTextRaw)
                  : deptTextRaw,
            );
            if (prepared == null) {
              parsedPhones = <String>[];
              phoneForAssociation = null;
            } else {
              parsedPhones = PhoneListParser.splitPhones(prepared);
              phoneForAssociation = prepared;
            }
          }
        }
        final userId = await users.insertUser(
          firstName: parsed.firstName,
          lastName: parsed.lastName,
          phones: parsedPhones.isEmpty ? null : parsedPhones,
          departmentId: departmentId,
        );

        await users.updateAssociationsIfNeeded(
          userId,
          phoneForAssociation,
          equipmentCode.isNotEmpty ? equipmentCode : null,
        );

        final s = state;
        final lookupNow = ref.read(lookupServiceProvider).value?.service;
        final departmentIdNow =
            s.selectedDepartmentId ??
            departmentId ??
            (s.departmentText.trim().isNotEmpty && lookupNow != null
                ? lookupNow.findDepartmentByName(s.departmentText)?.id
                : null);
        final equipTrim = s.equipmentText.trim();
        state = state.copyWith(
          selectedCaller: UserModel(
            id: userId,
            firstName: parsed.firstName,
            lastName: parsed.lastName,
            phones: parsedPhones,
            departmentId: departmentIdNow,
          ),
          selectedDepartmentId: departmentIdNow,
          selectedEquipment: equipTrim.isNotEmpty
              ? EquipmentModel(code: equipTrim)
              : s.selectedEquipment,
          callerDisplayText: s.callerDisplayText.trim().isNotEmpty
              ? s.callerDisplayText
              : name,
          departmentText: s.departmentText,
        );
        _host._callerAwaitingPhoneAssociation = parsedPhones.isEmpty;
        await refreshDirectoryCaches(
          ref,
          users: true,
          equipment: equipmentCode.isNotEmpty,
          departments: deptTextRaw.isNotEmpty,
        );
        if (!ref.mounted) {
          return 'Σφάλμα αποθήκευσης: το container δεν είναι ενεργό.';
        }
        final refreshedLookup = (await ref.read(
          lookupServiceProvider.future,
        )).service;
        final matchedNewCallerEquipment = equipTrim.isEmpty
            ? const <EquipmentModel>[]
            : refreshedLookup.findEquipmentsByCode(equipTrim);
        final resolvedEquipmentId = matchedNewCallerEquipment.isEmpty
            ? null
            : matchedNewCallerEquipment.first.id;
        final resolvedDepartmentId =
            departmentIdNow ??
            departmentId ??
            (s.departmentText.trim().isNotEmpty
                ? refreshedLookup.findDepartmentByName(s.departmentText)?.id
                : null);
        // Πλήρες EquipmentModel με id — αλλιώς το hasEquipmentAssociation μείνει false
        // και το submit κλήσης ξανατρέχει συσχέτιση + δεύτερη γρήγορη εκκρεμότητα.
        if (matchedNewCallerEquipment.isNotEmpty) {
          state = state.copyWith(
            selectedEquipment: matchedNewCallerEquipment.first,
          );
        }
        await _syncAssociationQuickTask(
          newEntityEligible: true,
          associationWorkDone: true,
          summaryText: msg,
          callerName:
              state.selectedCaller?.name ?? state.callerDisplayText.trim(),
          callerId: userId,
          departmentId: resolvedDepartmentId,
          equipmentId: resolvedEquipmentId,
          phoneText: s.selectedPhone?.trim(),
          userText: s.callerDisplayText.trim().isEmpty
              ? null
              : s.callerDisplayText.trim(),
          equipmentText: equipTrim.isEmpty ? null : equipTrim,
          departmentText: s.departmentText.trim().isEmpty
              ? null
              : s.departmentText.trim(),
        );
        final createdDeptNow =
            deptTextRaw.isNotEmpty && !departmentExistedBefore;
        final lines = <String>[];
        final fullName = (state.selectedCaller?.name ?? state.callerDisplayText)
            .trim();
        final deptSuffix = deptTextRaw.isNotEmpty
            ? ' στο τμήμα: $deptTextRaw'
            : '';
        lines.add('Δημιουργήθηκε νέος χρήστης $fullName$deptSuffix');
        if (createdDeptNow) {
          lines.add('Δημιουργήθηκε νέο τμήμα: $deptTextRaw');
        }
        if (phone != null && phone.isNotEmpty) {
          lines.add(
            phoneExistedBefore
                ? 'Συσχετίστηκε τηλέφωνο: $phone'
                : 'Δημιουργήθηκε νέο τηλέφωνο: $phone',
          );
        }
        if (equipmentCode.isNotEmpty) {
          lines.add(
            equipmentExistedBefore
                ? 'Συσχετίστηκε εξοπλισμός: $equipmentCode'
                : 'Δημιουργήθηκε νέος εξοπλισμός: $equipmentCode',
          );
        }
        // Αν υπάρχει επιπλέον "τεχνικό" tooltip μήνυμα, το αφήνουμε στο τέλος ως περίληψη.
        final summary = msg?.trim();
        if (summary != null && summary.isNotEmpty) {
          lines.add(summary);
        }
        await _host.trackDerivativeAuditsSince(auditSince);
        return lines.join('\n');
      } catch (e) {
        await refreshDirectoryCaches(
          ref,
          users: true,
          equipment: true,
          departments: true,
        );
        return 'Σφάλμα αποθήκευσης: ${humanizeUserFacingError(e)}';
      }
    }

    if (state.selectedCaller?.id == null) return null;
    final userId = state.selectedCaller!.id!;
    final phone = state.hasPhoneAssociation
        ? null
        : state.selectedPhone?.trim();
    final eqCode = state.hasEquipmentAssociation(lookupForAssoc)
        ? null
        : state.equipmentText.trim();
    final hadPhoneWork = phone != null && phone.isNotEmpty;
    final hadEqWork = eqCode != null && eqCode.isNotEmpty;
    final newPhoneRow =
        hadPhoneWork && !await phones.phoneNumberExists(phone);
    final newEquipmentRow =
        hadEqWork && !await equipmentRepo.equipmentCodeExists(eqCode);
    final deptTrimAssoc = state.departmentText.trim();
    final callerHadNoPrimaryDept =
        state.selectedCaller?.departmentId == null &&
        (state.selectedCaller?.departmentName ?? '').trim().isEmpty;
    // Όταν ο καλών δεν είχε κύριο τμήμα, η πρώτη ανάθεση τμήματος στο πορτοκαλί
    // βήμα δεν μπλοκάρεται από dialog «Όχι» (δεν υπάρχει παλιό τμήμα προς διατήρηση).
    final effectiveUpdatePrimaryDepartment = updatePrimaryDepartment ||
        (state.hasPendingDepartmentChange &&
            callerHadNoPrimaryDept &&
            deptTrimAssoc.isNotEmpty);
    final willCreateDept =
        effectiveUpdatePrimaryDepartment && deptTrimAssoc.isNotEmpty;
    final newDepartmentRow =
        willCreateDept && !await departments.departmentNameExists(deptTrimAssoc);
    final newEntityEligible =
        newPhoneRow || newEquipmentRow || newDepartmentRow;
    try {
      String? phoneToLink = phone;
      if (phoneToLink != null && phoneToLink.isNotEmpty) {
        final caller = state.selectedCaller;
        final targetDeptId = caller?.departmentId ??
            state.selectedDepartmentId ??
            (state.departmentText.trim().isNotEmpty && lookupForAssoc != null
                ? lookupForAssoc.findDepartmentByName(state.departmentText)?.id
                : null);
        final targetDeptName = targetDeptId != null
            ? (lookupForAssoc?.departmentIdToName[targetDeptId] ??
                  state.departmentText.trim())
            : state.departmentText.trim();
        final dialogContext = context;
        if (dialogContext != null && !dialogContext.mounted) {
          phoneToLink = null;
        } else {
          phoneToLink = await _confirmAndPreparePhoneAssociation(
            context: dialogContext,
            phonesRepo: phones,
            phone: phoneToLink,
            targetDepartmentId: targetDeptId,
            editingUserId: userId,
            userDisplayName: caller?.name ?? state.callerDisplayText.trim(),
            targetDepartmentName: targetDeptName,
          );
        }
      }
      await users.updateAssociationsIfNeeded(
        userId,
        phoneToLink,
        eqCode?.isNotEmpty == true ? eqCode : null,
      );

      final lookup = ref.read(lookupServiceProvider).value?.service;
      var selectedDepartmentId =
          state.selectedDepartmentId ??
          (state.departmentText.trim().isNotEmpty && lookup != null
              ? lookup.findDepartmentByName(state.departmentText)?.id
              : null);
      var updatedDepartmentId = state.selectedCaller?.departmentId;
      var primaryDepartmentChanged = false;
      if (effectiveUpdatePrimaryDepartment &&
          state.departmentText.trim().isNotEmpty &&
          state.selectedCaller?.id != null) {
        // Αν το τμήμα δεν υπάρχει ακόμα στη βάση, το δημιουργούμε ώστε να πάρουμε id.
        selectedDepartmentId ??= await departments.getOrCreateDepartmentIdByName(
          state.departmentText.trim(),
        );
      }

      if (effectiveUpdatePrimaryDepartment &&
          selectedDepartmentId != null &&
          selectedDepartmentId != state.selectedCaller?.departmentId &&
          state.selectedCaller?.id != null) {
        final updatedMap = Map<String, dynamic>.from(
          state.selectedCaller!.toMap(),
        );
        updatedMap['department_id'] = selectedDepartmentId;
        await users.updateUser(state.selectedCaller!.id!, updatedMap);
        updatedDepartmentId = selectedDepartmentId;
        primaryDepartmentChanged = true;
      }

      final s = state;
      final phoneNow = phoneToLink;
      final currentPhones = List<String>.from(
        s.selectedCaller?.phones ?? const [],
      );
      List<String> updatedPhones = currentPhones;
      if (phoneNow != null && phoneNow.isNotEmpty) {
        final joined = PhoneListParser.joinPhones(currentPhones);
        if (!PhoneListParser.containsPhone(joined, phoneNow)) {
          updatedPhones = [...currentPhones, phoneNow];
        }
      }
      state = state.copyWith(
        selectedCaller: UserModel(
          id: s.selectedCaller?.id,
          firstName: s.selectedCaller?.firstName,
          lastName: s.selectedCaller?.lastName,
          phones: updatedPhones,
          departmentId: updatedDepartmentId,
          notes: s.selectedCaller?.notes,
        ),
        selectedDepartmentId: primaryDepartmentChanged
            ? updatedDepartmentId
            : s.selectedDepartmentId,
        selectedEquipment: eqCode?.isNotEmpty == true
            ? EquipmentModel(
                id: s.selectedEquipment?.id,
                code: eqCode,
                type: s.selectedEquipment?.type,
                notes: s.selectedEquipment?.notes,
              )
            : s.selectedEquipment,
      );

      await refreshDirectoryCaches(
        ref,
        users: true,
        equipment: hadEqWork,
        departments: primaryDepartmentChanged || newDepartmentRow,
      );
      if (!ref.mounted) {
        return 'Σφάλμα αποθήκευσης: το container δεν είναι ενεργό.';
      }
      final refreshedLookup = (await ref.read(
        lookupServiceProvider.future,
      )).service;
      final matchedEquipment = eqCode?.isNotEmpty == true
          ? refreshedLookup.findEquipmentsByCode(eqCode!)
          : const <EquipmentModel>[];
      final resolvedEquipmentId = matchedEquipment.isNotEmpty
          ? matchedEquipment.first.id
          : s.selectedEquipment?.id;
      final resolvedDepartmentId =
          selectedDepartmentId ??
          (s.departmentText.trim().isNotEmpty
              ? refreshedLookup.findDepartmentByName(s.departmentText)?.id
              : null);
      if (matchedEquipment.isNotEmpty) {
        state = state.copyWith(selectedEquipment: matchedEquipment.first);
      }
      await _syncAssociationQuickTask(
        newEntityEligible: newEntityEligible,
        associationWorkDone:
            hadPhoneWork || hadEqWork || primaryDepartmentChanged,
        summaryText: msg,
        callerName: s.selectedCaller?.name ?? s.callerDisplayText.trim(),
        callerId: s.selectedCaller?.id,
        departmentId: resolvedDepartmentId,
        equipmentId: resolvedEquipmentId,
        phoneText: s.selectedPhone?.trim(),
        userText: s.callerDisplayText.trim().isEmpty
            ? null
            : s.callerDisplayText.trim(),
        equipmentText: s.equipmentText.trim().isEmpty
            ? null
            : s.equipmentText.trim(),
        departmentText: s.departmentText.trim().isEmpty
            ? null
            : s.departmentText.trim(),
      );
      await _host.trackDerivativeAuditsSince(auditSince);
      return (hadPhoneWork || hadEqWork || primaryDepartmentChanged)
          ? (msg ?? 'Προστέθηκε.')
          : null;
    } catch (e) {
      return 'Σφάλμα αποθήκευσης: ${humanizeUserFacingError(e)}';
    }
  }

  /// Μία γρήγορη εκκρεμότητα ανά κύκλο: δημιουργία ή append/merge στην υπάρχουσα.
  Future<void> _syncAssociationQuickTask({
    required bool newEntityEligible,
    required bool associationWorkDone,
    required String? summaryText,
    required String? callerName,
    required int? callerId,
    required int? departmentId,
    required int? equipmentId,
    String? phoneText,
    String? userText,
    String? equipmentText,
    String? departmentText,
  }) async {
    final taskService = ref.read(taskServiceProvider);
    final summary = summaryText?.trim();
    final hasSummary = summary != null && summary.isNotEmpty;
    final existingId = _host._associationQuickTaskId;
    if (existingId != null) {
      var touched = false;
      if (hasSummary && (newEntityEligible || associationWorkDone)) {
        final appended = await taskService.appendToQuickAddDescription(
          existingId,
          summary,
        );
        if (appended) touched = true;
      }
      final merged = await taskService.mergeQuickAddEntitySnapshot(
        taskId: existingId,
        callerId: callerId,
        departmentId: departmentId,
        equipmentId: equipmentId,
        phoneText: phoneText,
        userText: userText,
        equipmentText: equipmentText,
        departmentText: departmentText,
      );
      if (merged) touched = true;
      if (touched) invalidateTaskListProviders(ref);
      return;
    }

    if (!newEntityEligible) return;

    final id = await _insertQuickAddTask(
      callerName: callerName,
      summaryText: summaryText,
      callerId: callerId,
      departmentId: departmentId,
      equipmentId: equipmentId,
      phoneText: phoneText,
      userText: userText,
      equipmentText: equipmentText,
      departmentText: departmentText,
    );
    _host._associationQuickTaskId = id;
    invalidateTaskListProviders(ref);
  }

  Future<int> _insertQuickAddTask({
    required String? callerName,
    required String? summaryText,
    required int? callerId,
    required int? departmentId,
    required int? equipmentId,
    String? phoneText,
    String? userText,
    String? equipmentText,
    String? departmentText,
  }) async {
    final cleanSummary = summaryText?.trim();
    final caller = callerName?.trim();
    final descriptionCore = cleanSummary?.isNotEmpty == true
        ? cleanSummary!
        : (caller?.isNotEmpty == true
              ? 'Ενημερώθηκε οντότητα καλούντα'
              : 'Quick add');
    final quickDescription = '${Task.quickAddTag} $descriptionCore';
    return ref
        .read(taskServiceProvider)
        .createFromCall(
          callId: null,
          callerName: caller,
          description: quickDescription,
          callDate: DateTime.now(),
          callerId: callerId,
          equipmentId: equipmentId,
          departmentId: departmentId,
          phoneId: null,
          phoneText: phoneText?.isEmpty == true ? null : phoneText,
          userText: userText?.isEmpty == true ? null : userText,
          equipmentText: equipmentText?.isEmpty == true ? null : equipmentText,
          departmentText: departmentText?.isEmpty == true
              ? null
              : departmentText,
          priority: SmartEntitySelectorNotifier._criticalTaskPriority,
          categoryName: Task.quickAddCategoryEl,
        );
  }
}
