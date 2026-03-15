import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/utils/name_parser.dart';
import '../../../core/utils/phone_list_parser.dart';
import 'lookup_provider.dart';
import '../models/equipment_model.dart';
import '../models/user_model.dart';

/// Κατάσταση header φόρμας κλήσης: επιλογές, σφάλμα, πρόσφατα τηλέφωνα.
/// FocusNodes ΔΕΝ αποθηκεύονται εδώ — ζουν στο widget State.
class CallHeaderState {
  CallHeaderState({
    this.selectedPhone,
    this.selectedCaller,
    this.selectedEquipment,
    this.phoneError,
    List<String>? recentPhones,
    List<String>? phoneCandidates,
    List<UserModel>? callerCandidates,
    List<EquipmentModel>? equipmentCandidates,
    this.isPhoneAmbiguous = false,
    this.isEquipmentAmbiguous = false,
    this.callerNoMatch = false,
    this.equipmentNoMatch = false,
    this.hasAnyContent = false,
    this.equipmentText = '',
    this.callerDisplayText = '',
    this.phoneIsManual = false,
    this.callerIsManual = false,
    this.equipmentIsManual = false,
  })  : recentPhones = recentPhones ?? [],
        phoneCandidates = phoneCandidates ?? [],
        callerCandidates = callerCandidates ?? [],
        equipmentCandidates = equipmentCandidates ?? [];

  final String? selectedPhone;
  final UserModel? selectedCaller;
  final EquipmentModel? selectedEquipment;
  final String? phoneError;
  final List<String> recentPhones;
  final List<String> phoneCandidates;
  final List<UserModel> callerCandidates;
  final List<EquipmentModel> equipmentCandidates;
  final bool isPhoneAmbiguous;
  final bool isEquipmentAmbiguous;
  /// True όταν έγινε phone lookup και βρέθηκαν 0 χρήστες (υπόδειξη "Καμία αντιστοιχία").
  final bool callerNoMatch;
  /// True όταν έγινε equipment lookup και βρέθηκαν 0 (υπόδειξη "Καμία αντιστοιχία").
  final bool equipmentNoMatch;
  /// Ενημερώνεται μετά από Enter ή focus out· χρησιμοποιείται για εμφάνιση κουμπιού "Καθαρισμός όλων".
  final bool hasAnyContent;
  /// Το κείμενο που έχει πληκτρολογήσει ο χρήστης στο πεδίο Κωδικός Εξοπλισμού (ανεξάρτητα από το αν το επέλεξε).
  final String equipmentText;
  /// Κείμενο εμφάνισης καλούντα (όνομα ή "Άγνωστος").
  final String callerDisplayText;
  /// True όταν το τηλέφωνο έχει τροποποιηθεί χειροκίνητα από τον χρήστη.
  final bool phoneIsManual;
  /// True όταν ο καλών έχει τροποποιηθεί χειροκίνητα από τον χρήστη.
  final bool callerIsManual;
  /// True όταν ο εξοπλισμός έχει τροποποιηθεί χειροκίνητα από τον χρήστη.
  final bool equipmentIsManual;

  static const int _maxRecentPhones = 20;

  String get normalizedCallerDisplayText => callerDisplayText.trim();

  bool get isUnknownCaller => normalizedCallerDisplayText == 'Άγνωστος';

  bool get hasExplicitCallerText =>
      normalizedCallerDisplayText.isNotEmpty && !isUnknownCaller;

  bool get hasPhoneInput => selectedPhone?.trim().isNotEmpty == true;

  bool get hasEquipmentInput => equipmentText.trim().isNotEmpty;

  bool get hasPhoneAssociation {
    final callerPhone = selectedCaller?.phone?.trim() ?? '';
    final selPhone = selectedPhone?.trim() ?? '';
    if (selPhone.isEmpty) return false;
    return PhoneListParser.containsPhone(callerPhone, selPhone);
  }

  bool get hasEquipmentAssociation {
    if (selectedCaller == null) return false;
    final text = equipmentText.trim();
    if (text.isEmpty) return false;
    if (selectedEquipment != null && selectedEquipment!.userId == selectedCaller!.id) return true;
    
    // Έλεγχος αν ο εξοπλισμός (βάσει κειμένου) ανήκει ήδη στον χρήστη, μέσω της λίστας
    return equipmentCandidates.any((e) => e.code?.trim() == text || e.displayLabel == text);
  }

