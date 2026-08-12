import 'dart:convert';

import 'package:characters/characters.dart';

/// Ρυθμιζόμενοι κανόνες επικύρωσης του Καταλόγου.
///
/// Όλοι οι κανόνες είναι ΥΠΟΔΕΙΞΕΙΣ (προειδοποιήσεις) — δεν εμποδίζουν ποτέ
/// την αποθήκευση. Αποθηκεύονται ως JSON στο `app_settings` της ενεργής βάσης,
/// ώστε κάθε βάση να κουβαλά τους δικούς της κανόνες.
class CatalogValidationRules {
  const CatalogValidationRules({
    this.internalPhoneDigitsEnabled = true,
    this.internalPhoneDigits = 4,
    this.externalPhoneDigitsEnabled = true,
    this.externalPhoneDigits = 10,
    this.internalPrefixEnabled = true,
    this.internalPrefixFrom = 22,
    this.internalPrefixTo = 29,
    this.equipmentDigitsEnabled = true,
    this.equipmentMinDigits = 3,
    this.equipmentMaxDigits = 4,
    this.equipmentLatinCodeEnabled = true,
    this.equipmentForeignCodeEnabled = true,
    this.departmentNameEnabled = true,
    this.personNameEnabled = true,
    this.personNameAllowedSymbols = defaultPersonNameAllowedSymbols,
    this.phoneEquipmentCodeEnabled = true,
    this.swappedNamesEnabled = true,
    this.duplicateNamesEnabled = true,
    this.crossDepartmentPhoneEnabled = true,
    this.equipmentOwnerDepartmentEnabled = true,
    this.emptyDepartmentEnabled = true,
    this.lansweeperIdentifierEnabled = true,
  });

  /// Προεπιλεγμένες εξαιρέσεις: η ανοιχτή παρένθεση, γιατί το πεδίο «Όνομα»
  /// κρατά συχνά το πώς φωνάζουν τον άνθρωπο — «(Γωγώ) Γεωργία».
  static const String defaultPersonNameAllowedSymbols = '(';

  /// Έλεγχος πλήθους ψηφίων εσωτερικών τηλεφώνων.
  final bool internalPhoneDigitsEnabled;
  final int internalPhoneDigits;

  /// Έλεγχος πλήθους ψηφίων εξωτερικών τηλεφώνων.
  final bool externalPhoneDigitsEnabled;
  final int externalPhoneDigits;

  /// Έλεγχος προθέματος εσωτερικών. Εξετάζεται ΜΟΝΟ σε αριθμούς με
  /// [internalPhoneDigits] ψηφία — τα εξωτερικά δεν αφορούν το πρόθεμα.
  final bool internalPrefixEnabled;
  final int internalPrefixFrom;
  final int internalPrefixTo;

  /// Έλεγχος πλήθους ψηφίων κωδικού εξοπλισμού (εύρος από-έως).
  /// Εξετάζεται ΜΟΝΟ σε κωδικούς που είναι σκέτοι αριθμοί — σε «PC470» το
  /// πλήθος ψηφίων δεν σημαίνει τίποτα.
  final bool equipmentDigitsEnabled;
  final int equipmentMinDigits;
  final int equipmentMaxDigits;

  /// Κωδικός εξοπλισμού με λατινικά γράμματα (π.χ. «PC470»): **σπάνιο** αλλά
  /// θεμιτό. Η ένδειξη είναι διακριτική — αν το σχήμα είναι συνηθισμένο στη
  /// δική σας βάση, ο κανόνας σβήνει από εδώ.
  final bool equipmentLatinCodeEnabled;

  /// Κωδικός εξοπλισμού με ελληνικά γράμματα ή σύμβολα: **απίθανο**, σχεδόν
  /// πάντα ξεχασμένο ελληνικό πληκτρολόγιο («πισι2» αντί «pc2») ή σκουπίδι
  /// από βιαστική πληκτρολόγηση.
  final bool equipmentForeignCodeEnabled;

  /// Το όνομα τμήματος να μη μοιάζει με αριθμό/τηλέφωνο.
  final bool departmentNameEnabled;

  /// Όνομα/επώνυμο υπαλλήλου να μην ξεκινούν από ψηφίο ή σύμβολο.
  /// Παραμένει υπόδειξη: υπάρχουν καλούντες-εταιρείες (π.χ. «3π»).
  final bool personNameEnabled;

