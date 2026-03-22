import 'search_text_normalizer.dart';

/// Κλειδί ταύτισης ονοματεπώνυμου για διάλογο αλλαγής και διπλότυπα.
/// Σίγμα τελικό ς → σ πριν την κανονικοποίηση αναζήτησης (π.χ. Γιάννη ≈ Γιάννης).
class UserIdentityNormalizer {
  UserIdentityNormalizer._();

  static String identityKeyForPerson(String? firstName, String? lastName) {
    final raw =
        '${(firstName ?? '').trim()} ${(lastName ?? '').trim()}'.trim();
    if (raw.isEmpty) return '';
    final sigmaFolded = raw.replaceAll('ς', 'σ');
    return SearchTextNormalizer.normalizeForSearch(sigmaFolded);
  }
}
