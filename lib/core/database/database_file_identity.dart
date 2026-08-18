import 'dart:io';
import 'dart:typed_data';

/// Ταυτότητα αρχείου βάσης, όπως τη δίνει η κεφαλίδα των πρώτων 100 bytes.
///
/// Χρησιμεύει σε ένα μόνο ερώτημα: «είναι αυτό ακόμα το ίδιο αρχείο που
/// άνοιξα;». Η απάντηση δεν βγαίνει από ερώτημα SQL — βγαίνει από τα ίδια τα
/// bytes, γιατί ακριβώς όταν κάποιος αντικαθιστά το αρχείο απ' έξω, η σύνδεσή
/// μας δεν το μαθαίνει ποτέ: συνεχίζει να διαβάζει τις σελίδες που κρατά στη
/// μνήμη της.
///
/// Η ανάγνωση είναι σκόπιμα φτωχή σε απαιτήσεις: 100 bytes με κοινή χρήση,
/// χωρίς κλείδωμα, χωρίς σύνδεση SQLite. Σε κοινόχρηστη βάση αυτό έχει σημασία
/// — ένας φρουρός που κλειδώνει θα ήταν χειρότερος από το πρόβλημα που λύνει.
class DatabaseFileIdentity {
  const DatabaseFileIdentity({
    required this.fileSize,
    required this.pageSize,
    required this.changeCounter,
    required this.schemaCookie,
    required this.pageCount,
  });

  /// Μέγεθος αρχείου σε bytes.
  final int fileSize;

  /// Μέγεθος σελίδας. Σταθερό για μια δεδομένη βάση σε όλη τη ζωή της.
  final int pageSize;

  /// Μετρητής αλλαγών (bytes 24-27): αυξάνεται σε κάθε εγγραφή στο κύριο
  /// αρχείο. **Ποτέ δεν μειώνεται** όσο πρόκειται για την ίδια βάση.
  final int changeCounter;

  /// Μετρητής αλλαγών σχήματος (bytes 40-43). Επίσης μονότονα αύξων.
  final int schemaCookie;

  /// Πλήθος σελίδων της βάσης (bytes 28-31).
  final int pageCount;

  @override
  String toString() =>
      'DatabaseFileIdentity(size: $fileSize, page: $pageSize, '
      'change: $changeCounter, schema: $schemaCookie, pages: $pageCount)';
}

/// Η ετυμηγορία της σύγκρισης δύο στιγμιοτύπων ταυτότητας.
enum DatabaseIdentityVerdict {
  /// Τίποτα αδύνατο δεν συνέβη — είτε η βάση δεν άλλαξε, είτε άλλαξε νόμιμα
  /// (εγγραφή από αυτό ή από άλλο μηχάνημα). Καμία ενέργεια.
  unchangedOrNormal,

  /// Δεν μπορούμε να ξέρουμε: το αρχείο δεν διαβάστηκε (πεσμένο δίκτυο,
  /// στιγμιαίο κλείδωμα, οτιδήποτε). **Σιωπή, ποτέ συναγερμός.**
  unknown,

  /// Μεταβολή που είναι φυσικά αδύνατη για ζωντανή βάση: το αρχείο
  /// αντικαταστάθηκε απ' έξω.
  replaced,
}

/// Διαβάζει την ταυτότητα του αρχείου· `null` όταν δεν μπορεί να τη διαβάσει.
///
/// Το `null` σημαίνει **άγνοια, όχι σφάλμα**: άφταστο δικτυακό αρχείο, αρχείο
/// σε χρήση, δικαιώματα. Ο καλών το μεταφράζει σε [DatabaseIdentityVerdict.unknown]
/// και δεν ενοχλεί κανέναν.
Future<DatabaseFileIdentity?> readDatabaseFileIdentity(String path) async {
  if (path.trim().isEmpty) return null;
  RandomAccessFile? handle;
  try {
    final file = File(path);
    final length = await file.length();
    // Κάτω από 100 bytes δεν υπάρχει καν κεφαλίδα SQLite.
    if (length < 100) return null;
    handle = await file.open();
    final header = await handle.read(100);
    if (header.length < 100) return null;
    return parseDatabaseFileIdentity(header: header, fileSize: length);
  } catch (_) {
    // Κάθε αποτυχία ανάγνωσης είναι άγνοια, όχι εύρημα.
    return null;
  } finally {
    try {
      await handle?.close();
    } catch (_) {}
  }
}

/// Οι πρώτοι 16 bytes κάθε αρχείου SQLite.
const List<int> _kSqliteMagic = <int>[
  0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66, // "SQLite f"
  0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00, // "ormat 3\0"
];