  /// Σύμβολα που επιτρέπονται στην αρχή ονόματος/επωνύμου, χωρισμένα με
  /// κόμμα (π.χ. `(, -`). Τα ψηφία ΔΕΝ εξαιρούνται ποτέ από εδώ.
  final String personNameAllowedSymbols;

  // ---- Διασταυρώσεις: κανόνες που κοιτούν ΣΧΕΣΕΙΣ μεταξύ εγγραφών.
  // Τρέχουν μόνο στη σάρωση «Έλεγχος δεδομένων» — στις φόρμες δεν υπάρχει
  // ολόκληρη η βάση διαθέσιμη τη στιγμή της πληκτρολόγησης.

  /// Τηλέφωνο που ταυτίζεται με καταχωρημένο κωδικό εξοπλισμού
  /// (το ιστορικό λάθος «3685 ως τηλέφωνο»).
  final bool phoneEquipmentCodeEnabled;

  /// Ζεύγη υπαλλήλων με αντεστραμμένα όνομα/επώνυμο
  /// (Δρόσος Βασίλης / Βασίλης Δρόσος).
  final bool swappedNamesEnabled;

  /// Υπάλληλοι με ολόιδιο ονοματεπώνυμο — πιθανά διπλότυπα.
  final bool duplicateNamesEnabled;

  /// Ίδιο τηλέφωνο σε υπαλλήλους ΔΙΑΦΟΡΕΤΙΚΩΝ τμημάτων. Στο ίδιο τμήμα
  /// είναι θεμιτό (κοινό τηλέφωνο βάρδιας) και δεν ελέγχεται.
  final bool crossDepartmentPhoneEnabled;

  /// Εξοπλισμός χρεωμένος σε υπάλληλο άλλου τμήματος από αυτό που ανήκει.
  final bool equipmentOwnerDepartmentEnabled;

  /// Τμήμα χωρίς κανέναν υπάλληλο, τηλέφωνο και εξοπλισμό. Δεν είναι σφάλμα —
  /// ένα τμήμα μπορεί να αδειάσει θεμιτά — αλλά συνήθως θέλει απόφαση.
  final bool emptyDepartmentEnabled;

  /// Μορφή αναγνωριστικών Lansweeper (υπάλληλοι + τμήματα): `τομέας\όνομα`
  /// ή email. Χωρίς σωστή μορφή το αίτημα δεν θα βρει ποτέ τον χρήστη —
  /// ο κριτής είναι ο ΙΔΙΟΣ που προειδοποιεί και στις φόρμες.
  final bool lansweeperIdentifierEnabled;

