import '../../../core/database/directory_support.dart';

/// Καθαρισμός του τεχνικού `details` μιας εγγραφής audit για εμφάνιση.
///
/// Τα repositories γράφουν εκεί ένα ίχνος για τον προγραμματιστή: `calls
/// id=228`, `equipment id=23 (αφαίρεση κοινόχρηστου τμήματος 38)`, `calls
/// count=3`, `updateAssociationsIfNeeded userId=17`. Το ποια οντότητα αφορά η
/// εγγραφή το λέει ήδη η σύνοψη, οπότε το ίχνος είναι θόρυβος — εκτός από το
/// ελληνικό σχόλιο που κάποιες φορές το συνοδεύει.
///
/// Ο κανόνας είναι απλός και δεν χρειάζεται λίστα πινάκων για να συντηρείται:
/// **ό,τι δεν έχει ελληνικά γράμματα δεν το βλέπει ο χρήστης.**
///
/// Επιστρέφει `null` όταν δεν μένει τίποτα ανθρώπινο να δειχτεί.
String? humanizeAuditDetails(String? raw) {
  final base = DirectorySupport.stripAuditOriginSuffix(raw).trim();
  if (base.isEmpty) return null;

  final match = RegExp(r'^(.*?)\s*\(([^()]*)\)\s*$').firstMatch(base);
  final head = (match?.group(1) ?? base).trim();
  final comment = (match?.group(2) ?? '').trim();

  final parts = [
    if (_containsGreekLetter(head)) head,
    if (_containsGreekLetter(comment)) comment,
  ];
  if (parts.isEmpty) return null;
  return _capitalizeFirst(parts.join(' — '));
}

final RegExp _greekLetter = RegExp(r'[Ͱ-Ͽἀ-῿]');

bool _containsGreekLetter(String value) => _greekLetter.hasMatch(value);

String _capitalizeFirst(String value) {
  if (value.isEmpty) return value;
  final first = value.substring(0, 1).toUpperCase();
  return '$first${value.substring(1)}';
}