  /// True όταν υπάρχει ήδη γνωστός χρήστης και τουλάχιστον ένα από Τηλέφωνο/Εξοπλισμό έχει τιμή και δεν είναι συσχετισμένο.
  bool get needsExistingCallerAssociation {
    if (selectedCaller == null) return false;
    final phoneFilled = selectedPhone?.trim().isNotEmpty == true;
    final equipmentFilled = equipmentText.trim().isNotEmpty;
    if (!phoneFilled && !equipmentFilled) return false;

    final needsPhone = phoneFilled && !hasPhoneAssociation;
    final needsEquipment = equipmentFilled && !hasEquipmentAssociation;

    return needsPhone || needsEquipment;
  }

  /// True όταν δεν υπάρχει επιλεγμένος χρήστης από τη βάση, υπάρχει ρητό όνομα καλούντα
  /// και υπάρχει τουλάχιστον ένα στοιχείο προς καταχώρηση (τηλέφωνο ή εξοπλισμός).
  bool get needsNewCallerCreation =>
      selectedCaller == null &&
      hasExplicitCallerText &&
      (hasPhoneInput || hasEquipmentInput);

  /// Το κουμπί `+` εμφανίζεται είτε για νέα συσχέτιση σε υπάρχοντα χρήστη είτε για δημιουργία νέου καλούντα.
  bool get needsAssociation =>
      needsExistingCallerAssociation || needsNewCallerCreation;

  /// Πράσινο: μία πλήρης συσχέτιση ή και τα δύο μη συσχετισμένα. Πορτοκαλί: μερική ενημέρωση (και τα δύο συμπληρωμένα, μόνο το ένα συσχετισμένο).
  Color get associationColor {
    if (needsNewCallerCreation) {
      return Colors.green;
    }
    final phoneFilled = selectedPhone?.trim().isNotEmpty == true;
    final equipmentFilled = equipmentText.trim().isNotEmpty;

    final needsPhone = phoneFilled && !hasPhoneAssociation;
    final needsEquipment = equipmentFilled && !hasEquipmentAssociation;

    if (phoneFilled && equipmentFilled && (needsPhone != needsEquipment)) {
      return Colors.orange;
    }
    return Colors.green;
  }

  /// Τι ακριβώς θα συμβεί είτε για υπάρχοντα χρήστη είτε για νέο καλούντα.
  String? get associationTooltip {
    if (!needsAssociation) return null;
    final phoneFilled = hasPhoneInput;
    final equipmentFilled = hasEquipmentInput;

    if (needsNewCallerCreation) {
      final parts = <String>[];
      if (phoneFilled) {
        parts.add('τηλέφωνο: ${selectedPhone!.trim()}');
      }
      if (equipmentFilled) {
        parts.add('εξοπλισμό: ${equipmentText.trim()}');
      }
      if (parts.isEmpty) {
        return 'Προσθήκη νέου καλούντα: $normalizedCallerDisplayText';
      }
      return 'Προσθήκη νέου καλούντα: $normalizedCallerDisplayText με ${parts.join(' και ')}';
    }

    final name = selectedCaller?.name ?? 'άγνωστος';
    final parts = <String>[];
    if (phoneFilled && !hasPhoneAssociation) {
      parts.add('τηλεφώνου: ${selectedPhone!.trim()}');
    }
    if (equipmentFilled && !hasEquipmentAssociation) {
      parts.add('εξοπλισμού: ${equipmentText.trim()}');
    }
    if (parts.isEmpty) return null;
    return 'Προσθήκη ${parts.join(' και ')} στο $name';
  }

  /// True όταν μπορεί να γίνει υποβολή κλήσης: συμπληρωμένο τηλέφωνο.
  bool get canSubmitCall => selectedPhone?.trim().isNotEmpty == true;