  static final RegExp _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);

  /// Οι εξαιρέσεις ως σύνολο χαρακτήρων.
  ///
  /// Από κάθε στοιχείο κρατιέται ο πρώτος χαρακτήρας, και μόνο εφόσον είναι
  /// γνήσιο σύμβολο — γράμματα και ψηφία απορρίπτονται σιωπηλά, ώστε ένα
  /// «3» στο πεδίο να μην ακυρώνει τον κανόνα.
  ///
  /// Το ίδιο το κόμμα δεν μπορεί να εξαιρεθεί: είναι ο διαχωριστής.
  Set<String> get personNameAllowedSymbolSet {
    final out = <String>{};
    for (final part in personNameAllowedSymbols.split(',')) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final ch = trimmed.characters.first;
      if (_letterOrDigit.hasMatch(ch)) continue;
      out.add(ch);
    }
    return out;
  }

  CatalogValidationRules copyWith({
    bool? internalPhoneDigitsEnabled,
    int? internalPhoneDigits,
    bool? externalPhoneDigitsEnabled,
    int? externalPhoneDigits,
    bool? internalPrefixEnabled,
    int? internalPrefixFrom,
    int? internalPrefixTo,
    bool? equipmentDigitsEnabled,
    int? equipmentMinDigits,
    int? equipmentMaxDigits,
    bool? equipmentLatinCodeEnabled,
    bool? equipmentForeignCodeEnabled,
    bool? departmentNameEnabled,
    bool? personNameEnabled,
    String? personNameAllowedSymbols,
    bool? phoneEquipmentCodeEnabled,
    bool? swappedNamesEnabled,
    bool? duplicateNamesEnabled,
    bool? crossDepartmentPhoneEnabled,
    bool? equipmentOwnerDepartmentEnabled,
    bool? emptyDepartmentEnabled,
    bool? lansweeperIdentifierEnabled,
  }) {
    return CatalogValidationRules(
      internalPhoneDigitsEnabled:
          internalPhoneDigitsEnabled ?? this.internalPhoneDigitsEnabled,
      internalPhoneDigits: internalPhoneDigits ?? this.internalPhoneDigits,
      externalPhoneDigitsEnabled:
          externalPhoneDigitsEnabled ?? this.externalPhoneDigitsEnabled,
      externalPhoneDigits: externalPhoneDigits ?? this.externalPhoneDigits,
      internalPrefixEnabled:
          internalPrefixEnabled ?? this.internalPrefixEnabled,
      internalPrefixFrom: internalPrefixFrom ?? this.internalPrefixFrom,
      internalPrefixTo: internalPrefixTo ?? this.internalPrefixTo,
      equipmentDigitsEnabled:
          equipmentDigitsEnabled ?? this.equipmentDigitsEnabled,
      equipmentMinDigits: equipmentMinDigits ?? this.equipmentMinDigits,
      equipmentMaxDigits: equipmentMaxDigits ?? this.equipmentMaxDigits,
      equipmentLatinCodeEnabled:
          equipmentLatinCodeEnabled ?? this.equipmentLatinCodeEnabled,
      equipmentForeignCodeEnabled:
          equipmentForeignCodeEnabled ?? this.equipmentForeignCodeEnabled,
      departmentNameEnabled:
          departmentNameEnabled ?? this.departmentNameEnabled,
      personNameEnabled: personNameEnabled ?? this.personNameEnabled,
      personNameAllowedSymbols:
          personNameAllowedSymbols ?? this.personNameAllowedSymbols,
      phoneEquipmentCodeEnabled:
          phoneEquipmentCodeEnabled ?? this.phoneEquipmentCodeEnabled,
      swappedNamesEnabled: swappedNamesEnabled ?? this.swappedNamesEnabled,
      duplicateNamesEnabled:
          duplicateNamesEnabled ?? this.duplicateNamesEnabled,
      crossDepartmentPhoneEnabled:
          crossDepartmentPhoneEnabled ?? this.crossDepartmentPhoneEnabled,
      equipmentOwnerDepartmentEnabled:
          equipmentOwnerDepartmentEnabled ??
          this.equipmentOwnerDepartmentEnabled,
      emptyDepartmentEnabled:
          emptyDepartmentEnabled ?? this.emptyDepartmentEnabled,
      lansweeperIdentifierEnabled:
          lansweeperIdentifierEnabled ?? this.lansweeperIdentifierEnabled,
    );
  }

  Map<String, Object?> toJson() => {
    'internal_phone_digits_enabled': internalPhoneDigitsEnabled,
    'internal_phone_digits': internalPhoneDigits,
    'external_phone_digits_enabled': externalPhoneDigitsEnabled,
    'external_phone_digits': externalPhoneDigits,
    'internal_prefix_enabled': internalPrefixEnabled,
    'internal_prefix_from': internalPrefixFrom,
    'internal_prefix_to': internalPrefixTo,
    'equipment_digits_enabled': equipmentDigitsEnabled,
    'equipment_min_digits': equipmentMinDigits,
    'equipment_max_digits': equipmentMaxDigits,
    'equipment_latin_code_enabled': equipmentLatinCodeEnabled,
    'equipment_foreign_code_enabled': equipmentForeignCodeEnabled,
    'department_name_enabled': departmentNameEnabled,
    'person_name_enabled': personNameEnabled,
    'person_name_allowed_symbols': personNameAllowedSymbols,
    'phone_equipment_code_enabled': phoneEquipmentCodeEnabled,
    'swapped_names_enabled': swappedNamesEnabled,
    'duplicate_names_enabled': duplicateNamesEnabled,
    'cross_department_phone_enabled': crossDepartmentPhoneEnabled,
    'equipment_owner_department_enabled': equipmentOwnerDepartmentEnabled,
    'empty_department_enabled': emptyDepartmentEnabled,
    'lansweeper_identifier_enabled': lansweeperIdentifierEnabled,
  };

  String toRawJson() => jsonEncode(toJson());

  static bool _boolOf(Map<String, Object?> map, String key, bool fallback) {
    final v = map[key];
    return v is bool ? v : fallback;
  }

  static int _intOf(Map<String, Object?> map, String key, int fallback) {
    final v = map[key];
    return v is int && v > 0 ? v : fallback;
  }

  /// Το κενό string είναι έγκυρη τιμή («καμία εξαίρεση») — μόνο ο λάθος
  /// τύπος πέφτει στην προεπιλογή.
  static String _stringOf(
    Map<String, Object?> map,
    String key,
    String fallback,
  ) {
    final v = map[key];
    return v is String ? v : fallback;
  }

  factory CatalogValidationRules.fromJson(Map<String, Object?> map) {
    const d = CatalogValidationRules();
    return CatalogValidationRules(
      internalPhoneDigitsEnabled: _boolOf(
        map,
        'internal_phone_digits_enabled',
        d.internalPhoneDigitsEnabled,
      ),
      internalPhoneDigits: _intOf(
        map,
        'internal_phone_digits',
        d.internalPhoneDigits,
      ),
      externalPhoneDigitsEnabled: _boolOf(
        map,
        'external_phone_digits_enabled',
        d.externalPhoneDigitsEnabled,
      ),
      externalPhoneDigits: _intOf(
        map,
        'external_phone_digits',
        d.externalPhoneDigits,
      ),
      internalPrefixEnabled: _boolOf(
        map,
        'internal_prefix_enabled',
        d.internalPrefixEnabled,
      ),
      internalPrefixFrom: _intOf(
        map,
        'internal_prefix_from',
        d.internalPrefixFrom,
      ),
      internalPrefixTo: _intOf(map, 'internal_prefix_to', d.internalPrefixTo),
      equipmentDigitsEnabled: _boolOf(
        map,
        'equipment_digits_enabled',
        d.equipmentDigitsEnabled,
      ),
      equipmentLatinCodeEnabled: _boolOf(
        map,
        'equipment_latin_code_enabled',
        d.equipmentLatinCodeEnabled,
      ),
      equipmentForeignCodeEnabled: _boolOf(
        map,
        'equipment_foreign_code_enabled',
        d.equipmentForeignCodeEnabled,
      ),
      equipmentMinDigits: _intOf(
        map,
        'equipment_min_digits',
        d.equipmentMinDigits,
      ),
      equipmentMaxDigits: _intOf(
        map,
        'equipment_max_digits',
        d.equipmentMaxDigits,
      ),
      departmentNameEnabled: _boolOf(
        map,
        'department_name_enabled',
        d.departmentNameEnabled,
      ),
      personNameEnabled: _boolOf(
        map,
        'person_name_enabled',
        d.personNameEnabled,
      ),
      personNameAllowedSymbols: _stringOf(
        map,
        'person_name_allowed_symbols',
        d.personNameAllowedSymbols,
      ),
      phoneEquipmentCodeEnabled: _boolOf(
        map,
        'phone_equipment_code_enabled',
        d.phoneEquipmentCodeEnabled,
      ),
      swappedNamesEnabled: _boolOf(
        map,
        'swapped_names_enabled',
        d.swappedNamesEnabled,
      ),
      duplicateNamesEnabled: _boolOf(
        map,
        'duplicate_names_enabled',
        d.duplicateNamesEnabled,
      ),
      crossDepartmentPhoneEnabled: _boolOf(
        map,
        'cross_department_phone_enabled',
        d.crossDepartmentPhoneEnabled,
      ),
      equipmentOwnerDepartmentEnabled: _boolOf(
        map,
        'equipment_owner_department_enabled',
        d.equipmentOwnerDepartmentEnabled,
      ),
      emptyDepartmentEnabled: _boolOf(
        map,
        'empty_department_enabled',
        d.emptyDepartmentEnabled,
      ),
      lansweeperIdentifierEnabled: _boolOf(
        map,
        'lansweeper_identifier_enabled',
        d.lansweeperIdentifierEnabled,
      ),
    );
  }

  /// Αποκωδικοποίηση από το app_settings. Κενό/άκυρο JSON → προεπιλογές,
  /// ώστε η λειτουργία να δουλεύει αμέσως χωρίς καμία ρύθμιση.
  factory CatalogValidationRules.fromRawJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const CatalogValidationRules();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        return CatalogValidationRules.fromJson(decoded);
      }
      return const CatalogValidationRules();
    } on FormatException {
      return const CatalogValidationRules();
    }
  }
}
