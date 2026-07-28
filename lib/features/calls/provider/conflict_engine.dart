import '../../../core/services/lookup_service.dart';
import '../../../core/utils/name_parser.dart';
import '../../../core/utils/phone_list_parser.dart';
import '../../../core/utils/search_text_normalizer.dart';
import '../models/equipment_model.dart';
import '../models/user_model.dart';
import 'smart_entity_selector_state.dart';

/// Παρουσία της τιμής ενός πεδίου στη βάση.
enum FieldPresence {
  /// Κενό — ή τιμή που δεν μετράει καθόλου (τηλέφωνο < 3 ψηφία, «Άγνωστος»).
  absent,

  /// Έχει τιμή, αλλά η τιμή δεν βρέθηκε στον κατάλογο.
  unknown,

  /// Η τιμή αντιστοιχεί σε μία ή περισσότερες οντότητες της βάσης.
  known,
}

/// Κατάσταση μιας σχέσης ζεύγους.
enum _Bond {
  /// Η βάση επιβεβαιώνει τη σύνδεση — σιωπή.
  related,

  /// Λείπει η διάσταση σύγκρισης — απουσία πληροφορίας, όχι διαφωνία (§Α.5.α).
  neutral,

  /// Δεν σχετίζονται — γραμμή και στα δύο μέλη.
  broken,
}

/// Στιγμιότυπο των τεσσάρων πεδίων — η **μοναδική** είσοδος του υπολογισμού
///.
class ConflictSnapshot {
  const ConflictSnapshot({
    required this.phoneDigits,
    required this.caller,
    required this.callerText,
    required this.departmentId,
    required this.departmentText,
    required this.equipment,
    required this.equipmentText,
  });

  final String phoneDigits;
  final UserModel? caller;
  final String callerText;
  final int? departmentId;
  final String departmentText;
  final EquipmentModel? equipment;
  final String equipmentText;
}

/// Αποτέλεσμα υπολογισμού: οι δείκτες και ποια πεδία είναι συμπληρωμένα
/// (χρήσιμο για τη διατήρηση της άγκυρας).
class ConflictComputation {
  const ConflictComputation({
    required this.conflicts,
    required this.filledFields,
  });

  final Map<SelectorField, List<FieldConflict>> conflicts;
  final Set<SelectorField> filledFields;
}

/// Χάρτης σχέσεων μεταξύ των τεσσάρων πεδίων.
///
/// Για καθένα από τα **έξι ζεύγη** ρωτά τη βάση «σχετίζονται;». Κάθε ζεύγος που
/// δεν σχετίζεται γράφει γραμμή **και στα δύο** μέλη — η σχέση ανήκει στο
/// ζεύγος, ποτέ σε ένα «πεδίο-πηγή».
class ConflictEngine {
  ConflictEngine({required ConflictSnapshot snapshot, required this.lookup})
    : _s = snapshot;

  final ConflictSnapshot _s;
  final LookupService lookup;

  final Map<SelectorField, List<_Reason>> _out = {};

  static const String _kUnknownCaller = 'Άγνωστος';
  static const String _kNotInDatabase = 'Δεν είναι καταχωρημένο στη βάση';
  static const int _kMinPhoneDigits = 3;

  // ─────────────────────────── Δημόσιο API ───────────────────────────

  ConflictComputation run() {
    _out.clear();
    final filled = _filledFields;
    // §Α.3 κατώφλι: με ένα στοιχείο δεν υπάρχει σχέση να περιγραφεί.
    if (filled.length >= 2) {
      _evaluateAllPairs();
      _addNotInDatabaseLines();
    }
    return ConflictComputation(conflicts: _materialize(), filledFields: filled);
  }

  // ──────────────────── Παρουσία & δεδομένα ανά πεδίο ────────────────────

