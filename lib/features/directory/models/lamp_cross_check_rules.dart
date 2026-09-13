import 'dart:convert';

/// Διακόπτες της «Διασταύρωσης με Λάμπα».
///
/// Χωριστοί από τους Κανόνες Επικύρωσης επίτηδες: εκείνοι κρίνουν τον
/// Κατάλογο μόνο του, ενώ εδώ κάθε έλεγχος χρειάζεται και τη δεύτερη βάση.
/// Ανακατεμένοι θα έδιναν μια οθόνη όπου οι μισοί κανόνες σιωπούν χωρίς να
/// φαίνεται γιατί.
///
/// **Οι προεπιλογές δεν είναι τυχαίες:** ανοιχτοί μένουν οι έλεγχοι που
/// βγάζουν λίγα και σχεδόν πάντα αληθινά ευρήματα· κλειστοί όσοι συγκρίνουν
/// σχέσεις (τμήμα, κάτοχος, τηλέφωνα), όπου οι δύο βάσεις αποκλίνουν θεμιτά
/// στις μισές εγγραφές. Έτσι η πρώτη σάρωση είναι διαβάσιμη, και ο χρήστης
/// ανοίγει μόνος του ό,τι θέλει να κυνηγήσει.
///
/// Αποθηκεύονται ως JSON στο `app_settings` της ενεργής βάσης, ώστε κάθε
/// βάση να κουβαλά τις δικές της επιλογές.
class LampCrossCheckRules {
  const LampCrossCheckRules({
    this.userNameSpellingEnabled = true,
    this.userAmbiguousMatchEnabled = true,
    this.userMissingInLampEnabled = false,
    this.userDepartmentEnabled = false,
    this.userPhoneOnlyInLampEnabled = false,
    this.userPhoneOnlyInCatalogEnabled = false,
    this.departmentNameSpellingEnabled = true,
    this.departmentMissingInLampEnabled = false,
    this.departmentPhoneOnlyInLampEnabled = false,
    this.departmentPhoneOnlyInCatalogEnabled = false,
    this.equipmentMissingInLampEnabled = true,
    this.equipmentRetiredInLampEnabled = true,
    this.equipmentTypeEnabled = true,
    this.equipmentOwnerEnabled = false,
    this.equipmentDepartmentEnabled = false,
  });

  /// Ο ίδιος άνθρωπος γραμμένος αλλιώς στις δύο βάσεις — «Νατάσσα» έναντι
  /// «Νατάσα», ή χαλασμένος τονισμένος χαρακτήρας από την παλιά εξαγωγή.
  final bool userNameSpellingEnabled;

  /// Ο υπάλληλος μοιάζει με δύο ή περισσότερους της Λάμπας και κανένας δεν
  /// ταιριάζει ακριβώς. Χωρίς αυτό, οι υπόλοιποι έλεγχοι θα σιωπούσαν για
  /// τον άνθρωπο χωρίς να το πουν ποτέ.
  final bool userAmbiguousMatchEnabled;

  /// Ο υπάλληλος δεν βρέθηκε καθόλου στη Λάμπα. Θεμιτό για νέο προσωπικό,
  /// γι' αυτό κλειστός: η Λάμπα πάγωσε, ο Κατάλογος συνεχίζει.
  final bool userMissingInLampEnabled;

  /// Ταυτισμένος υπάλληλος με άλλο τμήμα στις δύο βάσεις.
  final bool userDepartmentEnabled;

  /// Τηλέφωνο που η Λάμπα ξέρει και ο Κατάλογος όχι.
  final bool userPhoneOnlyInLampEnabled;

  /// Τηλέφωνο που ο Κατάλογος ξέρει και η Λάμπα όχι.
  final bool userPhoneOnlyInCatalogEnabled;

  /// Η ονομασία του τμήματος γράφεται αλλιώς στα δύο συστήματα.
  final bool departmentNameSpellingEnabled;

  /// Το τμήμα δεν βρέθηκε καθόλου στα γραφεία της Λάμπας.
  final bool departmentMissingInLampEnabled;

  final bool departmentPhoneOnlyInLampEnabled;
  final bool departmentPhoneOnlyInCatalogEnabled;

  /// Ο κωδικός του Καταλόγου δεν υπάρχει στο μητρώο της Λάμπας — συνήθως
  /// λάθος πληκτρολόγηση ή μηχάνημα που δεν καταγράφηκε ποτέ.
  final bool equipmentMissingInLampEnabled;

  /// Η Λάμπα το έχει καταστραμμένο, αποσυρμένο ή χαμένο, ενώ ο Κατάλογος το
  /// δείχνει ζωντανό.
  final bool equipmentRetiredInLampEnabled;

