// Unit tests: η μία σειρά κειμένου της εφαρμογής.
//
//   flutter test test/core/utils/display_text_sort_test.dart

import 'package:call_logger/core/utils/display_text_sort.dart';
import 'package:flutter_test/flutter_test.dart';

List<String?> _sorted(List<String?> values, {bool ascending = true}) =>
    [...values]..sort((a, b) => compareDisplayText(a, b, ascending: ascending));

void main() {
  test('τόνοι και κεφαλαία δεν αλλάζουν τη σειρά: η «Όλγα» πάει στο Ο', () {
    expect(_sorted(['Όλγα', 'Αγγελική', 'Άννα', 'αθανασία', 'Αλέκα']), [
      'Αγγελική',
      'αθανασία',
      'Αλέκα',
      'Άννα',
      'Όλγα',
    ]);
  });

  test('τα λατινικά μπαίνουν πριν από τα ελληνικά, χωρίς διάκριση πεζών', () {
    expect(_sorted(['Αιμοδοσία', 'e-aima', 'DataMed', 'CCS']), [
      'CCS',
      'DataMed',
      'e-aima',
      'Αιμοδοσία',
    ]);
  });

  test('οι αριθμοί με φυσική σειρά: το 2 πριν από το 10', () {
    expect(_sorted(['Όροφος 10', 'Όροφος 2', 'Όροφος 1']), [
      'Όροφος 1',
      'Όροφος 2',
      'Όροφος 10',
    ]);
  });

  test('τα κενά πάντα στο τέλος — και στη φθίνουσα σειρά', () {
    expect(_sorted(['Σούλα', null, '', 'Άννα']), ['Άννα', 'Σούλα', null, '']);
    expect(_sorted(['Σούλα', null, '', 'Άννα'], ascending: false), [
      'Σούλα',
      'Άννα',
      null,
      '',
    ]);
  });

  test('η παύλα του κενού κελιού μετρά ως κενό', () {
    expect(_sorted(['—', 'Σούλα', 'Άννα'], ascending: false), [
      'Σούλα',
      'Άννα',
      '—',
    ]);
  });

  test('ίδια λέξη με και χωρίς τόνο: σταθερή σειρά, όχι τυχαία', () {
    expect(
      compareDisplayText('Αννα', 'Άννα'),
      -compareDisplayText('Άννα', 'Αννα'),
    );
    expect(compareDisplayText('Αννα', 'Άννα'), isNot(0));
  });
}
