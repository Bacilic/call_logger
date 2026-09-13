/// Εντοπισμός αλλοιωμένων χαρακτήρων σε κείμενο.
///
/// **Το πρόβλημα:** το ελληνικό «Ο» και το λατινικό «O» μοιάζουν ολόιδια στην
/// οθόνη, αλλά για τον υπολογιστή είναι δύο διαφορετικοί χαρακτήρες. Μια λέξη
/// που τους ανακατεύει δεν βρίσκεται ποτέ στην αναζήτηση, δεν ταιριάζει με τη
/// δίδυμή της, και κανείς δεν καταλαβαίνει γιατί. Το ίδιο ισχύει για τον
/// χαλασμένο χαρακτήρα που άφησε πίσω της μια παλιά μετατροπή αρχείου, εκεί
/// όπου έπρεπε να υπάρχει κεφαλαίο άλφα με τόνο.
///
/// **Τι ΔΕΝ πιάνει, επίτηδες:** γράμματα μαζί με ψηφία. Οι σειριακοί αριθμοί,
/// τα ονόματα μοντέλων και τα τεχνικά χαρακτηριστικά («133MHz») είναι γεμάτα
/// από αυτά, και είναι όλα θεμιτά — πάνω από εννέα χιλιάδες περιπτώσεις στη
/// Λάμπα. Το ψηφίο μετρά μόνο όταν βρίσκεται **ανάμεσα σε ελληνικά** γράμματα,
/// που είναι σπάνιο και σχεδόν πάντα λάθος πληκτρολογίου.
library;

/// Τι είδους αλλοίωση βρέθηκε.
enum MixedScriptKind {
  /// Ελληνικά και λατινικά γράμματα κολλητά μέσα στην ίδια λέξη.
  mixedAlphabets,

  /// Χαρακτήρας-σκουπίδι δίπλα σε γράμμα — τυπικά ο τροποποιητής αποστρόφου
  /// στη θέση του κεφαλαίου άλφα με τόνο.
  brokenCharacter,

  /// Ψηφίο ανάμεσα σε ελληνικά γράμματα.
  digitInsideGreekWord,
}

/// Μία ύποπτη λέξη μέσα σε ένα πεδίο.
class MixedScriptFinding {
  const MixedScriptFinding({
    required this.kind,
    required this.word,
    this.suggestion,
  });

  final MixedScriptKind kind;

  /// Η λέξη όπως είναι αποθηκευμένη.
  final String word;

  /// Πώς θα έπρεπε να γράφεται. `null` όταν ο κανόνας δεν μπορεί να
  /// αποφασίσει με βεβαιότητα — τότε η διόρθωση γίνεται με το χέρι.
  final String? suggestion;

  bool get hasSuggestion => suggestion != null;
}

/// Οι δύο όψεις του ίδιου γράμματος: ελληνικό προς λατινικό.
///
/// Μόνο όσα ζεύγη είναι **οπτικά ταυτόσημα**. Το «η» και το «n» μοιάζουν μόνο
/// σε ορισμένες γραμματοσειρές, οπότε μένουν έξω: μια λάθος μεταγραφή εκεί θα
/// κατέστρεφε ελληνικές λέξεις αντί να τις διορθώσει.
const Map<String, String> _greekToLatin = {
  'Α': 'A', 'Β': 'B', 'Ε': 'E', 'Ζ': 'Z', 'Η': 'H', 'Ι': 'I', 'Κ': 'K',
  'Μ': 'M', 'Ν': 'N', 'Ο': 'O', 'Ρ': 'P', 'Τ': 'T', 'Υ': 'Y', 'Χ': 'X',
  'α': 'a', 'β': 'b', 'ε': 'e', 'ι': 'i', 'κ': 'k', 'ο': 'o', 'ρ': 'p',
  'τ': 't', 'υ': 'u', 'χ': 'x',
};

/// Ο αντίστροφος πίνακας, φτιαγμένος από τον πρώτο ώστε να μην μπορούν να
/// αποκλίνουν: ένα ζεύγος που προστίθεται εκεί ισχύει αυτόματα και εδώ.
final Map<String, String> _latinToGreek = {
  for (final entry in _greekToLatin.entries) entry.value: entry.key,
};

/// Χαρακτήρες που δεν έχουν καμία δουλειά κολλητά σε γράμμα.
///
/// Ο τροποποιητής αποστρόφου (U+02BC) είναι ο ένοχος της παλιάς εξαγωγής:
/// κάθε κεφαλαίο άλφα με τόνο έγινε αυτός. Μαζί του μπαίνουν οι γείτονές του
/// και ο χαρακτήρας αντικατάστασης, που σημαίνει «εδώ χάθηκε κάτι».
///
/// Γράφονται όλοι ως κωδικοί: αρχείο πηγής που κουβαλά τέτοιον χαρακτήρα
/// αυτούσιο είναι ακριβώς το πρόβλημα που ψάχνει αυτός ο κώδικας.
const String _brokenCharacters =
    // Τροποποιητές τόνου και πνεύματος (U+02B9 έως U+02BF).
    '\u02B9\u02BA\u02BB\u02BC\u02BD\u02BE\u02BF'
    // Ελληνικά αριθμητικά σημεία και ο σκέτος τόνος.
    '\u0374\u0375\u00B4'
    // Ο χαρακτήρας αντικατάστασης.
    '\uFFFD';

