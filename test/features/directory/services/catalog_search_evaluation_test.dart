// Κοινός αξιολογητής αναζήτησης Καταλόγου: η αναζήτηση βρίσκει με βάση τα
// γεγονότα της εγγραφής (και τα κρυφά), και η σύνοψη λέει ρητά ποια κρυφά
// πεδία χρειάστηκαν — ώστε ένα «αόρατο» ταίριασμα να μη μοιάζει σφάλμα.
//
//   flutter test test/features/directory/services/catalog_search_evaluation_test.dart

import 'package:call_logger/features/directory/services/catalog_search_evaluation.dart';
import 'package:flutter_test/flutter_test.dart';

CatalogSearchFact _fact(String label, String text, {required bool visible}) =>
    CatalogSearchFact(label: label, text: text, isVisible: visible);

void main() {
  group('evaluateCatalogSearchRow', () {
    test('token σε ορατό πεδίο → ταιριάζει χωρίς χρέωση κρυφών', () {
      final result = evaluateCatalogSearchRow([
        _fact('Κωδικός', '3698', visible: true),
        _fact('Τμήμα', 'Ψυχιατρική', visible: false),
      ], '3698');

      expect(result.matches, isTrue);
      expect(result.hiddenLabelsNeeded, isEmpty);
    });

    test('token ΜΟΝΟ σε κρυφό πεδίο → ταιριάζει και χρεώνεται στο πεδίο', () {
      final result = evaluateCatalogSearchRow([
        _fact('Κωδικός', '3698', visible: true),
        _fact('Τμήμα', 'Ψυχιατρική', visible: false),
      ], 'ψυχιατρικη');

      expect(result.matches, isTrue);
      expect(result.hiddenLabelsNeeded, {'Τμήμα'});
    });

    test('token πουθενά → δεν ταιριάζει', () {
      final result = evaluateCatalogSearchRow([
        _fact('Κωδικός', '3698', visible: true),
        _fact('Τμήμα', 'Ψυχιατρική', visible: false),
      ], 'ορθοπεδικη');

      expect(result.matches, isFalse);
      expect(result.hiddenLabelsNeeded, isEmpty);
    });

    test('πολλά tokens μοιράζονται σε διαφορετικά πεδία (σαν blob)', () {
      final result = evaluateCatalogSearchRow([
        _fact('Όνομα', 'Μαρία', visible: true),
        _fact('Τμήμα', 'Ψυχιατρική', visible: false),
      ], 'μαρια ψυχιατρικη');

      expect(result.matches, isTrue);
      // Μόνο το token που ΔΕΝ καλύπτεται από ορατό πεδίο χρεώνεται.
      expect(result.hiddenLabelsNeeded, {'Τμήμα'});
    });

    test('token και σε ορατό ΚΑΙ σε κρυφό → καμία χρέωση (το ορατό αρκεί)',
        () {
      final result = evaluateCatalogSearchRow([
        _fact('Σημειώσεις', 'Ψυχιατρική κλινική', visible: true),
        _fact('Τμήμα', 'Ψυχιατρική', visible: false),
      ], 'ψυχιατρικη');

      expect(result.matches, isTrue);
      expect(result.hiddenLabelsNeeded, isEmpty);
    });

    test('κενό ερώτημα → όλα ταιριάζουν', () {
      final result = evaluateCatalogSearchRow([
        _fact('Κωδικός', '3698', visible: true),
      ], '   ');
      expect(result.matches, isTrue);
    });
  });

  group('catalogSearchResultsLineText', () {
    test('χωρίς ενεργή αναζήτηση → κενό (η γραμμή δεν εμφανίζεται)', () {
      expect(catalogSearchResultsLineText(CatalogSearchSummary.empty), '');
    });

    test('ενικός, πληθυντικός και μηδέν', () {
      String text(int n) => catalogSearchResultsLineText(
        CatalogSearchSummary(searchActive: true, totalMatches: n),
      );
      expect(text(0), 'Δεν βρέθηκαν αποτελέσματα');
      expect(text(1), 'Βρέθηκε 1 αποτέλεσμα');
      expect(text(5), 'Βρέθηκαν 5 αποτελέσματα');
    });

    test('με ευρήματα σε κρυφά πεδία → ονομαστική αναφορά με πλήθη', () {
      final text = catalogSearchResultsLineText(
        const CatalogSearchSummary(
          searchActive: true,
          totalMatches: 2,
          hiddenMatchCounts: {'Τμήμα': 1},
        ),
      );
      expect(text, 'Βρέθηκαν 2 αποτελέσματα · σε κρυφά πεδία — Τμήμα (1)');
    });

    test('περισσότερα κρυφά πεδία ενώνονται με κόμμα', () {
      final text = catalogSearchResultsLineText(
        const CatalogSearchSummary(
          searchActive: true,
          totalMatches: 4,
          hiddenMatchCounts: {'Τμήμα': 2, 'Σημειώσεις': 1},
        ),
      );
      expect(
        text,
        'Βρέθηκαν 4 αποτελέσματα · σε κρυφά πεδία — Τμήμα (2), Σημειώσεις (1)',
      );
    });
  });

  group('CatalogSearchSummaryBuilder', () {
    test('μετρά μόνο ταιριάσματα και ταξινομεί κρυφά κατά πλήθος', () {
      final builder = CatalogSearchSummaryBuilder()
        ..addMatch(const CatalogRowSearchResult(matches: false))
        ..addMatch(
          const CatalogRowSearchResult(
            matches: true,
            hiddenLabelsNeeded: {'Σημειώσεις'},
          ),
        )
        ..addMatch(
          const CatalogRowSearchResult(
            matches: true,
            hiddenLabelsNeeded: {'Τμήμα'},
          ),
        )
        ..addMatch(
          const CatalogRowSearchResult(
            matches: true,
            hiddenLabelsNeeded: {'Τμήμα'},
          ),
        );

      final summary = builder.build();
      expect(summary.totalMatches, 3);
      expect(summary.hiddenMatchCounts.keys.toList(), [
        'Τμήμα',
        'Σημειώσεις',
      ]);
      expect(summary.hiddenMatchCounts['Τμήμα'], 2);
    });
  });
}
