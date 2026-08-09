/// Πόσο καλά μια ωμή τιμή ταιριάζει με το **όνομα** μιας εγγραφής αναφοράς.
///
/// Το σενάριο: εξοπλισμός 5002, πεδίο συμβόλαιο, ωμή τιμή «30236». Η σύμβαση
/// υπάρχει — id 231, όνομα «30236 18/12/2024» — αλλά ο οδηγός έψαχνε το
/// «30236» μόνο ως **αναγνωριστικό** και βαθμολογούσε υποψηφίους από
/// συμφραζόμενα («χρησιμοποιείται στο ίδιο γραφείο»). Η σωστή σύμβαση δεν
/// εμφανιζόταν καθόλου και ο χρήστης θα δημιουργούσε διπλοεγγραφή.
///
/// Η ταύτιση ονόματος είναι **πολύ ισχυρότερη ένδειξη** από τα συμφραζόμενα:
/// το ότι δύο μηχανήματα κάθονται στο ίδιο γραφείο δεν λέει τίποτα για τη
/// σύμβασή τους, ενώ ένα όνομα που ξεκινά με τον ίδιο αριθμό πρωτοκόλλου
/// σχεδόν πάντα είναι το ίδιο έγγραφο.
library;

import '../../utils/text_similarity.dart';

/// Πόσο σίγουρη είναι η ταύτιση με το όνομα.
enum LampNameMatchStrength {
  /// Το όνομα είναι ακριβώς η τιμή.
  exact,

  /// Το όνομα **ξεκινά** με την τιμή ως ολόκληρη λέξη: «30236 18/12/2024».
  prefix,

  /// Η τιμή υπάρχει ως ολόκληρη λέξη κάπου μέσα στο όνομα.
  word,
}

extension LampNameMatchScore on LampNameMatchStrength {
  /// Βάρος στη βαθμολογία υποψηφίου. Η ισχυρή ταύτιση πρέπει να ξεπερνά
  /// άνετα το άθροισμα των ενδείξεων συμφραζομένων (55 + 25 + χρήση).
  int get score => switch (this) {
    LampNameMatchStrength.exact => 120,
    LampNameMatchStrength.prefix => 100,
    LampNameMatchStrength.word => 45,
  };

  String get reason => switch (this) {
    LampNameMatchStrength.exact => 'Η τιμή είναι το όνομα της εγγραφής.',
    LampNameMatchStrength.prefix =>
      'Το όνομα της εγγραφής ξεκινά με αυτή την τιμή.',
    LampNameMatchStrength.word => 'Η τιμή εμφανίζεται μέσα στο όνομα.',
  };
}

/// Ελέγχει αν η [rawValue] ταιριάζει με το [name], και πόσο δυνατά.
/// Επιστρέφει `null` όταν δεν ταιριάζει.
///
/// Η σύγκριση γίνεται σε **ολόκληρες λέξεις**: το «236» δεν ταιριάζει με το
/// «30236 18/12/2024», αλλιώς κάθε κοντός αριθμός θα κολλούσε σε τυχαία
/// συμβόλαια.
LampNameMatchStrength? lampReferenceNameMatch({
  required String rawValue,
  required String? name,
}) {
  final needle = TextSimilarity.normalize(rawValue);
  final haystack = TextSimilarity.normalize(name ?? '');
  if (needle.isEmpty || haystack.isEmpty) return null;

  if (needle == haystack) return LampNameMatchStrength.exact;

  final words = haystack.split(' ');
  if (words.isEmpty) return null;
  if (words.first == needle) return LampNameMatchStrength.prefix;
  if (words.contains(needle)) return LampNameMatchStrength.word;
  return null;
}
