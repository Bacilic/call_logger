import '../utils/homoglyph_text_normalizer.dart';

/// Γιατί μια αλλαγή σε κοινή λίστα δεν μπορεί να εφαρμοστεί πάνω στη φρέσκια
/// τιμή της.
enum CatalogListChangeBlock {
  /// Το στοιχείο που πήγε να μετονομαστεί ή να σβηστεί δεν υπάρχει πια.
  targetGone,

  /// Το όνομα που πήγε να μπει υπάρχει ήδη.
  nameTaken,
}

/// Η αλλαγή αποφασίστηκε πάνω σε εικόνα που δεν ισχύει πια: κάποιος άλλος
/// άγγιξε **το ίδιο** στοιχείο στο μεταξύ. Τίποτα δεν γράφτηκε.
class CatalogListChangedException implements Exception {
  const CatalogListChangedException(this.block, this.name);

  final CatalogListChangeBlock block;

  /// Το στοιχείο που έλειπε, ή το όνομα που βρέθηκε πιασμένο — όπως είναι
  /// γραμμένο στη φρέσκια λίστα.
  final String name;

  /// Τι λέμε στον χρήστη. Η οθόνη ανανεώνει τη λίστα πριν το δείξει.
  String get userMessage => switch (block) {
    CatalogListChangeBlock.targetGone =>
      'Το «$name» δεν υπάρχει πια στη λίστα — κάποιος την άλλαξε στο '
          'μεταξύ. Η λίστα ανανεώθηκε· ελέγξτε την και δοκιμάστε ξανά.',
    CatalogListChangeBlock.nameTaken =>
      'Το «$name» υπάρχει ήδη στη λίστα — κάποιος το πρόσθεσε στο μεταξύ. '
          'Η λίστα ανανεώθηκε.',
  };

  @override
  String toString() => 'CatalogListChangedException($block, $name)';
}

/// Μία αλλαγή **ενός στοιχείου** σε κοινή λίστα ονομάτων (κτίρια, ομάδες).
///
/// **Γιατί αλλαγή και όχι έτοιμη λίστα:** η λίστα είναι κοινή για όλους τους
/// σταθμούς και η οθόνη κρατά εικόνα που μπορεί να έχει γεράσει. Όποιος γράφει
/// ολόκληρη τη λίστα από εκείνη την εικόνα σβήνει ό,τι πρόσθεσε ο συνάδελφος.
/// Η αλλαγή περιγράφει μόνο ό,τι έκανε ο χρήστης και εφαρμόζεται πάνω στην
/// τιμή που ισχύει **τη στιγμή της εγγραφής** — οι αλλαγές των άλλων μένουν.
///
/// Αν όμως ο άλλος άγγιξε το ίδιο στοιχείο, δεν υπάρχει σωστή συγχώνευση: η
/// [applyTo] πετά [CatalogListChangedException] και τίποτα δεν γράφεται.
sealed class CatalogListChange {
  const CatalogListChange();

  const factory CatalogListChange.add(String name) = _AddName;

  const factory CatalogListChange.rename({
    required String from,
    required String to,
  }) = _RenameName;

  const factory CatalogListChange.remove(String name) = _RemoveName;

  /// Η νέα λίστα. Καθαρή συνάρτηση: η εγγραφή μπορεί να την ξανατρέξει.
  List<String> applyTo(List<String> current);

  /// Ίδιος κανόνας «είναι το ίδιο όνομα» με τον κατάλογο: αγνοεί πεζά/κεφαλαία,
  /// τόνους και αλφάβητο.
  static String _key(String name) {
    final key = HomoglyphTextNormalizer.normalizeForComparison(name);
    return key.isEmpty ? name.trim() : key;
  }

  static String? _sameNameIn(
    Iterable<String> names,
    String candidate, {
    String? except,
  }) {
    final key = _key(candidate);
    for (final name in names) {
      if (name != except && _key(name) == key) return name;
    }
    return null;
  }
}

class _AddName extends CatalogListChange {
  const _AddName(this.name);

  final String name;

  @override
  List<String> applyTo(List<String> current) {
    final taken = CatalogListChange._sameNameIn(current, name);
    if (taken != null) {
      throw CatalogListChangedException(
        CatalogListChangeBlock.nameTaken,
        taken,
      );
    }
    return [...current, name];
  }
}

class _RenameName extends CatalogListChange {
  const _RenameName({required this.from, required this.to});

  final String from;
  final String to;

  @override
  List<String> applyTo(List<String> current) {
    if (!current.contains(from)) {
      throw CatalogListChangedException(
        CatalogListChangeBlock.targetGone,
        from,
      );
    }
    final taken = CatalogListChange._sameNameIn(current, to, except: from);
    if (taken != null) {
      throw CatalogListChangedException(
        CatalogListChangeBlock.nameTaken,
        taken,
      );
    }
    return [
      for (final name in current)
        if (name == from) to else name,
    ];
  }
}

class _RemoveName extends CatalogListChange {
  const _RemoveName(this.name);

  final String name;

  @override
  List<String> applyTo(List<String> current) {
    if (!current.contains(name)) {
      throw CatalogListChangedException(
        CatalogListChangeBlock.targetGone,
        name,
      );
    }
    return [
      for (final other in current)
        if (other != name) other,
    ];
  }
}
