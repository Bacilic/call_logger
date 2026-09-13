import '../../../core/config/app_config.dart';
import '../../../core/services/building_map_storage.dart';
import '../../../core/services/portable_lamp_storage.dart';
import 'restore_plan.dart';

/// Τα συνοδευτικά στοιχεία που μπορεί να κουβαλά ένα πλήρες αντίγραφο.
///
/// Η βάση δεν είναι μέλος: έχει δική της, ξεχωριστή απόφαση (αν θα
/// αντικατασταθεί και με ποιο όνομα), ενώ τα μέλη εδώ απλώς αντιγράφονται
/// πάνω στους φακέλους της εφαρμογής.
enum RestorePortablePart { maps, toolImages, lexicon, lampDatabase }

/// Τι ζήτησε ο χρήστης να επαναφερθεί.
///
/// Συμβόλαιο: ό,τι μπορεί να μπει στο αντίγραφο μπορεί και να μην
/// επαναφερθεί. Η επιλογή είναι του χρήστη, ανά στοιχείο, και η αναφορά στο
/// τέλος λέει τι έγινε με καθένα — συμπεριλαμβανομένου εκείνου που
/// παραλείφθηκε κατ' επιλογή του.
class RestoreSelection {
  const RestoreSelection({required this.destination, required this.parts});

  /// Με ποιο όνομα γράφεται η βάση, ή `null` όταν η βάση **δεν** επαναφέρεται.
  final RestoreDestinationChoice? destination;

  /// Τα συνοδευτικά στοιχεία που ζητήθηκαν.
  final Set<RestorePortablePart> parts;

  bool get restoresDatabase => destination != null;

  bool includes(RestorePortablePart part) => parts.contains(part);

  /// Πόσα στοιχεία συνολικά θα επαναφερθούν (η βάση μετρά ως ένα).
  int get selectedCount => parts.length + (restoresDatabase ? 1 : 0);

  /// Τίποτα επιλεγμένο: το κουμπί της επαναφοράς δεν έχει δουλειά να κάνει.
  bool get isEmpty => selectedCount == 0;
}

/// Πώς ονομάζεται το στοιχείο μπροστά στον χρήστη.
///
/// Μία πηγή για τις ετικέτες: ο διάλογος επαναφοράς και η υπόδειξη του
/// κουμπιού έλεγαν άλλοτε διαφορετικά ονόματα για το ίδιο πράγμα
/// («Κατόψεις κτιρίων» και «Εικόνες Χαρτών»).
String restorePortablePartLabel(RestorePortablePart part) {
  switch (part) {
    case RestorePortablePart.maps:
      return 'Κατόψεις κτιρίων';
    case RestorePortablePart.toolImages:
      return 'Εικονίδια εργαλείων και χρηστών';
    case RestorePortablePart.lexicon:
      return 'Λεξικό';
    case RestorePortablePart.lampDatabase:
      return 'Βάση Λάμπας';
  }
}

/// Η ετικέτα της ίδιας της βάσης — δεν είναι [RestorePortablePart], αλλά
/// εμφανίζεται στις ίδιες λίστες.
const String restoreDatabaseLabel = 'Βάση δεδομένων';

/// Σε ποιο στοιχείο ανήκει μια εγγραφή του zip, ή `null` αν δεν ανήκει σε
/// καμία γνωστή κατηγορία (π.χ. το manifest ή το ίδιο το αρχείο βάσης).
///
/// Μία πηγή για την αντιστοίχιση φακέλου-σε-στοιχείο: όποιος φιλτράρει
/// εγγραφές ρωτά εδώ, ώστε ένας νέος φάκελος να μη χρειάζεται δύο διορθώσεις.
RestorePortablePart? restorePortablePartForEntry(String entryName) {
  final name = entryName.replaceAll(r'\', '/');
  if (name.startsWith('${BuildingMapStorage.backupZipMapsFolderName}/')) {
    return RestorePortablePart.maps;
  }
  if (name.startsWith('${AppConfig.portableImagesDirName}/')) {
    return RestorePortablePart.toolImages;
  }
  if (name.startsWith('${AppConfig.portableDictionariesDirName}/')) {
    return RestorePortablePart.lexicon;
  }
  if (name.startsWith('${PortableLampStorage.backupZipLampDbFolderName}/')) {
    return RestorePortablePart.lampDatabase;
  }
  return null;
}

/// Περνά η εγγραφή το φίλτρο των επιλογών του χρήστη;
///
/// Ό,τι δεν ανήκει σε γνωστή κατηγορία περνά: το φίλτρο κρίνει επιλογές, δεν
/// αποφασίζει τι είναι έγκυρο περιεχόμενο.
bool restoreEntryIsWanted(String entryName, Set<RestorePortablePart> parts) {
  final part = restorePortablePartForEntry(entryName);
  return part == null || parts.contains(part);
}
