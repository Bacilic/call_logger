/// Διευθύνσεις που κουβαλούν μυστικό (κλειδί API) μέσα τους.
///
/// Συμβόλαιο: ό,τι μεταφέρει μυστικό ταξιδεύει κρυπτογραφημένο — ή ο χρήστης
/// το ξέρει ρητά πριν το στείλει. Η εφαρμογή **δεν απαγορεύει** το `http`:
/// οι εσωτερικοί διακομιστές συχνά δεν έχουν πιστοποιητικό, και η απαγόρευση
/// θα έκοβε λειτουργία που δουλεύει. Προειδοποιεί.
library;

/// Ταξιδεύει το μυστικό αυτής της διεύθυνσης αναγνώσιμο στο δίκτυο;
///
/// Δέχεται και ημιτελές κείμενο (πρότυπα με `{κλειδί API}`, διευθύνσεις υπό
/// πληκτρολόγηση) — κοιτά μόνο το σχήμα, χωρίς να απαιτεί έγκυρη διεύθυνση.
/// Το loopback εξαιρείται: εκεί τα δεδομένα δεν φεύγουν από το μηχάνημα, και
/// ένας φρουρός που γκρινιάζει άδικα παύει να είναι πιστευτός.
bool urlCarriesSecretUnencrypted(String raw) {
  final t = raw.trim().toLowerCase();
  if (!t.startsWith('http://')) return false;
  return !_isLoopbackHost(_hostOf(t));
}

/// Το μήνυμα προς τον χρήστη, ή `null` όταν δεν υπάρχει λόγος ανησυχίας.
///
/// Το [secretLabel] ονομάζει το μυστικό όπως το ξέρει ο χρήστης («το κλειδί
/// API»), ώστε το μήνυμα να λέει τι ακριβώς εκτίθεται.
String? insecureSecretUrlWarning(String raw, {required String secretLabel}) {
  if (!urlCarriesSecretUnencrypted(raw)) return null;
  return 'Η διεύθυνση ξεκινά με http, οπότε $secretLabel ταξιδεύει αναγνώσιμο '
      'στο δίκτυο — όποιος παρακολουθεί τη σύνδεση μπορεί να το διαβάσει. '
      'Προτιμήστε https, αν ο διακομιστής το υποστηρίζει.';
}

String _hostOf(String lowercaseUrl) {
  final afterScheme = lowercaseUrl.substring('http://'.length);
  var end = afterScheme.length;
  for (final sep in const ['/', ':', '?', '#']) {
    final i = afterScheme.indexOf(sep);
    if (i >= 0 && i < end) end = i;
  }
  return afterScheme.substring(0, end);
}

bool _isLoopbackHost(String host) {
  return host == 'localhost' || host == '127.0.0.1' || host == '[::1]';
}
