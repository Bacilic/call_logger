import 'search_text_normalizer.dart';

/// Κοινός πυρήνας ομοιότητας κειμένου για όλη την εφαρμογή.
class TextSimilarity {
  TextSimilarity._();

  /// Κανονικοποίηση κειμένου αναφοράς (τόνοι, σημεία στίξης, κενά).
  static String normalize(String value) {
    return SearchTextNormalizer.normalizeForSearch(
      value.replaceAll(RegExp(r'[-/()\\]+'), ' '),
    );
  }

  /// Απόσταση Levenshtein μεταξύ δύο συμβολοσειρών.
  static int levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.length < b.length) {
      final tmp = a;
      a = b;
      b = tmp;
    }
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 0; i < a.length; i++) {
      final current = <int>[i + 1];
      for (var j = 0; j < b.length; j++) {
        final insert = current[j] + 1;
        final delete = previous[j + 1] + 1;
        final substitute = previous[j] + (a[i] == b[j] ? 0 : 1);
        current.add(
          [insert, delete, substitute].reduce((x, y) => x < y ? x : y),
        );
      }
      previous = current;
    }
    return previous.last;
  }

  /// Ταξινομημένα tokens μετά από κανονικοποίηση (για ανεξαρτησία σειράς λέξεων).
  static String sortedTokens(String normalized) {
    final tokens =
        normalized.split(' ').where((token) => token.isNotEmpty).toList()
          ..sort();
    return tokens.join(' ');
  }

  /// Βαθμολογία ομοιότητας 0–100.
  ///
  /// - 0 σε κενό
  /// - 100 σε ταύτιση μετά την κανονικοποίηση
  /// - [containmentScore] όταν το ένα περιέχει το άλλο
  /// - αλλιώς το καλύτερο Levenshtein ποσοστό (ακατέργαστο / ταξινομημένες λέξεις),
  ///   στρογγυλοποιημένο και περιορισμένο στο 0–95
  static int score(String a, String b, {int containmentScore = 72}) {
    final na = normalize(a);
    final nb = normalize(b);
    if (na.isEmpty || nb.isEmpty) return 0;
    if (na == nb) return 100;
    if (na.contains(nb) || nb.contains(na)) {
      return containmentScore;
    }
    final maxLen = na.length > nb.length ? na.length : nb.length;
    final distance1 = levenshtein(na, nb);
    final s1 = 1 - distance1 / maxLen;

    final aSorted = sortedTokens(na);
    final bSorted = sortedTokens(nb);
    final sortedMaxLen = aSorted.length > bSorted.length
        ? aSorted.length
        : bSorted.length;
    final distance2 = levenshtein(aSorted, bSorted);
    final s2 = sortedMaxLen == 0 ? 0.0 : 1 - distance2 / sortedMaxLen;

    final best = s1 > s2 ? s1 : s2;
    return (best * 100).round().clamp(0, 95);
  }
}
