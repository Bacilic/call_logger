import '../../utils/search_text_normalizer.dart';

class LampIssueMatchingEngine {
  /// Confidence για ταύτιση «το ένα περιέχει το άλλο» (substring containment).
  static const int substringContainmentConfidence = 72;

  /// Κοινή βαθμολόγηση ομοιότητας που επαναχρησιμοποιείται σε flows migration.
  int similarityConfidenceScore(
    String source,
    String candidate, {
    String? sourceDepartment,
    String? candidateDepartment,
  }) {
    final a = normalizeReferenceText(source);
    final b = normalizeReferenceText(candidate);
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 100;
    if (a.contains(b) || b.contains(a)) {
      return substringContainmentScore(
        sourceDepartment: sourceDepartment,
        candidateDepartment: candidateDepartment,
      );
    }
    final maxLen = a.length > b.length ? a.length : b.length;
    final distance1 = levenshtein(a, b);
    final s1 = 1 - distance1 / maxLen;

    final aSorted = _sortedTokensNormalized(a);
    final bSorted = _sortedTokensNormalized(b);
    final sortedMaxLen = aSorted.length > bSorted.length
        ? aSorted.length
        : bSorted.length;
    final distance2 = levenshtein(aSorted, bSorted);
    final s2 = sortedMaxLen == 0 ? 0.0 : 1 - distance2 / sortedMaxLen;

    final best = s1 > s2 ? s1 : s2;
    return (best * 100).round().clamp(0, 95);
  }

  String _sortedTokensNormalized(String normalized) {
    final tokens = normalized
        .split(' ')
        .where((token) => token.isNotEmpty)
        .toList()
      ..sort();
    return tokens.join(' ');
  }

  int substringContainmentScore({
    String? sourceDepartment,
    String? candidateDepartment,
  }) {
    final sourceDept = normalizeReferenceText(sourceDepartment ?? '');
    final candidateDept = normalizeReferenceText(candidateDepartment ?? '');
    if (sourceDept.isEmpty || candidateDept.isEmpty) {
      return substringContainmentConfidence;
    }
    if (sourceDept == candidateDept) {
      return substringContainmentConfidence;
    }
    return (substringContainmentConfidence - 32).clamp(20, 67);
  }

  String normalizeReferenceText(String value) {
    return SearchTextNormalizer.normalizeForSearch(
      value.replaceAll(RegExp(r'[-/()\\]+'), ' '),
    );
  }

  int levenshtein(String a, String b) {
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
}

class ReferenceRow {
  const ReferenceRow({
    required this.id,
    required this.label,
    required this.normalized,
  });

  final int id;
  final String label;
  final String normalized;
}

class FuzzyReferenceMatch {
  const FuzzyReferenceMatch(this.reference, this.score, this.distance);

  final ReferenceRow reference;
  final int score;
  final int distance;
}