  /// §Α.5.β: κάτω από 3 ψηφία το τηλέφωνο δεν είναι τιμή, είναι ημιτελής
  /// πληκτρολόγηση — αγνοείται εντελώς.
  late final bool _phoneEntered = _s.phoneDigits.length >= _kMinPhoneDigits;

  late final List<UserModel> _phoneUsers = _phoneEntered
      ? lookup.findUsersByPhone(_s.phoneDigits)
      : const [];

  late final int? _phoneSharedDeptId = _phoneEntered
      ? lookup.getDepartmentByPhone(_s.phoneDigits)?.id
      : null;

  late final Set<int> _phoneDeptIds = {
    ..._departmentIdsOf(_phoneUsers),
    ?_phoneSharedDeptId,
  };

  /// §Α.8: ο καλούντας ταυτοποιείται από το **όνομα**, όχι από δεμένο id.
  late final List<UserModel> _callerCandidates = _resolveCallerCandidates();

  late final Set<int> _callerDeptIds = _departmentIdsOf(_callerCandidates);

  late final int? _resolvedDepartmentId = _resolveDepartmentId();

  late final EquipmentModel? _resolvedEquipment = _resolveEquipment();

  late final List<UserModel> _equipmentOwners = _resolvedEquipment?.id != null
      ? lookup.findUsersForEquipment(_resolvedEquipment!.id!)
      : const [];

  late final Set<int> _equipmentDeptIds = {
    ..._departmentIdsOf(_equipmentOwners),
    ?_resolvedEquipment?.departmentId,
  };

  late final Map<SelectorField, FieldPresence> _presence = {
    SelectorField.phone: !_phoneEntered
        ? FieldPresence.absent
        : (_phoneUsers.isNotEmpty || _phoneSharedDeptId != null)
        ? FieldPresence.known
        : FieldPresence.unknown,
    SelectorField.caller: _callerTextIsMeaningful
        ? (_callerCandidates.isNotEmpty
              ? FieldPresence.known
              : FieldPresence.unknown)
        : FieldPresence.absent,
    SelectorField.department: _s.departmentText.trim().isEmpty
        ? FieldPresence.absent
        : (_resolvedDepartmentId != null
              ? FieldPresence.known
              : FieldPresence.unknown),
    SelectorField.equipment: _s.equipmentText.trim().isEmpty
        ? FieldPresence.absent
        : (_resolvedEquipment?.id != null
              ? FieldPresence.known
              : FieldPresence.unknown),
  };

  /// §Α.8 εξαίρεση: το «Άγνωστος» είναι δήλωση άγνοιας, όχι τιμή.
  bool get _callerTextIsMeaningful {
    final text = _s.callerText.trim();
    return text.isNotEmpty && text != _kUnknownCaller;
  }

  FieldPresence _presenceOf(SelectorField f) =>
      _presence[f] ?? FieldPresence.absent;

  bool _isKnown(SelectorField f) => _presenceOf(f) == FieldPresence.known;

  Set<SelectorField> get _filledFields => {
    for (final f in SelectorField.values)
      if (_presenceOf(f) != FieldPresence.absent) f,
  };

  bool get _anyKnownInForm => SelectorField.values.any(_isKnown);

  List<UserModel> _resolveCallerCandidates() {
    final bound = _s.caller;
    if (bound?.id != null) return [bound!];
    if (!_callerTextIsMeaningful) return const [];
    final text = _s.callerText.trim();
    return lookup
        .searchUsersByQuery(text)
        .where((u) => u.id != null && _isExactNameMatch(text, u))
        .toList();
  }

  int? _resolveDepartmentId() {
    if (_s.departmentId != null) return _s.departmentId;
    final text = _s.departmentText.trim();
    if (text.isEmpty) return null;
    return lookup.findDepartmentByName(text)?.id;
  }

