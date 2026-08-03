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

  /// Κάτω από αυτό το μήκος το κοινό τμήμα είναι θόρυβος και δεν μαρκάρεται.
  static const int kMinMatchedSpanLength = 3;

  /// Το μεγαλύτερο συνεχόμενο κοινό τμήμα των [a] και [b], χωρίς διάκριση
  /// πεζών/κεφαλαίων και τόνων. Επιστρέφει τη θέση του πάνω στο [a]·
  /// `length: 0` σημαίνει κανένα αξιόλογο κοινό τμήμα.
  ///
  /// Τροφοδοτεί την οπτική ανάδειξη του κοινού μέρους στους διαλόγους
  /// «Μήπως εννοείτε;». Καλύπτει και κοινή αρχή («Βασίλης Δροσούλης» /
  /// «Βασίλης Δρόσος» → «Βασίλης Δροσο») και εμπεριέχον όνομα
  /// («Γραφείο Πληροφορικής» / «Πληροφορική» → «Πληροφορική»).
  static ({int start, int length}) matchedSpan(String a, String b) {
    if (a.isEmpty || b.isEmpty) return (start: 0, length: 0);

    var best = 0;
    var bestEnd = 0;
    var previous = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0);
      for (var j = 1; j <= b.length; j++) {
        if (_foldChar(a[i - 1]) != _foldChar(b[j - 1])) continue;
        current[j] = previous[j - 1] + 1;
        if (current[j] > best) {
          best = current[j];
          bestEnd = i;
        }
      }
      previous = current;
    }

    if (best < kMinMatchedSpanLength) return (start: 0, length: 0);
    return (start: bestEnd - best, length: best);
  }

  static String _foldChar(String ch) {
    final lower = ch.toLowerCase();
    const folds = {
      'ς': 'σ',
      'ά': 'α',
      'έ': 'ε',
      'ή': 'η',
      'ί': 'ι',
      'ϊ': 'ι',
      'ΐ': 'ι',
      'ό': 'ο',
      'ύ': 'υ',
      'ϋ': 'υ',
      'ΰ': 'υ',
      'ώ': 'ω',
    };
    return folds[lower] ?? lower;
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
