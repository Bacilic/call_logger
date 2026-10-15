// Ο κανόνας κίνησης με τα πλήκτρα σε πίνακα γραμμών (καθαρή λογική).
//
//   flutter test test/core/widgets/row_navigation_logic_test.dart

import 'package:call_logger/core/widgets/row_navigation_logic.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  int? after(LogicalKeyboardKey key, int? current, {int count = 40}) =>
      rowIndexAfterKey(key: key, current: current, count: count, pageStep: 15);

  group('rowIndexAfterKey', () {
    test('↓ και ↑ κινούνται κατά μία γραμμή', () {
      expect(after(LogicalKeyboardKey.arrowDown, 5), 6);
      expect(after(LogicalKeyboardKey.arrowUp, 5), 4);
    });

    test('χωρίς εστίαση το ↓ πάει στην πρώτη και το ↑ στην τελευταία', () {
      expect(after(LogicalKeyboardKey.arrowDown, null), 0);
      expect(after(LogicalKeyboardKey.arrowUp, null), 39);
    });

    test('δεν βγαίνει έξω από τις γραμμές', () {
      expect(after(LogicalKeyboardKey.arrowDown, 39), 39);
      expect(after(LogicalKeyboardKey.arrowUp, 0), 0);
    });

    test(
      'Page Down/Up κινούνται κατά ένα βήμα σελίδας και κόβονται στα άκρα',
      () {
        expect(after(LogicalKeyboardKey.pageDown, 3), 18);
        expect(after(LogicalKeyboardKey.pageDown, 35), 39);
        expect(after(LogicalKeyboardKey.pageUp, 20), 5);
        expect(after(LogicalKeyboardKey.pageUp, 4), 0);
      },
    );

    test('Home και End πηγαίνουν στην πρώτη και στην τελευταία', () {
      expect(after(LogicalKeyboardKey.home, 20), 0);
      expect(after(LogicalKeyboardKey.end, 20), 39);
    });

    test(
      'εστίαση πέρα από το τέλος της λίστας (η λίστα μίκρυνε) διορθώνεται',
      () {
        expect(after(LogicalKeyboardKey.arrowUp, 99, count: 10), 8);
        expect(after(LogicalKeyboardKey.arrowDown, 99, count: 10), 9);
      },
    );

    test('χωρίς γραμμές, ή με πλήκτρο που δεν είναι κίνησης, δίνει null', () {
      expect(after(LogicalKeyboardKey.arrowDown, null, count: 0), isNull);
      expect(after(LogicalKeyboardKey.keyA, 3), isNull);
      expect(after(LogicalKeyboardKey.enter, 3), isNull);
    });
  });

  group('pageStartShowingRow', () {
    test('γραμμή μέσα στην τρέχουσα σελίδα: η σελίδα μένει', () {
      expect(
        pageStartShowingRow(focusedRow: 14, pageSize: 15, currentStart: 0),
        0,
      );
    });

    test('γραμμή στην επόμενη ή στην προηγούμενη σελίδα: η σελίδα αλλάζει', () {
      expect(
        pageStartShowingRow(focusedRow: 15, pageSize: 15, currentStart: 0),
        15,
      );
      expect(
        pageStartShowingRow(focusedRow: 14, pageSize: 15, currentStart: 15),
        0,
      );
      expect(
        pageStartShowingRow(focusedRow: 39, pageSize: 15, currentStart: 0),
        30,
      );
    });
  });
}
