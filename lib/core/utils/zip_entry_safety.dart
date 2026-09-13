// Πού επιτρέπεται να γραφτεί μια εγγραφή αρχειοθήκης — και πού όχι.
//
// Ένα `.zip` δεν κουβαλά μόνο περιεχόμενο· κουβαλά και **διαδρομές**, και οι
// διαδρομές του τις γράφει όποιος το έφτιαξε. Μια εγγραφή «maps_images/../x»
// βγάζει ένα επίπεδο έξω· μια «C:/Windows/x» αγνοεί εντελώς τον φάκελο
// προορισμού. Τα αντίγραφα που φτιάχνει η ίδια η εφαρμογή δεν έχουν τέτοιες
// διαδρομές — αλλά ο επιλογέας επαναφοράς δέχεται **οποιοδήποτε** αρχείο
// δώσει ο χρήστης.
//
// Ο κανόνας ζει εδώ και όχι μέσα στον καθένα που ξεπακετάρει, γιατί ήταν ήδη
// γραμμένος δύο φορές — σωστά στον εγκαταστάτη ενημερώσεων, καθόλου στην
// επαναφορά αντιγράφου. Κανόνας χωρίς σπίτι είναι κανόνας που η επόμενη ροή
// θα ξεχάσει.

import 'package:path/path.dart' as p;

/// Το αποτέλεσμα της κρίσης: είτε μια διαδρομή που είναι ασφαλές να γραφτεί,
/// είτε άρνηση με λόγο σε γλώσσα χρήστη.
///
/// Sealed επίτηδες: ο καλών δεν μπορεί να πάρει τη διαδρομή χωρίς να δει
/// πρώτα αν υπάρχει. Ένα API που επέστρεφε `String?` θα επέτρεπε το `!`.
sealed class ZipEntryTarget {
  const ZipEntryTarget();
}

/// Η εγγραφή μένει μέσα στον φάκελό της· γράφεται εδώ.
final class SafeZipEntryTarget extends ZipEntryTarget {
  const SafeZipEntryTarget(this.absolutePath);

  final String absolutePath;
}

/// Η εγγραφή απορρίπτεται — με πρόταση που μπορεί να μπει σε προειδοποίηση.
final class RejectedZipEntry extends ZipEntryTarget {
  const RejectedZipEntry(this.reason);

  /// Ελληνικά, για τον χρήστη. Δεν περιέχει τη λέξη «σφάλμα»: η εγγραφή
  /// παραλείφθηκε, η επαναφορά συνεχίζει.
  final String reason;
}

/// Κρίνει πού καταλήγει η [entryPath] κάτω από το [root].
///
/// Το [entryPath] είναι η διαδρομή **μέσα** στον φάκελο (ό,τι απομένει αφού
/// αφαιρεθεί το πρόθεμα του φακέλου από το όνομα της εγγραφής).
///
/// Η τελική κρίση δεν γίνεται με αναγνώριση μοτίβων αλλά με **σύγκριση της
/// πραγματικής διαδρομής**: ό,τι κι αν λέει το όνομα, το αποτέλεσμα πρέπει να
/// βρίσκεται κάτω από το [root]. Οι ονομαστικοί έλεγχοι από πάνω υπάρχουν
/// μόνο για να δίνουν καθαρό λόγο αντί για «κάπου αλλού».
ZipEntryTarget resolveZipEntryTarget({
  required String root,
  required String entryPath,
}) {
  final name = entryPath.replaceAll('\\', '/').trim();
  if (name.isEmpty) {
    return const RejectedZipEntry('Η εγγραφή δεν έχει όνομα αρχείου.');
  }

  if (_looksAbsolute(name)) {
    return RejectedZipEntry(
      'Η εγγραφή «$name» δείχνει σε απόλυτη διαδρομή, όχι μέσα στον φάκελο.',
    );
  }

  final normalizedRoot = p.normalize(p.absolute(root));
  final candidate = p.normalize(p.join(normalizedRoot, name));

  // `equals` σημαίνει ότι το «..» κατέβασε τη διαδρομή πάνω στο ίδιο το root:
  // θα έγραφε ΠΑΝΩ στον φάκελο, όχι μέσα του.
  if (!p.isWithin(normalizedRoot, candidate)) {
    return RejectedZipEntry(
      'Η εγγραφή «$name» δείχνει έξω από τον φάκελο προορισμού.',
    );
  }

  return SafeZipEntryTarget(candidate);
}

/// Το πρώτο όνομα εγγραφής που δεν θα έμενε μέσα στον φάκελό του, ή `null`.
///
/// Για τους καλούντες που κρίνουν **ολόκληρη** την αρχειοθήκη πριν αγγίξουν
/// οτιδήποτε — ο εγκαταστάτης ενημερώσεων ακυρώνει το πακέτο, αντί να
/// παραλείπει εγγραφές: εκεί μια ύποπτη διαδρομή σημαίνει ότι το πακέτο δεν
/// είναι αυτό που νομίζαμε.
String? firstEscapingEntryName(Iterable<String> entryNames) {
  // Πλασματική ρίζα: κρίνονται τα ονόματα καθαυτά, χωρίς να χρειάζεται να
  // υπάρχει φάκελος στον δίσκο.
  const probeRoot = r'C:\__zip_probe__';
  for (final raw in entryNames) {
    final target = resolveZipEntryTarget(root: probeRoot, entryPath: raw);
    if (target is RejectedZipEntry) return raw;
  }
  return null;
}

/// Απόλυτη διαδρομή σε POSIX (`/x`), σε Windows (`C:\x`, `C:/x`), ή διαδρομή
/// δικτύου (`\\server\share`).
///
/// Το γράμμα δίσκου ελέγχεται **χωρίς** να απαιτείται κάθετος μετά την άνω
/// τελεία: στα Windows το `C:φάκελος` είναι διαδρομή σχετική ως προς τον
/// τρέχοντα φάκελο *εκείνου του δίσκου* — εξίσου έξω από τον προορισμό.
bool _looksAbsolute(String name) {
  if (name.startsWith('/')) return true;
  if (name.startsWith('//')) return true;
  return RegExp(r'^[A-Za-z]:').hasMatch(name);
}