  EquipmentModel? _resolveEquipment() {
    final bound = _s.equipment;
    if (bound?.id != null) return bound;
    final text = _s.equipmentText.trim();
    if (text.isEmpty) return null;
    final normalized = SearchTextNormalizer.normalizeForSearch(text);
    for (final e in lookup.findEquipmentsByCode(text)) {
      if (SearchTextNormalizer.normalizeForSearch(e.code ?? '') == normalized) {
        return e;
      }
    }
    return null;
  }

  // ───────────────────────── Οι έξι σχέσεις ─────────────────────────

  void _evaluateAllPairs() {
    _evaluate(SelectorField.phone, SelectorField.caller, _bondPhoneCaller);
    _evaluate(
      SelectorField.phone,
      SelectorField.department,
      _bondPhoneDepartment,
    );
    _evaluate(
      SelectorField.phone,
      SelectorField.equipment,
      _bondPhoneEquipment,
    );
    _evaluate(
      SelectorField.caller,
      SelectorField.department,
      _bondCallerDepartment,
    );
    _evaluate(
      SelectorField.caller,
      SelectorField.equipment,
      _bondCallerEquipment,
    );
    _evaluate(
      SelectorField.department,
      SelectorField.equipment,
      _bondDepartmentEquipment,
    );
  }

  /// §Α.5: ο καλούντας έχει το τηλέφωνο, ή το τηλέφωνο είναι κοινόχρηστο του
  /// τμήματός του. §Α.9: αρκεί ένας υποψήφιος.
  _Bond _bondPhoneCaller() {
    final matches = _callerCandidates.any((caller) {
      if (PhoneListParser.containsPhone(caller.phoneJoined, _s.phoneDigits)) {
        return true;
      }
      if (_phoneUsers.any((u) => u.id == caller.id)) return true;
      return _phoneUsers.isEmpty &&
          _phoneSharedDeptId != null &&
          _phoneSharedDeptId == caller.departmentId;
    });
    return matches ? _Bond.related : _Bond.broken;
  }

  _Bond _bondPhoneDepartment() {
    if (_phoneDeptIds.isEmpty) return _Bond.neutral;
    return _phoneDeptIds.contains(_resolvedDepartmentId)
        ? _Bond.related
        : _Bond.broken;
  }

  _Bond _bondPhoneEquipment() {
    final shareOwner = _phoneUsers.any(
      (u) => _equipmentOwners.any((o) => o.id == u.id),
    );
    if (shareOwner) return _Bond.related;
    if (_phoneDeptIds.isEmpty || _equipmentDeptIds.isEmpty) {
      return _Bond.neutral;
    }
    return _phoneDeptIds.intersection(_equipmentDeptIds).isNotEmpty
        ? _Bond.related
        : _Bond.broken;
  }

  _Bond _bondCallerDepartment() {
    if (_callerDeptIds.isEmpty) return _Bond.neutral;
    return _callerDeptIds.contains(_resolvedDepartmentId)
        ? _Bond.related
        : _Bond.broken;
  }

  _Bond _bondCallerEquipment() {
    if (_equipmentOwners.any(
      (o) => _callerCandidates.any((c) => c.id == o.id),
    )) {
      return _Bond.related;
    }
    if (_equipmentOwners.isNotEmpty) return _Bond.broken;
    // Κοινόχρηστος εξοπλισμός: κρίνεται μόνο από το τμήμα.
    final eqDeptId = _resolvedEquipment?.departmentId;
    if (eqDeptId == null || _callerDeptIds.isEmpty) return _Bond.neutral;
    return _callerDeptIds.contains(eqDeptId) ? _Bond.related : _Bond.broken;
  }

  _Bond _bondDepartmentEquipment() {
    if (_equipmentDeptIds.isEmpty) return _Bond.neutral;
    return _equipmentDeptIds.contains(_resolvedDepartmentId)
        ? _Bond.related
        : _Bond.broken;
  }

  // ──────────────────── Αποτίμηση & καταχώρηση ζεύγους ────────────────────

