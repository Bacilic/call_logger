/// Κοινό λεξιλόγιο για τα μηνύματα μεταφοράς κατοχής (τηλέφωνο, εξοπλισμός).
///
/// Συμβόλαιο: κάθε ετικέτα ενέργειας ονομάζει ρητά ΑΠΟ ποιον αφαιρείται και ΣΕ
/// ποιον δίνεται, με τη μορφή «όνομα (τμήμα)» — τίποτα δεν υπονοείται. Ζει σε
/// ένα σημείο ώστε κάθε νέος διάλογος μεταφοράς να το τηρεί χωρίς να το ξέρει.
library;

/// Ονόματα κατόχων για μήνυμα: έως [maxNames], οι υπόλοιποι ως πλήθος.
String ownerNamesForMessage(
  Iterable<String> labels, {
  int maxNames = 3,
  String ifEmpty = '',
}) {
  final names = labels
      .map((label) => label.trim())
      .where((label) => label.isNotEmpty)
      .toList();
  if (names.isEmpty) return ifEmpty;
  if (names.length <= maxNames) return names.join(', ');
  final rest = names.length - maxNames;
  final restLabel = rest == 1
      ? 'και άλλον 1 χρήστη'
      : 'και άλλους $rest χρήστες';
  return '${names.take(maxNames).join(', ')} $restLabel';
}

/// Το τμήμα ως πηγή αφαίρεσης: «Φαρμακείο (κοινόχρηστο)».
String sharedDepartmentSource(String? departmentName) {
  final name = departmentName?.trim() ?? '';
  if (name.isEmpty) return 'το τμήμα που το έχει κοινόχρηστο';
  return '$name (κοινόχρηστο)';
}

/// «Αφαίρεση από Α (Τμήμα) και από Β (Τμήμα) και σύνδεση με Γ (Τμήμα)».
///
/// Κενός [target] σημαίνει ότι δεν δίνεται σε κανέναν — το μήνυμα το λέει αντί
/// να το αποσιωπήσει.
String removeAndAssignMessage({
  required List<String> sources,
  required String target,
}) {
  final from = sources
      .map((source) => source.trim())
      .where((source) => source.isNotEmpty)
      .toList();
  final to = target.trim();
  if (from.isEmpty) return to.isEmpty ? 'Καμία αλλαγή' : 'Σύνδεση με $to';
  final removal = 'Αφαίρεση από ${from.join(' και από ')}';
  if (to.isEmpty) return '$removal, χωρίς νέα σύνδεση';
  return '$removal και σύνδεση με $to';
}
