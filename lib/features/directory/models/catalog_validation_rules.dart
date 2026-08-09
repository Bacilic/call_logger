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
    this.departmentNameEnabled = true,
    this.personNameEnabled = true,
    this.personNameAllowedSymbols = defaultPersonNameAllowedSymbols,
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
  final bool equipmentDigitsEnabled;
  final int equipmentMinDigits;
  final int equipmentMaxDigits;

  /// Το όνομα τμήματος να μη μοιάζει με αριθμό/τηλέφωνο.
  final bool departmentNameEnabled;

  /// Όνομα/επώνυμο υπαλλήλου να μην ξεκινούν από ψηφίο ή σύμβολο.
  /// Παραμένει υπόδειξη: υπάρχουν καλούντες-εταιρείες (π.χ. «3π»).
  final bool personNameEnabled;

  /// Σύμβολα που επιτρέπονται στην αρχή ονόματος/επωνύμου, χωρισμένα με
  /// κόμμα (π.χ. `(, -`). Τα ψηφία ΔΕΝ εξαιρούνται ποτέ από εδώ.
  final String personNameAllowedSymbols;

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
    bool? departmentNameEnabled,
    bool? personNameEnabled,
    String? personNameAllowedSymbols,
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
      departmentNameEnabled:
          departmentNameEnabled ?? this.departmentNameEnabled,
      personNameEnabled: personNameEnabled ?? this.personNameEnabled,
      personNameAllowedSymbols:
          personNameAllowedSymbols ?? this.personNameAllowedSymbols,
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
    'department_name_enabled': departmentNameEnabled,
    'person_name_enabled': personNameEnabled,
    'person_name_allowed_symbols': personNameAllowedSymbols,
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