  /// Το είδος του Καταλόγου διαφέρει από την κατηγορία της Λάμπας. Πιάνει
  /// τον κωδικό που ταυτίστηκε τυχαία με άλλο μηχάνημα.
  final bool equipmentTypeEnabled;

  /// Το μηχάνημα είναι χρεωμένο σε άλλον άνθρωπο στις δύο βάσεις.
  final bool equipmentOwnerEnabled;

  /// Το μηχάνημα βρίσκεται σε άλλο τμήμα στις δύο βάσεις.
  final bool equipmentDepartmentEnabled;

  /// Αληθές όταν κανένας έλεγχος δεν είναι αναμμένος — τότε η σάρωση δεν
  /// έχει τίποτα να κάνει και το κουμπί το λέει, αντί να βγάζει «καθαρό».
  bool get allDisabled =>
      !userNameSpellingEnabled &&
      !userAmbiguousMatchEnabled &&
      !userMissingInLampEnabled &&
      !userDepartmentEnabled &&
      !userPhoneOnlyInLampEnabled &&
      !userPhoneOnlyInCatalogEnabled &&
      !departmentNameSpellingEnabled &&
      !departmentMissingInLampEnabled &&
      !departmentPhoneOnlyInLampEnabled &&
      !departmentPhoneOnlyInCatalogEnabled &&
      !equipmentMissingInLampEnabled &&
      !equipmentRetiredInLampEnabled &&
      !equipmentTypeEnabled &&
      !equipmentOwnerEnabled &&
      !equipmentDepartmentEnabled;

  LampCrossCheckRules copyWith({
    bool? userNameSpellingEnabled,
    bool? userAmbiguousMatchEnabled,
    bool? userMissingInLampEnabled,
    bool? userDepartmentEnabled,
    bool? userPhoneOnlyInLampEnabled,
    bool? userPhoneOnlyInCatalogEnabled,
    bool? departmentNameSpellingEnabled,
    bool? departmentMissingInLampEnabled,
    bool? departmentPhoneOnlyInLampEnabled,
    bool? departmentPhoneOnlyInCatalogEnabled,
    bool? equipmentMissingInLampEnabled,
    bool? equipmentRetiredInLampEnabled,
    bool? equipmentTypeEnabled,
    bool? equipmentOwnerEnabled,
    bool? equipmentDepartmentEnabled,
  }) {
    return LampCrossCheckRules(
      userNameSpellingEnabled:
          userNameSpellingEnabled ?? this.userNameSpellingEnabled,
      userAmbiguousMatchEnabled:
          userAmbiguousMatchEnabled ?? this.userAmbiguousMatchEnabled,
      userMissingInLampEnabled:
          userMissingInLampEnabled ?? this.userMissingInLampEnabled,
      userDepartmentEnabled:
          userDepartmentEnabled ?? this.userDepartmentEnabled,
      userPhoneOnlyInLampEnabled:
          userPhoneOnlyInLampEnabled ?? this.userPhoneOnlyInLampEnabled,
      userPhoneOnlyInCatalogEnabled:
          userPhoneOnlyInCatalogEnabled ?? this.userPhoneOnlyInCatalogEnabled,
      departmentNameSpellingEnabled:
          departmentNameSpellingEnabled ?? this.departmentNameSpellingEnabled,
      departmentMissingInLampEnabled:
          departmentMissingInLampEnabled ?? this.departmentMissingInLampEnabled,
      departmentPhoneOnlyInLampEnabled:
          departmentPhoneOnlyInLampEnabled ??
          this.departmentPhoneOnlyInLampEnabled,
      departmentPhoneOnlyInCatalogEnabled:
          departmentPhoneOnlyInCatalogEnabled ??
          this.departmentPhoneOnlyInCatalogEnabled,
      equipmentMissingInLampEnabled:
          equipmentMissingInLampEnabled ?? this.equipmentMissingInLampEnabled,
      equipmentRetiredInLampEnabled:
          equipmentRetiredInLampEnabled ?? this.equipmentRetiredInLampEnabled,
      equipmentTypeEnabled: equipmentTypeEnabled ?? this.equipmentTypeEnabled,
      equipmentOwnerEnabled:
          equipmentOwnerEnabled ?? this.equipmentOwnerEnabled,
      equipmentDepartmentEnabled:
          equipmentDepartmentEnabled ?? this.equipmentDepartmentEnabled,
    );
  }

