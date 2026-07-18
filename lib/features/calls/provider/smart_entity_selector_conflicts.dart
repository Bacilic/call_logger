part of 'smart_entity_selector_provider.dart';

/// Η «αλήθεια» που υπονοεί το πεδίο-πηγή κατά τον υπολογισμό συγκρούσεων.
class _SourceTruth {
  _SourceTruth({this.user, this.departmentId, this.departmentName});

  final UserModel? user;
  final int? departmentId;
  final String? departmentName;
}

/// Υπολογισμός δεικτών σύγκρουσης (v2 §Α).
mixin SmartEntitySelectorConflictsMixin on Notifier<SmartEntitySelectorState> {
  // ───────────────────────── Δείκτες σύγκρουσης (v2 §Α) ─────────────────────

  String _phoneDigitsOfState() =>
      state.selectedPhone?.replaceAll(RegExp(r'[^0-9]'), '').trim() ?? '';

  String _equipmentCodeOfState() {
    final code = state.selectedEquipment?.code?.trim();
    if (code != null && code.isNotEmpty) return code;
    return state.equipmentText.trim();
  }

  /// Ετικέτα πεδίου-πηγής για τα μηνύματα σύγκρουσης.
  String _sourceLabel(SelectorField field) {
    switch (field) {
      case SelectorField.phone:
        return 'Το τηλέφωνο ${_phoneDigitsOfState()}';
      case SelectorField.caller:
        final name =
            state.selectedCaller?.name ?? state.callerDisplayText.trim();
        return 'Ο καλούντας $name';
      case SelectorField.department:
        return 'Το τμήμα ${state.departmentText.trim()}';
      case SelectorField.equipment:
        return 'Ο εξοπλισμός ${_equipmentCodeOfState()}';
    }
  }

  void _addConflict(
    Map<SelectorField, List<FieldConflict>> target,
    SelectorField field,
    ConflictSeverity severity,
    String message,
  ) {
    (target[field] ??= <FieldConflict>[]).add(
      FieldConflict(severity: severity, message: message),
    );
  }

  /// Η «αλήθεια» που υπονοεί το πεδίο-πηγή: ένας μονοσήμαντος χρήστης και/ή ένα
  /// τμήμα. Επιστρέφει null όταν η πηγή είναι ασαφής (π.χ. >1 χρήστες) ή άγνωστη.
  _SourceTruth? _resolveSourceTruth(SelectorField source, LookupService lookup) {
    switch (source) {
      case SelectorField.phone:
        final digits = _phoneDigitsOfState();
        if (digits.length < 3) return null;
        final users = lookup.findUsersByPhone(digits);
        if (users.length == 1) {
          return _SourceTruth(user: users.first);
        }
        if (users.isEmpty) {
          final dept = lookup.getDepartmentByPhone(digits);
          if (dept?.id != null) {
            return _SourceTruth(departmentId: dept!.id, departmentName: dept.name);
          }
        }
        return null;
      case SelectorField.caller:
        final caller = state.selectedCaller;
        if (caller?.id == null) return null;
        return _SourceTruth(user: caller);
      case SelectorField.equipment:
        final eq = state.selectedEquipment;
        if (eq?.id == null) return null;
        final owners = lookup.findUsersForEquipment(eq!.id!);
        if (owners.length == 1) return _SourceTruth(user: owners.first);
        return null;
      case SelectorField.department:
        final id = state.selectedDepartmentId;
        if (id == null) return null;
        return _SourceTruth(
          departmentId: id,
          departmentName: state.departmentText.trim(),
        );
    }
  }

  /// Κόκκινες ασυμφωνίες: κάθε άλλο συμπληρωμένο πεδίο έναντι της πηγής.
  void _collectMismatches(
    SelectorField source,
    _SourceTruth truth,
    LookupService lookup,
    Map<SelectorField, List<FieldConflict>> out,
  ) {
    final label = _sourceLabel(source);
    final user = truth.user;
    final truthDeptId = user?.departmentId ?? truth.departmentId;
    final truthDeptName = truthDeptId == null
        ? null
        : (lookup.departmentIdToName[truthDeptId] ?? truth.departmentName);

    // ── Καλούντας ──
    if (source != SelectorField.caller &&
        state.callerDisplayText.trim().isNotEmpty &&
        state.callerDisplayText.trim() != 'Άγνωστος') {
      if (user != null) {
        final selected = state.selectedCaller;
        final identityDiffers = selected?.id != null
            ? selected!.id != user.id
            : SearchTextNormalizer.normalizeForSearch(
                    state.callerDisplayText) !=
                SearchTextNormalizer.normalizeForSearch(user.name ?? '');
        if (identityDiffers) {
          _addConflict(
            out,
            SelectorField.caller,
            ConflictSeverity.mismatch,
            '$label αντιστοιχεί σε: ${user.name ?? user.fullNameWithDepartment}',
          );
        }
      } else if (truthDeptId != null) {
        final selected = state.selectedCaller;
        if (selected?.id != null &&
            selected!.departmentId != null &&
            selected.departmentId != truthDeptId) {
          final callerDept =
              lookup.departmentIdToName[selected.departmentId] ?? '—';
          _addConflict(
            out,
            SelectorField.caller,
            ConflictSeverity.mismatch,
            'Ο καλούντας ${selected.name ?? ''} ανήκει στο τμήμα: $callerDept',
          );
        }
      }
    }

    // ── Τμήμα ──
    if (source != SelectorField.department &&
        state.departmentText.trim().isNotEmpty &&
        truthDeptId != null) {
      final selectedDeptId = state.selectedDepartmentId;
      final departmentDiffers = selectedDeptId != null
          ? selectedDeptId != truthDeptId
          : SearchTextNormalizer.normalizeForSearch(state.departmentText) !=
              SearchTextNormalizer.normalizeForSearch(truthDeptName ?? '');
      if (departmentDiffers) {
        _addConflict(
          out,
          SelectorField.department,
          ConflictSeverity.mismatch,
          '$label ανήκει στο τμήμα: ${truthDeptName ?? '—'}',
        );
      }
    }

    // ── Τηλέφωνο ──
    if (source != SelectorField.phone) {
      final phone = _phoneDigitsOfState();
      if (phone.isNotEmpty) {
        if (user != null) {
          if (!PhoneListParser.containsPhone(user.phoneJoined, phone)) {
            final expected = user.phones.isEmpty
                ? '—'
                : user.phones.join(', ');
            _addConflict(
              out,
              SelectorField.phone,
              ConflictSeverity.mismatch,
              '$label συνδέεται με τηλέφωνο: $expected',
            );
          }
        } else if (truthDeptId != null) {
          final phoneDeptIds = _departmentIdsForPhone(phone, lookup);
          if (phoneDeptIds.isNotEmpty && !phoneDeptIds.contains(truthDeptId)) {
            final phoneDeptName =
                lookup.departmentIdToName[phoneDeptIds.first] ?? '—';
            _addConflict(
              out,
              SelectorField.phone,
              ConflictSeverity.mismatch,
              'Το τηλέφωνο $phone συνδέεται με το τμήμα: $phoneDeptName',
            );
          }
        }
      }
    }

    // ── Εξοπλισμός ──
    if (source != SelectorField.equipment &&
        state.equipmentText.trim().isNotEmpty) {
      final eqId = state.selectedEquipment?.id;
      if (user != null && eqId != null) {
        final owned = lookup
            .findEquipmentsForUser(user.id!)
            .any((e) => e.id == eqId);
        if (!owned) {
          _addConflict(
            out,
            SelectorField.equipment,
            ConflictSeverity.mismatch,
            '$label δεν συνδέεται με τον εξοπλισμό: ${_equipmentCodeOfState()}',
          );
        }
      } else if (truthDeptId != null && eqId != null) {
        final eqDeptIds = lookup
            .findUsersForEquipment(eqId)
            .map((u) => u.departmentId)
            .whereType<int>()
            .toSet();
        if (eqDeptIds.isNotEmpty && !eqDeptIds.contains(truthDeptId)) {
          final eqDeptName = lookup.departmentIdToName[eqDeptIds.first] ?? '—';
          _addConflict(
            out,
            SelectorField.equipment,
            ConflictSeverity.mismatch,
            'Ο εξοπλισμός ${_equipmentCodeOfState()} ανήκει στο τμήμα: $eqDeptName',
          );
        }
      }
    }
  }

  Set<int> _departmentIdsForPhone(String phone, LookupService lookup) {
    final users = lookup.findUsersByPhone(phone);
    final ids = users.map((u) => u.departmentId).whereType<int>().toSet();
    if (ids.isNotEmpty) return ids;
    final orphan = lookup.getDepartmentByPhone(phone);
    return orphan?.id != null ? {orphan!.id!} : <int>{};
  }

  /// Κίτρινο: ο καλούντας είναι ελεύθερο κείμενο εκτός βάσης ενώ τουλάχιστον ένα
  /// άλλο πεδίο δείχνει σε γνωστή οντότητα (v2 §Α.6).
  void _collectCallerUnknownWarning(
    SelectorField source,
    LookupService lookup,
    Map<SelectorField, List<FieldConflict>> out,
  ) {
    if (source == SelectorField.caller) return;
    final text = state.callerDisplayText.trim();
    if (text.isEmpty || text == 'Άγνωστος') return;
    if (state.selectedCaller?.id != null) return;

    final phone = _phoneDigitsOfState();
    final phoneKnown =
        phone.length >= 3 && lookup.findUsersByPhone(phone).isNotEmpty;
    final equipmentKnown = state.selectedEquipment?.id != null;
    if (phoneKnown || equipmentKnown) {
      _addConflict(
        out,
        SelectorField.caller,
        ConflictSeverity.unknown,
        'Ο καλούντας δεν βρέθηκε στη βάση',
      );
    }
  }

  /// Επανυπολογισμός όλων των συγκρούσεων εξ αρχής μετά από ολοκληρωμένο lookup
  /// (v2 §Α.4 stateless). [source] = το πεδίο που μόλις τροποποιήθηκε· δεν παίρνει
  /// ποτέ δείκτη (§Α.5).
  void _recomputeConflicts(SelectorField source, LookupService? lookup) {
    if (lookup == null) {
      if (state.conflicts.isNotEmpty) {
        state = state.copyWith(clearConflicts: true);
      }
      return;
    }
    final out = <SelectorField, List<FieldConflict>>{};
    final truth = _resolveSourceTruth(source, lookup);
    if (truth != null) {
      _collectMismatches(source, truth, lookup, out);
    }
    _collectCallerUnknownWarning(source, lookup, out);
    out.remove(source); // §Α.5: η πηγή ποτέ δεν εμφανίζει δικό της δείκτη.
    out.removeWhere((_, v) => v.isEmpty);
    state = state.copyWith(
      conflicts: out,
      clearConflicts: out.isEmpty,
    );
  }
}
