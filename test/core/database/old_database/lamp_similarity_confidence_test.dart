import 'package:call_logger/core/database/old_database/lamp_issue_resolution_service.dart';
import 'package:call_logger/features/lamp/services/lamp_migration_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LampIssueResolutionService.similarityConfidenceScore', () {
    late LampIssueResolutionService resolution;

    setUp(() {
      resolution = LampIssueResolutionService();
    });

    test('διάκριση: μικρό τυπογραφικό vs εντελώς άσχετο όνομα', () {
      const source = 'Αναστασιος Παπαδοπουλος Κωνσταντινου';
      const typoCandidate = 'Αναστασιος Παπαδοπουλος Κωνσταντινος';
      const unrelatedCandidate = 'Άννα Πατσαρίκα';

      final typoScore = resolution.similarityConfidenceScore(
        source,
        typoCandidate,
      );
      final unrelatedScore = resolution.similarityConfidenceScore(
        source,
        unrelatedCandidate,
      );

      expect(
        typoScore,
        greaterThan(unrelatedScore + 15),
        reason: 'Τυπογραφικό σε μακρύ όνομα πρέπει να ξεχωρίζει από άσχετο',
      );
      expect(
        typoScore,
        greaterThan(LampMigrationService.kSuggestionConfidenceThreshold),
      );
    });

    test('ανεξαρτησία σειράς λέξεων: υψηλό σκορ για αντίστροφη σειρά', () {
      const source = 'Παπαδόπουλος Γιώργος';
      const candidate = 'Γιώργος Παπαδόπουλος';

      final score = resolution.similarityConfidenceScore(source, candidate);

      expect(
        score,
        greaterThanOrEqualTo(90),
        reason: 'Η αντίστροφη σειρά ονοματεπωνύμου πρέπει να θεωρείται σχεδόν ταύτιση',
      );
    });

    test('μεγάλα παρόμοια ονόματα δεν μηδενίζονται στο κατώφλι 20', () {
      const a = 'Αλεξανδρος Παπαδοπουλος Θεοδοσιου Μαριας';
      const b = 'Αλεξανδρος Παπαδοπουλου Θεοδοσιου Μαριας';

      final score = resolution.similarityConfidenceScore(a, b);

      expect(score, greaterThan(20));
      expect(score, greaterThan(LampMigrationService.kSuggestionConfidenceThreshold));
    });

    test('ακριβής ταύτιση μετά κανονικοποίηση παραμένει 100', () {
      expect(
        resolution.similarityConfidenceScore(
          'Γιωργος Παπαδοπουλος',
          'Γιώργος Παπαδόπουλος',
        ),
        100,
      );
    });

    test('substring containment κλάδος δεν αλλάζει', () {
      expect(
        resolution.similarityConfidenceScore(
          'Παπαδόπουλος',
          'Γιώργος Παπαδόπουλος',
          sourceDepartment: 'Τμήμα IT',
          candidateDepartment: 'Τμήμα IT',
        ),
        LampIssueResolutionService.substringContainmentConfidence,
      );
    });
  });
}
