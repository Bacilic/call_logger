import '../utils/conflict_actor_text.dart';

/// Κάποιος άλλος άλλαξε μια ρυθμιζόμενη λίστα όσο εγώ την επεξεργαζόμουν.
///
/// Οι λίστες με κόμματα (τύποι εξοπλισμού, κατηγορίες λεξικού) ζουν σε **ένα**
/// κλειδί και γράφονται ολόκληρες: ο χρήστης επεξεργάζεται ελεύθερο κείμενο,
/// οπότε η εφαρμογή δεν μπορεί να ξέρει αν ένα στοιχείο που λείπει σβήστηκε
/// επίτηδες ή απλώς δεν το είδε ποτέ η οθόνη μου. Γι' αυτό εδώ δεν γίνεται
/// σιωπηλή συγχώνευση — ρωτιέται ο άνθρωπος (απόφαση Διευθυντή 25/08/2026).
class SettingsListConflict {
  const SettingsListConflict({
    required this.expected,
    required this.fresh,
    required this.attempted,
  });

  /// Η λίστα όπως τη φόρτωσε ο διάλογος — η αφετηρία.
  final String expected;

  /// Η λίστα όπως είναι **τώρα** αποθηκευμένη.
  final String fresh;

  /// Η λίστα που πήγα να γράψω.
  final String attempted;

  /// Τα στοιχεία μιας λίστας με κόμματα, καθαρά και χωρίς κενά.
  static List<String> items(String csv) => csv
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();

  List<String> get _expectedItems => items(expected);
  List<String> get _freshItems => items(fresh);
  List<String> get _attemptedItems => items(attempted);

  /// Τι πρόσθεσε ο άλλος μετά την ανάγνωσή μου.
  List<String> get addedByOther =>
      _freshItems.where((item) => !_expectedItems.contains(item)).toList();

  /// Τι αφαίρεσε ο άλλος μετά την ανάγνωσή μου.
  List<String> get removedByOther =>
      _expectedItems.where((item) => !_freshItems.contains(item)).toList();

  bool get hasChanges => fresh.trim() != expected.trim();

  /// Τι άγγιξε ο άλλος, σε γραμμές έτοιμες για ανάγνωση.
  ///
  /// Ίδια στοιχεία με άλλη σειρά είναι κι αυτό αλλαγή: η σειρά της λίστας
  /// καθορίζει τη σειρά του μενού που βλέπει καθημερινά ο χρήστης.
  List<String> get changeLines {
    final lines = <String>[
      for (final item in addedByOther) 'Προστέθηκε: $item',
      for (final item in removedByOther) 'Αφαιρέθηκε: $item',
    ];
    if (lines.isEmpty && hasChanges) lines.add('Άλλαξε η σειρά της λίστας');
    return lines;
  }

  /// Στοιχεία που πρόσθεσε ο άλλος και **δεν** υπάρχουν στη δική μου λίστα.
  List<String> get lostIfIOverwrite =>
      addedByOther.where((item) => !_attemptedItems.contains(item)).toList();

  /// Στοιχεία που έσβησε ο άλλος και η δική μου λίστα θα τα **επαναφέρει**.
  List<String> get revivedIfIOverwrite =>
      removedByOther.where((item) => _attemptedItems.contains(item)).toList();

  /// «Κάποιος άλλος άλλαξε αυτή τη λίστα στις 13:10.»
  ///
  /// Οι ρυθμίσεις δεν περνούν από το Ιστορικό, οπότε το όνομα σπάνια είναι
  /// γνωστό — η πρόταση μένει σωστή και χωρίς αυτό.
  String headline({String? changedBy, DateTime? changedAt, DateTime? now}) {
    final moment = now ?? DateTime.now();
    return '${conflictActorName(changedBy)} άλλαξε αυτή τη λίστα'
        '${conflictMomentSuffix(changedAt, now: moment)}.';
  }

  /// Τι χάνεται αν επιμείνω στη δική μου λίστα.
  String get overwriteWarning {
    String quoted(List<String> list) => list.map((i) => '«$i»').join(', ');
    final parts = <String>[
      if (lostIfIOverwrite.isNotEmpty) 'θα χαθεί ${quoted(lostIfIOverwrite)}',
      if (revivedIfIOverwrite.isNotEmpty)
        'θα επανέλθει ${quoted(revivedIfIOverwrite)}',
    ];
    if (parts.isEmpty) {
      return 'Αν κρατήσετε τη δική σας λίστα, η ξένη αλλαγή θα αντικατασταθεί.';
    }
    return 'Αν κρατήσετε τη δική σας λίστα, ${parts.join(' και ')}.';
  }
}

/// Πετάγεται **πριν** γραφτεί τίποτα, όταν η λίστα άλλαξε στο μεταξύ.
class SettingsListStaleException implements Exception {
  const SettingsListStaleException(this.conflict);

  final SettingsListConflict conflict;

  @override
  String toString() => 'Η λίστα άλλαξε από άλλον χρήστη μετά την ανάγνωσή της.';
}
