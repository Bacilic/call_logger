/// Η εικόνα πατρόν ενός ορόφου, κρατημένη όσο δεν άλλαξε.
///
/// **Το πρόβλημα που λύνει:** η κάτοψη ζει ως εικόνα μέσα στη βάση, και η βάση
/// ζει σε δικτυακό φάκελο. Κάθε άνοιγμα ορόφου την κατέβαζε ολόκληρη ξανά —
/// μερικά MB πάνω από τη γραμμή του νοσοκομείου, για εικόνα που συνήθως δεν
/// έχει αλλάξει από το προηγούμενο άνοιγμα.
///
/// **Το κλειδί είναι το αποτύπωμα, όχι ο όροφος.** Αυτό είναι όλη η ουσία: αν
/// ο συνάδελφος φορτώσει νέα κάτοψη από άλλον σταθμό, το αποτύπωμα που
/// διαβάζει η επόμενη ανάγνωση κατάστασης είναι άλλο, η μνήμη δεν απαντά, και
/// η νέα εικόνα κατεβαίνει. Δεν χρειάζεται κανένας να «θυμηθεί» να ακυρώσει
/// τη μνήμη — η ακύρωση είναι ιδιότητα του κλειδιού.
///
/// **Κρατά bytes, όχι αποκωδικοποιημένη εικόνα.** Η αποκωδικοποιημένη εικόνα
/// έχει κάτοχο που την καταστρέφει όταν κλείνει η οθόνη· μια κοινή μνήμη
/// αποκωδικοποιημένων εικόνων θα έδινε στον δεύτερο όροφο εικόνα που ο πρώτος
/// έχει ήδη καταστρέψει. Το ακριβό είναι το δίκτυο, και αυτό γλιτώνεται.
library;

import 'dart:collection';
import 'dart:typed_data';

/// Πόσα MB εικόνων κρατιούνται συνολικά.
///
/// Μία αρχιτεκτονική κάτοψη είναι συνήθως 2–5 MB, οπότε το όριο καλύπτει
/// άνετα την εναλλαγή μεταξύ τριών-τεσσάρων ορόφων — που είναι ο πραγματικός
/// τρόπος δουλειάς — χωρίς να κρατά όλο το κτίριο στη μνήμη για πάντα.
const int kFloorPatternCacheMaxBytes = 24 * 1024 * 1024;

/// Μνήμη εικόνων πατρόν με κλειδί το αποτύπωμα και όριο συνολικών bytes.
///
/// Όταν γεμίσει, φεύγει αυτή που δεν ζητήθηκε για περισσότερη ώρα.
class FloorPlanPatternCache {
  FloorPlanPatternCache({this.maxBytes = kFloorPatternCacheMaxBytes});

  /// Η μνήμη που επιβιώνει του κάθε ανοίγματος ορόφου.
  ///
  /// Ο ελεγκτής του χάρτη φτιάχνεται από την αρχή σε κάθε άνοιγμα, οπότε μια
  /// μνήμη μέσα του δεν θα γλίτωνε ποτέ τίποτα.
  static final FloorPlanPatternCache instance = FloorPlanPatternCache();

  final int maxBytes;

  /// Σειρά χρήσης: το πρώτο κλειδί είναι το πιο παλιά ζητημένο.
  final LinkedHashMap<String, Uint8List> _entries =
      LinkedHashMap<String, Uint8List>();

  int _bytes = 0;

  /// Πόσα bytes κρατιούνται αυτή τη στιγμή.
  int get heldBytes => _bytes;

  /// Πόσες εικόνες κρατιούνται αυτή τη στιγμή.
  int get length => _entries.length;

  /// Η εικόνα με αυτό το αποτύπωμα, ή `null` αν δεν την έχουμε.
  Uint8List? get(String? hash) {
    if (hash == null) return null;
    final found = _entries.remove(hash);
    if (found == null) return null;
    // Η ανάγνωση ανανεώνει τη σειρά: ό,τι ζητιέται μένει.
    _entries[hash] = found;
    return found;
  }

  /// Κρατά την εικόνα με το αποτύπωμά της.
  ///
  /// Εικόνα μεγαλύτερη από το συνολικό όριο **δεν** κρατιέται καθόλου, αντί να
  /// αδειάσει τη μνήμη για να χωρέσει μόνη της.
  void put(String? hash, Uint8List bytes) {
    if (hash == null) return;
    if (bytes.lengthInBytes > maxBytes) return;
    final previous = _entries.remove(hash);
    if (previous != null) _bytes -= previous.lengthInBytes;
    _entries[hash] = bytes;
    _bytes += bytes.lengthInBytes;
    while (_bytes > maxBytes && _entries.isNotEmpty) {
      final oldest = _entries.keys.first;
      _bytes -= _entries.remove(oldest)!.lengthInBytes;
    }
  }
}
