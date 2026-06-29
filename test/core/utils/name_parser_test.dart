import 'package:call_logger/core/utils/name_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NameParserUtility.parseBothOrders', () {
    test('returns both first-last and last-first for two words', () {
      final orders = NameParserUtility.parseBothOrders('Γιώργος Παπαδόπουλος');

      expect(orders, hasLength(2));
      expect(
        orders,
        contains(
          (firstName: 'Γιώργος', lastName: 'Παπαδόπουλος'),
        ),
      );
      expect(
        orders,
        contains(
          (firstName: 'Παπαδόπουλος', lastName: 'Γιώργος'),
        ),
      );
    });

    test('single word yields first-only and last-only interpretations', () {
      final orders = NameParserUtility.parseBothOrders('Παπαδόπουλος');

      expect(orders, hasLength(2));
      expect(orders, contains((firstName: 'Παπαδόπουλος', lastName: '')));
      expect(orders, contains((firstName: '', lastName: 'Παπαδόπουλος')));
    });
  });
}
