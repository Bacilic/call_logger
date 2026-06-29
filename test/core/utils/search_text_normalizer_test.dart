import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SearchTextNormalizer.normalizeForSearch', () {
    test('maps final sigma ς and Σ-derived σ to the same key', () {
      final typed = SearchTextNormalizer.normalizeForSearch('Πληροφορικής');
      final fromUppercase =
          SearchTextNormalizer.normalizeForSearch('ΠΛΗΡΟΦΟΡΙΚΗΣ');

      expect(typed, equals(fromUppercase));
    });

    test('maps full department labels that differ only by final sigma', () {
      final typed =
          SearchTextNormalizer.normalizeForSearch('Τμήμα Πληροφορικής');
      final fromLamp =
          SearchTextNormalizer.normalizeForSearch('ΤΜΗΜΑ ΠΛΗΡΟΦΟΡΙΚΗΣ');

      expect(typed, equals(fromLamp));
    });
  });
}
