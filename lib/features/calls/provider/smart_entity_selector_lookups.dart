import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/lookup_service.dart';
import '../../../core/utils/name_parser.dart';
import '../../../core/utils/phone_list_parser.dart';
import '../../../core/utils/search_text_normalizer.dart';
import '../models/equipment_model.dart';
import '../models/user_model.dart';
import 'lookup_provider.dart';
import 'smart_entity_selector_provider.dart';

/// Lookup τηλεφώνου, καλούντα, εξοπλισμού και βοηθητικές autofill ρουτίνες.
///
/// Συνεργάτης του [SmartEntitySelectorNotifier] (Σύνθεση): δουλεύει πάνω στην
/// κατάσταση του host μέσω των δημόσιων γεφυρών του — δεν κρατά δική του.
class SmartEntitySelectorLookups {
  SmartEntitySelectorLookups(this.host);

  final SmartEntitySelectorNotifier host;

  SmartEntitySelectorState get state => host.selectorState;
  set state(SmartEntitySelectorState value) => host.selectorState = value;

  Ref get ref => host.selectorRef;

  bool get hasManualEquipmentSelection => state.equipmentText.trim().isNotEmpty;

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
    host.markPhoneUsed(trimmed);
  }

  /// **Μοναδικό** σημείο επιβολής του συμβολαίου των υποψήφιων τηλεφώνων:
  /// ακριβώς ένας αριθμός = απόφαση (μπαίνει στο πεδίο, χωρίς λίστα), δύο και
  /// πάνω = λίστα υποψηφίων, κανένας = καμία λίστα.
  ///
  /// Κάθε ροή που παράγει υποψήφια τηλέφωνα περνά από εδώ — έτσι καμία δεν
  /// μπορεί να ξεχάσει ότι το μοναδικό/ακριβές ταίριασμα κερδίζει.
  /// Προϋπόθεση κάθε καλούντος: το πεδίο τηλεφώνου είναι **κενό**.
  void applyPhoneCandidatesFromLookup(List<String> phones) {
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
    applyPhoneCandidatesFromLookup(phones);
  }

  /// **Μοναδικό** σημείο επιβολής του συμβολαίου για τον καλούντα:
  /// ακριβώς ένας υπάλληλος = απόφαση, δύο και πάνω = λίστα, κανένας = καθαρό
  /// πεδίο. Προϋπόθεση κάθε καλούντος: το πεδίο καλούντα είναι **κενό**.
  void applyCallerCandidatesFromLookup(List<UserModel> users) {
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
  void applyEquipmentCandidatesFromLookup(List<EquipmentModel> equipment) {
    if (equipment.length == 1) {
      final only = equipment.first;
      final text = _equipmentAutofillText(only);
      state = state.copyWith(
        selectedEquipment: only,
        equipmentText: text,
        equipmentCandidates: [],
        isEquipmentAmbiguous: false,
        equipmentNoMatch: false,
        hasAnyContent: host.computeHasAnyContent(equipmentText: text),
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
  void restoreDepartmentPhoneCandidatesIfNeeded(LookupService? lookup) {
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
    applyPhoneCandidatesFromLookup(phones);
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

  /// **Μοναδικό** σημείο του κανόνα «το τμήμα νικά»: με αναγνωρισμένο τμήμα
  /// στη φόρμα (όποιος κι αν το συμπλήρωσε), ένα τηλέφωνο ή ένας εξοπλισμός
  /// δεν φέρνει ανθρώπους άλλου τμήματος — ούτε ως συμπλήρωση ούτε ως λίστα.
  /// Η ασυμφωνία φαίνεται μόνο στους δείκτες διένεξης. Χωρίς τμήμα περνούν
  /// όλοι.
  List<UserModel> _withinLockedDepartment(List<UserModel> users) {
    final lockedDepartmentId = state.selectedDepartmentId;
    if (lockedDepartmentId == null) return users;
    return users.where((u) => u.departmentId == lockedDepartmentId).toList();
  }

  bool _isOutsideLockedDepartment(int departmentId) {
    final lockedDepartmentId = state.selectedDepartmentId;
    return lockedDepartmentId != null && departmentId != lockedDepartmentId;
  }

  /// Το στοιχείο ανήκει σε άλλο τμήμα από το κλειδωμένο, ή δεν υπάρχει στη
  /// βάση: ο Καλούντας και ο Εξοπλισμός συμπεριφέρονται σαν να είχε
  /// συμπληρωθεί μόνο το τμήμα — δείχνουν τους υποψήφιους **του** σε κενά
  /// πεδία, χωρίς να γράψουν τιμή. Χωρίς κλειδωμένο τμήμα δεν κάνει τίποτα.
  void _showLockedDepartmentCandidates(LookupService lookup) {
    restoreDepartmentCallerCandidatesIfNeeded(lookup);
    restoreDepartmentEquipmentCandidatesIfNeeded(lookup);
  }

  /// Το τμήμα που ανήκουν **όλοι** οι [users], ή `null` αν κάποιος δεν έχει
  /// τμήμα ή αν διαφέρουν.
  int? _sharedDepartmentIdOf(List<UserModel> users) {
    if (users.isEmpty || users.any((u) => u.departmentId == null)) return null;
    final ids = users.map((u) => u.departmentId!).toSet();
    return ids.length == 1 ? ids.single : null;
  }

  /// **Μοναδικό** σημείο του κανόνα «όλα δείχνουν ένα τμήμα» για ομάδα
  /// ανθρώπων (κοινό τηλέφωνο, εξοπλισμός πολλών κατόχων): όταν ανήκουν όλοι
  /// στο ίδιο τμήμα, αυτό συμπληρώνεται — μόνο σε **κενό** πεδίο Τμήματος.
  void _autofillSharedDepartmentIfEmpty(
    List<UserModel> users,
    LookupService lookup,
  ) {
    if (state.departmentText.trim().isNotEmpty ||
        state.selectedDepartmentId != null) {
      return;
    }
    final departmentId = _sharedDepartmentIdOf(users);
    if (departmentId == null) return;
    final name = lookup.departmentIdToName[departmentId];
    if (name == null) return;
    state = state.copyWith(
      departmentText: name,
      selectedDepartmentId: departmentId,
    );
  }

  /// Υπόδειξη τηλεφώνου για **ομάδα κατόχων** (εξοπλισμός πολλών κατόχων):
  /// ο ίδιος κανόνας με τον έναν κάτοχο — πρώτα τα δικά τους νούμερα, και
  /// μόνο όταν δεν μοιράζονται κανένα, τα τηλέφωνα του τμήματος.
  ///
  /// «Δικά τους» = όσα έχουν **όλοι** (π.χ. το τηλέφωνο της βάρδιας): ένας
  /// αριθμός που έχει μόνο ο ένας θα πρότεινε στα τυφλά έναν από τους δύο.
  void _autofillPhoneForSharedOwners(
    List<UserModel> owners,
    LookupService lookup,
  ) {
    if (!_canAutofillPhone() || owners.isEmpty) return;
    final common =
        owners
            .skip(1)
            .fold<Set<String>>(
              owners.first.phones.map((p) => p.trim()).toSet(),
              (acc, u) =>
                  acc.intersection(u.phones.map((p) => p.trim()).toSet()),
            )
          ..remove('');
    if (common.isNotEmpty) {
      applyPhoneCandidatesFromLookup(common.toList());
      return;
    }
    final departmentId =
        state.selectedDepartmentId ?? _sharedDepartmentIdOf(owners);
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
  void restoreDepartmentCallerCandidatesIfNeeded(LookupService? lookup) {
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
  void restoreDepartmentEquipmentCandidatesIfNeeded(LookupService? lookup) {
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
        NameParserUtility.stripDisplayDecorations(user.fullNameWithDepartment);
    final strippedName = NameParserUtility.stripDisplayDecorations(rawName);

    return normalizedQuery ==
        SearchTextNormalizer.normalizeForSearch(strippedName);
  }

  String departmentTextForUser(UserModel user) {
    if (user.departmentId == null) return '';
    final asyncLookup = ref.read(lookupServiceProvider);
    final lookup = asyncLookup.value?.service;
    if (lookup == null) return '';
    return lookup.departmentIdToName[user.departmentId] ?? '';
  }

  void performPhoneLookup(String phone) {
    if (host.isFillingFromLookup) return;

    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final generation = host.bumpPhoneLookupGeneration();
    if (digits.length < 3) {
      // Κάτω από 3 ψηφία το τηλέφωνο αγνοείται σαν κενό — οι σχέσεις
      // των υπόλοιπων πεδίων ξαναχτίζονται κανονικά χωρίς αυτό.
      host.runExclusiveLookup(null, () {
        state = state.copyWith(
          clearPhoneCandidates: true,
          clearCallerCandidates: true,
          clearSelectedCaller: true,
          clearEquipmentCandidates: true,
          clearSelectedEquipment: !hasManualEquipmentSelection,
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
      if (generation == host.phoneLookupGeneration) {
        _applyPhoneLookupWithCatalog(digits, snap.requireValue.service);
      }
      return;
    }
    // Κατά το πρώτο frame το AsyncValue μπορεί να είναι ακόμα loading.
    ref
        .read(lookupServiceProvider.future)
        .then((bundle) {
          if (!ref.mounted) return;
          if (generation != host.phoneLookupGeneration) return;
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

  /// Διανομέας της αναζήτησης τηλεφώνου: ποιοι έχουν αυτό το τηλέφωνο
  /// αποφασίζει ποια περίπτωση ισχύει. Κάθε περίπτωση ζει σε δική της μέθοδο,
  /// ώστε ένα σφάλμα στη μία να μην κρύβεται μέσα στις άλλες.
  ///
  /// Μετρούν μόνο οι κάτοχοι του κλειδωμένου τμήματος: κοινό τηλέφωνο με
  /// έναν κάτοχο μέσα στο τμήμα είναι η περίπτωση του ενός κατόχου.
  void _applyPhoneLookupWithCatalog(String digits, LookupService lookup) {
    host.runExclusiveLookup(SelectorField.phone, () {
      final allOwners = lookup.findUsersByPhone(digits);
      final users = _withinLockedDepartment(allOwners);
      if (allOwners.isEmpty) {
        _applyPhoneWithoutOwner(digits, lookup);
      } else if (users.isEmpty) {
        _applyPhoneWithoutOwner(
          digits,
          lookup,
          ownedOutsideLockedDepartment: true,
        );
      } else if (users.length == 1) {
        _applySinglePhoneOwner(digits, users.first);
      } else {
        _applySharedPhoneOwners(users, lookup);
      }
    });
  }

  /// Τηλέφωνο που δεν δίνει κάτοχο σε αυτή τη φόρμα: ίσως τηλέφωνο τμήματος,
  /// ίσως άγνωστο — ή τηλέφωνο που ανήκει σε άλλο τμήμα από το κλειδωμένο
  /// ([ownedOutsideLockedDepartment], ή τηλέφωνο τμήματος άλλου τμήματος).
  void _applyPhoneWithoutOwner(
    String digits,
    LookupService lookup, {
    bool ownedOutsideLockedDepartment = false,
  }) {
    final orphanDept = ownedOutsideLockedDepartment
        ? null
        : lookup.getDepartmentByPhone(digits);
    final belongsToAnotherDepartment =
        ownedOutsideLockedDepartment ||
        (orphanDept?.id != null && _isOutsideLockedDepartment(orphanDept!.id!));
    final canAutofillDepartment =
        state.departmentText.trim().isEmpty &&
        state.selectedDepartmentId == null;
    // Γράφοντας ψηφίο-ψηφίο, ένα ενδιάμεσο τηλέφωνο («224») μπορεί να έχει
    // ήδη δέσει κάτοχο· το τελικό («2244») δεν είναι δικό του. Το όνομα που
    // έγραψε ΜΟΝΗ της η εφαρμογή είναι πλέον μπαγιάτικο: αν μείνει, δείχνει
    // υπαρκτό υπάλληλο χωρίς δεσμό — η κλήση φεύγει με ελεύθερο κείμενο και
    // ο κανόνας του τμήματος δεν προλαβαίνει καν να τρέξει, γιατί βλέπει
    // γεμάτο πεδίο. Ό,τι πληκτρολόγησε ο χρήστης δεν αγγίζεται.
    final previous = state.selectedCaller;
    final autofilledName = previous == null
        ? ''
        : (previous.name ?? previous.fullNameWithDepartment).trim();
    final callerTextIsStaleAutofill =
        autofilledName.isNotEmpty &&
        state.callerDisplayText.trim() == autofilledName;
    state = state.copyWith(
      clearPhoneCandidates: true,
      callerCandidates: [],
      clearSelectedCaller: true,
      callerDisplayText: callerTextIsStaleAutofill
          ? ''
          : state.callerDisplayText,
      equipmentCandidates: [],
      clearSelectedEquipment: !hasManualEquipmentSelection,
      isPhoneAmbiguous: false,
      isEquipmentAmbiguous: false,
      // Τηλέφωνο άλλου τμήματος ΕΧΕΙ αντιστοιχία — απλώς δεν φέρνει κανέναν.
      callerNoMatch: !belongsToAnotherDepartment,
      equipmentNoMatch: false,
      departmentText: (orphanDept != null && canAutofillDepartment)
          ? orphanDept.name
          : state.departmentText,
      selectedDepartmentId: (orphanDept != null && canAutofillDepartment)
          ? orphanDept.id
          : state.selectedDepartmentId,
    );
    // Ούτε τηλέφωνο άλλου τμήματος ούτε άγνωστο τηλέφωνο λένε ποιος καλεί:
    // το λέει το τμήμα της φόρμας, αν υπάρχει.
    if (belongsToAnotherDepartment || orphanDept?.id == null) {
      _showLockedDepartmentCandidates(lookup);
      return;
    }
    if (orphanDept?.id != null) {
      _applyDepartmentCallerLookup(lookup, orphanDept!.id!);
      _applyDepartmentEquipmentLookup(lookup, orphanDept.id!);
    }
  }

  /// Τηλέφωνο με έναν κάτοχο: αυτός είναι ο καλών — αλλά μόνο σε κενά πεδία.
  /// Γραμμένος καλούντας ή τμήμα μένουν ανέγγιχτα· η τυχόν ασυμφωνία φαίνεται
  /// ως δείκτης διένεξης, δεν διορθώνεται σιωπηλά.
  void _applySinglePhoneOwner(String digits, UserModel user) {
    final canAutofillCaller = state.callerDisplayText.trim().isEmpty;
    final canAutofillDepartment = _canAutofillDepartmentForUser(user);
    state = state.copyWith(
      clearPhoneCandidates: true,
      callerCandidates: [],
      isPhoneAmbiguous: false,
      callerNoMatch: false,
      selectedCaller: canAutofillCaller ? user : state.selectedCaller,
      callerDisplayText: canAutofillCaller
          ? (user.name ?? user.fullNameWithDepartment)
          : state.callerDisplayText,
      departmentText: canAutofillDepartment
          ? departmentTextForUser(user)
          : state.departmentText,
      selectedDepartmentId: canAutofillDepartment
          ? user.departmentId
          : state.selectedDepartmentId,
    );
    host.markPhoneUsed(digits);
    if (user.id != null) {
      _performEquipmentLookupForUser(user.id!);
    }
  }

  /// Κοινό τηλέφωνο πολλών κατόχων: η λίστα τους γίνεται υποψήφιοι καλούντες.
  /// Το τμήμα συμπληρώνεται μόνο όταν όλοι ανήκουν στο ίδιο.
  void _applySharedPhoneOwners(List<UserModel> users, LookupService lookup) {
    _autofillSharedDepartmentIfEmpty(users, lookup);

    // Αν ο ήδη δεμένος καλούντας είναι ένας από τους κατόχους, μην τον
    // ξεδέσεις (κοινόχρηστο τηλέφωνο βάρδιας μετά από autofill εξοπλισμού).
    final selectedCallerId = state.selectedCaller?.id;
    final selectedCallerIsOwner =
        selectedCallerId != null && users.any((u) => u.id == selectedCallerId);
    if (selectedCallerIsOwner) {
      state = state.copyWith(
        clearPhoneCandidates: true,
        callerCandidates: [],
        isPhoneAmbiguous: false,
        callerNoMatch: false,
      );
      return;
    }

    state = state.copyWith(
      clearPhoneCandidates: true,
      callerCandidates: users,
      clearSelectedCaller: true,
      equipmentCandidates: [],
      clearSelectedEquipment: !hasManualEquipmentSelection,
      isPhoneAmbiguous: true,
      isEquipmentAmbiguous: false,
      callerNoMatch: false,
      equipmentNoMatch: false,
    );
  }

  /// Lookup εξοπλισμού για userId: 0 → no match hint, 1 → setEquipment, >1 → dropdown candidates.
  void performEquipmentLookup(int userId) {
    host.runExclusiveLookup(null, () {
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
        clearSelectedEquipment: !hasManualEquipmentSelection,
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
          hasAnyContent: host.computeHasAnyContent(equipmentText: text),
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
      clearSelectedEquipment: !hasManualEquipmentSelection,
      isEquipmentAmbiguous: true,
      equipmentNoMatch: false,
    );
  }

  /// Καλών τμήματος μετά από lookup κοινόχρηστου τηλεφώνου (χωρίς προσωπικό κάτοχο).
  ///
  /// Ίδιο συμβόλαιο με την επιλογή τμήματος από τη λίστα: **ένας** υπάλληλος
  /// συμπληρώνεται, δύο και πάνω γίνονται **λίστα υποψηφίων**. Το κοινόχρηστο
  /// τηλέφωνο δεν λέει ποιος καλεί, οπότε δεν διαλέγουμε — αλλά ούτε κρύβουμε
  /// τους υπαλλήλους: ως τις 29/09 το «δεν μαντεύουμε» άφηνε το πεδίο χωρίς
  /// λίστα και με «Καμία αντιστοιχία», ενώ το τμήμα είχε ανθρώπους.
  void _applyDepartmentCallerLookup(LookupService lookup, int departmentId) {
    if (state.callerDisplayText.trim().isNotEmpty) return;
    if (state.selectedCaller != null) return;
    final users = lookup.getUsersByDepartment(departmentId);
    if (users.isEmpty) return;
    applyCallerCandidatesFromLookup(users);
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
        clearSelectedEquipment: !hasManualEquipmentSelection,
        isEquipmentAmbiguous: false,
        equipmentNoMatch: true,
      );
      return;
    }
    applyEquipmentCandidatesFromLookup(list);
  }

  void performCallerLookup(String nameOrQuery, {String? phoneFieldDigits}) {
    host.runExclusiveLookup(SelectorField.caller, () {
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
            ? departmentTextForUser(user)
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
    host.runExclusiveLookup(
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

        final allOwners = equipment.id != null
            ? lookup.findUsersForEquipment(equipment.id!)
            : <UserModel>[];
        final owners = _withinLockedDepartment(allOwners);

        // Όλοι οι κάτοχοι ανήκουν σε άλλο τμήμα από το κλειδωμένο: κανένας
        // δεν συμπληρώνεται ούτε προτείνεται, ούτε το τηλέφωνό τους.
        if (owners.isEmpty && allOwners.isNotEmpty) {
          restoreDepartmentCallerCandidatesIfNeeded(lookup);
          return;
        }

        // Πολλαπλοί κάτοχοι → λίστα candidates, ποτέ αυτόματη επιλογή
        // του πρώτου. Ό,τι όμως μοιράζονται ΟΛΟΙ δεν είναι ασαφές: το κοινό
        // τμήμα και το κοινό τηλέφωνο συμπληρώνονται σε κενά πεδία, όπως με
        // έναν κάτοχο.
        if (owners.length > 1) {
          if (state.callerDisplayText.trim().isEmpty) {
            state = state.copyWith(
              callerCandidates: owners,
              clearSelectedCaller: true,
              callerNoMatch: false,
              isPhoneAmbiguous: false,
            );
          }
          _autofillSharedDepartmentIfEmpty(owners, lookup);
          _autofillPhoneForSharedOwners(owners, lookup);
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

        // Ένας κάτοχος (ή ο μόνος του κλειδωμένου τμήματος): αυτός είναι ο
        // καλών — αλλά μόνο σε κενά πεδία.
        final shouldAutofillDepartment = _canAutofillDepartmentForUser(user);
        if (state.callerDisplayText.trim().isEmpty) {
          state = state.copyWith(
            selectedCaller: user,
            callerCandidates: [],
            isPhoneAmbiguous: false,
            callerNoMatch: false,
            callerDisplayText: user.name ?? user.fullNameWithDepartment,
            departmentText: shouldAutofillDepartment
                ? departmentTextForUser(user)
                : state.departmentText,
            selectedDepartmentId: shouldAutofillDepartment
                ? user.departmentId
                : state.selectedDepartmentId,
          );
        } else if (shouldAutofillDepartment) {
          state = state.copyWith(
            departmentText: departmentTextForUser(user),
            selectedDepartmentId: user.departmentId,
          );
        }
        _autofillPhoneForCommittedUser(user, lookup);
      },
      onBeforeRecompute: () {
        final lookupForRestore = ref.read(lookupServiceProvider).value?.service;
        if (state.selectedDepartmentId != null) {
          restoreDepartmentPhoneCandidatesIfNeeded(lookupForRestore);
        }
      },
    );
  }
}
