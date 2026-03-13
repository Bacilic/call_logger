/// Utility για κανονικοποίηση και διαχωρισμό πλήρους ονόματος σε firstName / lastName.
/// Χρησιμοποιείται από UI και Domain· το Data Layer δέχεται ήδη διαχωρισμένα πεδία.
class NameParserUtility {
  NameParserUtility._();

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
