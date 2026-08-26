import '../../../core/utils/search_text_normalizer.dart';

/// Πρόταση «μήπως ψάχνετε χειριστή;» για λέξη της ελεύθερης αναζήτησης.
class OperatorKeywordSuggestion {
  const OperatorKeywordSuggestion({
    required this.operatorName,
    required this.matchedWord,
  });

  /// Το όνομα όπως εμφανίζεται στο φίλτρο «Χειριστής».
  final String operatorName;

  /// Η λέξη όπως την πληκτρολόγησε ο χρήστης — αυτή αφαιρείται από το
  /// κείμενο όταν η πρόταση γίνει δεκτή.
  final String matchedWord;
}

/// Ποιοι χειριστές ταιριάζουν με λέξεις της ελεύθερης αναζήτησης.
///
/// Το «ποιος το έκανε» δεν συμμετέχει στο ευρετήριο λέξεων-κλειδιών — είναι
/// φίλτρο με κλειστή λίστα, όπως το `from:` του Gmail· αλλιώς θα ανακατευόταν
/// αθεράπευτα με το «σε ποιον έγινε». Όποιος όμως πληκτρολογεί όνομα χειριστή
/// στο ελεύθερο κείμενο δεν το ξέρει: η αναζήτηση δουλεύει σωστά και **μοιάζει**
/// σπασμένη. Η πρόταση τον πιάνει ακριβώς εκείνη τη στιγμή και δείχνει το φίλτρο.
///
/// Ταίριασμα: λέξη με 3+ χαρακτήρες που είναι πρόθεμα λέξης του ονόματος,
/// αδιάφορο σε τόνους και πεζά-κεφαλαία — το «βασι» βρίσκει τον «Βασίλη».
/// Ο ήδη επιλεγμένος χειριστής ([alreadySelected]) δεν προτείνεται ξανά.
List<OperatorKeywordSuggestion> operatorKeywordSuggestions(
  String keyword,
  List<String> operatorNames, {
  String? alreadySelected,
}) {
  final words = [
    for (final word in keyword.trim().split(RegExp(r'\s+')))
      if (word.length >= 3) word,
  ];
  if (words.isEmpty) return const [];

  final suggestions = <OperatorKeywordSuggestion>[];
  for (final name in operatorNames) {
    if (name == alreadySelected) continue;
    final nameWords = [
      for (final part in SearchTextNormalizer.normalizeForSearch(
        name,
      ).split(RegExp(r'\s+')))
        if (part.isNotEmpty) part,
    ];
    if (nameWords.isEmpty) continue;
    for (final word in words) {
      final needle = SearchTextNormalizer.normalizeForSearch(word);
      if (needle.length < 3) continue;
      if (nameWords.any((part) => part.startsWith(needle))) {
        suggestions.add(
          OperatorKeywordSuggestion(operatorName: name, matchedWord: word),
        );
        break;
      }
    }
  }
  return suggestions;
}

/// Αφαιρεί μία λέξη από το ελεύθερο κείμενο αναζήτησης.
///
/// Όταν η πρόταση γίνει δεκτή, η λέξη έγινε φίλτρο — αν έμενε και στο κείμενο,
/// θα συνέχιζε να κόβει τα αποτελέσματα ως λέξη-κλειδί και η τομή θα έβγαζε
/// σχεδόν πάντα κενή λίστα.
String keywordWithoutWord(String keyword, String word) {
  final remaining = <String>[];
  var removed = false;
  for (final part in keyword.trim().split(RegExp(r'\s+'))) {
    if (!removed && part == word) {
      removed = true;
      continue;
    }
    if (part.isNotEmpty) remaining.add(part);
  }
  return remaining.join(' ');
}
