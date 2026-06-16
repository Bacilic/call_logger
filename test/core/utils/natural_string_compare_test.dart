import 'package:call_logger/core/utils/natural_string_compare.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('naturalCompareStrings', () {
    test('orders numeric segments naturally', () {
      expect(naturalCompareStrings('1ος', '2ος'), lessThan(0));
      expect(naturalCompareStrings('2ος', '10ος'), lessThan(0));
      expect(naturalCompareStrings('9ος', '10ος'), lessThan(0));
    });

    test('orders prefixed labels with embedded numbers', () {
      expect(
        naturalCompareStrings('Όροφος Α · 2ος', 'Όροφος Α · 10ος'),
        lessThan(0),
      );
    });

    test('falls back to lexicographic for non-numeric text', () {
      expect(naturalCompareStrings('Β', 'Γ'), lessThan(0));
    });
  });
}
