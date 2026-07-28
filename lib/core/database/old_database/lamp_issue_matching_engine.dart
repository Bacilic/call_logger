import '../../utils/text_similarity.dart';

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
    return TextSimilarity.score(
      source,
      candidate,
      containmentScore: substringContainmentScore(
        sourceDepartment: sourceDepartment,
        candidateDepartment: candidateDepartment,
      ),
    );
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
    return TextSimilarity.normalize(value);
  }

  int levenshtein(String a, String b) {
    return TextSimilarity.levenshtein(a, b);
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