/// Μεταφράζει τα 100 bytes της κεφαλίδας σε [DatabaseFileIdentity].
///
/// Χωριστά από την ανάγνωση, ώστε να ελέγχεται με σκέτα bytes.
DatabaseFileIdentity? parseDatabaseFileIdentity({
  required List<int> header,
  required int fileSize,
}) {
  if (header.length < 100) return null;
  for (var i = 0; i < _kSqliteMagic.length; i++) {
    if (header[i] != _kSqliteMagic[i]) return null;
  }
  final bytes = ByteData.sublistView(Uint8List.fromList(header));
  // Το 1 στη θέση του μεγέθους σελίδας σημαίνει 65536 (δεν χωρά σε 2 bytes).
  final rawPageSize = bytes.getUint16(16);
  final pageSize = rawPageSize == 1 ? 65536 : rawPageSize;
  return DatabaseFileIdentity(
    fileSize: fileSize,
    pageSize: pageSize,
    changeCounter: bytes.getUint32(24),
    pageCount: bytes.getUint32(28),
    schemaCookie: bytes.getUint32(40),
  );
}

/// Αποφασίζει αν το αρχείο αντικαταστάθηκε, συγκρίνοντας δύο στιγμιότυπα.
///
/// **Ο κανόνας: κατηγορούμε μόνο για το αδύνατο.** Μια νόμιμη εγγραφή —δική
/// μας ή του συναδέλφου στο διπλανό γραφείο— ανεβάζει τους μετρητές και αλλάζει
/// το μέγεθος· όλα αυτά προσπερνιούνται σιωπηλά. Συναγερμός σημαίνει μόνο για
/// μεταβολές που καμία ζωντανή βάση δεν μπορεί να κάνει στον εαυτό της:
///
/// 1. **Έπαψε να είναι αρχείο SQLite** — η κεφαλίδα δεν διαβάζεται.
/// 2. **Άλλαξε το μέγεθος σελίδας** — ορίζεται στη γέννηση της βάσης.
/// 3. **Μετρητής προς τα πίσω** (αλλαγών ή σχήματος) — οι μετρητές μόνο ανεβαίνουν.
/// 4. **Ακίνητος μετρητής με κινούμενο αρχείο** — αν δεν γράφτηκε τίποτα, τότε
///    ούτε το μέγεθος ούτε το πλήθος σελίδων μπορούν να έχουν αλλάξει.
///
/// Ο τέταρτος κανόνας είναι ο πιο χρήσιμος στην πράξη: πιάνει την αντιγραφή
/// άλλης βάσης που τυχαίνει να έχει μετρητή μεγαλύτερο ή ίσο του δικού μας.
DatabaseIdentityVerdict compareDatabaseFileIdentity({
  required DatabaseFileIdentity? before,
  required DatabaseFileIdentity? after,
}) {
  if (before == null || after == null) return DatabaseIdentityVerdict.unknown;

  if (after.pageSize != before.pageSize) {
    return DatabaseIdentityVerdict.replaced;
  }
  if (after.changeCounter < before.changeCounter) {
    return DatabaseIdentityVerdict.replaced;
  }
  if (after.schemaCookie < before.schemaCookie) {
    return DatabaseIdentityVerdict.replaced;
  }
  if (after.changeCounter == before.changeCounter &&
      (after.fileSize != before.fileSize ||
          after.pageCount != before.pageCount ||
          after.schemaCookie != before.schemaCookie)) {
    return DatabaseIdentityVerdict.replaced;
  }
  return DatabaseIdentityVerdict.unchangedOrNormal;
}

/// Διαβάζει την ταυτότητα και την κρίνει απέναντι στο [before], με δεύτερη
/// ματιά πριν κατηγορήσει.
///
/// Η δεύτερη ανάγνωση δεν είναι υπερβολή: τα 100 bytes μπορεί να διαβαστούν
/// ακριβώς την ώρα που κάποιος γράφει, δίνοντας μια στιγμιαία εικόνα που δεν
/// αντιστοιχεί σε καμία πραγματική κατάσταση. Ένας συναγερμός που ξυπνά τον
/// χρήστη αξίζει δύο αναγνώσεις των 100 bytes.
Future<DatabaseIdentityVerdict> verifyDatabaseFileIdentity({
  required String path,
  required DatabaseFileIdentity? before,
  Duration secondLookDelay = const Duration(milliseconds: 150),
  Future<DatabaseFileIdentity?> Function(String path) read =
      readDatabaseFileIdentity,
  Future<void> Function(Duration) wait = _defaultWait,
}) async {
  if (before == null) return DatabaseIdentityVerdict.unknown;

  final first = compareDatabaseFileIdentity(before: before, after: await read(path));
  if (first != DatabaseIdentityVerdict.replaced) return first;

  await wait(secondLookDelay);
  return compareDatabaseFileIdentity(before: before, after: await read(path));
}

Future<void> _defaultWait(Duration d) => Future<void>.delayed(d);

