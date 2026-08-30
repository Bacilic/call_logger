/// Ο κατάλογος των εικονιδίων που μπορεί να φορέσει ένα προφίλ χρήστη.
///
/// **Γιατί υπάρχει κατάλογος και όχι σκέτη διαδρομή αρχείου.** Το εικονίδιο
/// αποθηκεύεται στη βάση ως κλειδί (`gorilla`), όχι ως διαδρομή. Έτσι η βάση
/// δεν ξέρει πού ζουν τα αρχεία: αν αύριο αλλάξει ο φάκελος ή η μορφή τους,
/// αλλάζει μόνο αυτό το αρχείο και καμία εγγραφή.
///
/// **Κλειδί που δεν αναγνωρίζεται δεν είναι σφάλμα.** Παλαιότερη έκδοση της
/// εφαρμογής που ανοίγει βάση με νεότερο εικονίδιο απλώς δεν το βρίσκει στον
/// κατάλογο και δείχνει το κλασικό ανθρωπάκι — δες [findAvatar].
library;

/// Ένα εικονίδιο του καταλόγου.
class OperatorAvatar {
  const OperatorAvatar(this.key, this.label);

  /// Ό,τι γράφεται στη βάση. Ταυτίζεται με το όνομα του αρχείου.
  final String key;

  /// Πώς λέγεται στην οθόνη, όταν ο χρήστης διαλέγει.
  final String label;

  String get assetPath => 'assets/avatars/$key.webp';
}

/// Τα διαθέσιμα εικονίδια, με τη σειρά που εμφανίζονται στον επιλογέα.
///
/// Η σειρά είναι σταθερή και όχι αλφαβητική: ο χρήστης μαθαίνει πού κάθεται το
/// καθένα, και μια ανακατεμένη λίστα σε κάθε άνοιγμα θα τον ανάγκαζε να ψάχνει
/// από την αρχή.
const List<OperatorAvatar> kOperatorAvatars = <OperatorAvatar>[
  OperatorAvatar('woman', 'Γυναίκα'),
  OperatorAvatar('elder', 'Ηλικιωμένος'),
  OperatorAvatar('doctor', 'Γιατρός'),
  OperatorAvatar('chef', 'Σεφ'),
  OperatorAvatar('footballer', 'Ποδοσφαιριστής'),
  OperatorAvatar('hacker', 'Χάκερ'),
  OperatorAvatar('astronaut', 'Αστροναύτης'),
  OperatorAvatar('ninja', 'Νίντζα'),
  OperatorAvatar('pirate', 'Πειρατής'),
  OperatorAvatar('pirate_woman', 'Πειρατίνα'),
  OperatorAvatar('rocker', 'Ροκάς'),
  OperatorAvatar('rockstar_woman', 'Ροκ σταρ'),
  OperatorAvatar('noblewoman', 'Αρχόντισσα'),
  OperatorAvatar('angel', 'Άγγελος'),
  OperatorAvatar('gorilla', 'Γορίλας'),
  OperatorAvatar('platypus', 'Πλατύπους'),
  OperatorAvatar('ayeaye', 'Λεμούριος'),
];

/// Το εικονίδιο με αυτό το κλειδί, ή `null` όταν δεν υπάρχει τέτοιο.
///
/// Το `null` είναι κανονική απάντηση, όχι αποτυχία: προφίλ χωρίς εικονίδιο
/// (γιατί τελείωσαν, ή γιατί η βάση γράφτηκε από νεότερη έκδοση) δείχνει το
/// κλασικό ανθρωπάκι.
OperatorAvatar? findAvatar(String? key) {
  if (key == null || key.isEmpty) return null;
  for (final avatar in kOperatorAvatars) {
    if (avatar.key == key) return avatar;
  }
  return null;
}

/// Η ετικέτα του εικονιδίου, ή «Κλασικό» όταν δεν υπάρχει.
String avatarLabelFor(String? key) => findAvatar(key)?.label ?? 'Κλασικό';
