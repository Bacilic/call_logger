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
