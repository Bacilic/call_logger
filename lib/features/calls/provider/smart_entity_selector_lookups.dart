part of 'smart_entity_selector_provider.dart';

/// Lookup τηλεφώνου, καλούντα, εξοπλισμού και βοηθητικές autofill ρουτίνες.
mixin SmartEntitySelectorLookupsMixin on Notifier<SmartEntitySelectorState> {
  SmartEntitySelectorNotifier get _host => this as SmartEntitySelectorNotifier;

  bool get _hasManualEquipmentSelection => state.equipmentText.trim().isNotEmpty;

  List<String> _splitPhones(String? rawPhone) {
    return PhoneListParser.splitPhones(rawPhone);
  }

  void _setPhoneValueFromLookup(String phone) {
    final trimmed = phone.trim();
    if (trimmed.isEmpty) return;
    state = state.copyWith(
      selectedPhone: trimmed,
      clearSelectedPhone: false,
      clearPhoneError: true,
      clearPhoneCandidates: true,
      isPhoneAmbiguous: false,
    );
    _host.markPhoneUsed(trimmed);
  }

  void _setPhoneCandidatesFromLookup(List<String> phones) {
    if (phones.isEmpty) return;
    final sorted = List<String>.from(phones);
    sorted.sort((a, b) => a.compareTo(b));
    state = state.copyWith(
      phoneCandidates: sorted,
      clearSelectedPhone: true,
      isPhoneAmbiguous: true,
      clearPhoneError: true,
    );
  }

  /// Γεμίζει/διατηρεί ένα μόνο εσωτερικό τηλέφωνο από το προφίλ χρήστη (λίστα στο DB).
  /// - Αν το πεδίο είχε κατά λάθος ολόκληρη τη συνενωμένη λίστα (`phoneJoined`), την καθαρίζει και συνεχίζει με λογική πολλαπλών.
  /// - Αν υπάρχει έγκυρο token μέσα στη λίστα, το κρατάει.
  /// - Αν είναι κενό και υπάρχουν πολλά → candidates· αν ένα → αυτό.
  void _autofillPhoneFromUserProfile(UserModel user) {
    if (!_canAutofillPhone()) return;
    final pool = user.phoneJoined.trim();
    final phones = List<String>.from(user.phones);
    if (phones.isEmpty) return;

    var previous = state.selectedPhone?.trim() ?? '';
    if (previous.isNotEmpty &&
        pool.isNotEmpty &&
        previous == pool &&
        phones.length > 1) {
      state = state.copyWith(clearSelectedPhone: true, clearPhoneError: true);
      previous = '';
    }

    if (phones.length == 1) {
      final only = phones.first;
      if (previous.isEmpty) {
        _setPhoneValueFromLookup(only);
      } else if (PhoneListParser.containsPhone(pool, previous)) {
        _setPhoneValueFromLookup(previous);
      }
      return;
    }

    if (previous.isNotEmpty && PhoneListParser.containsPhone(pool, previous)) {
      _setPhoneValueFromLookup(previous);
      return;
    }
    if (previous.isNotEmpty) {
      return;
    }
    _setPhoneCandidatesFromLookup(phones);
  }

  bool _canAutofillPhone() {
    // v2 §Β.1: autofill μόνο σε κενό πεδίο (isFilled = false), ανεξάρτητα
    // από το πώς αποκτήθηκε η τρέχουσα τιμή.
    return state.selectedPhone?.trim().isEmpty ?? true;
  }

  /// Autofill τηλεφώνου από τον κάτοχο του εξοπλισμού μόνο όταν δεν υπάρχει ήδη
  /// επιλεγμένος αριθμός — αλλιώς (π.χ. lookup γραμμής) δεν καλούμε
  /// `_setPhoneCandidatesFromLookup` (αποφυγή `clearSelectedPhone`).
  bool _shouldApplyEquipmentOwnerPhoneAutofill() {
    if (!_canAutofillPhone()) return false;
    return state.selectedPhone?.trim().isEmpty ?? true;
  }

  /// Μετά επιλογή εξοπλισμού, διατηρεί τους υποψήφιους αριθμούς του επιλεγμένου τμήματος.
  void _restoreDepartmentPhoneCandidatesIfNeeded(LookupService? lookup) {
    final deptId = state.selectedDepartmentId;
    if (lookup == null || deptId == null) return;
    if (state.selectedPhone?.trim().isNotEmpty == true) return;
    final phones = lookup.getPhonesByDepartment(deptId);
    if (phones.isEmpty) return;
    state = state.copyWith(
      phoneCandidates: phones,
      clearSelectedPhone: true,
      isPhoneAmbiguous: phones.length > 1,
      clearPhoneError: true,
    );
  }

  /// Μετά καθαρισμό εξοπλισμού, επαναφέρει τους υποψήφιους εξοπλισμούς του τμήματος.
  void _restoreDepartmentEquipmentCandidatesIfNeeded(LookupService? lookup) {
    final deptId = state.selectedDepartmentId;
    if (lookup == null || deptId == null) return;
    if (state.equipmentText.trim().isNotEmpty) return;
    final equipment = lookup.getAllEquipmentByDepartment(deptId);
    if (equipment.isEmpty) return;
    state = state.copyWith(
      equipmentCandidates: equipment,
      clearSelectedEquipment: true,
      isEquipmentAmbiguous: equipment.length > 1,
      equipmentNoMatch: false,
    );
  }

  bool _canAutofillDepartmentForUser(UserModel user) {
    // v2 §Β.1: το τμήμα συμπληρώνεται αυτόματα μόνο όταν το πεδίο είναι κενό.
    // Συμπληρωμένο τμήμα (isFilled) δεν αντικαθίσταται — η τυχόν σύγκρουση
    // εκτίθεται μέσω δείκτη (Φάση 2).
    return state.departmentText.trim().isEmpty;
  }

  String _departmentTextForUser(UserModel user) {
    if (user.departmentId == null) return '';
    final asyncLookup = ref.read(lookupServiceProvider);
    final lookup = asyncLookup.value?.service;
    if (lookup == null) return '';
    return lookup.departmentIdToName[user.departmentId] ?? '';
  }

  void performPhoneLookup(String phone) {
    if (_host._isFillingFromLookup) return;

    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final generation = ++_host._phoneLookupGeneration;
    if (digits.length < 3) {
      _host._isFillingFromLookup = true;
      try {
        state = state.copyWith(
          clearPhoneCandidates: true,
          clearCallerCandidates: true,
          clearSelectedCaller: true,
          clearEquipmentCandidates: true,
          clearSelectedEquipment: !_hasManualEquipmentSelection,
          isPhoneAmbiguous: false,
          isEquipmentAmbiguous: false,
          callerNoMatch: false,
          equipmentNoMatch: false,
          clearConflicts: true,
        );
      } finally {
        _host._isFillingFromLookup = false;
      }
      return;
    }

    final snap = ref.read(lookupServiceProvider);
    if (snap.hasValue) {
      if (generation == _host._phoneLookupGeneration) {
        _applyPhoneLookupWithCatalog(digits, snap.requireValue.service);
      }
      return;
    }
    // Κατά το πρώτο frame το AsyncValue μπορεί να είναι ακόμα loading.
    ref
        .read(lookupServiceProvider.future)
        .then((bundle) {
          if (!ref.mounted) return;
          if (generation != _host._phoneLookupGeneration) return;
          final currentDigits = (state.selectedPhone ?? '')
              .replaceAll(RegExp(r'[^0-9]'), '');
          if (currentDigits != digits) return;
          _applyPhoneLookupWithCatalog(digits, bundle.service);
        })
        .catchError((Object e, StackTrace st) {
          developer.log(
            'performPhoneLookup async load failed',
            name: 'SmartEntitySelectorNotifier',
            error: e,
            stackTrace: st,
          );
        });
  }

  void _applyPhoneLookupWithCatalog(String digits, LookupService lookup) {
    if (_host._isFillingFromLookup) return;
    _host._isFillingFromLookup = true;
    try {
      final users = lookup.findUsersByPhone(digits);
      if (users.isEmpty) {
        final orphanDept = lookup.getDepartmentByPhone(digits);
        final canAutofillDepartment =
            state.departmentText.trim().isEmpty &&
            state.selectedDepartmentId == null;
        state = state.copyWith(
          clearPhoneCandidates: true,
          callerCandidates: [],
          clearSelectedCaller: true,
          equipmentCandidates: [],
          clearSelectedEquipment: true,
          isPhoneAmbiguous: false,
          isEquipmentAmbiguous: false,
          callerNoMatch: true,
          equipmentNoMatch: false,
          departmentText: (orphanDept != null && canAutofillDepartment)
              ? orphanDept.name
              : state.departmentText,
          selectedDepartmentId: (orphanDept != null && canAutofillDepartment)
              ? orphanDept.id
              : state.selectedDepartmentId,
        );
        if (orphanDept?.id != null) {
          _applyDepartmentEquipmentLookup(lookup, orphanDept!.id!);
        }
        return;
      }
      if (users.length == 1) {
        final user = users.first;
        final name = user.name ?? user.fullNameWithDepartment;
        final shouldAutofillDepartment = _canAutofillDepartmentForUser(user);
        final canAutofillCaller = state.callerDisplayText.trim().isEmpty;
        if (canAutofillCaller) {
          state = state.copyWith(
            clearPhoneCandidates: true,
            selectedCaller: user,
            callerCandidates: [],
            isPhoneAmbiguous: false,
            callerNoMatch: false,
            callerDisplayText: name,
            departmentText: shouldAutofillDepartment
                ? _departmentTextForUser(user)
                : state.departmentText,
            selectedDepartmentId: shouldAutofillDepartment
                ? user.departmentId
                : state.selectedDepartmentId,
          );
        } else if (shouldAutofillDepartment) {
          state = state.copyWith(
            clearPhoneCandidates: true,
            callerCandidates: [],
            isPhoneAmbiguous: false,
            callerNoMatch: false,
            departmentText: _departmentTextForUser(user),
            selectedDepartmentId: user.departmentId,
          );
        } else {
          state = state.copyWith(
            clearPhoneCandidates: true,
            callerCandidates: [],
            isPhoneAmbiguous: false,
            callerNoMatch: false,
          );
        }
        _host.markPhoneUsed(digits);
        if (users.first.id != null) {
          _performEquipmentLookupForUser(users.first.id!);
        }
        return;
      }
      state = state.copyWith(
        clearPhoneCandidates: true,
        callerCandidates: users,
        clearSelectedCaller: true,
        equipmentCandidates: [],
        clearSelectedEquipment: !_hasManualEquipmentSelection,
        isPhoneAmbiguous: true,
        isEquipmentAmbiguous: false,
        callerNoMatch: false,
        equipmentNoMatch: false,
      );
    } finally {
      _host._recomputeConflicts(SelectorField.phone, lookup);
      _host._isFillingFromLookup = false;
    }
  }

  /// Lookup εξοπλισμού για userId: 0 → no match hint, 1 → setEquipment, >1 → dropdown candidates.
  void performEquipmentLookup(int userId) {
    if (_host._isFillingFromLookup) return;
    _host._isFillingFromLookup = true;
    try {
      _performEquipmentLookupForUser(userId);
    } finally {
      _host._isFillingFromLookup = false;
    }
  }

  String _equipmentAutofillText(EquipmentModel equipment) {
    final code = equipment.code?.trim();
    if (code != null && code.isNotEmpty) return code;
    return equipment.displayLabel.trim();
  }

  void _performEquipmentLookupForUser(int userId) {
    final asyncLookup = ref.read(lookupServiceProvider);
    final lookup = asyncLookup.value?.service;
    if (lookup == null) return;
    final list = lookup.findEquipmentsForUser(userId);
    if (list.isEmpty) {
      state = state.copyWith(
        equipmentCandidates: [],
        clearSelectedEquipment: !_hasManualEquipmentSelection,
        isEquipmentAmbiguous: false,
        equipmentNoMatch: true,
      );
      return;
    }
    if (list.length == 1) {
      final canAutofillEquipment = state.equipmentText.trim().isEmpty;
      if (canAutofillEquipment) {
        final equipment = list.first;
        final text = _equipmentAutofillText(equipment);
        state = state.copyWith(
          selectedEquipment: equipment,
          equipmentText: text,
          equipmentCandidates: [],
          isEquipmentAmbiguous: false,
          equipmentNoMatch: false,
          hasAnyContent: _host._computeHasAnyContent(equipmentText: text),
        );
      } else {
        state = state.copyWith(
          equipmentCandidates: [],
          isEquipmentAmbiguous: false,
          equipmentNoMatch: false,
        );
      }
      return;
    }
    state = state.copyWith(
      equipmentCandidates: list,
      clearSelectedEquipment: !_hasManualEquipmentSelection,
      isEquipmentAmbiguous: true,
      equipmentNoMatch: false,
    );
  }

  /// Εξοπλισμός τμήματος μετά από lookup ορφανού τηλεφώνου (χωρίς καλούντα).
  void _applyDepartmentEquipmentLookup(LookupService lookup, int departmentId) {
    if (state.equipmentText.trim().isNotEmpty) return;
    final list = lookup.getAllEquipmentByDepartment(departmentId);
    if (list.isEmpty) {
      state = state.copyWith(
        equipmentCandidates: [],
        clearSelectedEquipment: !_hasManualEquipmentSelection,
        isEquipmentAmbiguous: false,
        equipmentNoMatch: true,
      );
      return;
    }
    if (list.length == 1) {
      final equipment = list.first;
      final text = _equipmentAutofillText(equipment);
      state = state.copyWith(
        selectedEquipment: equipment,
        equipmentText: text,
        equipmentCandidates: list,
        isEquipmentAmbiguous: false,
        equipmentNoMatch: false,
        hasAnyContent: _host._computeHasAnyContent(equipmentText: text),
      );
      return;
    }
    state = state.copyWith(
      equipmentCandidates: list,
      clearSelectedEquipment: !_hasManualEquipmentSelection,
      isEquipmentAmbiguous: true,
      equipmentNoMatch: false,
    );
  }

  void performCallerLookup(String nameOrQuery, {String? phoneFieldDigits}) {
    if (_host._isFillingFromLookup) return;
    _host._isFillingFromLookup = true;
    try {
      final query = nameOrQuery.trim();
      if (query.isEmpty || query == 'Άγνωστος') return;
      final asyncLookup = ref.read(lookupServiceProvider);
      final lookup = asyncLookup.value?.service;
      if (lookup == null) return;
      final users = lookup.searchUsersByQuery(query);
      if (users.isEmpty) {
        state = state.copyWith(
          callerCandidates: [],
          clearSelectedCaller: true,
          callerNoMatch: true,
          isPhoneAmbiguous: false,
          clearPhoneCandidates: true,
          equipmentNoMatch: false,
        );
        return;
      }
      if (users.length > 1) {
        state = state.copyWith(
          callerCandidates: users,
          clearSelectedCaller: true,
          callerNoMatch: false,
          clearPhoneCandidates: true,
          isPhoneAmbiguous: false,
        );
        return;
      }

      final user = users.first;
      final displayName = user.name ?? user.fullNameWithDepartment;
      final shouldAutofillDepartment = _canAutofillDepartmentForUser(user);
      state = state.copyWith(
        selectedCaller: user,
        clearPhoneCandidates: true,
        callerCandidates: [],
        callerNoMatch: false,
        isPhoneAmbiguous: false,
        callerDisplayText: displayName,
        departmentText: shouldAutofillDepartment
            ? _departmentTextForUser(user)
            : state.departmentText,
        selectedDepartmentId: shouldAutofillDepartment
            ? user.departmentId
            : state.selectedDepartmentId,
      );
      final snap =
          phoneFieldDigits?.replaceAll(RegExp(r'[^0-9]'), '').trim() ?? '';
      if (snap.isNotEmpty &&
          (state.selectedPhone == null ||
              state.selectedPhone!.trim().isEmpty)) {
        state = state.copyWith(
          selectedPhone: snap,
          clearSelectedPhone: false,
          clearPhoneError: true,
        );
      }
      _autofillPhoneFromUserProfile(user);

      final canAutofillEquipment = state.equipmentText.trim().isEmpty;
      if (user.id != null && canAutofillEquipment) {
        _performEquipmentLookupForUser(user.id!);
      }
    } finally {
      _host._recomputeConflicts(
        SelectorField.caller,
        ref.read(lookupServiceProvider).value?.service,
      );
      _host._isFillingFromLookup = false;
    }
  }

  void performEquipmentLookupByCode(String code) {
    if (_host._isFillingFromLookup) return;
    _host._isFillingFromLookup = true;
    try {
      final query = code.trim();
      if (query.isEmpty) return;
      final asyncLookup = ref.read(lookupServiceProvider);
      final lookup = asyncLookup.value?.service;
      if (lookup == null) return;
      final list = lookup.findEquipmentsByCode(query);
      if (list.isEmpty) {
        // Το ίδιο το πεδίο εξοπλισμού δεν ταιριάζει σε καμία οντότητα: η τυχόν
        // προηγούμενη επιλογή είναι άκυρη και καθαρίζεται.
        state = state.copyWith(
          equipmentCandidates: [],
          clearSelectedEquipment: true,
          isEquipmentAmbiguous: false,
          equipmentNoMatch: true,
        );
        return;
      }
      if (list.length > 1) {
        state = state.copyWith(
          equipmentCandidates: list,
          clearSelectedEquipment: true,
          isEquipmentAmbiguous: true,
          equipmentNoMatch: false,
        );
        return;
      }

      final equipment = list.first;
      final resolvedText = equipment.code?.trim().isNotEmpty == true
          ? equipment.code!.trim()
          : query;
      state = state.copyWith(
        selectedEquipment: equipment,
        equipmentText: resolvedText,
        equipmentCandidates: [],
        isEquipmentAmbiguous: false,
        equipmentNoMatch: false,
      );

      final owners = equipment.id != null
          ? lookup.findUsersForEquipment(equipment.id!)
          : <UserModel>[];

      // v2 §Δ.3: πολλαπλοί κάτοχοι → λίστα candidates, ποτέ αυτόματη επιλογή
      // του πρώτου. Δεν αλλάζουμε καλούντα/τμήμα/τηλέφωνο αυτόματα όταν η
      // αντιστοίχιση κατόχου είναι ασαφής.
      if (owners.length > 1) {
        if (state.callerDisplayText.trim().isEmpty) {
          state = state.copyWith(
            callerCandidates: owners,
            clearSelectedCaller: true,
            callerNoMatch: false,
            isPhoneAmbiguous: false,
          );
        }
        return;
      }

      final user = owners.isNotEmpty ? owners.first : null;
      if (user == null) {
        return;
      }

      final shouldAutofillDepartment = _canAutofillDepartmentForUser(user);
      final canAutofillCaller = state.callerDisplayText.trim().isEmpty;
      // v2 §Β: «κλειδωμένο» τμήμα = συμπληρωμένο πεδίο (isFilled) με ταυτοποιημένο id.
      final hasLockedDepartmentSelection = state.selectedDepartmentId != null;
      final isCallerOutsideSelectedDepartment =
          hasLockedDepartmentSelection &&
          user.departmentId != state.selectedDepartmentId;
      if (canAutofillCaller && !isCallerOutsideSelectedDepartment) {
        state = state.copyWith(
          selectedCaller: user,
          callerCandidates: [],
          isPhoneAmbiguous: false,
          callerNoMatch: false,
          callerDisplayText: user.name ?? user.fullNameWithDepartment,
          departmentText: shouldAutofillDepartment
              ? _departmentTextForUser(user)
              : state.departmentText,
          selectedDepartmentId: shouldAutofillDepartment
              ? user.departmentId
              : state.selectedDepartmentId,
        );
      } else if (shouldAutofillDepartment) {
        state = state.copyWith(
          departmentText: _departmentTextForUser(user),
          selectedDepartmentId: user.departmentId,
        );
      }

      if (_shouldApplyEquipmentOwnerPhoneAutofill() &&
          !hasLockedDepartmentSelection) {
        _autofillPhoneFromUserProfile(user);
      }
    } finally {
      final lookupForRestore =
          ref.read(lookupServiceProvider).value?.service;
      if (state.selectedDepartmentId != null) {
        _restoreDepartmentPhoneCandidatesIfNeeded(lookupForRestore);
      }
      _host._recomputeConflicts(
        SelectorField.equipment,
        ref.read(lookupServiceProvider).value?.service,
      );
      _host._isFillingFromLookup = false;
    }
  }
}
