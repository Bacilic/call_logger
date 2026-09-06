import 'dart:convert';

import 'package:characters/characters.dart';

/// Πόσο σοβαρό είναι αυτό που πιάνει ένας κανόνας.
///
/// Δηλώνεται **μία φορά ανά κανόνα** και από αυτήν προκύπτουν τα επίπεδα
/// αυστηρότητας. Έτσι ένας νέος κανόνας μπαίνει μόνος του στο σωστό επίπεδο:
/// δεν υπάρχουν τρεις χειρόγραφες λίστες να ξεχαστεί να ενημερωθούν.
enum CatalogRuleSeverity {
  /// Σχεδόν πάντα λάθος που βλάπτει: ξεχασμένο ελληνικό πληκτρολόγιο σε
  /// κωδικό, σύνδεση που δείχνει σε ξένο υπολογιστή, δικό μας μηχάνημα
  /// χρεωμένο σε εταιρεία.
  error,

  /// Πιθανό λάθος που θέλει ματιά: λάθος πλήθος ψηφίων, ίδιο τηλέφωνο σε δύο
  /// τμήματα, όνομα που ξεκινά από ψηφίο.
  inconsistency,

  /// Κατάσταση, όχι λάθος: τμήμα που άδειασε, τμήμα χωρίς κτίριο, κωδικός με
  /// λατινικά γράμματα. Θυμίζει να αποφασίσετε, δεν κατηγορεί.
  reminder,
}

/// Έτοιμο πακέτο κανόνων — αφετηρία, όχι κλειδαριά.
///
/// Μετά την επιλογή ο χρήστης αλλάζει ό,τι θέλει· τότε κανένα επίπεδο δεν
/// ταιριάζει και η οθόνη δείχνει «Προσαρμοσμένο». Το επίπεδο **δεν
/// αποθηκεύεται πουθενά**: υπολογίζεται από τους ίδιους τους διακόπτες, ώστε
/// να μην μπορεί ποτέ να πει «Μεσαίο» ενώ οι διακόπτες λένε κάτι άλλο.
enum CatalogStrictnessLevel {
  all('Όλοι οι έλεγχοι', 'Κάθε κανόνας ενεργός, μαζί με τις υπενθυμίσεις'),
  medium('Μεσαίο', 'Σφάλματα και ασυνέπειες — έξω οι υπενθυμίσεις'),
  minimal('Ελάχιστοι έλεγχοι', 'Μόνο ό,τι είναι σχεδόν πάντα λάθος');

  const CatalogStrictnessLevel(this.label, this.description);

  /// Πώς λέγεται το επίπεδο στο κουμπί.
  final String label;

  /// Μία γραμμή που εξηγεί τι ανάβει, κάτω από τα κουμπιά.
  final String description;

  /// Ανάβει αυτό το επίπεδο τους κανόνες της συγκεκριμένης βαρύτητας;
  bool includes(CatalogRuleSeverity severity) => switch (this) {
    CatalogStrictnessLevel.all => true,
    CatalogStrictnessLevel.medium => severity != CatalogRuleSeverity.reminder,
    CatalogStrictnessLevel.minimal => severity == CatalogRuleSeverity.error,
  };
}

