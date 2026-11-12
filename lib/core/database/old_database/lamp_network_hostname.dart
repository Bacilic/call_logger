/// Ονόματα υπολογιστών τύπου εξοπλισμού στη Λάμπα (`PC3846`, `PR1802`…): από
/// αυτά βγαίνει ο κωδικός του εξοπλισμού στον οποίο ανήκει μια διεύθυνση
/// δικτύου.
library;

final RegExp _equipmentHostnamePattern = RegExp(
  r'^(PC|PR|SW|LAPTOP|PRINT|HP)0*(\d+)$',
  caseSensitive: false,
);

/// Αριθμητικό μέρος hostname τύπου εξοπλισμού (`PC3846` → 3846)·
/// `null` για ονόματα χρήστη/περιγραφικά/κενά.
int? lampNetworkHostnameCode(String hostname) {
  final match = _equipmentHostnamePattern.firstMatch(hostname.trim());
  if (match == null) return null;
  return int.tryParse(match.group(2)!);
}