  void _evaluate(SelectorField a, SelectorField b, _Bond Function() bondOf) {
    final pa = _presenceOf(a);
    final pb = _presenceOf(b);
    if (pa == FieldPresence.absent || pb == FieldPresence.absent) return;

    final bothUnknown =
        pa == FieldPresence.unknown && pb == FieldPresence.unknown;
    // §Α.4.β: όταν τίποτα στη φόρμα δεν υπάρχει στη βάση, το «δεν σχετίζονται»
    // δεν πληροφορεί κανέναν.
    if (bothUnknown && !_anyKnownInForm) return;

    // Άγνωστο μέλος ⇒ δεν υπάρχει σχέση να βρεθεί· αλλιώς ρωτάμε τη βάση.
    final bond = (pa == FieldPresence.known && pb == FieldPresence.known)
        ? bondOf()
        : _Bond.broken;
    if (bond != _Bond.broken) return;

    final severity = _severityFor(a, b);
    _addReason(a, b, severity, _phrase(from: a, to: b));
    _addReason(b, a, severity, _phrase(from: b, to: a));
  }

  /// §Α.4 + §Α.4.α: δύο γνωστά ⇒ αλλαγή σχέσης (κόκκινο)· ένα άγνωστο ⇒
  /// προσθήκη (κίτρινο), εκτός αν η προσθήκη αρπάζει δεσμευμένη σχέση.
  ConflictSeverity _severityFor(SelectorField a, SelectorField b) {
    if (_isKnown(a) && _isKnown(b)) return ConflictSeverity.mismatch;
    if (!_isKnown(a) && !_isKnown(b)) return ConflictSeverity.unknown;
    final known = _isKnown(a) ? a : b;
    final incoming = _isKnown(a) ? b : a;
    return _wouldSeizeExclusiveBond(known: known, incoming: incoming)
        ? ConflictSeverity.mismatch
        : ConflictSeverity.unknown;
  }

  /// Τηλέφωνο και εξοπλισμός ανήκουν **αποκλειστικά**· ο υπάλληλος ανήκει σε
  /// **ένα** τμήμα. Αντίθετα, ένας υπάλληλος χωράει πολλά τηλέφωνα/εξοπλισμούς
  /// και ένα τμήμα χωράει τα πάντα (§Α.4.α).
  bool _wouldSeizeExclusiveBond({
    required SelectorField known,
    required SelectorField incoming,
  }) {
    if (incoming == SelectorField.caller) {
      if (known == SelectorField.phone) return _phoneUsers.isNotEmpty;
      if (known == SelectorField.equipment) return _equipmentOwners.isNotEmpty;
      return false;
    }
    if (incoming == SelectorField.department) {
      switch (known) {
        case SelectorField.phone:
          return _phoneDeptIds.isNotEmpty;
        case SelectorField.caller:
          return _callerDeptIds.isNotEmpty;
        case SelectorField.equipment:
          return _equipmentDeptIds.isNotEmpty;
        case SelectorField.department:
          return false;
      }
    }
    return false;
  }

  /// §Α.4: μονομερής γραμμή, μόνο στο πεδίο με άγνωστη τιμή, πάντα τελευταία.
  void _addNotInDatabaseLines() {
    for (final f in SelectorField.values) {
      if (_presenceOf(f) != FieldPresence.unknown) continue;
      (_out[f] ??= []).add(
        const _Reason(
          severity: ConflictSeverity.unknown,
          message: _kNotInDatabase,
          counterpart: null,
          isTrailing: true,
        ),
      );
    }
  }

  void _addReason(
    SelectorField field,
    SelectorField counterpart,
    ConflictSeverity severity,
    String message,
  ) {
    (_out[field] ??= []).add(
      _Reason(
        severity: severity,
        message: message,
        counterpart: counterpart,
        isTrailing: false,
      ),
    );
  }

