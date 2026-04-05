import 'package:characters/characters.dart';

/// Μετρήσεις για φίλτρα λεξικού.
///
/// **letters_count**: grapheme clusters ([Characters])· εξαιρούνται μόνο `-`, `'` και `'` (U+2019)
/// από το πλήθος γραμμάτων (όχι από τα διακριτικά).
///
/// **diacritic_mark_count**: παύλα/απόστροφοι ως +1 έκαστο· ανά grapheme με ελληνική βάση,
/// ένα «σύνολο» τόνου/διαλυτικών/συνδυασμού (π.χ. ΐ) = +1· προσυντεθειμένα ελληνικά με τόνο
/// (π.χ. ά, U+1Fxx πολυτονικά με πνεύμα) = +1· NFD συνδυαστικά σε ελληνικό γράμμα = +1 ανά cluster.
/// Λατινικές λέξεις χωρίς ελληνική βάση: δεν προστίθενται τόνοι από combining εκτός αν υπάρχει ελληνικό γράμμα.
class LexiconWordMetrics {
  const LexiconWordMetrics({
    required this.lettersCount,
    required this.diacriticMarkCount,
  });

  final int lettersCount;
  final int diacriticMarkCount;

  static LexiconWordMetrics compute(String raw) {
    final s = raw.trim();
    if (s.isEmpty) {
      return const LexiconWordMetrics(lettersCount: 0, diacriticMarkCount: 0);
    }
    var letters = 0;
    var diacritics = 0;
    for (final g in s.characters) {
      if (_isHyphenOrApostropheGrapheme(g)) {
        diacritics++;
        continue;
      }
      letters++;
      if (_clusterHasGreekDiacriticBundle(g)) {
        diacritics++;
      }
    }
    return LexiconWordMetrics(
      lettersCount: letters,
      diacriticMarkCount: diacritics,
    );
  }
}

bool _isHyphenOrApostropheGrapheme(String g) {
  if (g == '-' || g == "'" || g == '\u2019') return true;
  return false;
}

/// Κύρια ελληνικά γράμματα χωρίς τόνο/διαλυτικά (μονοσύλλαβο rune).
bool _isCoreGreekLetterWithoutMark(int r) {
  if (r >= 0x391 && r <= 0x3A1) return true;
  if (r >= 0x3A3 && r <= 0x3A9) return true;
  if (r >= 0x3B1 && r <= 0x3C9) return true;
  return false;
}

/// Προσυντεθειμένο ελληνικό με τόνο/διαλυτικά/πολυτονικό (ένα rune = τουλάχιστον ένα «σημείο»).
bool _isPrecomposedGreekWithDiacritic(int r) {
  if (_isCoreGreekLetterWithoutMark(r)) return false;
  if (r >= 0x386 && r <= 0x38F) return true;
  if (r == 0x390) return true;
  if (r >= 0x3AA && r <= 0x3AB) return true;
  if (r >= 0x3AC && r <= 0x3CE) return true;
  if (r >= 0x3CA && r <= 0x3CB) return true;
  if (r >= 0x1F00 && r <= 0x1FFC) return true;
  return false;
}

/// Συνδυαστικά διακριτικά που χρησιμοποιούνται με ελληνικά (NFD).
bool _isCombiningGreekDiacritic(int r) {
  if (r >= 0x300 && r <= 0x314) return true;
  if (r >= 0x342 && r <= 0x345) return true;
  return false;
}

bool _hasGreekLetterBaseInCluster(String g) {
  for (final r in g.runes) {
    if (_isCoreGreekLetterWithoutMark(r)) return true;
    if (_isPrecomposedGreekWithDiacritic(r)) return true;
  }
  return false;
}

bool _clusterHasGreekDiacriticBundle(String g) {
  for (final r in g.runes) {
    if (_isPrecomposedGreekWithDiacritic(r)) return true;
  }
  if (!_hasGreekLetterBaseInCluster(g)) return false;
  for (final r in g.runes) {
    if (_isCombiningGreekDiacritic(r)) return true;
  }
  return false;
}
