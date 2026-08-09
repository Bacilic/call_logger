// Πρόταση γραφείου/τμήματος από ελεύθερο κείμενο.
//
// Τα γραφεία και οι τιμές είναι αληθινά, από τη Λάμπα της 08/08. Το κρίσιμο
// ζεύγος: «Γιατροί Μαιευτικής» πρέπει να βρει τη Μαιευτική-Γυναικολογική
// Κλινική, αν και καμία λέξη δεν ταιριάζει ολόκληρη.
//
//   flutter test test/core/database/old_database/lamp_place_suggestion_test.dart

import 'package:call_logger/core/database/old_database/lamp_place_suggestion.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../test_reporter.dart';

void main() {
  const places = <LampPlaceRow>[
    (
      id: 27,
      officeName: 'Γραφείο Ιατρών Γυναικολογικής',
      departmentName: 'Μαιευτική-Γυναικολογική Κλινική',
    ),
    (
      id: 171,
      officeName: 'Προϊσταμένη Γυναικολογικής',
      departmentName: 'Μαιευτική-Γυναικολογική Κλινική',
    ),
    (
      id: 182,
      officeName: 'Διευθυντής Γυναικολογικής',
      departmentName: 'Μαιευτική-Γυναικολογική Κλινική',
    ),
    (id: 19, officeName: 'Διοικητικό Ξενώνα', departmentName: 'Ξενώνας'),
    (id: 205, officeName: 'Γραφείο Ιατρών Ξενώνα', departmentName: 'Ξενώνας'),
    (
      id: 29,
      officeName: 'Γραμματεία ΤΕΠ',
      departmentName: 'Γραμματεία ΤΕΙ - ΤΕΠ',
    ),
    (
      id: 247,
      officeName: 'Προϊσταμένη Γραμματείας ΤΕΙ',
      departmentName: 'Γραμματεία ΤΕΙ - ΤΕΠ',
    ),
    (
      id: 288,
      officeName: 'Οδηγοί - Γραφείο Γραμματείας ΤΕΙ',
      departmentName: 'Γραμματεία ΤΕΙ - ΤΕΠ',
    ),
    (id: 43, officeName: 'Γραφείο Υλικού #1', departmentName: 'Οικονομικό'),
  ];

  LampPlaceSuggestion suggest(String value) =>
      lampPlaceSuggestion(rawValue: value, places: places);

  group('βρίσκει τον χώρο χωρίς ακριβή ταύτιση', () {
    test('«Γιατροί Μαιευτικής» → Μαιευτική-Γυναικολογική Κλινική', () {
      final result = suggest('Γιατροί Μαιευτικής');

      expect(
        result.matches.map((m) => m.id),
        containsAll(<int>[27, 171, 182]),
        reason: greekExpectMsg(
          'Καμία λέξη δεν ταιριάζει ολόκληρη — «Γιατροί» δεν είναι «Ιατρών» '
          'και «Μαιευτικής» δεν είναι «Γυναικολογικής». Η ρίζα «μαιευτ» τα '
          'δένει',
        ),
      );
      expect(result.sharedDepartment, 'Μαιευτική-Γυναικολογική Κλινική');
      expect(result.sentence, contains('ανήκουν όλα στο τμήμα'));
    });

    test('«ΟΔΗΓΟΙ» βρίσκει το γραφείο των οδηγών', () {
      final result = suggest('ΟΔΗΓΟΙ');

      expect(result.matches.single.id, 288);
      expect(result.sentence, contains('Κοντινότερο γραφείο: 288'));
    });

    test('τα κεφαλαία και οι τόνοι δεν εμποδίζουν', () {
      expect(suggest('ΞΕΝΩΝΑΣ').matches.map((m) => m.id), containsAll(<int>[19, 205]));
    });
  });

  group('ταξινόμηση', () {
    test('η ακριβής ταύτιση ονόματος γραφείου προηγείται', () {
      final result = suggest('Γραμματεία ΤΕΠ');

      expect(
        result.matches.first.id,
        29,
        reason: greekExpectMsg(
          'Το γραφείο που λέγεται ακριβώς έτσι πρέπει να είναι πρώτο, όχι '
          'θαμμένο ανάμεσα σε όσα μοιράζονται τη λέξη «Γραμματεία»',
        ),
      );
    });

    test('η λίστα κόβεται και λέει πόσα έμειναν', () {
      final result = lampPlaceSuggestion(
        rawValue: 'Γραμματεία ΤΕΠ',
        places: places,
        limit: 2,
      );

      expect(result.matches, hasLength(2));
      expect(result.totalMatchCount, greaterThan(2));
      expect(result.sentence, contains('ακόμη'));
    });

    test('διαφορετικά τμήματα: δεν λέει ψεύτικο κοινό τμήμα', () {
      // Το «Γραφείο Ιατρών» υπάρχει και στη Γυναικολογική και στον Ξενώνα.
      final result = suggest('Γραφείο Ιατρών');

      expect(result.sharedDepartment, isNull);
      expect(result.sentence, startsWith('Κοντινότερα γραφεία:'));
    });
  });

  group('δεν μαντεύει', () {
    test('όνομα ανθρώπου δεν είναι χώρος', () {
      expect(suggest('Μαρία Κυζιρίδου').isEmpty, isTrue);
      expect(suggest('Μαλατέστα Καλλή').isEmpty, isTrue);
    });

    test('λέξη που δεν υπάρχει πουθενά', () {
      expect(suggest('Φύλακες').isEmpty, isTrue);
      expect(suggest('Φύλακες').sentence, isNull);
    });

    test('κενό και πολύ κοντές λέξεις', () {
      expect(suggest('').isEmpty, isTrue);
      expect(
        suggest('#1 ΜΤ').isEmpty,
        isTrue,
        reason: greekExpectMsg(
          'Λέξεις δύο γραμμάτων ταιριάζουν παντού — θα έβγαζαν τυχαία '
          'γραφεία και θα κατεύθυναν λάθος',
        ),
      );
    });
  });
}
