/// Utility για κανονικοποίηση και διαχωρισμό πλήρους ονόματος σε firstName / lastName.
/// Χρησιμοποιείται από UI και Domain· το Data Layer δέχεται ήδη διαχωρισμένα πεδία.
class NameParserUtility {
  NameParserUtility._();

  /// Αφαιρεί τυχόν παρενθετικό τμήμα στο τέλος (π.χ. " (Τμήμα)") για αναζήτηση/parse.
  /// Χρήση: όταν το κείμενο προέρχεται από fullNameWithDepartment ώστε να μην μπει το τμήμα στο επώνυμο.
  static String stripParentheticalSuffix(String value) {
    final v = value.trim();
    final idx = v.indexOf(' (');
    if (idx <= 0) return v;
    return v.substring(0, idx).trim();
  }

  /// Κανονικοποιεί το [fullName] (trim, πολλαπλά κενά → ένα) και το χωρίζει σε όνομα/επώνυμο.
  ///
  /// Heuristics:
  /// - Κενό → `('', '')`
  /// - 1 λέξη → `(λέξη, '')`
  /// - 2+ λέξεις → πρώτη λέξη = [firstName], όλες οι υπόλοιπες ενωμένες με κενό = [lastName]
  static ({String firstName, String lastName}) parse(String fullName) {
    final normalized = fullName
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) {
      return (firstName: '', lastName: '');
    }
    final parts = normalized.split(' ');
    if (parts.length == 1) {
      return (firstName: parts.single, lastName: '');
    }
    return (
      firstName: parts.first,
      lastName: parts.sublist(1).join(' '),
    );
  }
}
