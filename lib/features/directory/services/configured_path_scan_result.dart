import 'configured_path_check.dart';

/// Μία ομάδα ρυθμισμένων διαδρομών που διαβάζεται μαζί.
///
/// Η ομαδοποίηση δεν είναι διακοσμητική: όταν η ανάγνωση σκάει, σκάει για
/// **όλη** την ομάδα — και το όνομά της είναι ό,τι θα διαβάσει ο χρήστης στο
/// «δεν ελέγχθηκαν …». Γράφεται σε πτώση που κουμπώνει σε αυτή τη φράση.
class ConfiguredPathGroup {
  const ConfiguredPathGroup({required this.name, required this.load});

  /// «τα εργαλεία απομακρυσμένης σύνδεσης», «ο φάκελος αντιγράφων ασφαλείας».
  final String name;

  final Future<List<ConfiguredPathEntry>> Function() load;
}

/// Τι κατάφερε να διαβάσει η απογραφή — και τι **όχι**.
///
/// Οι δύο λίστες ταξιδεύουν μαζί επίτηδες: μια απογραφή που επέστρεφε σκέτη
/// λίστα διαδρομών δεν είχε τρόπο να πει «δεν κοίταξα εδώ», οπότε μια
/// κλειδωμένη βάση έβγαινε ως «δεν υπάρχει τίποτα να ελεγχθεί».
class ConfiguredPathInventory {
  const ConfiguredPathInventory({
    required this.entries,
    required this.unreadableGroups,
  });

  final List<ConfiguredPathEntry> entries;

  /// Ονόματα ομάδων που δεν διαβάστηκαν, με τη σειρά που δηλώθηκαν.
  final List<String> unreadableGroups;
}

/// Το αποτέλεσμα του ελέγχου διαδρομών, με τα ανεξέταστα δίπλα στα ευρήματα.
///
/// **Κενή λίστα ευρημάτων ΔΕΝ σημαίνει «όλα καθαρά».** Σημαίνει «καθαρά όσα
/// εξετάστηκαν» — και το [isFullyChecked] είναι το μόνο που επιτρέπει στην
/// οθόνη να μιλήσει για «όλες τις διαδρομές».
class ConfiguredPathScanResult {
  const ConfiguredPathScanResult({
    required this.invalidPaths,
    required this.uncheckedGroups,
  });

  final List<ConfiguredPathEntry> invalidPaths;

  /// Ομάδες που δεν μπόρεσαν να διαβαστούν — τυπικά επειδή η κοινόχρηστη βάση
  /// ήταν κλειδωμένη από συνάδελφο τη στιγμή του ελέγχου.
  final List<String> uncheckedGroups;

  /// True μόνο όταν εξετάστηκε **κάθε** ομάδα.
  bool get isFullyChecked => uncheckedGroups.isEmpty;
}

/// Διαβάζει τις ομάδες μία-μία και κρατά ονομαστικά όσες δεν τα κατάφεραν.
///
/// **Ο μοναδικός `catch` της απογραφής ζει εδώ.** Όσο κάθε ομάδα έπιανε μόνη
/// της το σφάλμα της, δύο από τις τρεις το κατάπιναν σιωπηλά — και μια νέα
/// ομάδα δεν είχε τίποτα να της θυμίσει τον κανόνα. Τώρα η σιωπή είναι
/// αδύνατη: όποιος προσθέτει ομάδα, κληρονομεί την καταγραφή.
///
/// Οι ομάδες διαβάζονται με τη σειρά: η μία εξαρτάται από την ίδια βάση με
/// την άλλη, οπότε παράλληλη ανάγνωση θα πλήθαινε τα κλειδώματα χωρίς όφελος.
Future<ConfiguredPathInventory> collectConfiguredPaths(
  List<ConfiguredPathGroup> groups,
) async {
  final entries = <ConfiguredPathEntry>[];
  final unreadable = <String>[];
  for (final group in groups) {
    try {
      entries.addAll(await group.load());
    } catch (_) {
      unreadable.add(group.name);
    }
  }
  return ConfiguredPathInventory(
    entries: entries,
    unreadableGroups: unreadable,
  );
}
