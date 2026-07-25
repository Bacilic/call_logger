/// Οι διαδρομές που εμφανίζει το dropdown διαδρομών βάσης δεδομένων.
///
/// **Συμβόλαιο:** η *ενεργή* διαδρομή βρίσκεται ΠΑΝΤΑ μέσα στη λίστα, ώστε το
/// dropdown να μπορεί να δείχνει πάντα τη βάση που είναι όντως ανοιχτή. Χωρίς
/// αυτή την εγγύηση το widget αναγκάζεται σε εφεδρική τιμή («η πρώτη πρόσφατη»)
/// και εμφανίζει ως ενεργή μια βάση που δεν είναι — ψέμα στην οθόνη.
///
/// Η σειρά των πρόσφατων διαδρομών διατηρείται· η ενεργή μπαίνει πρώτη μόνο
/// όταν λείπει. Τυχόν διπλότυπα αφαιρούνται, γιατί το `DropdownButton` απαιτεί
/// **ακριβώς μία** επιλογή να ταιριάζει με την τιμή του.
List<String> databasePathDropdownOptions({
  required String currentPath,
  required List<String> recentPaths,
}) {
  final options = recentPaths.contains(currentPath)
      ? <String>{...recentPaths}
      : <String>{currentPath, ...recentPaths};
  return List<String>.unmodifiable(options);
}
