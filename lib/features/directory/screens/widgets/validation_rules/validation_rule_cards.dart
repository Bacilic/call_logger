/// Οι κάρτες με τους διακόπτες των κανόνων επικύρωσης.
///
/// Καθαρή δήλωση: ποιοι κανόνες υπάρχουν, πώς λέγονται, τι παράδειγμα
/// δείχνουν και ποιο πεδίο των [CatalogValidationRules] αγγίζει ο καθένας.
/// Η αποθήκευση δεν γίνεται εδώ — φεύγει προς τα πάνω μέσω της [onApply],
/// ώστε η προσθήκη ενός κανόνα να μην απαιτεί γνώση του πώς γράφονται οι
/// ρυθμίσεις στη βάση.
library;

import 'package:flutter/material.dart';

import '../../../models/catalog_validation_rules.dart';
import 'validation_rule_field_controllers.dart';
import 'validation_rule_widgets.dart';

/// Πώς περιγράφεται μια αλλαγή κανόνα: τι άγγιξε ο χρήστης, πάνω σε ό,τι
/// είναι αποθηκευμένο εκείνη τη στιγμή.
typedef ValidationRuleChange =
    CatalogValidationRules Function(CatalogValidationRules current);

/// Τα όρια των ρυθμιζόμενων αριθμών.
///
/// Ζουν εδώ, δίπλα στη δήλωση του κανόνα που τα χρησιμοποιεί: τα πεδία τα
/// ανακοινώνουν στον χρήστη και τα επιβάλλουν στην αποθήκευση.
const int _minDigits = 1;
const int _maxDigits = 15;
const int _minPrefix = 10;
const int _maxPrefix = 99;

/// Όλες οι κάρτες κανόνων, στη σειρά που τις βλέπει ο χρήστης.
class ValidationRuleCards extends StatelessWidget {
  const ValidationRuleCards({
    super.key,
    required this.rules,
    required this.fields,
    required this.onApply,
  });

  final CatalogValidationRules rules;
  final ValidationRuleFieldControllers fields;
  final void Function(ValidationRuleChange change) onApply;

