import 'dart:convert';

/// Η στοίχιση κάθε αρχείου JSON του έργου.
const JsonEncoder _prettyEncoder = JsonEncoder.withIndent('  ');

/// Κωδικοποιεί [value] ως **αρχείο** JSON: στοιχισμένο και με τελική νέα
/// γραμμή.
///
/// Ο κωδικοποιητής του SDK δεν κλείνει με `\n`, οπότε κάθε σημείο που έγραφε
/// μόνο του άφηνε αρχείο χωρίς κατάληξη γραμμής. Στο `assets/changelog.json`
/// αυτό φαινόταν: το git σήμαινε την τελευταία γραμμή ως αλλαγμένη σε κάθε
/// δημοσίευση, θορυβώντας τη σύγκριση εκδόσεων χωρίς να έχει αλλάξει τίποτα.
///
/// Γράφεται εδώ μία φορά ώστε κανένα μελλοντικό σημείο γραφής να μην μπορεί
/// να το ξεχάσει. Για JSON που πάει σε **οθόνη ή log** — όχι σε αρχείο — η
/// τελική γραμμή δεν έχει νόημα: εκεί χρησιμοποιείται σκέτος κωδικοποιητής.
String encodeJsonDocument(Object? value) =>
    '${_prettyEncoder.convert(value)}\n';

/// Τα κλειδιά που εμφανίζονται **δεύτερη φορά** μέσα στο ίδιο αντικείμενο,
/// με τη γραμμή όπου εμφανίστηκαν.
///
/// **Γιατί χρειάζεται:** ο αποκωδικοποιητής του SDK δέχεται σιωπηλά το διπλό
/// κλειδί και κρατά το δεύτερο — το πρώτο σβήνεται χωρίς καμία ένδειξη. Στο
/// `changelog.json` αυτό σημαίνει χαμένες εγγραφές ιστορικού: ένα δεύτερο
/// `"fixed"` στην ίδια κάρτα εξαφανίζει όλες τις διορθώσεις του πρώτου.
///
/// Προϋποθέτει έγκυρο JSON (ελέγχεται πρώτα με `jsonDecode`)· εδώ μετράμε
/// μόνο κλειδιά, χωρίς δεύτερη πλήρη ανάλυση.
List<({String key, int line})> findDuplicateJsonKeys(String source) {
  final duplicates = <({String key, int line})>[];
  // Ένα σύνολο κλειδιών ανά ανοιχτό αντικείμενο· `null` για πίνακα.
  final open = <Set<String>?>[];
  var expectKey = false;
  var line = 1;
  var i = 0;
  while (i < source.length) {
    final c = source[i];
    if (c == '\n') {
      line++;
    } else if (c == '"') {
      final raw = StringBuffer();
      i++;
      while (i < source.length && source[i] != '"') {
        if (source[i] == r'\' && i + 1 < source.length) {
          raw.write(source[i]);
          i++;
        }
        raw.write(source[i]);
        i++;
      }
      if (expectKey) {
        final key = jsonDecode('"$raw"') as String;
        if (!open.last!.add(key)) duplicates.add((key: key, line: line));
        expectKey = false;
      }
    } else if (c == '{') {
      open.add(<String>{});
      expectKey = true;
    } else if (c == '[') {
      open.add(null);
      expectKey = false;
    } else if (c == '}' || c == ']') {
      if (open.isNotEmpty) open.removeLast();
      expectKey = false;
    } else if (c == ',') {
      expectKey = open.isNotEmpty && open.last != null;
    }
    i++;
  }
  return duplicates;
}