/// Ένας διακόπτης κανόνα: πόσο σοβαρός είναι, πώς διαβάζεται και πώς αλλάζει.
///
/// Η λίστα [CatalogValidationRules.ruleSwitches] είναι η **μοναδική απογραφή**
/// των διακοπτών — ένας νέος κανόνας θέλει μία γραμμή εκεί, και τα επίπεδα
/// αυστηρότητας τον μαθαίνουν αυτόματα.
typedef CatalogRuleSwitch = ({
  CatalogRuleSeverity severity,
  bool Function(CatalogValidationRules rules) isOn,
  CatalogValidationRules Function(CatalogValidationRules rules, bool value)
  toggled,
});

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
    this.departmentBuildingEnabled = true,
    this.lansweeperIdentifierEnabled = true,
    this.equipmentInCompanyEnabled = true,
    this.equipmentWithoutDepartmentEnabled = true,
    this.companyInternalPhoneEnabled = true,
    this.duplicateRemoteTargetEnabled = true,
    this.nicknameInNameEnabled = true,
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

  /// Τμήμα χωρίς κτίριο. Από τότε που το κτίριο διαλέγεται από κοινό
  /// κατάλογο, το κενό δεν προκύπτει από πληκτρολόγηση αλλά από απόφαση —
  /// διαγραφή κτιρίου από τη λίστα, ή μεταφορά από τη Λάμπα που το άφησε για
  /// αργότερα. Εδώ μαζεύονται όσα περιμένουν ακόμη τη διόρθωσή τους.
  final bool departmentBuildingEnabled;

  /// Μορφή αναγνωριστικών Lansweeper (υπάλληλοι + τμήματα): `τομέας\όνομα`
  /// ή email. Χωρίς σωστή μορφή το αίτημα δεν θα βρει ποτέ τον χρήστη —
  /// ο κριτής είναι ο ΙΔΙΟΣ που προειδοποιεί και στις φόρμες.
  final bool lansweeperIdentifierEnabled;

  /// Εξοπλισμός χρεωμένος σε **εταιρεία** — είτε το τμήμα του είναι εταιρεία,
  /// είτε ο κάτοχός του ανήκει σε εταιρεία.
  ///
  /// Η εξωτερική μονάδα (Κέντρο Υγείας) δεν ελέγχεται: εκεί τα μηχανήματα
  /// είναι δικά μας. Η εταιρεία δεν κρατά ποτέ δικό μας εξοπλισμό.
  final bool equipmentInCompanyEnabled;

  /// Εξοπλισμός χωρίς τμήμα. Ο κανόνας του πεδίου λέει «ποτέ ορφανός», όμως
  /// μια διαγραμμένη καρτέλα τμήματος αφήνει τον εξοπλισμό ακέφαλο.
  final bool equipmentWithoutDepartmentEnabled;

  /// Τηλέφωνο εσωτερικής μορφής σε **εταιρεία**: τετραψήφιο με πρόθεμα του
  /// τηλεφωνικού μας κέντρου μέσα στην DataMed σημαίνει σχεδόν πάντα λάθος
  /// Είδος ή λάθος αριθμό. Ζει ΜΟΝΟ στη φόρμα — στη σάρωση δεν μπαίνει.
  final bool companyInternalPhoneEnabled;

  /// Ίδιος στόχος απομακρυσμένης σύνδεσης σε δύο μηχανήματα: το ίδιο
  /// αναγνωριστικό AnyDesk ή η ίδια διεύθυνση VNC σε δύο κωδικούς σημαίνει
  /// μπαγιάτικη εγγραφή μετά από αντικατάσταση — και σύνδεση σε ξένο
  /// υπολογιστή. Η απομακρυσμένη επιφάνεια των Windows εξαιρείται: εκεί η
  /// κοινή τιμή είναι θεμιτή.
  final bool duplicateRemoteTargetEnabled;

  /// Όνομα υπαλλήλου που κουβαλά ψευδώνυμο σε παρένθεση — «(Γωγώ) Γεωργία».
  ///
  /// Ήταν ο μόνος τρόπος όσο δεν υπήρχε πεδίο ψευδωνύμου, και κρύβει σιωπηλά
  /// διπλότυπα: ο έλεγχος συγκρίνει το όνομα ολόκληρο, οπότε η «Γεωργία» και η
  /// «(Γωγώ) Γεωργία» του ίδιου επωνύμου περνούν για δύο ανθρώπους.
  final bool nicknameInNameEnabled;

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

  // ---- Επίπεδα αυστηρότητας.

  /// Η απογραφή ΟΛΩΝ των διακοπτών, με τη βαρύτητα του καθενός.
  ///
  /// Νέος κανόνας ⇒ **μία γραμμή εδώ**. Αν ξεχαστεί, το σχετικό τεστ σκάει:
  /// μετρά πόσοι διακόπτες μένουν αναμμένοι μετά από «Ελάχιστοι έλεγχοι» και
  /// πόσοι ανάβουν με «Όλοι οι έλεγχοι», διαβάζοντας το [toJson].
  static final List<CatalogRuleSwitch> ruleSwitches = [
    // --- Σχεδόν πάντα λάθος.
    (
      severity: CatalogRuleSeverity.error,
      isOn: (r) => r.equipmentForeignCodeEnabled,
      toggled: (r, v) => r.copyWith(equipmentForeignCodeEnabled: v),
    ),
    (
      severity: CatalogRuleSeverity.error,
      isOn: (r) => r.phoneEquipmentCodeEnabled,
      toggled: (r, v) => r.copyWith(phoneEquipmentCodeEnabled: v),
    ),
    (
      severity: CatalogRuleSeverity.error,
      isOn: (r) => r.duplicateRemoteTargetEnabled,
      toggled: (r, v) => r.copyWith(duplicateRemoteTargetEnabled: v),
    ),
    (
      severity: CatalogRuleSeverity.error,
      isOn: (r) => r.equipmentInCompanyEnabled,
      toggled: (r, v) => r.copyWith(equipmentInCompanyEnabled: v),
    ),
    (
      severity: CatalogRuleSeverity.error,
      isOn: (r) => r.duplicateNamesEnabled,
      toggled: (r, v) => r.copyWith(duplicateNamesEnabled: v),
    ),
    (
      severity: CatalogRuleSeverity.error,
      isOn: (r) => r.equipmentWithoutDepartmentEnabled,
      toggled: (r, v) => r.copyWith(equipmentWithoutDepartmentEnabled: v),
    ),

    // --- Πιθανό λάθος που θέλει ματιά.
    (
      severity: CatalogRuleSeverity.inconsistency,
      isOn: (r) => r.internalPhoneDigitsEnabled,
      toggled: (r, v) => r.copyWith(internalPhoneDigitsEnabled: v),
    ),
    (
      severity: CatalogRuleSeverity.inconsistency,
      isOn: (r) => r.externalPhoneDigitsEnabled,
      toggled: (r, v) => r.copyWith(externalPhoneDigitsEnabled: v),
    ),
    (
      severity: CatalogRuleSeverity.inconsistency,
      isOn: (r) => r.internalPrefixEnabled,
      toggled: (r, v) => r.copyWith(internalPrefixEnabled: v),
    ),
    (
      severity: CatalogRuleSeverity.inconsistency,
      isOn: (r) => r.companyInternalPhoneEnabled,
      toggled: (r, v) => r.copyWith(companyInternalPhoneEnabled: v),
    ),
    (
      severity: CatalogRuleSeverity.inconsistency,
      isOn: (r) => r.equipmentDigitsEnabled,
      toggled: (r, v) => r.copyWith(equipmentDigitsEnabled: v),
    ),
    (
      severity: CatalogRuleSeverity.inconsistency,
      isOn: (r) => r.departmentNameEnabled,
      toggled: (r, v) => r.copyWith(departmentNameEnabled: v),
    ),
    (
      severity: CatalogRuleSeverity.inconsistency,
      isOn: (r) => r.personNameEnabled,
      toggled: (r, v) => r.copyWith(personNameEnabled: v),
    ),
    (
      severity: CatalogRuleSeverity.inconsistency,
      isOn: (r) => r.lansweeperIdentifierEnabled,
      toggled: (r, v) => r.copyWith(lansweeperIdentifierEnabled: v),
    ),
    (
      severity: CatalogRuleSeverity.inconsistency,
      isOn: (r) => r.swappedNamesEnabled,
      toggled: (r, v) => r.copyWith(swappedNamesEnabled: v),
    ),
    (
      severity: CatalogRuleSeverity.inconsistency,
      isOn: (r) => r.crossDepartmentPhoneEnabled,
      toggled: (r, v) => r.copyWith(crossDepartmentPhoneEnabled: v),
    ),
    (
      severity: CatalogRuleSeverity.inconsistency,
      isOn: (r) => r.equipmentOwnerDepartmentEnabled,
      toggled: (r, v) => r.copyWith(equipmentOwnerDepartmentEnabled: v),
    ),
    (
      severity: CatalogRuleSeverity.inconsistency,
      isOn: (r) => r.nicknameInNameEnabled,
      toggled: (r, v) => r.copyWith(nicknameInNameEnabled: v),
    ),

    // --- Κατάσταση, όχι λάθος.
    (
      severity: CatalogRuleSeverity.reminder,
      isOn: (r) => r.emptyDepartmentEnabled,
      toggled: (r, v) => r.copyWith(emptyDepartmentEnabled: v),
    ),
    (
      severity: CatalogRuleSeverity.reminder,
      isOn: (r) => r.departmentBuildingEnabled,
      toggled: (r, v) => r.copyWith(departmentBuildingEnabled: v),
    ),
    (
      severity: CatalogRuleSeverity.reminder,
      isOn: (r) => r.equipmentLatinCodeEnabled,
      toggled: (r, v) => r.copyWith(equipmentLatinCodeEnabled: v),
    ),
  ];

  /// Οι ίδιοι κανόνες με τους διακόπτες ρυθμισμένους στο πακέτο του [level].
  ///
  /// Οι **αριθμητικές τιμές δεν πειράζονται**: τα ψηφία, το πρόθεμα και τα
  /// εξαιρούμενα σύμβολα είναι ρυθμίσεις του χρήστη για το πώς μοιάζουν τα
  /// δικά του δεδομένα — το επίπεδο απαντά μόνο στο «τι ελέγχεται».
  CatalogValidationRules withStrictness(CatalogStrictnessLevel level) {
    var out = this;
    for (final rule in ruleSwitches) {
      out = rule.toggled(out, level.includes(rule.severity));
    }
    return out;
  }

  /// Το επίπεδο στο οποίο αντιστοιχούν οι τρέχοντες διακόπτες, ή `null` όταν
  /// δεν ταιριάζει κανένα — τότε η οθόνη λέει «Προσαρμοσμένο».
  ///
  /// Υπολογίζεται από τους διακόπτες αντί να αποθηκεύεται, ώστε να μην μπορεί
  /// ποτέ να αποκλίνει από αυτό που πραγματικά ισχύει.
  CatalogStrictnessLevel? get strictnessLevel {
    for (final level in CatalogStrictnessLevel.values) {
      final matches = ruleSwitches.every(
        (rule) => rule.isOn(this) == level.includes(rule.severity),
      );
      if (matches) return level;
    }
    return null;
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
    bool? departmentBuildingEnabled,
    bool? lansweeperIdentifierEnabled,
    bool? equipmentInCompanyEnabled,
    bool? equipmentWithoutDepartmentEnabled,
    bool? companyInternalPhoneEnabled,
    bool? duplicateRemoteTargetEnabled,
    bool? nicknameInNameEnabled,
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
      departmentBuildingEnabled:
          departmentBuildingEnabled ?? this.departmentBuildingEnabled,
      lansweeperIdentifierEnabled:
          lansweeperIdentifierEnabled ?? this.lansweeperIdentifierEnabled,
      equipmentInCompanyEnabled:
          equipmentInCompanyEnabled ?? this.equipmentInCompanyEnabled,
      equipmentWithoutDepartmentEnabled:
          equipmentWithoutDepartmentEnabled ??
          this.equipmentWithoutDepartmentEnabled,
      companyInternalPhoneEnabled:
          companyInternalPhoneEnabled ?? this.companyInternalPhoneEnabled,
      duplicateRemoteTargetEnabled:
          duplicateRemoteTargetEnabled ?? this.duplicateRemoteTargetEnabled,
      nicknameInNameEnabled:
          nicknameInNameEnabled ?? this.nicknameInNameEnabled,
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
    'department_building_enabled': departmentBuildingEnabled,
    'lansweeper_identifier_enabled': lansweeperIdentifierEnabled,
    'equipment_in_company_enabled': equipmentInCompanyEnabled,
    'equipment_without_department_enabled': equipmentWithoutDepartmentEnabled,
    'company_internal_phone_enabled': companyInternalPhoneEnabled,
    'duplicate_remote_target_enabled': duplicateRemoteTargetEnabled,
    'nickname_in_name_enabled': nicknameInNameEnabled,
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
      departmentBuildingEnabled: _boolOf(
        map,
        'department_building_enabled',
        d.departmentBuildingEnabled,
      ),
      lansweeperIdentifierEnabled: _boolOf(
        map,
        'lansweeper_identifier_enabled',
        d.lansweeperIdentifierEnabled,
      ),
      equipmentInCompanyEnabled: _boolOf(
        map,
        'equipment_in_company_enabled',
        d.equipmentInCompanyEnabled,
      ),
      equipmentWithoutDepartmentEnabled: _boolOf(
        map,
        'equipment_without_department_enabled',
        d.equipmentWithoutDepartmentEnabled,
      ),
      companyInternalPhoneEnabled: _boolOf(
        map,
        'company_internal_phone_enabled',
        d.companyInternalPhoneEnabled,
      ),
      duplicateRemoteTargetEnabled: _boolOf(
        map,
        'duplicate_remote_target_enabled',
        d.duplicateRemoteTargetEnabled,
      ),
      nicknameInNameEnabled: _boolOf(
        map,
        'nickname_in_name_enabled',
        d.nicknameInNameEnabled,
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
