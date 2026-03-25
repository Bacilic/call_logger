/// Utility για ομοιόμορφη κανονικοποίηση κειμένου αναζήτησης.
///
/// Χρησιμοποιείται από Κατάλογο και φόρμα Κλήσεων ώστε να ισχύει ενιαία
/// συμπεριφορά χωρίς διάκριση τόνου/διαλυτικών (π.χ. ι=ί=ϊ=ΐ).
class SearchTextNormalizer {
  SearchTextNormalizer._();

  /// Επιστρέφει string σε πεζά, χωρίς ελληνικά διακριτικά και με συμπτυγμένα κενά.
  static String normalizeForSearch(String value) {
    return value
        .toLowerCase()
        .replaceAll('_', ' ')
        .replaceAll('ά', 'α')
        .replaceAll('έ', 'ε')
        .replaceAll('ή', 'η')
        .replaceAll('ί', 'ι')
        .replaceAll('ϊ', 'ι')
        .replaceAll('ΐ', 'ι')
        .replaceAll('ό', 'ο')
        .replaceAll('ύ', 'υ')
        .replaceAll('ϋ', 'υ')
        .replaceAll('ΰ', 'υ')
        .replaceAll('ώ', 'ω')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Κανονικοποίηση λεξικής μορφής: πεζά, χωρίς ελληνικά διακριτικά, trim.
  ///
  /// Δεν μετατρέπει `underscore` σε κενό (σε αντίθεση με [normalizeForSearch])·
  /// για λεξικό / IT όρους όπως `snake_case`.
  static String normalizeDictionaryForm(String value) {
    return value
        .toLowerCase()
        .replaceAll('ά', 'α')
        .replaceAll('έ', 'ε')
        .replaceAll('ή', 'η')
        .replaceAll('ί', 'ι')
        .replaceAll('ϊ', 'ι')
        .replaceAll('ΐ', 'ι')
        .replaceAll('ό', 'ο')
        .replaceAll('ύ', 'υ')
        .replaceAll('ϋ', 'υ')
        .replaceAll('ΰ', 'υ')
        .replaceAll('ώ', 'ω')
        .trim();
  }

  /// Ελέγχει αν ένα κείμενο ταιριάζει με ήδη κανονικοποιημένο query.
  ///
  /// Κανόνες:
  /// - άμεσο περιέχει (contains)
  /// - ή token-prefix match (π.χ. "βα δρο" -> "βασιλης δροσος")
  static bool matchesNormalizedQuery(String text, String normalizedQuery) {
    if (normalizedQuery.isEmpty) return true;
    final normalizedText = normalizeForSearch(text);
    if (normalizedText.contains(normalizedQuery)) return true;

    final queryTokens = normalizedQuery
        .split(' ')
        .where((token) => token.isNotEmpty)
        .toList();
    if (queryTokens.isEmpty) return true;

    final textTokens = normalizedText
        .split(' ')
        .where((token) => token.isNotEmpty)
        .toList();

    return queryTokens.every(
      (queryToken) => textTokens.any((textToken) => textToken.startsWith(queryToken)),
    );
  }

  /// Κανονικοποιεί [text] και [query] και επιστρέφει true μόνο αν κάθε token
  /// του query (διαχωρισμός με κενά μετά την κανονικοποίηση) εμφανίζεται ως
  /// υποσύνολο στο κανονικοποιημένο [text] ([String.contains]).
  ///
  /// Κενό ή μόνο-κενά query θεωρείται «χωρίς φίλτρο» → true.
  static bool containsAllTokens(String text, String query) {
    final normalizedText = normalizeForSearch(text);
    final normalizedQuery = normalizeForSearch(query);
    if (normalizedQuery.isEmpty) return true;
    final tokens = normalizedQuery
        .split(' ')
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return true;
    return tokens.every((token) => normalizedText.contains(token));
  }
}
