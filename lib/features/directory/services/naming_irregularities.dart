import '../../../core/utils/search_text_normalizer.dart';

/// Οι έλεγχοι του κανόνα «Παρατυπίες ονοματολογίας».
///
/// **Ένας διακόπτης, πολλοί έλεγχοι** (απόφαση Διευθυντή 22/10/2026): μικρές
/// παρατυπίες ονομάτων που δεν αξίζουν δικό τους διακόπτη η καθεμία.
///
/// Η [checks] είναι η **μοναδική απογραφή** τους: από αυτήν γράφεται η
/// εξήγηση του κανόνα στις Ρυθμίσεις. Νέος έλεγχος ⇒ μία γραμμή εκεί και η
/// συνάρτησή του εδώ· ένας έλεγχος που φεύγει, φεύγει κι από εκεί — αλλιώς η
/// εξήγηση θα υποσχόταν κάτι που δεν γίνεται.
///
/// Η σύγκριση αγνοεί τόνους και κεφαλαία: «ΓΙΩΡΓΟΣ» και «Γιώργος» είναι το
/// ίδιο όνομα.
abstract final class NamingIrregularities {
  /// Τι ελέγχει ο κανόνας, όπως το διαβάζει ο χρήστης στις Ρυθμίσεις.
  static const List<String> checks = [
    'Επώνυμο ίδιο με το όνομα (υπάλληλος)',
    'Ψευδώνυμο ίδιο με το όνομα ή με το επώνυμο (υπάλληλος)',
    'Η ίδια λέξη δύο φορές στο όνομα τμήματος, όπου κι αν βρίσκεται — '
        'π.χ. «Γραφείο Υλικού Υλικού». Άρθρα, «και», «σε», «για», «&» και '
        'μονά γράμματα δεν μετρούν',
  ];

  /// «Το επώνυμο είναι ίδιο με το όνομα» — ή `null`.
  static String? sameLastAndFirstName({
    required String lastName,
    required String firstName,
  }) {
    final last = _norm(lastName);
    if (last.isEmpty || last != _norm(firstName)) return null;
    return 'Το επώνυμο είναι ίδιο με το όνομα';
  }

  /// «Το ψευδώνυμο είναι ίδιο με το όνομα/επώνυμο» — ή `null`.
  static String? nicknameRepeatsName({
    required String nickname,
    required String firstName,
    required String lastName,
  }) {
    final nick = _norm(nickname);
    if (nick.isEmpty) return null;
    if (nick == _norm(firstName)) return 'Το ψευδώνυμο είναι ίδιο με το όνομα';
    if (nick == _norm(lastName)) {
      return 'Το ψευδώνυμο είναι ίδιο με το επώνυμο';
    }
    return null;
  }

  /// «Η λέξη «Υλικού» υπάρχει δύο φορές στο όνομα» — ή `null`.
  ///
  /// Μετρά οπουδήποτε μέσα στο όνομα, όχι μόνο σε διαδοχικές λέξεις (απόφαση
  /// 17/10). Η λέξη γράφεται όπως την έγραψε ο χρήστης την πρώτη φορά.
  static String? repeatedWordInDepartmentName(String name) {
    // Κλειδί → η λέξη όπως γράφτηκε πρώτη φορά, για το μήνυμα.
    final seen = <String, String>{};
    for (final match in _word.allMatches(name)) {
      final original = match.group(0)!;
      final key = _norm(original);
      // Μονό γράμμα ή ψηφίο — «Α», «Β», «1»: αρίθμηση, όχι λέξη.
      if (key.runes.length <= 1 || _connectives.contains(key)) continue;
      final first = seen.putIfAbsent(key, () => original);
      if (!identical(first, original)) {
        return 'Η λέξη «$first» υπάρχει δύο φορές στο όνομα';
      }
    }
    return null;
  }

  /// Λέξη = γράμματα και ψηφία· το «&» και τα σημεία στίξης δεν είναι λέξεις.
  static final RegExp _word = RegExp(r'[\p{L}\p{N}]+', unicode: true);

  /// Συνδετικές λέξεις που επαναλαμβάνονται θεμιτά — «Γραφείο του Διευθυντή
  /// του Νοσοκομείου» (απόφαση 22/10/2026): τα άρθρα, το «και», το «για» και
  /// το «σε» με τις συναιρέσεις του («στο», «στη»…). Γραμμένες ήδη
  /// κανονικοποιημένες (πεζά, χωρίς τόνους, «σ» αντί «ς»).
  static const Set<String> _connectives = {
    'ο', 'η', 'το', 'οι', 'τα', 'του', 'τησ', 'των', 'τον', 'την', 'τουσ', //
    'τισ', 'και', 'για', 'σε', 'στο', 'στη', 'στην', 'στον', 'στα', //
    'στουσ', 'στισ', 'στου', 'στησ', 'στων',
  };

  static String _norm(String value) =>
      SearchTextNormalizer.normalizeForSearch(value.trim());
}
