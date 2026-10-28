import 'package:shared_preferences/shared_preferences.dart';

import '../models/operator.dart';
import '../utils/search_text_normalizer.dart';

/// Πόσα ονόματα κρατά ο σταθμός.
///
/// Η λίστα υπάρχει για να ξεχωρίζει «εδώ κάθεται ένας» από «εδώ κάθονται
/// πολλοί» — δεν είναι αρχείο επισκεπτών. Ένα όριο εμποδίζει έναν σταθμό που
/// τον χρησιμοποιεί όλο το τμήμα να μεγαλώνει τη λίστα χωρίς τέλος.
const int maxRememberedWorkstationOperators = 10;

/// Ποιοι έχουν διαλέξει **ρητά** ταυτότητα σε αυτόν τον υπολογιστή.
///
/// Ζει στις τοπικές ρυθμίσεις του μηχανήματος, **ποτέ στη βάση**: η βάση είναι
/// κοινή για όλους τους συναδέλφους, ενώ το ερώτημα «ποιος κάθεται μπροστά σε
/// αυτή την οθόνη» αφορά μόνο αυτόν τον σταθμό.
///
/// Κρατά **ονόματα, όχι αναγνωριστικά**. Ένα αναγνωριστικό από άλλη βάση θα
/// έδειχνε σιωπηλά σε λάθος πρόσωπο· ένα όνομα που δεν υπάρχει απλώς δεν
/// βρίσκεται, και η αναγνώριση πέφτει πίσω στον λογαριασμό Windows.
///
/// Γράφεται **μόνο από ρητή ανθρώπινη επιλογή** — την οθόνη «Ποιος είστε;» και
/// τον διάλογο «Αλλαγή χρήστη». Η αυτόματη αναγνώριση από τον λογαριασμό
/// Windows δεν αφήνει ίχνος: αλλιώς ο πρώτος που αναγνωρίστηκε αυτόματα θα
/// έμενε για πάντα στη λίστα και ο σταθμός θα ρωτούσε αιώνια.
///
/// **Μία μνήμη ανά βάση (απόφαση 28/10/2026).** Η ερώτηση είναι «ποιος έχει
/// δουλέψει εδώ **με αυτή τη βάση**». Με μία κοινή μνήμη, η βάση του
/// νοσοκομείου, ανοιγμένη πρώτη φορά στο σπίτι, βρήκε ένα όνομα που ο
/// υπολογιστής θυμόταν από τη βάση του σπιτιού και μπήκε σιωπηλά. Ίδιο όνομα
/// σε δύο βάσεις δεν σημαίνει πάντα ίδιος άνθρωπος. Η βάση αναγνωρίζεται από
/// την ταυτότητα που κουβαλά μέσα της (`ensureDatabaseIdentity`), όχι από το
/// όνομα του αρχείου της.
class WorkstationOperators {
  const WorkstationOperators._();

  /// Η παλιά, κοινή για όλες τις βάσεις μνήμη. Διαβάζεται μία φορά, στην
  /// πρώτη βάση που ανοίγει μετά την αναβάθμιση, και μετά σβήνεται.
  static const String legacyStorageKey = 'workstation_operator_names_v1';

  static const String _storagePrefix = 'workstation_operator_names_v2::';

  static String? _database;

  /// Ποια βάση είναι ανοιχτή. Το ορίζει η αναγνώριση ταυτότητας σε κάθε
  /// άνοιγμα ή αλλαγή βάσης, πριν από οποιαδήποτε ανάγνωση της μνήμης.
  ///
  /// Χωρίς γνωστή ταυτότητα (η βάση δεν τη δέχτηκε) ο σταθμός δεν θυμάται
  /// κανέναν, και η αναγνώριση πέφτει στον λογαριασμό Windows ή ρωτά —
  /// η άγνοια πέφτει στην πλευρά της ερώτησης, όχι της εικασίας.
  static Future<void> useDatabase(String? identity) async {
    final id = identity?.trim() ?? '';
    _database = id.isEmpty ? null : id;
    if (_database == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getStringList(legacyStorageKey);
      if (legacy == null) return;
      // Ό,τι θυμόταν ο σταθμός ως τώρα αφορούσε τη βάση που χρησιμοποιούσε:
      // περνά σε εκείνη, ώστε η αναβάθμιση να μη ρωτήσει κανέναν χωρίς λόγο.
      // Οι βάσεις που θα ανοίξουν αργότερα ξεκινούν χωρίς μνήμη.
      if (!prefs.containsKey(_key)) {
        await prefs.setStringList(_key, legacy);
      }
      await prefs.remove(legacyStorageKey);
    } catch (_) {
      // Η μνήμη είναι ευκολία: αν οι τοπικές ρυθμίσεις δεν απαντούν, η
      // αναγνώριση συνεχίζει με τον λογαριασμό Windows.
    }
  }