/// Με τι αντικαθίσταται ο χαλασμένος χαρακτήρας.
///
/// Και τα πέντε παραδείγματα της Λάμπας («Άννα», «Άγγελος», «Άδειες», «Άνω»,
/// «Άσσου») ήταν κεφαλαίο άλφα με τόνο, οπότε αυτή είναι η πρόταση. Παραμένει
/// πρόταση προς έγκριση: αν κάποτε εμφανιστεί άλλο γράμμα, ο χρήστης το
/// διορθώνει με το χέρι αντί να το δεχτεί στα τυφλά.
const String kBrokenCharacterReplacement = 'Ά';

final RegExp _greekLetter = RegExp(r'[Ͱ-Ͽἀ-῿]');
final RegExp _latinLetter = RegExp(r'[A-Za-z]');
final RegExp _digit = RegExp(r'[0-9]');

/// Τα όρια της λέξης: ό,τι δεν είναι κενό ή σημείο στίξης που χωρίζει.
///
/// Η παύλα και η τελεία χωρίζουν, ώστε το «e-Ραντεβού» και το «mac.παλιάς» να
/// διαβάζονται ως δύο λέξεις και να μη σημαίνονται άδικα.
final RegExp _wordPattern = RegExp(r'[^\s,;/()\[\]\-_.:+*&#|«»"]+');

/// Γειτνίαση ελληνικού και λατινικού γράμματος χωρίς τίποτα ενδιάμεσα.
final RegExp _adjacentMixed = RegExp(
  r'[Ͱ-Ͽἀ-῿][A-Za-z]|[A-Za-z][Ͱ-Ͽἀ-῿]',
);

final RegExp _digitBetweenGreek = RegExp(
  r'[Ͱ-Ͽἀ-῿][0-9]+[Ͱ-Ͽἀ-῿]',
);

/// Κάτω από αυτό το μήκος η λέξη δεν κρίνεται: σε δύο χαρακτήρες δεν υπάρχει
/// αρκετό συμφραζόμενο για να πει κανείς ποιο αλφάβητο εννοούσε ο γράφων.
const int kMixedScriptMinWordLength = 2;

/// Βρίσκει τις ύποπτες λέξεις μέσα σε ένα πεδίο.
///
/// Επιστρέφει κενή λίστα για κείμενο που δεν έχει τίποτα — που είναι η
/// συντριπτική πλειοψηφία.
List<MixedScriptFinding> findMixedScriptWords(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return const [];

  final out = <MixedScriptFinding>[];
  for (final match in _wordPattern.allMatches(text)) {
    final word = match.group(0)!;
    if (word.length < kMixedScriptMinWordLength) continue;

    if (_hasBrokenCharacterNextToLetter(word)) {
      out.add(
        MixedScriptFinding(
          kind: MixedScriptKind.brokenCharacter,
          word: word,
          suggestion: _repairBrokenCharacters(word),
        ),
      );
      continue;
    }

    if (_adjacentMixed.hasMatch(word)) {
      out.add(
        MixedScriptFinding(
          kind: MixedScriptKind.mixedAlphabets,
          word: word,
          suggestion: _unifyAlphabet(word),
        ),
      );
      continue;
    }

    if (_digitBetweenGreek.hasMatch(word)) {
      out.add(
        MixedScriptFinding(
          kind: MixedScriptKind.digitInsideGreekWord,
          word: word,
          // Εδώ η πρόταση είναι «όλα λατινικά»: τέτοιες λέξεις είναι σχεδόν
          // πάντα κωδικοί που γράφτηκαν με ελληνικό πληκτρολόγιο. Δίνεται
          // μόνο όταν ΚΑΘΕ γράμμα έχει λατινικό δίδυμο — αλλιώς η μεταγραφή
          // θα διέλυε μια κανονική ελληνική λέξη.
          suggestion: _toLatinIfFullyMappable(word),
        ),
      );
    }
  }
  return out;
}

