/// Ταύτιση ονομάτων υπαλλήλων που διαφέρουν σε λίγα γράμματα.
///
/// Το σενάριο που τη γέννησε: η ωμή τιμή λέει «Μαλατέστα Καλλή» ενώ στη βάση
/// ο ίδιος άνθρωπος είναι «Μαλατέστα Καλή». Η ταύτιση με κλειδί ταυτότητας
/// απαιτεί ισότητα γράμμα προς γράμμα, δεν βρίσκει τίποτα, και ο οδηγός
/// προτείνει **νέο** υπάλληλο — δηλαδή διπλοεγγραφή δίπλα σε υπάρχουσα με 21
/// εξοπλισμούς.
///
/// Ο κανόνας: **ένα από τα δύο ονόματα ταιριάζει απόλυτα και το άλλο διαφέρει
/// σε λίγα γράμματα.** Το επώνυμο κρίνεται αυστηρότερα από το μικρό όνομα,
/// γιατί το μικρό όνομα έχει παραλλαγές γραφής (Καλή/Καλλή) ενώ το επώνυμο
/// συνήθως αλλάζει μόνο όταν αλλάζει πρόσωπο.
///
/// Το κριτήριο δοκιμάστηκε πάνω σε ολόκληρη τη Λάμπα: βρίσκει τη «Μαλατέστα
/// Καλή» και απορρίπτει τον «Πρόβος Βασίλης» ως υποψήφιο για τον «Βασίλη
/// Δρόσο» — δύο γράμματα διαφορά στο επώνυμο, δηλαδή άλλος άνθρωπος. Χαλαρό
/// κριτήριο πάνω σε ολόκληρο το ονοματεπώνυμο τους μπέρδευε, και μάλιστα
/// πειστικά: ο «Πρόβος» έχει 14 εξοπλισμούς και θα έδειχνε ισχυρή επιλογή.
library;

import '../../utils/text_similarity.dart';

/// Πόσο επιτρέπεται να διαφέρει το **επώνυμο** όταν το μικρό όνομα ταιριάζει.
const int kLampOwnerLastNameTolerance = 1;

/// Πόσο επιτρέπεται να διαφέρει το **μικρό όνομα** όταν το επώνυμο ταιριάζει.
const int kLampOwnerFirstNameTolerance = 2;

/// Κάτω από αυτό το μήκος καμία απόκλιση δεν είναι ασφαλής: σε ονόματα δύο ή
/// τριών γραμμάτων ένα γράμμα διαφορά είναι συνήθως άλλος άνθρωπος («Ζωή»
/// και «Ζωγ»), όχι τυπογραφικό λάθος.
const int kLampOwnerMinLengthForTolerance = 4;

/// Πόσο και πού διαφέρει ένα ζεύγος ονομάτων που θεωρήθηκε κοντινό.
class LampOwnerNameDeviation {
  const LampOwnerNameDeviation({
    required this.lastNameDistance,
    required this.firstNameDistance,
  });

  /// Διορθώσεις γραμμάτων που χωρίζουν τα δύο επώνυμα.
  final int lastNameDistance;

  /// Διορθώσεις γραμμάτων που χωρίζουν τα δύο μικρά ονόματα.
  final int firstNameDistance;

  int get totalDistance => lastNameDistance + firstNameDistance;

  bool get isExact => totalDistance == 0;

  /// Τι ακριβώς διαφέρει, σε ανθρώπινη γλώσσα — μπαίνει δίπλα στον υποψήφιο
  /// ώστε ο χρήστης να δει τον λόγο και όχι απλώς ένα ποσοστό.
  String get description {
    if (isExact) return 'ίδιο όνομα';
    final letters = totalDistance == 1 ? '1 γράμμα' : '$totalDistance γράμματα';
    return lastNameDistance == 0
        ? 'το μικρό όνομα διαφέρει σε $letters'
        : 'το επώνυμο διαφέρει σε $letters';
  }
}

/// Ελέγχει αν δύο ονοματεπώνυμα είναι αρκετά κοντά ώστε να αφορούν τον ίδιο
/// άνθρωπο. Επιστρέφει `null` όταν δεν είναι.
///
/// Δεν αποφασίζει: ο διάλογος επίλυσης είναι χειροκίνητος και ο χρήστης
/// κρίνει. Η δουλειά της είναι να **μην κρύψει** τον προφανή υποψήφιο.
LampOwnerNameDeviation? lampOwnerNameDeviation({
  required String? candidateLastName,
  required String? candidateFirstName,
  required String? ownerLastName,
  required String? ownerFirstName,
}) {
  final candidateLast = TextSimilarity.normalize(candidateLastName ?? '');
  final candidateFirst = TextSimilarity.normalize(candidateFirstName ?? '');
  final ownerLast = TextSimilarity.normalize(ownerLastName ?? '');
  final ownerFirst = TextSimilarity.normalize(ownerFirstName ?? '');

  // Χωρίς κανένα όνομα δεν υπάρχει τίποτα να ταιριάξει· δύο άδειες εγγραφές
  // δεν είναι «ο ίδιος άνθρωπος».
  if (candidateLast.isEmpty && candidateFirst.isEmpty) return null;
  if (ownerLast.isEmpty && ownerFirst.isEmpty) return null;

  final lastDistance = TextSimilarity.levenshtein(candidateLast, ownerLast);
  final firstDistance = TextSimilarity.levenshtein(candidateFirst, ownerFirst);

  bool longEnough(String a, String b) {
    final shorter = a.length < b.length ? a.length : b.length;
    return shorter >= kLampOwnerMinLengthForTolerance;
  }

  if (lastDistance == 0 &&
      firstDistance <= kLampOwnerFirstNameTolerance &&
      (firstDistance == 0 || longEnough(candidateFirst, ownerFirst))) {
    return LampOwnerNameDeviation(
      lastNameDistance: 0,
      firstNameDistance: firstDistance,
    );
  }

  if (firstDistance == 0 &&
      lastDistance <= kLampOwnerLastNameTolerance &&
      longEnough(candidateLast, ownerLast)) {
    return LampOwnerNameDeviation(
      lastNameDistance: lastDistance,
      firstNameDistance: 0,
    );
  }

  return null;
}