  Map<SelectorField, List<FieldConflict>> _materialize() {
    final result = <SelectorField, List<FieldConflict>>{};
    for (final entry in _out.entries) {
      if (entry.value.isEmpty) continue;
      result[entry.key] = [
        for (final r in entry.value)
          FieldConflict(
            severity: r.severity,
            message: r.message,
            counterpart: r.counterpart,
            isTrailing: r.isTrailing,
          ),
      ];
    }
    return Map.unmodifiable(result);
  }

  // ───────────────────────── Διατύπωση γραμμών ─────────────────────────

  /// «{Υποκείμενο του πεδίου μου} — δεν σχετίζεται με {το άλλο μέλος}» (§Α.7).
  String _phrase({required SelectorField from, required SelectorField to}) {
    final subject = _subject(from);
    if (from == SelectorField.caller && to == SelectorField.department) {
      return '$subject — δεν ανήκει στο τμήμα ${_departmentName()}';
    }
    if (from == SelectorField.department && to == SelectorField.caller) {
      return '$subject — δεν περιλαμβάνει: ${_callerName()}';
    }
    return '$subject — δεν σχετίζεται με ${_objectPhrase(to)}';
  }

  String _subject(SelectorField field) {
    switch (field) {
      case SelectorField.phone:
        return 'Τηλέφωνο ${_s.phoneDigits}';
      case SelectorField.caller:
        return _callerName();
      case SelectorField.department:
        return 'Τμήμα ${_departmentName()}';
      case SelectorField.equipment:
        return 'Εξοπλισμός ${_equipmentCode()}';
    }
  }

  String _objectPhrase(SelectorField field) {
    switch (field) {
      case SelectorField.phone:
        return 'το τηλέφωνο ${_s.phoneDigits}';
      case SelectorField.caller:
        return _callerName();
      case SelectorField.department:
        return 'το τμήμα ${_departmentName()}';
      case SelectorField.equipment:
        return 'τον εξοπλισμό ${_equipmentCode()}';
    }
  }

  /// Με έναν υποψήφιο δείχνουμε το όνομά του· με περισσότερους (συνωνυμία),
  /// το κείμενο του πεδίου — που είναι ακριβώς το κοινό τους όνομα.
  String _callerName() {
    if (_callerCandidates.length == 1) {
      final caller = _callerCandidates.first;
      final name = caller.name?.trim();
      if (name != null && name.isNotEmpty) return name;
      final full = caller.fullNameWithDepartment.trim();
      if (full.isNotEmpty) return full;
    }
    return _s.callerText.trim();
  }

  String _departmentName() => _s.departmentText.trim();

  String _equipmentCode() {
    final code = _resolvedEquipment?.code?.trim();
    if (code != null && code.isNotEmpty) return code;
    return _s.equipmentText.trim();
  }

  // ───────────────────────── Βοηθητικά ─────────────────────────

  Set<int> _departmentIdsOf(List<UserModel> users) =>
      users.map((u) => u.departmentId).whereType<int>().toSet();

  /// Ίδιο κριτήριο με το lookup του πεδίου καλούντα: κανονικοποιημένο πλήρες
  /// όνομα, χωρίς το «(Τμήμα)» που προστίθεται για εμφάνιση σε λίστες.
  static bool _isExactNameMatch(String query, UserModel user) {
    final normalizedQuery = SearchTextNormalizer.normalizeForSearch(query);
    if (normalizedQuery.isEmpty) return false;
    final rawName =
        user.name ??
        NameParserUtility.stripParentheticalSuffix(user.fullNameWithDepartment);
    final stripped = NameParserUtility.stripParentheticalSuffix(rawName);
    return normalizedQuery == SearchTextNormalizer.normalizeForSearch(stripped);
  }
}

/// Εσωτερική εγγραφή πριν τη μετατροπή σε [FieldConflict].
class _Reason {
  const _Reason({
    required this.severity,
    required this.message,
    required this.counterpart,
    required this.isTrailing,
  });

  final ConflictSeverity severity;
  final String message;
  final SelectorField? counterpart;
  final bool isTrailing;
}