/// Εφαρμόζει μια πρόταση πάνω στο **ολόκληρο** πεδίο, αντικαθιστώντας μόνο τη
/// συγκεκριμένη λέξη.
///
/// Δουλεύει σε όρια λέξης, ώστε η διόρθωση του «ΜΟΤΟΡ» να μην αγγίξει το
/// «ΜΟΤΟΡΑΚΙ» που τυχαίνει να είναι δίπλα.
String applyMixedScriptSuggestion(
  String fieldValue,
  String word,
  String suggestion,
) {
  final buffer = StringBuffer();
  var cursor = 0;
  for (final match in _wordPattern.allMatches(fieldValue)) {
    if (match.group(0) != word) continue;
    buffer.write(fieldValue.substring(cursor, match.start));
    buffer.write(suggestion);
    cursor = match.end;
  }
  buffer.write(fieldValue.substring(cursor));
  return buffer.toString();
}

bool _hasBrokenCharacterNextToLetter(String word) {
  for (var i = 0; i < word.length; i++) {
    if (!_brokenCharacters.contains(word[i])) continue;
    final before = i > 0 ? word[i - 1] : '';
    final after = i + 1 < word.length ? word[i + 1] : '';
    if (_isLetter(before) || _isLetter(after)) return true;
  }
  return false;
}

bool _isLetter(String ch) =>
    ch.isNotEmpty && (_greekLetter.hasMatch(ch) || _latinLetter.hasMatch(ch));

String _repairBrokenCharacters(String word) {
  final buffer = StringBuffer();
  for (var i = 0; i < word.length; i++) {
    final ch = word[i];
    if (!_brokenCharacters.contains(ch)) {
      buffer.write(ch);
      continue;
    }
    final before = i > 0 ? word[i - 1] : '';
    final after = i + 1 < word.length ? word[i + 1] : '';
    buffer.write(
      _isLetter(before) || _isLetter(after) ? kBrokenCharacterReplacement : ch,
    );
  }
  return buffer.toString();
}

/// Φέρνει όλη τη λέξη σε ένα αλφάβητο.
///
/// **Πρώτα κρίνει τι είναι εφικτό, μετά τι είναι πιθανό.** Μια λέξη μπορεί να
/// γραφτεί σε ένα αλφάβητο μόνο αν κάθε γράμμα της έχει εκεί οπτικό δίδυμο:
/// το «Ηz» δεν γίνεται ποτέ ελληνικό, γιατί το «z» δεν έχει ελληνική όψη, άρα
/// ήταν εξαρχής λατινικό και γίνεται «Hz». Όταν είναι εφικτά και τα δύο,
/// αποφασίζει η πλειοψηφία των γραμμάτων: ο γράφων ήθελε ένα αλφάβητο και του
/// ξέφυγαν λίγοι χαρακτήρες από το άλλο.
///
/// Επιστρέφει `null` όταν δεν είναι εφικτό κανένα αλφάβητο, ή όταν είναι και
/// τα δύο με ισοπαλία γραμμάτων. Τότε κρίνει ο άνθρωπος, αντί να μαντέψει η
/// εφαρμογή.
String? _unifyAlphabet(String word) {
  final greek = _greekLetter.allMatches(word).length;
  final latin = _latinLetter.allMatches(word).length;
  if (greek == 0 || latin == 0) return null;

  final asGreek = _transliterate(word, _latinLetter, _latinToGreek);
  final asLatin = _transliterate(word, _greekLetter, _greekToLatin);

  if (asGreek != null && asLatin == null) return asGreek;
  if (asLatin != null && asGreek == null) return asLatin;
  if (asGreek == null && asLatin == null) return null;
  if (greek == latin) return null;
  return greek > latin ? asGreek : asLatin;
}

/// Μεταγράφει κάθε γράμμα του [from] μέσω του [table].
///
/// `null` όταν έστω ένα γράμμα δεν έχει δίδυμο: τότε η λέξη δεν ανήκει σε
/// αυτό το αλφάβητο και η μεταγραφή θα την κατέστρεφε.
String? _transliterate(String word, RegExp from, Map<String, String> table) {
  final buffer = StringBuffer();
  for (final ch in word.split('')) {
    if (!from.hasMatch(ch)) {
      buffer.write(ch);
      continue;
    }
    final mapped = table[ch];
    if (mapped == null) return null;
    buffer.write(mapped);
  }
  final result = buffer.toString();
  return result == word ? null : result;
}

String? _toLatinIfFullyMappable(String word) {
  final buffer = StringBuffer();
  for (final ch in word.split('')) {
    if (!_greekLetter.hasMatch(ch)) {
      buffer.write(ch);
      continue;
    }
    final mapped = _greekToLatin[ch];
    if (mapped == null) return null;
    buffer.write(mapped);
  }
  final result = buffer.toString();
  if (result == word) return null;
  // Χωρίς ψηφίο δεν υπάρχει λόγος να γίνει κωδικός: μια καθαρά ελληνική λέξη
  // δεν έφτασε ποτέ εδώ, αλλά ο φρουρός κρατά τον κανόνα ρητό.
  return _digit.hasMatch(word) ? result : null;
}
