import '../models/operator.dart';
import '../models/operator_presence.dart';

/// Γιατί ένα προφίλ δεν προσφέρεται — ή προσφέρεται με επιφύλαξη.
enum ProfileLockKind {
  /// Κανείς άλλος δεν το κρατά· επιλέγεται κανονικά.
  free,

  /// Το κρατά ζωντανή συνεδρία αλλού· δεν επιλέγεται.
  lockedElsewhere,

  /// Το κρατά ζωντανή συνεδρία αλλού, **αλλά** είναι προφίλ διαχειριστή.
  ///
  /// Επιλέγεται μετά από ρητή επιβεβαίωση: χωρίς κωδικούς, ο διαχειριστής
  /// είναι ο μόνος δρόμος επιστροφής όταν το μητρώο λέει ψέματα.
  adminOpenElsewhere,
}

/// Η κατάσταση ενός προφίλ τη στιγμή της επιλογής.
class ProfileAvailability {
  const ProfileAvailability(this.kind, {this.station});

  static const ProfileAvailability free = ProfileAvailability(
    ProfileLockKind.free,
  );

  final ProfileLockKind kind;

  /// Ο υπολογιστής όπου είναι ανοιχτό· `null` όταν είναι ελεύθερο.
  final String? station;

  bool get isLocked => kind == ProfileLockKind.lockedElsewhere;

  bool get needsAdminConfirmation => kind == ProfileLockKind.adminOpenElsewhere;
}

/// Ποια προφίλ κρατά αυτή τη στιγμή **άλλο** ανοιχτό αντίγραφο της εφαρμογής.
///
/// **Καθαρή συνάρτηση, ένα σημείο επιβολής.** Ο κανόνας «είναι ανοιχτό αλλού;»
/// γράφεται εδώ και μόνο εδώ: οθόνες, διάλογοι και η αυτόματη αναγνώριση της
/// εκκίνησης ρωτούν την ίδια απάντηση. Αν καθένας τον ξανάγραφε με δικά του
/// λόγια, η επόμενη πόρτα που θα προστεθεί θα τον ξεχνούσε σιωπηλά.
///
/// **Τρεις όροι, όχι ένας.** Ένα ίχνος κλειδώνει μόνο όταν είναι φρέσκο, όταν
/// το κρατά ακόμη ανοιχτό αντίγραφο, **και** όταν αυτό το αντίγραφο δεν είναι
/// το δικό μας. Ο τρίτος όρος δεν είναι λεπτομέρεια: μετά από κατάρρευση και
/// άμεση επανεκκίνηση στον ίδιο υπολογιστή το ίχνος ανήκει στο ίδιο αντίγραφο,
/// και ο άνθρωπος δεν επιτρέπεται να κλειδωθεί έξω από τον εαυτό του.
///
/// Το [now] και το [myInstance] δίνονται πάντα απ' έξω — ο κανόνας ελέγχεται
/// χωρίς οθόνη και χωρίς δεύτερο ρολόι.
Map<int, ProfileAvailability> profileAvailability({
  required List<Operator> profiles,
  required List<OperatorPresence> marks,
  required DateTime now,
  required String myInstance,
}) {
  final mine = myInstance.trim();

  // Το πιο πρόσφατο ζωντανό ίχνος ξένου αντιγράφου, ανά προφίλ: όταν κάποιος
  // κρατά το ίδιο προφίλ από δύο θέσεις, το μήνυμα δείχνει εκεί που ήταν
  // τελευταία φορά — η παλιότερη θέση είναι η λιγότερο χρήσιμη πληροφορία.
  final holders = <int, OperatorPresence>{};
  for (final mark in marks) {
    if (!mark.isOnlineAt(now)) continue;
    final holder = mark.instance?.trim() ?? '';
    if (holder.isEmpty) continue;
    if (mine.isNotEmpty && holder == mine) continue;
    final known = holders[mark.operatorId];
    if (known == null || mark.lastSeenAt.isAfter(known.lastSeenAt)) {
      holders[mark.operatorId] = mark;
    }
  }

  final out = <int, ProfileAvailability>{};
  for (final profile in profiles) {
    final id = profile.id;
    if (id == null) continue;
    final holder = holders[id];
    if (holder == null) {
      out[id] = ProfileAvailability.free;
      continue;
    }
    out[id] = ProfileAvailability(
      profile.isAdmin
          ? ProfileLockKind.adminOpenElsewhere
          : ProfileLockKind.lockedElsewhere,
      station: holder.station,
    );
  }
  return out;
}

/// Η κατάσταση ενός προφίλ, με ασφαλή απάντηση όταν λείπει από τον χάρτη.
///
/// Η άγνοια πέφτει στην πλευρά που δεν εμποδίζει: ένα προφίλ για το οποίο δεν
/// ξέρουμε τίποτα επιλέγεται κανονικά.
ProfileAvailability availabilityFor(
  Map<int, ProfileAvailability> availability,
  Operator profile,
) {
  final id = profile.id;
  if (id == null) return ProfileAvailability.free;
  return availability[id] ?? ProfileAvailability.free;
}
