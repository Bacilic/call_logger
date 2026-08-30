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
class WorkstationOperators {
  const WorkstationOperators._();

  static const String storageKey = 'workstation_operator_names_v1';

  /// Τα ονόματα που θυμάται ο σταθμός, με τον τελευταίο πρώτο.
  ///
  /// Η μνήμη του σταθμού είναι ευκολία, όχι προϋπόθεση: αν οι τοπικές
  /// ρυθμίσεις δεν διαβάζονται, η αναγνώριση συνεχίζει με τον λογαριασμό
  /// Windows αντί να σταματήσει η εκκίνηση.
  static Future<List<String>> names() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(storageKey) ?? const <String>[];
    } catch (_) {
      return const <String>[];
    }
  }

  /// Σημειώνει ότι αυτό το πρόσωπο διάλεξε ταυτότητα εδώ.
  static Future<void> remember(String displayName) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(storageKey) ?? const <String>[];
    await prefs.setStringList(
      storageKey,
      rememberedAfterPick(current, displayName),
    );
  }

  /// «Εδώ κάθομαι μόνο εγώ» — σβήνει όλους τους άλλους από τη μνήμη.
  ///
  /// Ο συνάδελφος που κάθισε μια φορά για δέκα λεπτά δεν πρέπει να κάνει τον
  /// σταθμό να ρωτά για έναν μήνα.
  static Future<void> keepOnly(String displayName) async {
    final prefs = await SharedPreferences.getInstance();
    final name = displayName.trim();
    await prefs.setStringList(
      storageKey,
      name.isEmpty ? const <String>[] : <String>[name],
    );
  }

  /// Ξεχνά τα πάντα — ο σταθμός επιστρέφει στην αναγνώριση από τον λογαριασμό.
  static Future<void> forgetAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
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

/// Σειρά εμφάνισης στον επιλογέα: πρώτα όσοι έχουν δουλέψει εδώ (τελευταίος
/// πρώτος), μετά οι υπόλοιποι όπως ήρθαν από τη βάση.
///
/// Όταν ο σταθμός ρωτά, ρωτά επειδή εναλλάσσονται άνθρωποι — και ο πιθανότερος
/// είναι αυτός που κάθισε τελευταίος.
List<Operator> orderProfilesForWorkstation(
  List<Operator> profiles,
  List<String> remembered,
) {
  final known = rememberedWorkstationProfiles(remembered, profiles);
  final knownKeys = <String>{
    for (final profile in known)
      SearchTextNormalizer.normalizeForSearch(profile.displayName),
  };
  return <Operator>[
    ...known,
    for (final profile in profiles)
      if (!knownKeys.contains(
        SearchTextNormalizer.normalizeForSearch(profile.displayName),
      ))
        profile,
  ];
}