  CallHeaderState copyWith({
    String? selectedPhone,
    bool clearSelectedPhone = false,
    UserModel? selectedCaller,
    bool clearSelectedCaller = false,
    EquipmentModel? selectedEquipment,
    bool clearSelectedEquipment = false,
    String? phoneError,
    bool clearPhoneError = false,
    List<String>? recentPhones,
    List<String>? phoneCandidates,
    bool clearPhoneCandidates = false,
    List<UserModel>? callerCandidates,
    bool clearCallerCandidates = false,
    List<EquipmentModel>? equipmentCandidates,
    bool clearEquipmentCandidates = false,
    bool? isPhoneAmbiguous,
    bool? isEquipmentAmbiguous,
    bool? callerNoMatch,
    bool? equipmentNoMatch,
    bool? hasAnyContent,
    String? equipmentText,
    String? callerDisplayText,
    bool? phoneIsManual,
    bool? callerIsManual,
    bool? equipmentIsManual,
  }) {
    return CallHeaderState(
      selectedPhone: clearSelectedPhone ? null : (selectedPhone ?? this.selectedPhone),
      selectedCaller: clearSelectedCaller ? null : (selectedCaller ?? this.selectedCaller),
      selectedEquipment: clearSelectedEquipment ? null : (selectedEquipment ?? this.selectedEquipment),
      phoneError: clearPhoneError ? null : (phoneError ?? this.phoneError),
      recentPhones: recentPhones ?? this.recentPhones,
      phoneCandidates: clearPhoneCandidates ? [] : (phoneCandidates ?? this.phoneCandidates),
      callerCandidates: clearCallerCandidates ? [] : (callerCandidates ?? this.callerCandidates),
      equipmentCandidates: clearEquipmentCandidates ? [] : (equipmentCandidates ?? this.equipmentCandidates),
      isPhoneAmbiguous: isPhoneAmbiguous ?? this.isPhoneAmbiguous,
      isEquipmentAmbiguous: isEquipmentAmbiguous ?? this.isEquipmentAmbiguous,
      callerNoMatch: callerNoMatch ?? this.callerNoMatch,
      equipmentNoMatch: equipmentNoMatch ?? this.equipmentNoMatch,
      hasAnyContent: hasAnyContent ?? this.hasAnyContent,
      equipmentText: equipmentText ?? this.equipmentText,
      callerDisplayText: callerDisplayText ?? this.callerDisplayText,
      phoneIsManual: phoneIsManual ?? this.phoneIsManual,
      callerIsManual: callerIsManual ?? this.callerIsManual,
      equipmentIsManual: equipmentIsManual ?? this.equipmentIsManual,
    );
  }

  CallHeaderState copyWithClearSelections() {
    return copyWith(
      clearSelectedPhone: true,
      clearSelectedCaller: true,
      clearSelectedEquipment: true,
      clearPhoneError: true,
      clearPhoneCandidates: true,
      clearCallerCandidates: true,
      clearEquipmentCandidates: true,
      isPhoneAmbiguous: false,
      isEquipmentAmbiguous: false,
      callerNoMatch: false,
      equipmentNoMatch: false,
      hasAnyContent: false,
      equipmentText: '',
      callerDisplayText: '',
      phoneIsManual: false,
      callerIsManual: false,
      equipmentIsManual: false,
    );
  }
}

/// Notifier για το header: update/clear, recentPhones, clearAfterSubmit.
/// FocusNodes και Controllers εγγράφονται από το widget.
class CallHeaderNotifier extends Notifier<CallHeaderState> {
  FocusNode? _phoneFocusNode;
  FocusNode? _callerFocusNode;
  FocusNode? _equipmentFocusNode;
  TextEditingController? _phoneController;
  TextEditingController? _callerController;
  TextEditingController? _equipmentController;
  bool _isFillingFromLookup = false;

  FocusNode? get phoneFocusNode => _phoneFocusNode;
  FocusNode? get callerFocusNode => _callerFocusNode;
  FocusNode? get equipmentFocusNode => _equipmentFocusNode;

  void registerFocusNodes({
    required FocusNode phone,
    required FocusNode caller,
    required FocusNode equipment,
  }) {
    _phoneFocusNode = phone;
    _callerFocusNode = caller;
    _equipmentFocusNode = equipment;
  }

  void registerControllers({
    required TextEditingController phone,
    required TextEditingController caller,
    required TextEditingController equipment,
  }) {
    _phoneController = phone;
    _callerController = caller;
    _equipmentController = equipment;
  }

