import 'search_text_normalizer.dart';

/// Κανονικοποίηση για σύγκριση κειμένου με ελληνικούς↔λατινικούς ομοιόγλυφους.
///
/// Χρησιμοποιείται μόνο σε λογική σύγκρισης (όχι αποθήκευση).
class HomoglyphTextNormalizer {
  HomoglyphTextNormalizer._();

  static const Map<String, String> _toCanonical = {
    'a': 'a',
    'α': 'a',
    'b': 'b',
    'β': 'b',
    'e': 'e',
    'ε': 'e',
    'z': 'z',
    'ζ': 'z',
    'h': 'h',
    'η': 'h',
    'i': 'i',
    'ι': 'i',
    'k': 'k',
    'κ': 'k',
    'm': 'm',
    'μ': 'm',
    'n': 'n',
    'ν': 'n',
    'o': 'o',
    'ο': 'o',
    'p': 'p',
    'ρ': 'p',
    't': 't',
    'τ': 't',
    'y': 'y',
    'υ': 'y',
    'x': 'x',
    'χ': 'x',
  };

  static String normalizeForComparison(String value) {
    final base = SearchTextNormalizer.normalizeForSearch(value);
    final buffer = StringBuffer();
    for (final rune in base.runes) {
      final ch = String.fromCharCode(rune);
      buffer.write(_toCanonical[ch] ?? ch);
    }
    return buffer.toString();
  }
}
