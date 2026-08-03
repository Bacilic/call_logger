// Unit test: ελληνικό τρίγραμμο ημέρας εβδομάδας.
//
//   flutter test test/core/utils/greek_weekday_test.dart

import 'package:call_logger/core/utils/greek_weekday.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('τρίγραμμο ανά ημέρα εβδομάδας', () {
    expect(weekdayShortEl(DateTime(2026, 7, 27)), 'ΔΕΥ');
    expect(weekdayShortEl(DateTime(2026, 7, 28)), 'ΤΡΙ');
    expect(weekdayShortEl(DateTime(2026, 7, 29)), 'ΤΕΤ');
    expect(weekdayShortEl(DateTime(2026, 7, 30)), 'ΠΕΜ');
    expect(weekdayShortEl(DateTime(2026, 7, 31)), 'ΠΑΡ');
    expect(weekdayShortEl(DateTime(2026, 8)), 'ΣΑΒ');
    expect(weekdayShortEl(DateTime(2026, 8, 2)), 'ΚΥΡ');
  });
}
