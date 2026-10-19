/// Μία σελίδα της λίστας του Λεξικού: οι γραμμές και το συνολικό πλήθος.
class LexiconListPage {
  const LexiconListPage({required this.rows, required this.totalCount});

  final List<Map<String, dynamic>> rows;
  final int totalCount;
}

/// Οι φορτώσεις της λίστας του Λεξικού: πλήρης φόρτωση (νέα αναζήτηση ή
/// φίλτρο) και «επόμενη παρτίδα» της συνεχούς κύλισης.
///
/// Κανόνας: **μόνο η πιο πρόσφατη φόρτωση γράφει στη λίστα.** Σε βάση δικτύου
/// μια παρτίδα μπορεί να φτάσει αφού ο χρήστης έχει ήδη αλλάξει αναζήτηση· αν
/// εφαρμοζόταν, θα κολλούσε στο τέλος της νέας λίστας λέξεις που δεν
/// ταιριάζουν στο νέο φίλτρο. Μια πλήρης φόρτωση ακυρώνει κάθε φόρτωση που
/// ξεκίνησε πριν από αυτήν· το μπαγιάτικο αποτέλεσμα επιστρέφει `null`.
class LexiconListLoader {
  int _generation = 0;

  /// Πλήρης φόρτωση. Το [offsetFor] παίρνει το πλήθος και λέει από πού να
  /// ξεκινήσει η σελίδα (στη σελιδοποίηση μπορεί να διορθώσει τη σελίδα).
  Future<LexiconListPage?> reload({
    required Future<int> Function() count,
    required Future<int> Function(int totalCount) offsetFor,
    required Future<List<Map<String, dynamic>>> Function(int offset) page,
  }) async {
    final ticket = ++_generation;
    final total = await count();
    if (ticket != _generation) return null;
    final offset = await offsetFor(total);
    if (ticket != _generation) return null;
    final rows = await page(offset);
    if (ticket != _generation) return null;
    return LexiconListPage(rows: rows, totalCount: total);
  }

  /// Η επόμενη παρτίδα, από τη θέση [offset].
  Future<List<Map<String, dynamic>>?> loadMore({
    required int offset,
    required Future<List<Map<String, dynamic>>> Function(int offset) page,
  }) async {
    final ticket = _generation;
    final rows = await page(offset);
    if (ticket != _generation) return null;
    return rows;
  }
}