  /// Ο διακόπτης ενός κανόνα, σε μία γραμμή.
  void _toggle(ValidationRuleChange change) => onApply(change);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _phoneCard(),
        const SizedBox(height: 12),
        _equipmentCard(),
        const SizedBox(height: 12),
        _departmentCard(),
        const SizedBox(height: 12),
        _userCard(),
        const SizedBox(height: 12),
        _lansweeperCard(),
        const SizedBox(height: 12),
        _crossChecksCard(),
      ],
    );
  }

  // ---- Τηλέφωνα.

  Widget _phoneCard() {
    return RuleCard(
      icon: Icons.phone_outlined,
      title: 'Τηλέφωνα',
      children: [
        RuleRow(
          enabled: rules.internalPhoneDigitsEnabled,
          onToggle: (v) =>
              _toggle((c) => c.copyWith(internalPhoneDigitsEnabled: v)),
          example:
              'Παράδειγμα υπόδειξης: «Το 253 έχει 3 ψηφία — '
              'τα εσωτερικά έχουν ${rules.internalPhoneDigits}»',
          child: InlineNumberField(
            label: 'Ψηφία εσωτερικών τηλεφώνων:',
            controller: fields.internalDigits.controller,
            focusNode: fields.internalDigits.focusNode,
            maxLength: 2,
            min: _minDigits,
            max: _maxDigits,
            currentValue: rules.internalPhoneDigits,
            onCommitted: (v) =>
                onApply((c) => c.copyWith(internalPhoneDigits: v)),
          ),
        ),
        RuleRow(
          enabled: rules.externalPhoneDigitsEnabled,
          onToggle: (v) =>
              _toggle((c) => c.copyWith(externalPhoneDigitsEnabled: v)),
          example:
              'Παράδειγμα υπόδειξης: «Το 210123456 έχει 9 ψηφία — '
              'αναμένονται ${rules.internalPhoneDigits} (εσωτερικό) '
              'ή ${rules.externalPhoneDigits} (εξωτερικό)»',
          child: InlineNumberField(
            label: 'Ψηφία εξωτερικών τηλεφώνων:',
            controller: fields.externalDigits.controller,
            focusNode: fields.externalDigits.focusNode,
            maxLength: 2,
            min: _minDigits,
            max: _maxDigits,
            currentValue: rules.externalPhoneDigits,
            onCommitted: (v) =>
                onApply((c) => c.copyWith(externalPhoneDigits: v)),
          ),
        ),
        RuleRow(
          enabled: rules.internalPrefixEnabled,
          onToggle: (v) => _toggle((c) => c.copyWith(internalPrefixEnabled: v)),
          note:
              'Ελέγχεται μόνο σε αριθμούς με '
              '${rules.internalPhoneDigits} ψηφία — τα εξωτερικά '
              'δεν εξετάζονται',
          example:
              'Παράδειγμα υπόδειξης: «Το 3122 δεν ξεκινά από '
              '${rules.internalPrefixFrom}–${rules.internalPrefixTo}»',
          child: InlineRangeFields(
            label: 'Πρόθεμα εσωτερικών: από',
            fromController: fields.prefixFrom.controller,
            toController: fields.prefixTo.controller,
            fromFocusNode: fields.prefixFrom.focusNode,
            toFocusNode: fields.prefixTo.focusNode,
            min: _minPrefix,
            max: _maxPrefix,
            currentFrom: rules.internalPrefixFrom,
            currentTo: rules.internalPrefixTo,
            onCommitted: (from, to) => onApply(
              (c) =>
                  c.copyWith(internalPrefixFrom: from, internalPrefixTo: to),
            ),
          ),
        ),
        RuleRow(
          enabled: rules.companyInternalPhoneEnabled,
          onToggle: (v) =>
              _toggle((c) => c.copyWith(companyInternalPhoneEnabled: v)),
          note:
              'Μόνο στη φόρμα, και μόνο όταν το Είδος είναι '
              '«Εταιρεία» — στον «Έλεγχο δεδομένων» δεν εμφανίζεται',
          example:
              'Παράδειγμα υπόδειξης: «Το 2534 έχει μορφή δικού μας '
              'εσωτερικού — οι εταιρείες δεν έχουν εσωτερικά του '
              'νοσοκομείου»',
          child: const RuleLabel('Εταιρεία με τηλέφωνο σε μορφή εσωτερικού'),
        ),
      ],
    );
  }

  // ---- Εξοπλισμός.

  Widget _equipmentCard() {
    return RuleCard(
      icon: Icons.computer_outlined,
      title: 'Εξοπλισμός',
      children: [
        RuleRow(
          enabled: rules.equipmentDigitsEnabled,
          onToggle: (v) => _toggle((c) => c.copyWith(equipmentDigitsEnabled: v)),
          example:
              'Παράδειγμα υπόδειξης: «Το 25067 έχει 5 ψηφία — '
              'αναμένονται ${rules.equipmentMinDigits} έως '
              '${rules.equipmentMaxDigits}»',
          child: InlineRangeFields(
            label: 'Ψηφία κωδικού: από',
            fromController: fields.equipmentMin.controller,
            toController: fields.equipmentMax.controller,
            fromFocusNode: fields.equipmentMin.focusNode,
            toFocusNode: fields.equipmentMax.focusNode,
            min: _minDigits,
            max: _maxDigits,
            currentFrom: rules.equipmentMinDigits,
            currentTo: rules.equipmentMaxDigits,
            onCommitted: (min, max) => onApply(
              (c) =>
                  c.copyWith(equipmentMinDigits: min, equipmentMaxDigits: max),
            ),
          ),
        ),
        RuleRow(
          enabled: rules.equipmentLatinCodeEnabled,
          onToggle: (v) =>
              _toggle((c) => c.copyWith(equipmentLatinCodeEnabled: v)),
          example:
              'Παράδειγμα υπόδειξης: «Το «PC470» έχει γράμματα — '
              'σπάνιο σχήμα κωδικού, οι περισσότεροι είναι σκέτοι '
              'αριθμοί»',
          child: const RuleLabel(
            'Διακριτική ένδειξη σε κωδικούς με λατινικά γράμματα',
          ),
        ),
        RuleRow(
          enabled: rules.duplicateRemoteTargetEnabled,
          onToggle: (v) =>
              _toggle((c) => c.copyWith(duplicateRemoteTargetEnabled: v)),
          note:
              'Η απομακρυσμένη επιφάνεια των Windows εξαιρείται — '
              'εκεί η κοινή τιμή είναι θεμιτή. Ελέγχεται και στη '
              'φόρμα και στον «Έλεγχο δεδομένων».',
          example:
              'Παράδειγμα υπόδειξης: «Το «AnyDesk» δείχνει την ίδια '
              'τιμή «123456789» σε 2 μηχανήματα»',
          child: const RuleLabel('Ίδιος στόχος απομακρυσμένης σε δύο μηχανήματα'),
        ),
        RuleRow(
          enabled: rules.equipmentForeignCodeEnabled,
          onToggle: (v) =>
              _toggle((c) => c.copyWith(equipmentForeignCodeEnabled: v)),
          example:
              'Παράδειγμα υπόδειξης: «Το «πισι2» έχει χαρακτήρες '
              'εκτός λατινικών: π ι σ — μάλλον ξεχασμένο ελληνικό '
              'πληκτρολόγιο»',
          child: const RuleLabel(
            'Έντονη ένδειξη σε κωδικούς με ελληνικά ή σύμβολα',
          ),
        ),
      ],
    );
  }

  // ---- Τμήματα.

  Widget _departmentCard() {
    return RuleCard(
      icon: Icons.apartment_outlined,
      title: 'Τμήματα',
      children: [
        RuleRow(
          enabled: rules.departmentNameEnabled,
          onToggle: (v) => _toggle((c) => c.copyWith(departmentNameEnabled: v)),
          example:
              'Παράδειγμα υπόδειξης: «Το 2545 μοιάζει με τηλέφωνο, '
              'όχι με όνομα τμήματος»',
          child: const RuleLabel(
            'Το όνομα να μη μοιάζει με αριθμό ή τηλέφωνο',
          ),
        ),
      ],
    );
  }

  // ---- Υπάλληλοι.

  Widget _userCard() {
    return RuleCard(
      icon: Icons.person_outline,
      title: 'Υπάλληλοι',
      children: [
        RuleRow(
          enabled: rules.nicknameInNameEnabled,
          onToggle: (v) => _toggle((c) => c.copyWith(nicknameInNameEnabled: v)),
          note:
              'Ελέγχεται μόνο όσο το πεδίο «Ψευδώνυμο» είναι κενό· '
              'το εύρημα ανοίγει την καρτέλα με τα δύο κομμάτια ήδη '
              'χωρισμένα, για να τα δείτε πριν αποθηκεύσετε',
          example:
              'Παράδειγμα υπόδειξης: «Το «Γωγώ» μοιάζει με '
              'ψευδώνυμο μέσα στο όνομα — με δικό του πεδίο, το '
              'όνομα μένει «Γεωργία»»',
          child: const RuleLabel('Ψευδώνυμο σε παρένθεση μέσα στο όνομα'),
        ),
        RuleRow(
          enabled: rules.personNameEnabled,
          onToggle: (v) => _toggle((c) => c.copyWith(personNameEnabled: v)),
          example:
              'Παράδειγμα υπόδειξης: «Ξεκινά από ψηφίο ή σύμβολο '
              '— οι εταιρείες καταχωρούνται στα Τμήματα, με Είδος '
              '«Εταιρεία»»',
          child: _PersonNameRuleContent(
            field: fields.allowedSymbols,
            onSymbolsChanged: (text) =>
                onApply((c) => c.copyWith(personNameAllowedSymbols: text)),
          ),
        ),
        RuleRow(
          enabled: rules.userWithoutDepartmentEnabled,
          onToggle: (v) =>
              _toggle((c) => c.copyWith(userWithoutDepartmentEnabled: v)),
          note:
              'Πριν υπάρξει το Είδος, οι εταιρείες καταχωρούνταν '
              'ως υπάλληλοι χωρίς τμήμα. Σήμερα μια τέτοια καρτέλα '
              'είναι είτε ξεχασμένη εταιρεία που θέλει μεταφορά '
              'στα Τμήματα, είτε άνθρωπος που έχασε το τμήμα του',
          example: 'Παράδειγμα υπόδειξης: «Δεν ανήκει σε κανένα τμήμα»',
          child: const RuleLabel('Υπάλληλος χωρίς τμήμα'),
        ),
      ],
    );
  }

  // ---- Lansweeper.

  Widget _lansweeperCard() {
    return RuleCard(
      icon: Icons.confirmation_number_outlined,
      title: 'Lansweeper',
      subtitle:
          'Οι φόρμες δείχνουν πάντα την προειδοποίηση — ο '
          'διακόπτης αφορά τον «Έλεγχο δεδομένων».',
      children: [
        RuleRow(
          enabled: rules.lansweeperIdentifierEnabled,
          onToggle: (v) =>
              _toggle((c) => c.copyWith(lansweeperIdentifierEnabled: v)),
          note:
              'Ελέγχονται τα αναγνωριστικά υπαλλήλων και οι '
              'γενικοί λογαριασμοί τμημάτων',
          example:
              'Παράδειγμα υπόδειξης: «Το «Γραφείο Λοιμώξεων '
              'gnk\\loimokseis1» δεν μοιάζει με αναγνωριστικό '
              'Lansweeper (τομέας\\όνομα ή email)»',
          child: const RuleLabel(
            'Αναγνωριστικά σε μορφή τομέας\\όνομα ή email',
          ),
        ),
      ],
    );
  }

  // ---- Διασταυρώσεις.

  Widget _crossChecksCard() {
    return RuleCard(
      icon: Icons.compare_arrows_outlined,
      title: 'Διασταυρώσεις',
      subtitle:
          'Κοιτούν ολόκληρο τον κατάλογο — τρέχουν μόνο στον '
          '«Έλεγχο δεδομένων», όχι στις φόρμες.',
      children: [
        RuleRow(
          enabled: rules.emptyDepartmentEnabled,
          onToggle: (v) => _toggle((c) => c.copyWith(emptyDepartmentEnabled: v)),
          note:
              'Δεν είναι σφάλμα — ένα τμήμα μπορεί να αδειάσει '
              'θεμιτά· η υπόδειξη θυμίζει να αποφασίσετε τι το κάνετε',
          example:
              'Παράδειγμα υπόδειξης: «Δεν έχει κανέναν υπάλληλο, '
              'κοινόχρηστο τηλέφωνο ή εξοπλισμό»',
          child: const RuleLabel('Τμήματα χωρίς κανένα εξάρτημα'),
        ),
        RuleRow(
          enabled: rules.departmentBuildingEnabled,
          onToggle: (v) =>
              _toggle((c) => c.copyWith(departmentBuildingEnabled: v)),
          note:
              'Το κτίριο διαλέγεται από τη λίστα (Διάφορα → '
              'Τμήματα)· κενό μένει όταν σβηστεί ένα κτίριο ή όταν '
              'η μεταφορά από τη Λάμπα το άφησε για αργότερα',
          example: 'Παράδειγμα υπόδειξης: «Δεν έχει κτίριο»',
          child: const RuleLabel('Τμήματα χωρίς κτίριο'),
        ),
        RuleRow(
          enabled: rules.departmentGroupEnabled,
          onToggle: (v) => _toggle((c) => c.copyWith(departmentGroupEnabled: v)),
          note:
              'Η ομάδα οργανώνει τον επιλογέα του χάρτη: χωρίς '
              'αυτήν το τμήμα πέφτει στα «Λοιπά». Εταιρείες και '
              'εξωτερικές μονάδες εξαιρούνται — δεν μπαίνουν στον '
              'χάρτη',
          example: 'Παράδειγμα υπόδειξης: «Δεν ανήκει σε καμία ομάδα»',
          child: const RuleLabel('Τμήματα χωρίς ομάδα'),
        ),
        RuleRow(
          enabled: rules.phoneEquipmentCodeEnabled,
          onToggle: (v) =>
              _toggle((c) => c.copyWith(phoneEquipmentCodeEnabled: v)),
          example:
              'Παράδειγμα υπόδειξης: «Το 3685 είναι καταχωρημένος '
              'κωδικός εξοπλισμού — ίσως γράφτηκε σε λάθος πεδίο»',
          child: const RuleLabel(
            'Τηλέφωνο που ταυτίζεται με κωδικό εξοπλισμού',
          ),
        ),
        RuleRow(
          enabled: rules.swappedNamesEnabled,
          onToggle: (v) => _toggle((c) => c.copyWith(swappedNamesEnabled: v)),
          example:
              'Παράδειγμα υπόδειξης: «Πιθανό ίδιο πρόσωπο με '
              'αντεστραμμένα πεδία»',
          child: const RuleLabel('Υπάλληλοι με αντεστραμμένο όνομα/επώνυμο'),
        ),
        RuleRow(
          enabled: rules.duplicateNamesEnabled,
          onToggle: (v) => _toggle((c) => c.copyWith(duplicateNamesEnabled: v)),
          example:
              'Παράδειγμα υπόδειξης: «Ίδιο ονοματεπώνυμο σε 2 '
              'εγγραφές — πιθανό διπλότυπο»',
          child: const RuleLabel('Υπάλληλοι με ολόιδιο ονοματεπώνυμο'),
        ),
        RuleRow(
          enabled: rules.crossDepartmentPhoneEnabled,
          onToggle: (v) =>
              _toggle((c) => c.copyWith(crossDepartmentPhoneEnabled: v)),
          note:
              'Στο ίδιο τμήμα το κοινό τηλέφωνο βάρδιας είναι '
              'θεμιτό και δεν ελέγχεται',
          example:
              'Παράδειγμα υπόδειξης: «Το 2534 είναι καταχωρημένο '
              'σε 2 υπαλλήλους σε 2 τμήματα»',
          child: const RuleLabel(
            'Ίδιο τηλέφωνο σε υπαλλήλους διαφορετικών τμημάτων',
          ),
        ),
        RuleRow(
          enabled: rules.equipmentOwnerDepartmentEnabled,
          onToggle: (v) =>
              _toggle((c) => c.copyWith(equipmentOwnerDepartmentEnabled: v)),
          example:
              'Παράδειγμα υπόδειξης: «Χρεωμένος στην εγγραφή '
              '«Ψαρρά Σοφία» (Γραμματεία ΤΕΠ), ενώ ανήκει στο '
              '«Χειρουργική»»',
          child: const RuleLabel(
            'Εξοπλισμός χρεωμένος σε υπάλληλο άλλου τμήματος',
          ),
        ),
        RuleRow(
          enabled: rules.equipmentInCompanyEnabled,
          onToggle: (v) =>
              _toggle((c) => c.copyWith(equipmentInCompanyEnabled: v)),
          note:
              'Οι εξωτερικές μονάδες (Κέντρα Υγείας) δεν '
              'ελέγχονται — εκεί τα μηχανήματα είναι δικά μας',
          example:
              'Παράδειγμα υπόδειξης: «Ανήκει στην εταιρεία '
              '«DataMed» — ο κατάλογος εξοπλισμού είναι του '
              'νοσοκομείου»',
          child: const RuleLabel('Εξοπλισμός που κατέληξε σε εταιρεία'),
        ),
        RuleRow(
          enabled: rules.equipmentWithoutDepartmentEnabled,
          onToggle: (v) =>
              _toggle((c) => c.copyWith(equipmentWithoutDepartmentEnabled: v)),
          note:
              'Οι φόρμες ζητούν πάντα τμήμα· κενό μένει όταν '
              'διαγραφεί η καρτέλα του τμήματος. Σιωπά όταν το '
              'μηχάνημα είναι χρεωμένο σε υπάλληλο που έχει τμήμα',
          example: 'Παράδειγμα υπόδειξης: «Δεν ανήκει σε κανένα τμήμα»',
          child: const RuleLabel('Εξοπλισμός χωρίς τμήμα'),
        ),
      ],
    );
  }
}

/// Ο κανόνας του ονόματος: η δήλωση, το πεδίο των εξαιρούμενων συμβόλων και
/// η επεξήγησή του.
class _PersonNameRuleContent extends StatelessWidget {
  const _PersonNameRuleContent({
    required this.field,
    required this.onSymbolsChanged,
  });

  final ValidationRuleField field;
  final ValueChanged<String> onSymbolsChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const RuleLabel(
          'Όνομα και επώνυμο να μην ξεκινούν από ψηφίο ή σύμβολο',
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const RuleLabel('Εξαιρούνται τα σύμβολα:'),
            const SizedBox(width: 8),
            CommitTextField(
              controller: field.controller,
              focusNode: field.focusNode,
              width: 140,
              hintText: '(, -',
              onCommitted: onSymbolsChanged,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Χωρισμένα με κόμμα. Τα ψηφία δεν εξαιρούνται ποτέ. '
          'Η ανοιχτή παρένθεση επιτρέπει το «(Γωγώ) Γεωργία».',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
