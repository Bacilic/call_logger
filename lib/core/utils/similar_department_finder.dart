import '../../features/directory/models/department_model.dart';
import 'text_similarity.dart';

/// Αποτέλεσμα ομοιότητας με υπάρχον τμήμα καταλόγου.
class SimilarDepartmentMatch {
  const SimilarDepartmentMatch({required this.department, required this.score});

  final DepartmentModel department;
  final int score;
}

/// Εντοπισμός υπαρχόντων τμημάτων με όνομα παρόμοιο στο πληκτρολογημένο.
class SimilarDepartmentFinder {
  SimilarDepartmentFinder._();

  /// Ελάχιστο score για πρόταση παρόμοιου τμήματος.
  static const int kDepartmentSuggestionMinScore = 80;

  /// Υπάρχοντα τμήματα με score ∈ [κατώφλι, 100) — η ακριβής ταύτιση (100) εξαιρείται.
  static List<SimilarDepartmentMatch> findSimilarDepartments({
    required Iterable<DepartmentModel> departments,
    required String typedName,
  }) {
    final typed = typedName.trim();
    if (typed.isEmpty) return const [];

    final matches = <SimilarDepartmentMatch>[];
    for (final d in departments) {
      if (d.isDeleted) continue;
      final name = d.name.trim();
      if (name.isEmpty) continue;

      final score = TextSimilarity.score(
        typed,
        name,
        containmentScore: kDepartmentSuggestionMinScore,
      );
      if (score < kDepartmentSuggestionMinScore) continue;
      if (score >= 100) continue;

      matches.add(SimilarDepartmentMatch(department: d, score: score));
    }

    matches.sort((a, b) => b.score.compareTo(a.score));
    return matches;
  }
}
