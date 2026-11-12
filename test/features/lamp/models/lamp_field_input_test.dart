// Τα πεδία ποσού και ορόφου στα παράθυρα επεξεργασίας της Λάμπας.
//
// Ο χρήστης γράφει ελληνικά: κόμμα για δεκαδικά, τελεία για χιλιάδες. Πριν,
// το «1.537» αποθηκευόταν όπως γράφτηκε και διαβαζόταν 1,54 €· και ο όροφος
// «1,5» γινόταν σιωπηλά κενός.
//
//   flutter test test/features/lamp/models/lamp_field_input_test.dart

import 'package:call_logger/features/lamp/models/lamp_field_input.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('el'));

  group('Κόστος — ελληνική γραφή', () {
    test('τελεία = χιλιάδες, κόμμα = δεκαδικά', () {
      expect(LampFieldInput.parseGreekMoney('1.537'), 1537);
      expect(LampFieldInput.parseGreekMoney('1537'), 1537);
      expect(LampFieldInput.parseGreekMoney('1.537,50'), 1537.5);
      expect(LampFieldInput.parseGreekMoney('1537,5'), 1537.5);
      expect(LampFieldInput.parseGreekMoney('1.234.567,8 €'), 1234567.8);
    });

    test('ό,τι δεν είναι ελληνική γραφή απορρίπτεται', () {
      expect(LampFieldInput.parseGreekMoney('1537.50'), isNull);
      expect(LampFieldInput.parseGreekMoney('1,537.50'), isNull);
      expect(LampFieldInput.parseGreekMoney('15.37'), isNull);
      expect(LampFieldInput.parseGreekMoney('abc'), isNull);
    });

    test('το αποθηκευμένο «1537.5000» δείχνεται ελληνικά στην επεξεργασία', () {
      expect(LampFieldInput.moneyForEdit('1537.5000'), '1.537,50');
      expect(LampFieldInput.moneyForEdit('12.0000'), '12,00');
    });

    test('άνοιγμα και αποθήκευση δεν αλλάζουν το ποσό', () {
      final shown = LampFieldInput.moneyForEdit('1537.5000')!;
      final stored = LampFieldInput.moneyForStorage(
        LampFieldInput.parseGreekMoney(shown)!,
      );
      expect(stored, '1537.5000');
    });

    test('το ποσό γράφεται με τη μορφή των υπόλοιπων κοστών', () {
      expect(LampFieldInput.moneyForStorage(1537), '1537.0000');
    });
  });

  group('Όροφος — ακέραιος', () {
    test('ακέραιος γίνεται δεκτός, και ο αρνητικός (υπόγειο)', () {
      expect(LampFieldInput.floorError('2'), isNull);
      expect(LampFieldInput.floorError('-1'), isNull);
    });

    test('δεκαδικός ή κείμενο απορρίπτεται με μήνυμα, όχι σιωπηλά', () {
      expect(LampFieldInput.floorError('1,5'), isNotNull);
      expect(LampFieldInput.floorError('abc'), isNotNull);
    });
  });
}