  /// Μηδενισμός για τα τεστ — η ανοιχτή βάση είναι καθολική κατάσταση.
  static void resetForTest() => _database = null;

  static String get _key => '$_storagePrefix$_database';

  /// Τα ονόματα που θυμάται ο σταθμός για την ανοιχτή βάση, τελευταίος πρώτος.
  ///
  /// Η μνήμη του σταθμού είναι ευκολία, όχι προϋπόθεση: αν οι τοπικές
  /// ρυθμίσεις δεν διαβάζονται, η αναγνώριση συνεχίζει με τον λογαριασμό
  /// Windows αντί να σταματήσει η εκκίνηση.
  static Future<List<String>> names() async {
    if (_database == null) return const <String>[];
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_key) ?? const <String>[];
    } catch (_) {
      return const <String>[];
    }
  }

  /// Σημειώνει ότι αυτό το πρόσωπο διάλεξε ταυτότητα εδώ, με αυτή τη βάση.
  static Future<void> remember(String displayName) async {
    if (_database == null) return;
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_key) ?? const <String>[];
    await prefs.setStringList(_key, rememberedAfterPick(current, displayName));
  }

  /// «Εδώ κάθομαι μόνο εγώ» — σβήνει όλους τους άλλους από τη μνήμη.
  ///
  /// Ο συνάδελφος που κάθισε μια φορά για δέκα λεπτά δεν πρέπει να κάνει τον
  /// σταθμό να ρωτά για έναν μήνα.
  static Future<void> keepOnly(String displayName) async {
    if (_database == null) return;
    final prefs = await SharedPreferences.getInstance();
    final name = displayName.trim();
    await prefs.setStringList(
      _key,
      name.isEmpty ? const <String>[] : <String>[name],
    );
  }

  /// Ξεχνά τα πάντα για την ανοιχτή βάση — ο σταθμός επιστρέφει στην
  /// αναγνώριση από τον λογαριασμό.
  static Future<void> forgetAll() async {
    if (_database == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

/// Η μνήμη του σταθμού μετά από ρητή επιλογή: ο τελευταίος πρώτος, χωρίς
/// διπλοεγγραφές και με όριο.
///
/// Η σύγκριση αγνοεί τόνους και πεζά/κεφαλαία, όπως κάθε σύγκριση ελληνικού
/// ονόματος στην εφαρμογή — αλλιώς «Βασίλης» και «βασιλησ» θα ήταν δύο
/// άνθρωποι και ο σταθμός θα ρωτούσε χωρίς λόγο.
List<String> rememberedAfterPick(List<String> current, String picked) {
  final name = picked.trim();
  if (name.isEmpty) return List<String>.of(current);

  final target = SearchTextNormalizer.normalizeForSearch(name);
  final rest = <String>[
    for (final existing in current)
      if (SearchTextNormalizer.normalizeForSearch(existing.trim()) != target)
        existing,
  ];
  return <String>[
    name,
    ...rest,
  ].take(maxRememberedWorkstationOperators).toList();
}

/// Τα προφίλ που ο σταθμός θυμάται — όσα υπάρχουν ακόμη και είναι ενεργά, με
/// τη σειρά της μνήμης (τελευταίος πρώτος).
///
/// Ό,τι δεν ταιριάζει αγνοείται σιωπηλά: το προφίλ μπορεί να μετονομάστηκε, να
/// απενεργοποιήθηκε, ή η βάση να άλλαξε εντελώς.
List<Operator> rememberedWorkstationProfiles(
  List<String> remembered,
  List<Operator> profiles,
) {
  final byName = <String, Operator>{};
  for (final profile in profiles) {
    if (!profile.isActive) continue;
    byName.putIfAbsent(
      SearchTextNormalizer.normalizeForSearch(profile.displayName),
      () => profile,
    );
  }

  final matched = <Operator>[];
  final seen = <String>{};
  for (final name in remembered) {
    final key = SearchTextNormalizer.normalizeForSearch(name.trim());
    final match = byName[key];
    if (match == null || !seen.add(key)) continue;
    matched.add(match);
  }
  return matched;
}

/// Το **ενεργό** προφίλ που είναι δεμένο σε αυτόν τον λογαριασμό Windows.
///
/// `null` όταν ο λογαριασμός δεν αντιστοιχεί σε κανέναν — η συνηθισμένη
/// περίπτωση σε κοινόχρηστο σταθμό, όπου τα προφίλ είναι αυτόνομα.
///
/// Δουλεύει πάνω σε λίστα που έχει ήδη διαβαστεί, ώστε η εκκίνηση να μη ρωτά
/// τη βάση δεύτερη φορά για κάτι που μόλις κατέβασε.
Operator? activeProfileForWindowsAccount(
  List<Operator> profiles,
  String? account,
) {
  final wanted = normalizeWindowsAccount(account);
  if (wanted == null) return null;
  for (final profile in profiles) {
    if (!profile.isActive) continue;
    if (profile.windowsAccount == wanted) return profile;
  }
  return null;
}

/// Αρκεί η μνήμη του σταθμού, ή τη διαψεύδει ο λογαριασμός Windows;
///
/// **Το σενάριο που το γέννησε:** ο Βασίλης κάθεται πέντε μέρες στον
/// υπολογιστή του Βλάση όσο εκείνος λείπει, και πατά «Εδώ κάθομαι μόνο εγώ»
/// για να σταματήσουν οι ερωτήσεις. Ο Βλάσης γυρίζει, ανοίγει τον δικό του
/// υπολογιστή με τον δικό του λογαριασμό — και η εφαρμογή τον έβαζε μέσα **ως
/// Βασίλη**, σιωπηλά. Οι κλήσεις του γράφονταν σε άλλο όνομα μέχρι να το
/// προσέξει.
///
/// Η πληροφορία υπήρχε από την αρχή: ο λογαριασμός Windows είναι δεμένος στο
/// προφίλ του Βλάση. Απλώς κανείς δεν τη ρωτούσε, γιατί η μνήμη του σταθμού
/// απαντούσε πρώτη και έκλεινε το ερώτημα.
///
/// Επιστρέφει `true` **μόνο** στη διαφωνία: όταν ο λογαριασμός δείχνει σε άλλο
/// ενεργό προφίλ από αυτό που θυμάται ο σταθμός. Χωρίς δεμένο λογαριασμό, ή
/// όταν δείχνει στον ίδιο άνθρωπο, η εκκίνηση μένει ακριβώς όπως ήταν.
bool workstationMemoryIsContradicted({
  required Operator remembered,
  required List<Operator> profiles,
  required String? windowsAccount,
}) {
  final byAccount = activeProfileForWindowsAccount(profiles, windowsAccount);
  if (byAccount == null) return false;
  if (byAccount.id != null && remembered.id != null) {
    return byAccount.id != remembered.id;
  }
  return SearchTextNormalizer.normalizeForSearch(byAccount.displayName) !=
      SearchTextNormalizer.normalizeForSearch(remembered.displayName);
}

/// Σειρά εμφάνισης στον επιλογέα: πρώτος ο άνθρωπος του λογαριασμού Windows,
/// μετά όσοι έχουν δουλέψει εδώ (τελευταίος πρώτος), μετά οι υπόλοιποι.
///
/// Όταν ο σταθμός ρωτά, ρωτά επειδή εναλλάσσονται άνθρωποι. Ο λογαριασμός
/// Windows λέει ποιος έκανε είσοδο **τώρα**, ενώ η μνήμη λέει ποιος καθόταν
/// **κάποτε** — η φρέσκια ένδειξη είναι καλύτερη εικασία από την ιστορική, και
/// γι' αυτό προηγείται.
List<Operator> orderProfilesForWorkstation(
  List<Operator> profiles,
  List<String> remembered, {
  String? windowsAccount,
}) {
  final byAccount = activeProfileForWindowsAccount(profiles, windowsAccount);
  final known = rememberedWorkstationProfiles(remembered, profiles);
  final placed = <String>{};

  String keyOf(Operator profile) =>
      SearchTextNormalizer.normalizeForSearch(profile.displayName);

  final ordered = <Operator>[];
  void add(Operator profile) {
    if (placed.add(keyOf(profile))) ordered.add(profile);
  }

  if (byAccount != null) add(byAccount);
  known.forEach(add);
  profiles.forEach(add);
  return ordered;
}
