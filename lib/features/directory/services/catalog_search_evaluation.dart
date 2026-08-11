import '../../../core/utils/search_text_normalizer.dart';

/// Κοινή αξιολόγηση αναζήτησης για τις καρτέλες του Καταλόγου.
///
/// Η αρχή: **η αναζήτηση βρίσκει με βάση τα γεγονότα της εγγραφής, όχι με
/// βάση το τι χωράει στην οθόνη.** Οι στήλες ρυθμίζουν μόνο τι ΒΛΕΠΕΙΣ.
/// Επειδή έτσι μια εγγραφή μπορεί να ταιριάξει χωρίς τίποτα ορατό να το
/// εξηγεί, ο αξιολογητής επιστρέφει και ΠΟΙΑ κρυφά πεδία χρειάστηκαν —
/// ώστε η γραμμή αποτελεσμάτων να το πει ρητά αντί να μοιάζει σφάλμα.

/// Ένα γεγονός της εγγραφής: ετικέτα (όπως θα την πούμε στον χρήστη),
/// κείμενο και αν εμφανίζεται αυτή τη στιγμή ως στήλη στον πίνακα.
class CatalogSearchFact {
  const CatalogSearchFact({
    required this.label,
    required this.text,
    required this.isVisible,
  });

  final String label;
  final String text;
  final bool isVisible;
}

/// Αποτέλεσμα για ΜΙΑ εγγραφή.
class CatalogRowSearchResult {
  const CatalogRowSearchResult({
    required this.matches,
    this.hiddenLabelsNeeded = const <String>{},
  });

  final bool matches;

  /// Ετικέτες κρυφών πεδίων χωρίς τα οποία η εγγραφή ΔΕΝ θα ταίριαζε.
  /// Κενό όταν τα ορατά πεδία αρκούν (ή όταν δεν ταιριάζει καθόλου).
  final Set<String> hiddenLabelsNeeded;
}

/// Ταίριασμα με τη σημασιολογία του [SearchTextNormalizer.containsAllTokens]:
/// κάθε token του ερωτήματος πρέπει να βρεθεί σε ΚΑΠΟΙΟ γεγονός (οποιοδήποτε).
///
/// Ένα token «χρεώνεται» στα κρυφά πεδία μόνο όταν ΚΑΝΕΝΑ ορατό δεν το
/// περιέχει — τότε επιστρέφονται όλες οι ετικέτες κρυφών που το περιέχουν.
CatalogRowSearchResult evaluateCatalogSearchRow(
  List<CatalogSearchFact> facts,
  String query,
) {
  final normalizedQuery = SearchTextNormalizer.normalizeForSearch(query);
  final tokens = normalizedQuery
      .split(' ')
      .where((t) => t.isNotEmpty)
      .toList(growable: false);
  if (tokens.isEmpty) return const CatalogRowSearchResult(matches: true);

  final normalized = [
    for (final fact in facts)
      (
        label: fact.label,
        text: SearchTextNormalizer.normalizeForSearch(fact.text),
        isVisible: fact.isVisible,
      ),
  ];

  final hiddenLabelsNeeded = <String>{};
  for (final token in tokens) {
    var foundVisible = false;
    var foundAnywhere = false;
    final hiddenHits = <String>{};
    for (final fact in normalized) {
      if (fact.text.isEmpty || !fact.text.contains(token)) continue;
      foundAnywhere = true;
      if (fact.isVisible) {
        foundVisible = true;
        break;
      }
      hiddenHits.add(fact.label);
    }
    if (!foundAnywhere) {
      return const CatalogRowSearchResult(matches: false);
    }
    if (!foundVisible) {
      hiddenLabelsNeeded.addAll(hiddenHits);
    }
  }
  return CatalogRowSearchResult(
    matches: true,
    hiddenLabelsNeeded: hiddenLabelsNeeded,
  );
}

/// Σύνοψη μιας ολοκληρωμένης αναζήτησης, για τη γραμμή αποτελεσμάτων.
class CatalogSearchSummary {
  const CatalogSearchSummary({
    required this.searchActive,
    required this.totalMatches,
    this.hiddenMatchCounts = const <String, int>{},
  });

  /// Χωρίς ενεργό ερώτημα δεν υπάρχει τίποτα να ανακοινωθεί.
  static const empty = CatalogSearchSummary(
    searchActive: false,
    totalMatches: 0,
  );

  final bool searchActive;
  final int totalMatches;

  /// Ετικέτα κρυφού πεδίου → πόσες εγγραφές ταιριάζουν ΜΟΝΟ χάρη σε αυτό.
  final Map<String, int> hiddenMatchCounts;

  bool get hasHiddenMatches => hiddenMatchCounts.isNotEmpty;
}

/// Συσσωρευτής: τρέχει μέσα στο φιλτράρισμα κάθε καρτέλας.
class CatalogSearchSummaryBuilder {
  CatalogSearchSummaryBuilder();

  int _total = 0;
  final Map<String, int> _hidden = <String, int>{};

  void addMatch(CatalogRowSearchResult result) {
    if (!result.matches) return;
    _total++;
    for (final label in result.hiddenLabelsNeeded) {
      _hidden[label] = (_hidden[label] ?? 0) + 1;
    }
  }

  CatalogSearchSummary build() {
    // Σταθερή, προβλέψιμη σειρά: πρώτα τα πεδία με τα περισσότερα ευρήματα.
    final entries = _hidden.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return CatalogSearchSummary(
      searchActive: true,
      totalMatches: _total,
      hiddenMatchCounts: {for (final e in entries) e.key: e.value},
    );
  }
}

/// Το κείμενο της γραμμής αποτελεσμάτων. Κενό όταν δεν τρέχει αναζήτηση.
///
/// «Βρέθηκαν 2 αποτελέσματα · σε κρυφά πεδία — Τμήμα (1)»
///
/// Επίτηδες ΔΕΝ μιλά για «φίλτρα»: τα chips των στηλών κρύβουν στήλες, δεν
/// κόβουν γραμμές — κανένα αποτέλεσμα δεν αφαιρείται από αυτά.
String catalogSearchResultsLineText(CatalogSearchSummary summary) {
  if (!summary.searchActive) return '';
  final n = summary.totalMatches;
  final head = switch (n) {
    0 => 'Δεν βρέθηκαν αποτελέσματα',
    1 => 'Βρέθηκε 1 αποτέλεσμα',
    _ => 'Βρέθηκαν $n αποτελέσματα',
  };
  if (!summary.hasHiddenMatches) return head;
  final parts = summary.hiddenMatchCounts.entries
      .map((e) => '${e.key} (${e.value})')
      .join(', ');
  return '$head · σε κρυφά πεδία — $parts';
}
