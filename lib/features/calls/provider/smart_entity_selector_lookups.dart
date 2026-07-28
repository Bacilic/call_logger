part of 'smart_entity_selector_provider.dart';

/// Lookup τηλεφώνου, καλούντα, εξοπλισμού και βοηθητικές autofill ρουτίνες.
mixin SmartEntitySelectorLookupsMixin on Notifier<SmartEntitySelectorState> {
  SmartEntitySelectorNotifier get _host => this as SmartEntitySelectorNotifier;

  bool get _hasManualEquipmentSelection =>
      state.equipmentText.trim().isNotEmpty;

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

  /// **Μοναδικό** σημείο επιβολής του συμβολαίου των υποψήφιων τηλεφώνων:
  /// ακριβώς ένας αριθμός = απόφαση (μπαίνει στο πεδίο, χωρίς λίστα), δύο και
  /// πάνω = λίστα υποψηφίων, κανένας = καμία λίστα.
  ///
  /// Κάθε ροή που παράγει υποψήφια τηλέφωνα περνά από εδώ — έτσι καμία δεν
  /// μπορεί να ξεχάσει ότι το μοναδικό/ακριβές ταίριασμα κερδίζει.
  /// Προϋπόθεση κάθε καλούντος: το πεδίο τηλεφώνου είναι **κενό**.
  void _applyPhoneCandidatesFromLookup(List<String> phones) {
    final sorted =
        phones
            .map((phone) => phone.trim())
            .where((phone) => phone.isNotEmpty)
            .toList()
          ..sort((a, b) => a.compareTo(b));
    if (sorted.length == 1) {
      _setPhoneValueFromLookup(sorted.first);
      return;
    }
    state = state.copyWith(
      phoneCandidates: sorted,
      clearSelectedPhone: true,
      isPhoneAmbiguous: sorted.length > 1,
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
    _applyPhoneCandidatesFromLookup(phones);
  }

  /// **Μοναδικό** σημείο επιβολής του συμβολαίου για τον καλούντα:
  /// ακριβώς ένας υπάλληλος = απόφαση, δύο και πάνω = λίστα, κανένας = καθαρό
  /// πεδίο. Προϋπόθεση κάθε καλούντος: το πεδίο καλούντα είναι **κενό**.
  void _applyCallerCandidatesFromLookup(List<UserModel> users) {
    if (users.length == 1) {
      final user = users.first;
      state = state.copyWith(
        selectedCaller: user,
        callerCandidates: [],
        callerNoMatch: false,
        callerDisplayText: user.name ?? user.fullNameWithDepartment,
      );
      return;
    }
    state = state.copyWith(
      callerCandidates: users,
      clearSelectedCaller: true,
      callerDisplayText: '',
      callerNoMatch: false,
    );
  }

  /// **Μοναδικό** σημείο επιβολής του συμβολαίου για τον εξοπλισμό:
  /// ακριβώς ένας = απόφαση, δύο και πάνω = λίστα, κανένας = καθαρό πεδίο.
  /// Προϋπόθεση κάθε καλούντος: το πεδίο εξοπλισμού είναι **κενό**.
  ///
  /// Το `equipmentCandidates` σημαίνει **μόνο** «δεν αποφασίστηκε ακόμα»: όταν
  /// υπάρχει απόφαση, αδειάζει. Οι προτάσεις του overlay για ένα επιλεγμένο
  /// τμήμα χτίζονται χωριστά, στο `departmentEquipmentsForSuggestions`.
  void _applyEquipmentCandidatesFromLookup(List<EquipmentModel> equipment) {
    if (equipment.length == 1) {
      final only = equipment.first;
      final text = _equipmentAutofillText(only);
      state = state.copyWith(
        selectedEquipment: only,
        equipmentText: text,
        equipmentCandidates: [],
        isEquipmentAmbiguous: false,
        equipmentNoMatch: false,
        hasAnyContent: _host._computeHasAnyContent(equipmentText: text),
      );
      return;
    }
    state = state.copyWith(
      equipmentCandidates: equipment,
      clearSelectedEquipment: true,
      isEquipmentAmbiguous: equipment.length > 1,
      equipmentNoMatch: false,
    );
  }

  bool _canAutofillPhone() {
    // Autofill μόνο σε κενό πεδίο (isFilled = false), ανεξάρτητα
    // από το πώς αποκτήθηκε η τρέχουσα τιμή.
    return state.selectedPhone?.trim().isEmpty ?? true;
  }

  /// Επαναφέρει τους **υποψήφιους** αριθμούς του τμήματος σε άδειο πεδίο.
  ///
  /// **Ποτέ δεν γράφει τιμή** — ούτε όταν ο υποψήφιος είναι ένας. Καλείται αφού
  /// ο χρήστης **άδειασε** το πεδίο (σβήσιμο τηλεφώνου, καθαρισμό εξοπλισμού),
  /// και το άδειασμα είναι ρητή του πρόθεση: η αυτόματη συμπλήρωση είναι
  /// υπόδειξη, όχι κλείδωμα. Αν ξαναγράφαμε την τιμή, ο χρήστης δεν θα μπορούσε
  /// ποτέ να καταγράψει κλήση με τηλέφωνο άλλου τμήματος.
  ///
  /// Η στενότερη πηγή κερδίζει: οι αριθμοί του κατόχου/καλούντα δεν
  /// αντικαθίστανται από τους αριθμούς ολόκληρου του τμήματος, γιατί η ευρύτερη
  /// λίστα περιέχει αριθμούς άλλων ανθρώπων και οδηγεί σε λάθος επιλογή.
  void _restoreDepartmentPhoneCandidatesIfNeeded(LookupService? lookup) {
    final deptId = state.selectedDepartmentId;
    if (lookup == null || deptId == null) return;
    if (state.selectedPhone?.trim().isNotEmpty == true) return;
    if (state.phoneCandidates.isNotEmpty) return;
    final phones = lookup.getPhonesByDepartment(deptId);
    if (phones.isEmpty) return;
    final sorted = List<String>.from(phones)..sort((a, b) => a.compareTo(b));
    state = state.copyWith(
      phoneCandidates: sorted,
      clearSelectedPhone: true,
      isPhoneAmbiguous: sorted.length > 1,
      clearPhoneError: true,
    );
  }

  /// Υπόδειξη τηλεφώνου από το τμήμα μετά από **επικύρωση οντότητας** από τον
  /// χρήστη (π.χ. κατοχύρωση κωδικού εξοπλισμού χωρίς κάτοχο).
  ///
  /// Σε αντίθεση με την επαναφορά υποψηφίων, εδώ ο χρήστης μόλις **πρόσθεσε**
  /// πληροφορία, οπότε ο μοναδικός αριθμός του τμήματος είναι απόφαση.
  void _autofillDepartmentPhoneIfEmpty(LookupService lookup, int departmentId) {
    if (state.selectedPhone?.trim().isNotEmpty == true) return;
    final phones = lookup.getPhonesByDepartment(departmentId);
    if (phones.isEmpty) return;
    _applyPhoneCandidatesFromLookup(phones);
  }

  /// Υπόδειξη τηλεφώνου για **επικυρωμένο υπάλληλο**: πρώτα τα δικά του νούμερα.
  ///
  /// Όταν δεν έχει κανένα, αναλαμβάνουν τα τηλέφωνα του τμήματός του — η
  /// στενότερη πηγή υπερισχύει, αλλά όταν είναι ΚΕΝΗ ισχύει η επόμενη: ο
  /// υπάλληλος χωρίς προσωπικό αριθμό καλεί από το κοινόχρηστο του τμήματος.
  void _autofillPhoneForCommittedUser(UserModel user, LookupService lookup) {
    if (user.phones.isNotEmpty) {
      _autofillPhoneFromUserProfile(user);
      return;
    }
    final departmentId = state.selectedDepartmentId ?? user.departmentId;
    if (departmentId == null) return;
    _autofillDepartmentPhoneIfEmpty(lookup, departmentId);
  }

  /// Επαναφέρει τους **υποψήφιους** υπαλλήλους του τμήματος σε άδειο πεδίο
  /// καλούντα — συμμετρικά με τηλέφωνο και εξοπλισμό.
  ///
  /// **Ποτέ δεν γράφει όνομα**, ούτε όταν ο υπάλληλος είναι ένας: το άδειασμα
  /// είναι ρητή πρόθεση του χρήστη. Αν συμπληρωνόταν, σε μονοπρόσωπο τμήμα ο
  /// καλών θα ήταν αδύνατο να σβηστεί — η ίδια παγίδα με το τηλέφωνο.
  ///
  /// Κενό ορατό πεδίο σημαίνει «κανένας καλών», οπότε λύνεται και η τυχόν
  /// ταυτοποίηση που είχε μείνει από προηγούμενη επιλογή.
  void _restoreDepartmentCallerCandidatesIfNeeded(LookupService? lookup) {
    final deptId = state.selectedDepartmentId;
    if (lookup == null || deptId == null) return;
    if (state.callerDisplayText.trim().isNotEmpty) return;
    final users = lookup.getUsersByDepartment(deptId);
    if (users.isEmpty) return;
    state = state.copyWith(
      callerCandidates: users,
      clearSelectedCaller: true,
      callerNoMatch: false,
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
    // Το τμήμα συμπληρώνεται αυτόματα μόνο όταν το πεδίο είναι κενό.
    // Συμπληρωμένο τμήμα (isFilled) δεν αντικαθίσταται — η τυχόν σύγκρουση
    // εκτίθεται μέσω δείκτη (Φάση 2).
    return state.departmentText.trim().isEmpty;
  }

  /// Ακριβές ταίριασμα πλήρους ονόματος με τη ΓΡΑΦΗ ΤΟΥ ΚΑΤΑΛΟΓΟΥ (όνομα επώνυμο),
  /// μετά από αφαίρεση παρενθετικού τμήματος — διαχωρίζει μερικό από πλήρες query.
  ///
  /// Η ανάστροφη σειρά («επώνυμο όνομα») ΔΕΝ μετράει εδώ: το ταίριασμα ξαναγράφει
  /// το πεδίο με το αποθηκευμένο όνομα, οπότε θα άλλαζε σιωπηλά ό,τι πληκτρολόγησε
  /// ο χρήστης. Ο υπάλληλος παραμένει ορατός ως υποψήφιος στη λίστα του πεδίου και
  /// η ταυτοποίηση προτείνεται κατά την καταγραφή της κλήσης.
  bool _isExactCallerNameMatch(String query, UserModel user) {
    final normalizedQuery = SearchTextNormalizer.normalizeForSearch(query);
    if (normalizedQuery.isEmpty) return false;

    final rawName =
        user.name ??
        NameParserUtility.stripParentheticalSuffix(user.fullNameWithDepartment);
    final strippedName = NameParserUtility.stripParentheticalSuffix(rawName);

    return normalizedQuery ==
        SearchTextNormalizer.normalizeForSearch(strippedName);
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
      // Κάτω από 3 ψηφία το τηλέφωνο αγνοείται σαν κενό — οι σχέσεις
      // των υπόλοιπων πεδίων ξαναχτίζονται κανονικά χωρίς αυτό.
      _host.runExclusiveLookup(null, () {
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
        );
      });
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
          final currentDigits = (state.selectedPhone ?? '').replaceAll(
            RegExp(r'[^0-9]'),
            '',
          );
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
    _host.runExclusiveLookup(SelectorField.phone, () {
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
          clearSelectedEquipment: !_hasManualEquipmentSelection,
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
          _applyDepartmentCallerLookup(lookup, orphanDept!.id!);
          _applyDepartmentEquipmentLookup(lookup, orphanDept.id!);
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
      final sharedDeptIds = users
          .map((u) => u.departmentId)
          .whereType<int>()
          .toSet();
      final allShareSameDepartment =
          users.isNotEmpty &&
          users.every((u) => u.departmentId != null) &&
          sharedDeptIds.length == 1;
      final sharedDeptId = allShareSameDepartment ? sharedDeptIds.single : null;
      final sharedDeptName = sharedDeptId == null
          ? null
          : lookup.departmentIdToName[sharedDeptId];
      final canAutofillSharedDepartment =
          state.departmentText.trim().isEmpty &&
          state.selectedDepartmentId == null;

      // Αν ο ήδη δεμένος καλούντας είναι ένας από τους κατόχους, μην τον
      // ξεδέσεις (κοινόχρηστο τηλέφωνο βάρδιας μετά από autofill εξοπλισμού).
      final selectedCallerId = state.selectedCaller?.id;
      final selectedCallerIsOwner =
          selectedCallerId != null &&
          users.any((u) => u.id == selectedCallerId);
      if (selectedCallerIsOwner) {
        state = state.copyWith(
          clearPhoneCandidates: true,
          callerCandidates: [],
          isPhoneAmbiguous: false,
          callerNoMatch: false,
          departmentText:
              (canAutofillSharedDepartment && sharedDeptName != null)
              ? sharedDeptName
              : state.departmentText,
          selectedDepartmentId:
              (canAutofillSharedDepartment && sharedDeptId != null)
              ? sharedDeptId
              : state.selectedDepartmentId,
        );
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
        departmentText: (canAutofillSharedDepartment && sharedDeptName != null)
            ? sharedDeptName
            : state.departmentText,
        selectedDepartmentId:
            (canAutofillSharedDepartment && sharedDeptId != null)
            ? sharedDeptId
            : state.selectedDepartmentId,
      );
    });
  }

  /// Lookup εξοπλισμού για userId: 0 → no match hint, 1 → setEquipment, >1 → dropdown candidates.
  void performEquipmentLookup(int userId) {
    _host.runExclusiveLookup(null, () {
      _performEquipmentLookupForUser(userId);
    });
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
      // Χωρίς δικά του μηχανήματα, αναλαμβάνουν τα κοινόχρηστα του τμήματος —
      // αλλιώς το «Καμία αντιστοιχία» θα διαφωνούσε με το overlay, που τα
      // δείχνει ήδη. (Ο βοηθός βάζει ο ίδιος «Καμία αντιστοιχία» αν ούτε το
      // τμήμα έχει μηχανήματα.)
      final departmentId = state.selectedDepartmentId;
      if (departmentId != null && state.equipmentText.trim().isEmpty) {
        _applyDepartmentEquipmentLookup(lookup, departmentId);
        return;
      }
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

  /// Καλών τμήματος μετά από lookup κοινόχρηστου τηλεφώνου (χωρίς προσωπικό κάτοχο).
  ///
  /// Ίδιο συμβόλαιο με τα υπόλοιπα πεδία: **ένας** μη διαγραμμένος υπάλληλος στο
  /// τμήμα είναι απόφαση και συμπληρώνεται. Με δύο και πάνω δεν μαντεύουμε — το
  /// κοινόχρηστο τηλέφωνο δεν λέει ποιος από αυτούς καλεί.
  void _applyDepartmentCallerLookup(LookupService lookup, int departmentId) {
    if (state.callerDisplayText.trim().isNotEmpty) return;
    if (state.selectedCaller != null) return;
    final users = lookup.getUsersByDepartment(departmentId);
    if (users.length != 1) return;
    _applyCallerCandidatesFromLookup(users);
  }

  /// Εξοπλισμός τμήματος μετά από lookup ορφανού τηλεφώνου (χωρίς καλούντα).
  ///
  /// Η απόφαση «ένας ή πολλοί» ανήκει στο κοινό σημείο επιβολής· εδώ μένει μόνο
  /// ό,τι είναι ειδικό αυτής της ροής: το τμήμα χωρίς κανένα μηχάνημα σημαίνει
  /// «καμία αντιστοιχία» για το πεδίο.
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
    _applyEquipmentCandidatesFromLookup(list);
  }

  void performCallerLookup(String nameOrQuery, {String? phoneFieldDigits}) {
    _host.runExclusiveLookup(SelectorField.caller, () {
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
      if (!_isExactCallerNameMatch(query, user)) {
        state = state.copyWith(
          callerCandidates: users,
          clearSelectedCaller: true,
          callerNoMatch: false,
          clearPhoneCandidates: true,
          isPhoneAmbiguous: false,
        );
        return;
      }

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
      _autofillPhoneForCommittedUser(user, lookup);

      final canAutofillEquipment = state.equipmentText.trim().isEmpty;
      if (user.id != null && canAutofillEquipment) {
        _performEquipmentLookupForUser(user.id!);
      }
    });
  }

  void performEquipmentLookupByCode(String code) {
    _host.runExclusiveLookup(
      SelectorField.equipment,
      () {
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

        // Ακριβής κωδικός (π.χ. «506») υπερισχύει των μερικών ταιριασμάτων
        // (5067, 5068, …) κατά την κατοχύρωση — όχι κατά τις προτάσεις πληκτρολόγησης.
        final queryNorm = SearchTextNormalizer.normalizeForSearch(query);
        final exactMatches = list
            .where(
              (e) =>
                  SearchTextNormalizer.normalizeForSearch(e.code ?? '') ==
                  queryNorm,
            )
            .toList();
        final resolved = exactMatches.length == 1 ? exactMatches : list;

        if (resolved.length > 1) {
          state = state.copyWith(
            equipmentCandidates: resolved,
            clearSelectedEquipment: true,
            isEquipmentAmbiguous: true,
            equipmentNoMatch: false,
          );
          return;
        }

        final equipment = resolved.first;
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

        // Πολλαπλοί κάτοχοι → λίστα candidates, ποτέ αυτόματη επιλογή
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
          if (equipment.departmentId != null &&
              state.departmentText.trim().isEmpty &&
              state.selectedDepartmentId == null) {
            state = state.copyWith(
              departmentText:
                  lookup.departmentIdToName[equipment.departmentId] ?? '',
              selectedDepartmentId: equipment.departmentId,
            );
          }
          // Εξοπλισμός χωρίς κάτοχο: η υπόδειξη τηλεφώνου έρχεται από το τμήμα.
          // Γίνεται εδώ, όπου ο χρήστης μόλις κατοχύρωσε κωδικό — όχι στην
          // επαναφορά υποψηφίων, που δεν έχει δικαίωμα να γράψει τιμή.
          final departmentId = state.selectedDepartmentId;
          if (departmentId != null) {
            _autofillDepartmentPhoneIfEmpty(lookup, departmentId);
          }
          return;
        }

        final shouldAutofillDepartment = _canAutofillDepartmentForUser(user);
        final canAutofillCaller = state.callerDisplayText.trim().isEmpty;
        // «κλειδωμένο» τμήμα = συμπληρωμένο πεδίο (isFilled) με ταυτοποιημένο id.
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

        // Ο φραγμός του κλειδωμένου τμήματος κρίνει τη **σχέση** (είναι ο
        // κάτοχος εκτός του κλειδωμένου τμήματος;) και όχι την ύπαρξη
        // κλειδώματος: κάτοχος που ανήκει στο ήδη επιλεγμένο τμήμα δίνει
        // απολύτως έγκυρο τηλέφωνο — το ίδιο κριτήριο με τη συμπλήρωση του
        // καλούντα παραπάνω.
        if (!isCallerOutsideSelectedDepartment) {
          _autofillPhoneForCommittedUser(user, lookup);
        }
      },
      onBeforeRecompute: () {
        final lookupForRestore = ref.read(lookupServiceProvider).value?.service;
        if (state.selectedDepartmentId != null) {
          _restoreDepartmentPhoneCandidatesIfNeeded(lookupForRestore);
        }
      },
    );
  }
}
