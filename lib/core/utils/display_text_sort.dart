import 'natural_string_compare.dart';
import 'search_text_normalizer.dart';

/// Η **μία** σειρά κειμένου της εφαρμογής, για κάθε ταξινόμηση που βλέπει ο
/// χρήστης: πίνακες, λίστες επιλογής, προτάσεις.
///
/// Απόφαση Διευθυντή 17/10/2026:
/// 1. **Τόνοι και κεφαλαία δεν μετρούν** — η «Όλγα» πάει στο Ο, όχι πριν από
///    το Α (η σύγκριση χαρακτήρα-χαρακτήρα έβαζε τα τονισμένα κεφαλαία πρώτα).
/// 2. **Λατινικά πριν από ελληνικά** — η σειρά της Εξερεύνησης των Windows.
/// 3. **Αριθμοί με φυσική σειρά** — το «Όροφος 2» πριν από το «Όροφος 10».
/// 4. **Κενά πάντα στο τέλος**, και στη φθίνουσα σειρά: όποιος ταξινομεί κατά
///    «Ψευδώνυμο» θέλει να δει πρώτα όσους έχουν.
///
/// Δύο τιμές που διαφέρουν μόνο σε τόνο ή κεφαλαίο παίρνουν πάντα την ίδια
/// σειρά μεταξύ τους, ώστε η λίστα να μη «χορεύει» από ταξινόμηση σε
/// ταξινόμηση.
int compareDisplayText(String? a, String? b, {bool ascending = true}) {
  final ta = a?.trim() ?? '';
  final tb = b?.trim() ?? '';
  final emptyA = _isBlank(ta);
  final emptyB = _isBlank(tb);
  if (emptyA || emptyB) {
    if (emptyA && emptyB) return 0;
    return emptyA ? 1 : -1;
  }
  final c = _compareFilled(ta, tb);
  return ascending ? c : -c;
}

/// Η παύλα που δείχνουν οι πίνακες στη θέση του κενού κελιού μετρά ως κενό.
bool _isBlank(String trimmed) =>
    trimmed.isEmpty || trimmed == '—' || trimmed == '-';

int _compareFilled(String a, String b) {
  final byKey = naturalCompareStrings(
    SearchTextNormalizer.normalizeForSearch(a),
    SearchTextNormalizer.normalizeForSearch(b),
  );
  if (byKey != 0) return byKey;
  return a.compareTo(b);
}

/// Ίδια σειρά για εγγραφές με περισσότερα από ένα κλειδιά (π.χ. επώνυμο,
/// μετά όνομα): αποφασίζει το πρώτο κλειδί που διαφέρει.
///
/// Για τις λίστες που έρχονται από τη βάση: το `COLLATE NOCASE` εξομοιώνει
/// μόνο τα λατινικά και βάζει τα τονισμένα κεφαλαία πριν από το Α, οπότε η
/// σειρά που βλέπει ο χρήστης δίνεται πάντα από εδώ, όχι από το ερώτημα.
List<T> sortedForDisplay<T>(
  Iterable<T> items,
  List<String?> Function(T item) keys,
) {
  return items.toList()..sort((a, b) {
    final ka = keys(a);
    final kb = keys(b);
    for (var i = 0; i < ka.length && i < kb.length; i++) {
      final c = compareDisplayText(ka[i], kb[i]);
      if (c != 0) return c;
    }
    return 0;
  });
}
