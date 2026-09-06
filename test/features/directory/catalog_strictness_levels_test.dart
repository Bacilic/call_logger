// Επίπεδα αυστηρότητας των κανόνων επικύρωσης: τι ανάβει το καθένα, πώς
// αναγνωρίζεται, και ο φρουρός που πιάνει κανόνα ξεχασμένο από την απογραφή.
//
// Ολόκληρο αρχείο (από ρίζα έργου):
//   flutter test test/features/directory/catalog_strictness_levels_test.dart

import 'package:call_logger/features/directory/models/catalog_validation_rules.dart';
import 'package:flutter_test/flutter_test.dart';

/// Πόσοι διακόπτες είναι αναμμένοι, μετρημένοι από το ΑΠΟΘΗΚΕΥΜΕΝΟ σχήμα.
///
/// Δεν διαβάζει την απογραφή [CatalogValidationRules.ruleSwitches] — αυτήν
/// ακριβώς ελέγχει. Αν ένας κανόνας λείπει από εκεί, θα μείνει στην τιμή που
/// είχε και το πλήθος δεν θα βγει.
int _enabledCount(CatalogValidationRules rules) {
  return rules.toJson().entries
      .where((e) => e.key.endsWith('_enabled') && e.value == true)
      .length;
}

int _switchCount(CatalogValidationRules rules) {
  return rules.toJson().keys.where((k) => k.endsWith('_enabled')).length;
}

void main() {
  const defaults = CatalogValidationRules();

  group('Τι ανάβει κάθε επίπεδο', () {
    test('«Όλοι οι έλεγχοι»: κάθε διακόπτης αναμμένος', () {
      final rules = defaults.withStrictness(CatalogStrictnessLevel.all);

      expect(_enabledCount(rules), _switchCount(rules));
    });

    test('«Ελάχιστοι έλεγχοι»: μόνο τα σχεδόν πάντα λάθος', () {
      final rules = defaults.withStrictness(CatalogStrictnessLevel.minimal);

      expect(rules.equipmentForeignCodeEnabled, isTrue);
      expect(rules.phoneEquipmentCodeEnabled, isTrue);
      expect(rules.duplicateRemoteTargetEnabled, isTrue);
      expect(rules.equipmentInCompanyEnabled, isTrue);
      expect(rules.duplicateNamesEnabled, isTrue);
      expect(rules.equipmentWithoutDepartmentEnabled, isTrue);

      expect(rules.internalPhoneDigitsEnabled, isFalse);
      expect(rules.emptyDepartmentEnabled, isFalse);
      expect(rules.equipmentLatinCodeEnabled, isFalse);
    });

    test('«Μεσαίο»: σφάλματα και ασυνέπειες, έξω οι υπενθυμίσεις', () {
      final rules = defaults.withStrictness(CatalogStrictnessLevel.medium);

      expect(rules.equipmentForeignCodeEnabled, isTrue);
      expect(rules.internalPhoneDigitsEnabled, isTrue);
      expect(rules.crossDepartmentPhoneEnabled, isTrue);

      expect(rules.emptyDepartmentEnabled, isFalse);
      expect(rules.departmentBuildingEnabled, isFalse);
      expect(rules.equipmentLatinCodeEnabled, isFalse);
    });

    test('τα τρία επίπεδα ανάβουν όλο και λιγότερα', () {
      final all = _enabledCount(
        defaults.withStrictness(CatalogStrictnessLevel.all),
      );
      final medium = _enabledCount(
        defaults.withStrictness(CatalogStrictnessLevel.medium),
      );
      final minimal = _enabledCount(
        defaults.withStrictness(CatalogStrictnessLevel.minimal),
      );

      expect(all, greaterThan(medium));
      expect(medium, greaterThan(minimal));
      expect(minimal, greaterThan(0));
    });
  });

  group('Αναγνώριση του επιπέδου από τους διακόπτες', () {
    test('μετά από επιλογή, το ίδιο επίπεδο αναγνωρίζεται', () {
      for (final level in CatalogStrictnessLevel.values) {
        expect(defaults.withStrictness(level).strictnessLevel, level);
      }
    });

    test('οι προεπιλογές είναι «Όλοι οι έλεγχοι»', () {
      expect(defaults.strictnessLevel, CatalogStrictnessLevel.all);
    });

    test('αλλαγή ενός διακόπτη: Προσαρμοσμένο', () {
      final custom = defaults
          .withStrictness(CatalogStrictnessLevel.medium)
          .copyWith(emptyDepartmentEnabled: true);

      expect(custom.strictnessLevel, isNull);
    });

    test('επιστροφή στο πακέτο: το επίπεδο ξαναναγνωρίζεται', () {
      final back = defaults
          .withStrictness(CatalogStrictnessLevel.medium)
          .copyWith(emptyDepartmentEnabled: true)
          .copyWith(emptyDepartmentEnabled: false);

      expect(back.strictnessLevel, CatalogStrictnessLevel.medium);
    });
  });

  group('Τι ΔΕΝ αγγίζει το επίπεδο', () {
    test('τα ψηφία, τα προθέματα και οι εξαιρέσεις μένουν όπως ήταν', () {
      const tuned = CatalogValidationRules(
        internalPhoneDigits: 5,
        externalPhoneDigits: 11,
        internalPrefixFrom: 30,
        internalPrefixTo: 39,
        equipmentMinDigits: 2,
        equipmentMaxDigits: 6,
        personNameAllowedSymbols: '(, -',
      );

      final after = tuned.withStrictness(CatalogStrictnessLevel.minimal);

      expect(after.internalPhoneDigits, 5);
      expect(after.externalPhoneDigits, 11);
      expect(after.internalPrefixFrom, 30);
      expect(after.internalPrefixTo, 39);
      expect(after.equipmentMinDigits, 2);
      expect(after.equipmentMaxDigits, 6);
      expect(after.personNameAllowedSymbols, '(, -');
    });

    test('το επίπεδο επιβιώνει στην αποθήκευση μέσω των διακοπτών', () {
      final saved = defaults.withStrictness(CatalogStrictnessLevel.minimal);
      final reloaded = CatalogValidationRules.fromRawJson(saved.toRawJson());

      expect(reloaded.strictnessLevel, CatalogStrictnessLevel.minimal);
    });
  });

  group('Φρουρός επεκτασιμότητας', () {
    // Ένας νέος κανόνας θέλει ΜΙΑ γραμμή στο ruleSwitches. Αν ξεχαστεί, τα
    // επίπεδα θα τον αφήνουν στην τιμή που έχει — αυτά τα δύο τεστ το πιάνουν
    // χωρίς να χρειάζεται να ενημερωθεί καμία λίστα εδώ.
    test('κάθε διακόπτης του σχήματος υπάρχει στην απογραφή', () {
      expect(
        CatalogValidationRules.ruleSwitches, //
        hasLength(_switchCount(defaults)),
      );
    });

    test('ξεκινώντας από σβηστά, το «Όλοι» ανάβει ΟΛΟΥΣ', () {
      // Το «Ελάχιστοι» σβήνει ό,τι δεν είναι σφάλμα· αν κάποιος διακόπτης
      // λείπει από την απογραφή, θα μείνει αναμμένος και θα φανεί εδώ.
      final minimal = defaults.withStrictness(CatalogStrictnessLevel.minimal);
      final back = minimal.withStrictness(CatalogStrictnessLevel.all);

      expect(_enabledCount(back), _switchCount(back));
    });
  });
}