  Map<String, Object?> toJson() => {
    'user_name_spelling_enabled': userNameSpellingEnabled,
    'user_ambiguous_match_enabled': userAmbiguousMatchEnabled,
    'user_missing_in_lamp_enabled': userMissingInLampEnabled,
    'user_department_enabled': userDepartmentEnabled,
    'user_phone_only_in_lamp_enabled': userPhoneOnlyInLampEnabled,
    'user_phone_only_in_catalog_enabled': userPhoneOnlyInCatalogEnabled,
    'department_name_spelling_enabled': departmentNameSpellingEnabled,
    'department_missing_in_lamp_enabled': departmentMissingInLampEnabled,
    'department_phone_only_in_lamp_enabled': departmentPhoneOnlyInLampEnabled,
    'department_phone_only_in_catalog_enabled':
        departmentPhoneOnlyInCatalogEnabled,
    'equipment_missing_in_lamp_enabled': equipmentMissingInLampEnabled,
    'equipment_retired_in_lamp_enabled': equipmentRetiredInLampEnabled,
    'equipment_type_enabled': equipmentTypeEnabled,
    'equipment_owner_enabled': equipmentOwnerEnabled,
    'equipment_department_enabled': equipmentDepartmentEnabled,
  };

  String toRawJson() => jsonEncode(toJson());

  static bool _boolOf(Map<String, Object?> map, String key, bool fallback) {
    final value = map[key];
    return value is bool ? value : fallback;
  }

  factory LampCrossCheckRules.fromJson(Map<String, Object?> map) {
    const d = LampCrossCheckRules();
    return LampCrossCheckRules(
      userNameSpellingEnabled: _boolOf(
        map,
        'user_name_spelling_enabled',
        d.userNameSpellingEnabled,
      ),
      userAmbiguousMatchEnabled: _boolOf(
        map,
        'user_ambiguous_match_enabled',
        d.userAmbiguousMatchEnabled,
      ),
      userMissingInLampEnabled: _boolOf(
        map,
        'user_missing_in_lamp_enabled',
        d.userMissingInLampEnabled,
      ),
      userDepartmentEnabled: _boolOf(
        map,
        'user_department_enabled',
        d.userDepartmentEnabled,
      ),
      userPhoneOnlyInLampEnabled: _boolOf(
        map,
        'user_phone_only_in_lamp_enabled',
        d.userPhoneOnlyInLampEnabled,
      ),
      userPhoneOnlyInCatalogEnabled: _boolOf(
        map,
        'user_phone_only_in_catalog_enabled',
        d.userPhoneOnlyInCatalogEnabled,
      ),
      departmentNameSpellingEnabled: _boolOf(
        map,
        'department_name_spelling_enabled',
        d.departmentNameSpellingEnabled,
      ),
      departmentMissingInLampEnabled: _boolOf(
        map,
        'department_missing_in_lamp_enabled',
        d.departmentMissingInLampEnabled,
      ),
      departmentPhoneOnlyInLampEnabled: _boolOf(
        map,
        'department_phone_only_in_lamp_enabled',
        d.departmentPhoneOnlyInLampEnabled,
      ),
      departmentPhoneOnlyInCatalogEnabled: _boolOf(
        map,
        'department_phone_only_in_catalog_enabled',
        d.departmentPhoneOnlyInCatalogEnabled,
      ),
      equipmentMissingInLampEnabled: _boolOf(
        map,
        'equipment_missing_in_lamp_enabled',
        d.equipmentMissingInLampEnabled,
      ),
      equipmentRetiredInLampEnabled: _boolOf(
        map,
        'equipment_retired_in_lamp_enabled',
        d.equipmentRetiredInLampEnabled,
      ),
      equipmentTypeEnabled: _boolOf(
        map,
        'equipment_type_enabled',
        d.equipmentTypeEnabled,
      ),
      equipmentOwnerEnabled: _boolOf(
        map,
        'equipment_owner_enabled',
        d.equipmentOwnerEnabled,
      ),
      equipmentDepartmentEnabled: _boolOf(
        map,
        'equipment_department_enabled',
        d.equipmentDepartmentEnabled,
      ),
    );
  }

  /// Κενό ή άκυρο JSON σημαίνει «καμία ρύθμιση ακόμη» και δίνει τις
  /// προεπιλογές, ώστε η λειτουργία να δουλεύει από την πρώτη στιγμή.
  factory LampCrossCheckRules.fromRawJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const LampCrossCheckRules();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        return LampCrossCheckRules.fromJson(decoded);
      }
      return const LampCrossCheckRules();
    } on FormatException {
      return const LampCrossCheckRules();
    }
  }
}