  void unregisterFocusNodes() {
    _phoneFocusNode = null;
    _callerFocusNode = null;
    _equipmentFocusNode = null;
  }

  void unregisterControllers() {
    _phoneController = null;
    _callerController = null;
    _equipmentController = null;
  }

  bool _computeHasAnyContent() {
    return (_phoneController?.text.trim().isNotEmpty ?? false) ||
        (_callerController?.text.trim().isNotEmpty ?? false) ||
        (_equipmentController?.text.trim().isNotEmpty ?? false) ||
        state.selectedCaller != null ||
        state.selectedEquipment != null ||
        state.callerCandidates.isNotEmpty ||
        state.equipmentCandidates.isNotEmpty;
  }

  /// Κλήση μετά από Enter ή focus out· ενημερώνει hasAnyContent για εμφάνιση κουμπιού "Καθαρισμός όλων"
  /// και αποθηκεύει το equipmentText για να μπορεί να συσχετιστεί ακόμα κι αν δεν επιλέχθηκε.
  void checkContent() {
    state = state.copyWith(
      hasAnyContent: _computeHasAnyContent(),
      equipmentText: _equipmentController?.text.trim() ?? '',
    );
  }

  @override
  CallHeaderState build() {
    return CallHeaderState();
  }

  void updatePhone(String? value) {
    state = state.copyWith(
      selectedPhone: value,
      clearSelectedPhone: value == null,
      clearPhoneError: true,
      clearPhoneCandidates: true,
    );
    if (value == null || value.trim().isEmpty) {
      state = state.copyWith(
        clearCallerCandidates: true,
        clearSelectedCaller: true,
        clearEquipmentCandidates: true,
        clearSelectedEquipment: true,
        isPhoneAmbiguous: false,
        isEquipmentAmbiguous: false,
        callerNoMatch: false,
        equipmentNoMatch: false,
      );
    } else {
      state = state.copyWith(
        clearCallerCandidates: true,
        clearSelectedCaller: true,
        clearEquipmentCandidates: true,
        clearSelectedEquipment: true,
        isPhoneAmbiguous: false,
        isEquipmentAmbiguous: false,
        callerNoMatch: false,
        equipmentNoMatch: false,
      );
    }
  }

  /// Επιλογή τηλεφώνου από λίστα candidates που προήλθαν από ήδη γνωστό caller.
  /// Δεν καθαρίζει caller/equipment context.
  void selectPhoneFromCandidates(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    state = state.copyWith(
      selectedPhone: trimmed,
      clearSelectedPhone: false,
      clearPhoneError: true,
      clearPhoneCandidates: true,
      isPhoneAmbiguous: false,
      phoneIsManual: true,
    );
    _phoneController?.value = TextEditingValue(
      text: trimmed,
      selection: TextSelection.collapsed(offset: trimmed.length),
    );
    markPhoneUsed(trimmed);

    final callerId = state.selectedCaller?.id;
    final canAutofillEquipment =
        !state.equipmentIsManual || state.equipmentText.trim().isEmpty;
    if (callerId != null && canAutofillEquipment) {
      performEquipmentLookup(callerId);
    }
  }

  void markPhoneAsManual() {
    if (state.phoneIsManual) return;
    state = state.copyWith(phoneIsManual: true);
  }

  void markCallerAsManual() {
    if (state.callerIsManual) return;
    state = state.copyWith(callerIsManual: true);
  }

  void markEquipmentAsManual() {
    if (state.equipmentIsManual) return;
    state = state.copyWith(equipmentIsManual: true);
  }

  void clearPhone() {
    state = state.copyWithClearSelections();
  }

  /// Μηδενίζει selectedPhone, selectedCaller, selectedEquipment, phoneError, candidates και κείμενο πεδίων.
  void clearAll() {
    _phoneController?.clear();
    _callerController?.clear();
    _equipmentController?.clear();
    state = state.copyWithClearSelections();
  }

