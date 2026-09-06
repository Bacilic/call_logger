/// Utility για κανονικοποίηση και διαχωρισμό πλήρους ονόματος σε firstName / lastName.
/// Χρησιμοποιείται από UI και Domain· το Data Layer δέχεται ήδη διαχωρισμένα πεδία.
class NameParserUtility {
  NameParserUtility._();

  /// Χωρίζει ένα «Όνομα» που κουβαλά ψευδώνυμο σε παρένθεση.
  ///
  /// **Δύο σχήματα υπάρχουν στα δεδομένα**, και τα δύο θεμιτά όσο δεν υπήρχε
  /// πεδίο ψευδωνύμου:
  /// - «(Γωγώ) Γεωργία» — η παρένθεση κρατά το ψευδώνυμο
  /// - «Βίκυ (Βασιλική)» — η παρένθεση κρατά το επίσημο όνομα
  ///
  /// Και στα δύο το **ψευδώνυμο γράφεται πρώτο** — έτσι το έγραψε ο χρήστης
  /// και στις τέσσερις εγγραφές της βάσης, γιατί έτσι τον φωνάζουν. Αυτή η
  /// υπόθεση γίνεται ρητή στο μήνυμα του ευρήματος: ο χρήστης βλέπει τι θα
  /// μπει πού πριν αποθηκεύσει, και ανταλλάσσει αν χρειάζεται.
  ///
  /// Επιστρέφει `null` όταν δεν υπάρχει τέτοιο σχήμα, ώστε ο καλών να μη
  /// χρειάζεται δεύτερο έλεγχο.
  ///
  /// **Είναι η ΜΟΝΗ υλοποίηση του διαχωρισμού.** Τη χρησιμοποιούν και ο
  /// κανόνας επικύρωσης που εντοπίζει το σχήμα, και η φόρμα που προτείνει τη
  /// μεταφορά: αν αποκλίνουν, ο χρήστης θα έβλεπε άλλο εύρημα και άλλη
  /// πρόταση.
  ///
  /// Δεν αγγίζει παρενθέσεις στη μέση ή στο τέλος — μόνο το σχήμα «στην αρχή,
  /// με κείμενο μετά», που είναι ο τρόπος που γράφτηκαν τα ψευδώνυμα όσο δεν
  /// υπήρχε πεδίο για αυτά.
  static ({String nickname, String name})? splitNicknameFromName(String value) {
    final v = value.trim();

    // Σχήμα Α — «(Γωγώ) Γεωργία»: η παρένθεση κρατά το ψευδώνυμο.
    if (v.startsWith('(')) {
      final close = v.indexOf(')');
      if (close <= 1) return null;
      final nickname = v.substring(1, close).trim();
      final rest = v.substring(close + 1).trim();
      if (nickname.isEmpty || rest.isEmpty) return null;
      return (nickname: nickname, name: rest);
    }

    // Σχήμα Β — «Βίκυ (Βασιλική)»: η παρένθεση κρατά το επίσημο όνομα.
    if (v.endsWith(')')) {
      final open = v.lastIndexOf(' (');
      if (open <= 0) return null;
      final nickname = v.substring(0, open).trim();
      final formal = v.substring(open + 2, v.length - 1).trim();
      if (nickname.isEmpty || formal.isEmpty) return null;
      return (nickname: nickname, name: formal);
    }

    return null;
  }