/// Μυρίζει αυτό το σφάλμα «διαβάζω βάση που δεν είναι πια εκεί»;
///
/// Όταν το αρχείο αντικατασταθεί, η ανοιχτή σύνδεση κρατά στη μνήμη της σελίδες
/// της παλιάς βάσης και διαβάζει από τον δίσκο σελίδες της νέας. Το SQLite
/// βλέπει ασυνεπές δέντρο και λέει «database disk image is malformed» — μιλά
/// για **ό,τι διάβασε**, όχι για το αρχείο, που μπορεί να είναι μια χαρά.
///
/// Δεν είναι απόδειξη: την ίδια φωνή βγάζει και μια πραγματικά φθαρμένη βάση.
/// Είναι όμως η πιο **έγκαιρη** ένδειξη που υπάρχει — έρχεται τη στιγμή που ο
/// χρήστης χτυπά το πρόβλημα, χωρίς να περιμένει τον επόμενο περιοδικό έλεγχο.
/// Γι' αυτό οδηγεί σε έλεγχο ταυτότητας, ποτέ κατευθείαν σε συμπέρασμα.
bool looksLikeCorruptImageError(Object error) {
  final lower = error.toString().toLowerCase();
  return lower.contains('disk image is malformed') ||
      lower.contains('database disk image') ||
      lower.contains('sqlite_corrupt') ||
      (lower.contains('malformed') && lower.contains('database'));
}

/// Ετυμηγορία δομικού ελέγχου: χωρά το αρχείο τις σελίδες που δηλώνει;
enum DatabaseStructuralVerdict {
  /// Το αρχείο είναι τουλάχιστον όσο μεγάλο υπόσχεται η κεφαλίδα του.
  ok,

  /// Δεν διαβάστηκε ταυτότητα. **Σιωπή, ποτέ συναγερμός.**
  unknown,

  /// Η κεφαλίδα δηλώνει περισσότερες σελίδες από όσες χωρά το αρχείο —
  /// ο κατάλογος της βάσης δείχνει σε σελίδες που δεν υπάρχουν.
  truncated,
}

/// Ελέγχει αν το αρχείο χωρά τις σελίδες που δηλώνει η κεφαλίδα του.
///
/// Κοστίζει όσο και η ανάγνωση των 100 bytes που έχει ήδη γίνει: καμία
/// σύνδεση SQLite, κανένα κλείδωμα, καμία σάρωση περιεχομένου. Πιάνει το
/// αντίγραφο που δεν πρόλαβε να ολοκληρωθεί — τη συχνότερη μορφή αρχείου που
/// «είναι εκεί, διαβάζεται, και δεν ανοίγει».
///
/// **Κατηγορούμε μόνο για το αδύνατο**, όπως και το
/// [compareDatabaseFileIdentity]: αρχείο μεγαλύτερο από όσο δηλώνει είναι
/// απολύτως νόμιμο (η βάση κρατά χώρο που δεν χρησιμοποιεί) και προσπερνιέται
/// σιωπηλά. Μόνο το **μικρότερο** είναι αδύνατο για ακέραιο αρχείο.
DatabaseStructuralVerdict inspectDatabaseFileStructure(
  DatabaseFileIdentity? identity,
) {
  if (identity == null) return DatabaseStructuralVerdict.unknown;
  if (identity.pageSize <= 0 || identity.pageCount <= 0) {
    return DatabaseStructuralVerdict.unknown;
  }
  final declaredBytes = identity.pageCount * identity.pageSize;
  if (identity.fileSize < declaredBytes) {
    return DatabaseStructuralVerdict.truncated;
  }
  return DatabaseStructuralVerdict.ok;
}

/// Μυρίζει αυτό το σφάλμα «αντιγράφηκε ενώ η βάση δούλευε»;
///
/// Όταν αντιγράφεις αρχείο SQLite που εκείνη τη στιγμή γράφεται, ο αντιγραφέας
/// διαβάζει το αρχείο σε κομμάτια· ανάμεσα στα κομμάτια η βάση αλλάζει. Το
/// αποτέλεσμα δεν αντιστοιχεί σε **καμία** πραγματική στιγμή: ο κατάλογος
/// είναι από τη μία στιγμή και τα δεδομένα από την άλλη, οπότε το SQLite
/// ψάχνει πίνακα σε σελίδα που δεν υπάρχει.
///
/// Ξεχωρίζει σκόπιμα από το [looksLikeCorruptImageError]: εκείνο μιλά για
/// **ό,τι διάβασε** μια ανοιχτή σύνδεση όταν το αρχείο αντικαταστάθηκε από
/// κάτω της, και οδηγεί στον φρουρό αντικατάστασης. Εδώ το αρχείο είναι
/// ασυνεπές **από μόνο του** — καμία επανασύνδεση δεν το θεραπεύει.
bool looksLikeCopiedWhileInUseError(Object error) {
  final lower = error.toString().toLowerCase();
  return lower.contains('invalid rootpage') ||
      lower.contains('malformed database schema');
}