  /// Μηδενίζει μόνο τις λίστες candidates και τα ambiguous flags (όχι τα επιλεγμένα πεδία).
  void clearAllCandidates() {
    state = state.copyWith(
      clearPhoneCandidates: true,
      clearCallerCandidates: true,
      clearEquipmentCandidates: true,
      isPhoneAmbiguous: false,
      isEquipmentAmbiguous: false,
      callerNoMatch: false,
      equipmentNoMatch: false,
    );
  }

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
      phoneIsManual: false,
    );
    _phoneController?.value = TextEditingValue(
      text: trimmed,
      selection: TextSelection.collapsed(offset: trimmed.length),
    );
    markPhoneUsed(trimmed);
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
    _phoneController?.clear();
  }

  bool _canAutofillPhone() {
    return !state.phoneIsManual || (state.selectedPhone?.trim().isEmpty ?? true);
  }

  /// Lookup τηλεφώνου: 0 → no match hint, 1 → setCaller + equipment lookup, >1 → dropdown candidates.
  Future<void> performPhoneLookup(String phone) async {
    if (_isFillingFromLookup) return;
    _isFillingFromLookup = true;
    try {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 3) {
      state = state.copyWith(
        clearPhoneCandidates: true,
        clearCallerCandidates: true,
        clearSelectedCaller: true,
        clearEquipmentCandidates: true,
        clearSelectedEquipment: true,
        isPhoneAmbiguous: false,
        isEquipmentAmbiguous: false,
        callerNoMatch: false,
        equipmentNoMatch: false,
      );
      return;
    }
    final asyncLookup = ref.read(lookupServiceProvider);
    final lookup = asyncLookup.hasValue ? asyncLookup.value : null;
    if (lookup == null) return;
    final users = lookup.findUsersByPhone(digits);
    if (users.isEmpty) {
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
      );
      return;
    }
    if (users.length == 1) {
      final name = users.first.name ?? users.first.fullNameWithDepartment;
      final canAutofillCaller =
          !state.callerIsManual || state.callerDisplayText.trim().isEmpty;
      if (canAutofillCaller) {
        state = state.copyWith(
          clearPhoneCandidates: true,
          selectedCaller: users.first,
          callerCandidates: [],
          isPhoneAmbiguous: false,
          callerNoMatch: false,
          callerDisplayText: name,
          callerIsManual: false,
        );
      } else {
        state = state.copyWith(
          clearPhoneCandidates: true,
          callerCandidates: [],
          isPhoneAmbiguous: false,
          callerNoMatch: false,
        );
      }
      markPhoneUsed(digits);
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
      clearSelectedEquipment: true,
      isPhoneAmbiguous: true,
      isEquipmentAmbiguous: false,
      callerNoMatch: false,
      equipmentNoMatch: false,
    );
    } finally {
      _isFillingFromLookup = false;
    }
  }

  /// Lookup εξοπλισμού για userId: 0 → no match hint, 1 → setEquipment, >1 → dropdown candidates.
  void performEquipmentLookup(int userId) {
    if (_isFillingFromLookup) return;
    _isFillingFromLookup = true;
    try {
      _performEquipmentLookupForUser(userId);
    } finally {
      _isFillingFromLookup = false;
    }
  }

  void _performEquipmentLookupForUser(int userId) {
    final asyncLookup = ref.read(lookupServiceProvider);
    final lookup = asyncLookup.hasValue ? asyncLookup.value : null;
    if (lookup == null) return;
    final list = lookup.findEquipmentsForUser(userId);
    if (list.isEmpty) {
      state = state.copyWith(
        equipmentCandidates: [],
        clearSelectedEquipment: true,
        isEquipmentAmbiguous: false,
        equipmentNoMatch: true,
      );
      return;
    }
    if (list.length == 1) {
      final canAutofillEquipment =
          !state.equipmentIsManual || state.equipmentText.trim().isEmpty;
      if (canAutofillEquipment) {
        state = state.copyWith(
          selectedEquipment: list.first,
          equipmentCandidates: [],
          isEquipmentAmbiguous: false,
          equipmentNoMatch: false,
          equipmentIsManual: false,
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
      clearSelectedEquipment: true,
      isEquipmentAmbiguous: true,
      equipmentNoMatch: false,
    );
  }

  void performCallerLookup(String nameOrQuery) {
    if (_isFillingFromLookup) return;
    _isFillingFromLookup = true;
    try {
      final query = nameOrQuery.trim();
      if (query.isEmpty || query == 'Άγνωστος') return;
      final asyncLookup = ref.read(lookupServiceProvider);
      final lookup = asyncLookup.hasValue ? asyncLookup.value : null;
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
      state = state.copyWith(
        selectedCaller: user,
        clearPhoneCandidates: true,
        callerCandidates: [],
        callerNoMatch: false,
        isPhoneAmbiguous: false,
        callerDisplayText: displayName,
        callerIsManual: false,
      );

      if (_canAutofillPhone()) {
        final phones = _splitPhones(user.phone);
        if (phones.length == 1) {
          _setPhoneValueFromLookup(phones.first);
        } else if (phones.length > 1) {
          _setPhoneCandidatesFromLookup(phones);
        }
      }

      final canAutofillEquipment =
          !state.equipmentIsManual || state.equipmentText.trim().isEmpty;
      if (user.id != null && canAutofillEquipment) {
        _performEquipmentLookupForUser(user.id!);
      }
    } finally {
      _isFillingFromLookup = false;
    }
  }

  void performEquipmentLookupByCode(String code) {
    if (_isFillingFromLookup) return;
    _isFillingFromLookup = true;
    try {
      final query = code.trim();
      if (query.isEmpty) return;
      final asyncLookup = ref.read(lookupServiceProvider);
      final lookup = asyncLookup.hasValue ? asyncLookup.value : null;
      if (lookup == null) return;
      final list = lookup.findEquipmentsByCode(query);
      if (list.isEmpty) {
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
      state = state.copyWith(
        selectedEquipment: equipment,
        clearPhoneCandidates: true,
        equipmentCandidates: [],
        isEquipmentAmbiguous: false,
        equipmentNoMatch: false,
        equipmentIsManual: false,
      );

      final user = lookup.findUserById(equipment.userId);
      if (user == null) return;

      final canAutofillCaller =
          !state.callerIsManual || state.callerDisplayText.trim().isEmpty;
      if (canAutofillCaller) {
        state = state.copyWith(
          selectedCaller: user,
          callerCandidates: [],
          isPhoneAmbiguous: false,
          callerNoMatch: false,
          callerDisplayText: user.name ?? user.fullNameWithDepartment,
          callerIsManual: false,
        );
      }

      if (_canAutofillPhone()) {
        final phones = _splitPhones(user.phone);
        if (phones.length == 1) {
          _setPhoneValueFromLookup(phones.first);
        } else if (phones.length > 1) {
          _setPhoneCandidatesFromLookup(phones);
        }
      }
    } finally {
      _isFillingFromLookup = false;
    }
  }

  void clearPhoneCandidates() {
    state = state.copyWith(
      clearPhoneCandidates: true,
      isPhoneAmbiguous: false,
    );
  }

  void setCaller(UserModel? value) {
    state = state.copyWith(
      selectedCaller: value,
      clearSelectedCaller: value == null,
      clearPhoneCandidates: true,
      clearCallerCandidates: true,
      isPhoneAmbiguous: false,
      callerNoMatch: false,
      callerDisplayText: value?.name ?? value?.fullNameWithDepartment ?? '',
    );
  }

  void updateSelectedCaller(UserModel? value) {
    setCaller(value);
  }

  void updateCallerDisplayText(String text) {
    state = state.copyWith(callerDisplayText: text);
  }

  void clearCaller() {
    state = state.copyWith(
      clearSelectedCaller: true,
      clearPhoneCandidates: true,
      clearCallerCandidates: true,
      isPhoneAmbiguous: false,
      callerDisplayText: '',
    );
  }

  void setEquipment(EquipmentModel? value) {
    state = state.copyWith(
      selectedEquipment: value,
      clearSelectedEquipment: value == null,
      clearEquipmentCandidates: true,
      isEquipmentAmbiguous: false,
      equipmentNoMatch: false,
    );
  }

  void clearEquipment() {
    state = state.copyWith(clearSelectedEquipment: true, clearEquipmentCandidates: true, isEquipmentAmbiguous: false);
  }

  void setPhoneError(String? message) {
    state = state.copyWith(
      phoneError: message,
      clearPhoneError: message == null,
    );
  }

  void clearPhoneError() {
    state = state.copyWith(clearPhoneError: true);
  }

  void markPhoneUsed(String phone) {
    final trimmed = phone.trim();
    if (trimmed.isEmpty) return;
    final list = List<String>.from(state.recentPhones);
    list.remove(trimmed);
    list.insert(0, trimmed);
    if (list.length > CallHeaderState._maxRecentPhones) {
      list.length = CallHeaderState._maxRecentPhones;
    }
    state = state.copyWith(recentPhones: list);
  }

  void clearAfterSubmit() {
    state = state.copyWithClearSelections();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _phoneFocusNode?.requestFocus();
    });
  }

  void requestPhoneFocus() {
    _phoneFocusNode?.requestFocus();
  }

  /// Προσθέτει τηλέφωνο/εξοπλισμό στον τρέχοντα χρήστη στη βάση· invalidate lookup· επιστρέφει μήνυμα για SnackBar.
  Future<String?> associateCurrentIfNeeded() async {
    if (!state.needsAssociation) return null;

    final msg = state.associationTooltip;
    if (state.needsNewCallerCreation) {
      final name = NameParserUtility.stripParentheticalSuffix(state.normalizedCallerDisplayText);
      final phone = state.selectedPhone?.trim();
      final equipmentCode = state.equipmentText.trim();
      final parsed = NameParserUtility.parse(name);
      final userId = await DatabaseHelper.instance.insertUser(
        firstName: parsed.firstName,
        lastName: parsed.lastName,
        phone: phone?.isNotEmpty == true ? phone : null,
      );

      await DatabaseHelper.instance.updateAssociationsIfNeeded(
        userId,
        phone,
        equipmentCode.isNotEmpty ? equipmentCode : null,
      );

      state = state.copyWith(
        selectedCaller: UserModel(
          id: userId,
          firstName: parsed.firstName,
          lastName: parsed.lastName,
          phone: phone?.isNotEmpty == true ? phone : null,
        ),
        selectedEquipment: equipmentCode.isNotEmpty
            ? EquipmentModel(code: equipmentCode, userId: userId)
            : state.selectedEquipment,
        callerDisplayText: name,
        phoneIsManual: false,
        callerIsManual: false,
        equipmentIsManual: false,
      );
      ref.invalidate(lookupServiceProvider);
      return msg ?? 'Προστέθηκε.';
    }

    if (state.selectedCaller?.id == null) return null;
    final userId = state.selectedCaller!.id!;
    final phone = state.hasPhoneAssociation ? null : state.selectedPhone?.trim();
    final eqCode = state.hasEquipmentAssociation ? null : state.equipmentText.trim();

    await DatabaseHelper.instance.updateAssociationsIfNeeded(
      userId,
      phone,
      eqCode?.isNotEmpty == true ? eqCode : null,
    );

    final currentPhone = state.selectedCaller?.phone?.trim();
    final updatedPhone = phone?.isNotEmpty == true
        ? (currentPhone == null || currentPhone.isEmpty
              ? phone
              : PhoneListParser.containsPhone(currentPhone, phone)
                  ? currentPhone
                  : PhoneListParser.joinPhones([
                      ...PhoneListParser.splitPhones(currentPhone),
                      phone!,
                    ]))
        : currentPhone;
    state = state.copyWith(
      selectedCaller: UserModel(
        id: state.selectedCaller?.id,
        firstName: state.selectedCaller?.firstName,
        lastName: state.selectedCaller?.lastName,
        phone: updatedPhone,
        department: state.selectedCaller?.department,
        location: state.selectedCaller?.location,
        notes: state.selectedCaller?.notes,
      ),
      selectedEquipment: eqCode?.isNotEmpty == true
          ? EquipmentModel(
              id: state.selectedEquipment?.id,
              code: eqCode,
              type: state.selectedEquipment?.type,
              notes: state.selectedEquipment?.notes,
              userId: userId,
            )
          : state.selectedEquipment,
      phoneIsManual: false,
      callerIsManual: false,
      equipmentIsManual: false,
    );

    ref.invalidate(lookupServiceProvider);
    return msg ?? 'Προστέθηκε.';
  }
}

final callHeaderProvider =
    NotifierProvider<CallHeaderNotifier, CallHeaderState>(CallHeaderNotifier.new);