  /// Αφαιρεί ό,τι προσθέτει η **εμφάνιση** γύρω από το όνομα, ώστε να μείνει
  /// σκέτο «Όνομα Επώνυμο» για parse, ταύτιση και δημιουργία εγγραφής.
  ///
  /// Δύο στολίδια μπαίνουν στα κείμενα των λιστών:
  /// - το τμήμα στο τέλος — «Γεωργία Παπαγεωργίου (Ακτινολογικό)»
  /// - το ψευδώνυμο στην αρχή — «(Γωγώ) Γεωργία Παπαγεωργίου»
  ///
  /// **Είναι το ΜΟΝΟ σημείο που τα ξεχωρίζει.** Χωρίς την αρχική παρένθεση, ο
  /// νέος καλών που δημιουργείται από τη φόρμα κλήσης θα έπαιρνε το «(Γωγώ)»
  /// ως όνομα, και η ταύτιση με υπάρχοντα υπάλληλο θα αποτύγχανε σιωπηλά.
  static String stripDisplayDecorations(String value) {
    var v = value.trim();

    // Ψευδώνυμο στην αρχή: κόβεται μόνο όταν η παρένθεση ΚΛΕΙΝΕΙ και μένει
    // κείμενο μετά — αλλιώς ένα όνομα που ξεκινά θεμιτά με παρένθεση θα
    // εξαφανιζόταν ολόκληρο.
    if (v.startsWith('(')) {
      final close = v.indexOf(')');
      if (close > 0 && close < v.length - 1) {
        final rest = v.substring(close + 1).trim();
        if (rest.isNotEmpty) v = rest;
      }
    }

    // Το τμήμα κλείνει ΠΑΝΤΑ το κείμενο, οπότε κόβεται από το τέλος. Με
    // κόψιμο στην πρώτη « (» το «Βίκυ (Βασιλική) Κίτσιου (Γραφείο)» θα
    // κατέληγε σκέτο «Βίκυ» — χαμένο επώνυμο, και νέος καλών χωρίς αυτό.
    if (!v.endsWith(')')) return v;
    final open = v.lastIndexOf(' (');
    if (open <= 0) return v;
    return v.substring(0, open).trim();
  }

  /// Κανονικοποιεί το [fullName] (trim, πολλαπλά κενά → ένα) και το χωρίζει σε όνομα/επώνυμο.
  ///
  /// Heuristics:
  /// - Κενό → `('', '')`
  /// - 1 λέξη → `(λέξη, '')`
  /// - 2+ λέξεις → πρώτη λέξη = [firstName], όλες οι υπόλοιπες ενωμένες με κενό = [lastName]
  static ({String firstName, String lastName}) parse(String fullName) {
    final normalized = fullName.trim().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) {
      return (firstName: '', lastName: '');
    }
    final parts = normalized.split(' ');
    if (parts.length == 1) {
      return (firstName: parts.single, lastName: '');
    }
    return (firstName: parts.first, lastName: parts.sublist(1).join(' '));
  }

  /// Επιστρέφει όλες τις εύλογες ερμηνείες διάταξης ονόματος/επωνύμου.
  ///
  /// - Μονή λέξη → ταιριάζει είτε ως όνομα είτε ως επώνυμο.
  /// - Δύο+ λέξεις → πρώτη-υπόλοιπες ΚΑΙ τελευταία-προηγούμενες (αν διαφέρουν).
  static List<({String firstName, String lastName})> parseBothOrders(
    String fullName,
  ) {
    final normalized = stripDisplayDecorations(
      fullName,
    ).trim().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return const [];

    final commaIndex = normalized.indexOf(',');
    if (commaIndex > 0) {
      final lastName = normalized.substring(0, commaIndex).trim();
      final firstName = normalized.substring(commaIndex + 1).trim();
      if (lastName.isNotEmpty && firstName.isNotEmpty) {
        return [(firstName: firstName, lastName: lastName)];
      }
    }

    final parts = normalized.split(' ');
    if (parts.length == 1) {
      final word = parts.single;
      return [(firstName: word, lastName: ''), (firstName: '', lastName: word)];
    }

    final interpretations = <({String firstName, String lastName})>{
      (firstName: parts.first, lastName: parts.sublist(1).join(' ')),
      (
        firstName: parts.last,
        lastName: parts.sublist(0, parts.length - 1).join(' '),
      ),
    };
    return interpretations.toList(growable: false);
  }
}
