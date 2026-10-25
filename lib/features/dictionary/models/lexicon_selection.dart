/// Η ταυτότητα μιας γραμμής του Λεξικού: εγγραφή του Πλήρους Λεξικού ή
/// πρόχειρο (που δεν έχει ακόμη αριθμό εγγραφής).
String lexiconRowKey(Map<String, dynamic> row) {
  final entryId = row['entry_id'] as int?;
  if (entryId != null) return 'lex_e_$entryId';
  return 'lex_d_${row['norm_key'] as String? ?? ''}';
}

/// Οι λέξεις που έχει μαζέψει ο χρήστης για έλεγχο με ΤΝ.
///
/// Επιβιώνει της αλλαγής σελίδας και φίλτρου: κρατά αντίγραφο κάθε γραμμής,
/// με τη σειρά που επιλέχθηκε — αυτή είναι και η σειρά αποστολής. Η «άγκυρα»
/// είναι το τελευταίο κλικ, η αρχή μιας περιοχής με Shift.
class LexiconSelection {
  const LexiconSelection({
    this.rows = const <String, Map<String, dynamic>>{},
    this.anchorKey,
  });

  final Map<String, Map<String, dynamic>> rows;
  final String? anchorKey;

  int get count => rows.length;
  bool get isEmpty => rows.isEmpty;
  bool contains(Map<String, dynamic> row) =>
      rows.containsKey(lexiconRowKey(row));

  /// Κλικ στο κουτάκι: μπαίνει ή βγαίνει μία λέξη, και γίνεται άγκυρα.
  LexiconSelection toggle(Map<String, dynamic> row) {
    final key = lexiconRowKey(row);
    final next = Map<String, Map<String, dynamic>>.of(rows);
    if (next.remove(key) == null) next[key] = Map.of(row);
    return LexiconSelection(rows: next, anchorKey: key);
  }

  /// Shift + κλικ: επιλέγει όλες τις λέξεις από την άγκυρα ως την [target],
  /// με τη σειρά της λίστας. Άγκυρα που δεν φαίνεται στη [visible] (άλλη
  /// σελίδα, άλλο φίλτρο) δεν ορίζει περιοχή — το κλικ μετρά απλό.
  LexiconSelection selectRange(
    List<Map<String, dynamic>> visible,
    Map<String, dynamic> target,
  ) {
    final targetIndex = visible.indexWhere(
      (r) => lexiconRowKey(r) == lexiconRowKey(target),
    );
    final anchorIndex = anchorKey == null
        ? -1
        : visible.indexWhere((r) => lexiconRowKey(r) == anchorKey);
    if (targetIndex < 0 || anchorIndex < 0) return toggle(target);
    final from = anchorIndex < targetIndex ? anchorIndex : targetIndex;
    final to = anchorIndex < targetIndex ? targetIndex : anchorIndex;
    return addAll(
      visible.sublist(from, to + 1),
    )._withAnchor(lexiconRowKey(target));
  }

  /// Προσθέτει όσες λείπουν, χωρίς να αλλάξει τη σειρά των υπαρχουσών.
  LexiconSelection addAll(Iterable<Map<String, dynamic>> more) {
    final next = Map<String, Map<String, dynamic>>.of(rows);
    for (final row in more) {
      next.putIfAbsent(lexiconRowKey(row), () => Map.of(row));
    }
    return LexiconSelection(rows: next, anchorKey: anchorKey);
  }

  LexiconSelection removeAll(Iterable<Map<String, dynamic>> less) {
    final next = Map<String, Map<String, dynamic>>.of(rows);
    for (final row in less) {
      next.remove(lexiconRowKey(row));
    }
    return LexiconSelection(rows: next, anchorKey: anchorKey);
  }

  /// Οι πρώτες [n] με τη σειρά επιλογής — όσες φεύγουν σε μία αποστολή.
  List<Map<String, dynamic>> firstBatch(int n) =>
      rows.values.take(n).toList(growable: false);

  /// Όλες οι [page] επιλεγμένες: `true`· καμία: `false`· μερικές: `null`.
  bool? pageState(List<Map<String, dynamic>> page) {
    if (page.isEmpty) return false;
    final selected = page.where(contains).length;
    if (selected == 0) return false;
    return selected == page.length ? true : null;
  }

  LexiconSelection _withAnchor(String key) =>
      LexiconSelection(rows: rows, anchorKey: key);
}
