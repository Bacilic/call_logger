// Ταξινόμηση του πίνακα Ιστορικού κλήσεων: τι τιμή παίρνει κάθε γραμμή ανά
// στήλη και με ποια σειρά βγαίνουν. Τιμές από εκτέλεση του σημερινού κώδικα.
//
//   flutter test test/features/history/history_call_row_sort_test.dart

import 'package:call_logger/features/history/utils/history_call_row_sort.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final rows = <Map<String, dynamic>>[
    {
      'id': 1,
      'user_first_name': 'Αθανάσιος',
      'user_last_name': 'Π.',
      'date': '2026-10-11',
      'time': '09:05',
      'duration': 65,
      'has_open_task': 1,
      'lansweeper_state': 'sent',
      'user_department': 'Ακτινολογικό',
    },
    {
      'id': 2,
      'user_first_name': 'Όλγα',
      'user_last_name': 'Κ.',
      'date': '2026-10-11',
      'time': '08:00',
      'duration': '120',
      'has_open_task': 0,
      'lansweeper_state': null,
      'user_department': 'Ήπαρ',
    },
    {
      'id': 3,
      'user_first_name': 'Ελένη',
      'user_last_name': null,
      'date': 'xx',
      'time': null,
      'duration': null,
      'has_open_task': '1',
      'lansweeper_state': '',
      'user_department': '',
    },
    {
      'id': 4,
      'user_first_name': null,
      'user_last_name': null,
      'date': '2026-01-05',
      'time': '',
      'duration': 'abc',
      'has_open_task': true,
      'lansweeper_state': 'failed',
      'user_department': 'Βιοχημικό',
    },
  ];

  List<Object?> ids(List<Map<String, dynamic>> list) =>
      list.map((e) => e['id']).toList();

  test('ημερομηνία: χωρίς ώρα = μεσάνυχτα, άκυρη = πρώτη στην αύξουσα', () {
    expect(rows.map(parseHistoryCallDateTime).toList(), [
      DateTime(2026, 10, 11, 9, 5),
      DateTime(2026, 10, 11, 8, 0),
      null,
      DateTime(2026, 1, 5),
    ]);
    expect(ids(sortHistoryCallRows(rows, 0, true)), [3, 4, 2, 1]);
    expect(ids(sortHistoryCallRows(rows, 0, false)), [1, 2, 4, 3]);
  });

  test('καλούντας: ονοματεπώνυμο, «—» όταν λείπει', () {
    expect(rows.map(historyCallerDisplay).toList(), [
      'Αθανάσιος Π.',
      'Όλγα Κ.',
      'Ελένη',
      '—',
    ]);
  });

  test(
    'κείμενα συγκρίνονται χαρακτήρα-χαρακτήρα: τονισμένο κεφαλαίο πριν από το Α',
    () {
      // Φωτογραφία της σημερινής συμπεριφοράς (δες Πρόχειρο στις Βελτιώσεις).
      expect(ids(sortHistoryCallRows(rows, 1, true)), [2, 1, 3, 4]);
      expect(ids(sortHistoryCallRows(rows, 3, true)), [3, 2, 1, 4]);
    },
  );

  test(
    'διάρκεια: αριθμός και αριθμητικό κείμενο μετρούν, τα υπόλοιπα = -1',
    () {
      expect(rows.map((r) => historyCallSortValue(r, 7)).toList(), [
        65,
        120,
        -1,
        -1,
      ]);
      expect(ids(sortHistoryCallRows(rows, 7, false)).take(2), [2, 1]);
    },
  );

  test('συνδέσεις: εκκρεμότητα + κατάσταση Lansweeper εκτός «ακαταχώρητη»', () {
    expect(rows.map((r) => historyCallSortValue(r, 8)).toList(), [2, 0, 1, 2]);
    expect(historyFlagIsSet(' 1 '), isTrue);
    expect(historyFlagIsSet('true'), isFalse);
  });

  test('η ταξινόμηση φτιάχνει νέα λίστα — η αρχική μένει ως είχε', () {
    sortHistoryCallRows(rows, 1, true);
    expect(ids(rows), [1, 2, 3, 4]);
  });
}
