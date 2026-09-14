import 'package:call_logger/core/database/old_database/lamp_scientific_serial.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isScientificSerial', () {
    test('εντοπίζει ελληνική υποδιαστολή με θετικό εκθέτη', () {
      expect(isScientificSerial('4,928E+11'), isTrue);
    });

    test('εντοπίζει τελεία δεκαδικού με θετικό εκθέτη', () {
      expect(isScientificSerial('5.16771E+12'), isTrue);
    });

    test('εντοπίζει με κενά γύρω από την τιμή', () {
      expect(isScientificSerial('  4,928E+11  '), isTrue);
    });

    test('απορρίπτει κανονικό σειριακό', () {
      expect(isScientificSerial('SN-492800000000'), isFalse);
    });

    test('απορρίπτει κενό ή null', () {
      expect(isScientificSerial(null), isFalse);
      expect(isScientificSerial(''), isFalse);
      expect(isScientificSerial('   '), isFalse);
    });

    test('απορρίπτει αριθμό χωρίς εκθέτη', () {
      expect(isScientificSerial('4928'), isFalse);
      expect(isScientificSerial('4,928'), isFalse);
    });

    test(
      'γνήσιος σειριακός με E ανάμεσα σε ψηφία ΔΕΝ είναι επιστημονική μορφή',
      () {
        // Πραγματικό παράδειγμα από τη βάση Λάμπας: κωδικός 1788, EDIMAX
        // THREE PORTS. Ήταν το ΜΟΝΟ εύρημα του ελέγχου σε 3.155 σειριακούς —
        // και ήταν λάθος. Παραβιάζει τη μορφή του Excel τρεις φορές: μάντισσα
        // έξι ψηφίων χωρίς υποδιαστολή, εκθέτης χωρίς πρόσημο, και εκθέτης με
        // αρχικά μηδενικά.
        expect(isScientificSerial('310128E000079'), isFalse);
      },
    );

    test('απορρίπτει μάντισσα με πάνω από ένα ψηφίο πριν την υποδιαστολή', () {
      // Το υπολογιστικό φύλλο κανονικοποιεί πάντα σε ένα ψηφίο: 3,10128E+11.
      expect(isScientificSerial('310128E+11'), isFalse);
      expect(isScientificSerial('49,28E+11'), isFalse);
    });

    test('απορρίπτει εκθέτη χωρίς πρόσημο', () {
      expect(isScientificSerial('4,928E11'), isFalse);
    });

    test('απορρίπτει εκθέτη με αρχικά μηδενικά', () {
      expect(isScientificSerial('4,928E+011'), isFalse);
    });

    test('δέχεται ακέραια μάντισσα ενός ψηφίου', () {
      // Σπάνιο αλλά θεμιτό: ο αριθμός είναι ακριβώς 4×10¹¹.
      expect(isScientificSerial('4E+11'), isTrue);
    });
  });

  group('scientificSerialCleanDigits', () {
    test('4,928E+11 → 4928', () {
      expect(scientificSerialCleanDigits('4,928E+11'), '4928');
    });

    test('5.16771E+12 → 516771', () {
      expect(scientificSerialCleanDigits('5.16771E+12'), '516771');
    });

    test('αφαιρεί πρόσημο από την ουσία', () {
      expect(scientificSerialCleanDigits('-4.928E+11'), '4928');
    });
  });

  group('scientificSerialExpectedLength', () {
    test('E+11 → 12', () {
      expect(scientificSerialExpectedLength('4,928E+11'), 12);
    });

    test('E+12 → 13', () {
      expect(scientificSerialExpectedLength('5.16771E+12'), 13);
    });

    test('επιστρέφει null για μη επιστημονική μορφή', () {
      expect(scientificSerialExpectedLength('SN-100'), isNull);
    });
  });
}
