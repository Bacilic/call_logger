import 'dart:io';

import 'package:path/path.dart' as p;

/// Τα αρχεία που μπορεί να συνοδεύουν μια βάση SQLite.
///
/// `-wal` και `-shm` ανήκουν στο WAL· το `-journal` στο κλασικό ημερολόγιο
/// αναίρεσης. Δεν συνυπάρχουν ποτέ και τα τρία — αλλά μια βάση που άλλαξε
/// τρόπο, ή που έπεσε στη μέση μιας εγγραφής, μπορεί να αφήσει πίσω της
/// οποιοδήποτε από αυτά. Γι' αυτό η λίστα είναι μία και κοινή: ένα συνοδό που
/// ξεχνιέται σε κάποιο σημείο είναι ακριβώς ο τρόπος να καταστραφεί μια βάση.
const List<String> kDatabaseSidecarSuffixes = <String>[
  '-wal',
  '-shm',
  '-journal',
];

/// Μετονομάζει το κύριο αρχείο βάσης μαζί με όσα συνοδά του υπάρχουν.
///
/// Τα συνοδά ταξιδεύουν **μαζί** με το κύριο αρχείο: ένα `-journal` που θα
/// έμενε πίσω περιγράφει ημιτελή εγγραφή σε βάση που δεν βρίσκεται πια εκεί.
Future<void> renameDatabaseBundle(String dbPath, String newMainFileName) async {
  final dir = p.dirname(dbPath);
  final newMain = p.join(dir, newMainFileName);

  await File(dbPath).rename(newMain);
  for (final suffix in kDatabaseSidecarSuffixes) {
    final sidecar = File('$dbPath$suffix');
    if (await sidecar.exists()) {
      await sidecar.rename('$newMain$suffix');
    }
  }
}

/// Σβήνει ανεκτικά τα συνοδά αρχεία του [dbPath].
///
/// **Καλείται ΜΟΝΟ αφού το κύριο αρχείο έχει αντικατασταθεί.** Εκεί τα συνοδά
/// ανήκουν σε βάση που δεν υπάρχει πια, και είναι επικίνδυνα: το SQLite θα τα
/// εφαρμόσει πάνω στη νέα βάση σαν να ήταν δικά της — δηλαδή θα γράψει σελίδες
/// της παλιάς πάνω στη νέα.
///
/// Έξω από αυτό το πλαίσιο η διαγραφή θα ήταν **λάθος**: ένα ζωντανό
/// `-journal` κρατά την αναίρεση μιας εγγραφής που δεν πρόλαβε να ολοκληρωθεί,
/// και σβήνοντάς το αφήνεις τη βάση μισογραμμένη χωρίς δρόμο επιστροφής.
Future<void> deleteDatabaseSidecars(String dbPath) async {
  for (final suffix in kDatabaseSidecarSuffixes) {
    try {
      final file = File('$dbPath$suffix');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}

/// Μοναδικό όνομα με κλιμάκωση: ημερομηνία → `HH-mm` → `HH-mm-ss` → αριθμός.
///
/// Μορφή ημερομηνίας: `dd-MM-yyyy` (ίδια με τα αντίγραφα αναβάθμισης σχήματος).
String resolveUniqueTimestampedFileName({
  required String directory,
  required String baseName,
  required String suffix,
  required String extension,
  DateTime? now,
  bool Function(String absolutePath)? fileExists,
}) {
  final n = now ?? DateTime.now();
  final ext = extension.isEmpty
      ? '.db'
      : (extension.startsWith('.') ? extension : '.$extension');
  final date = _dateStamp(n);

  bool exists(String fileName) {
    final full = p.join(directory, fileName);
    if (fileExists != null) return fileExists(full);
    try {
      return File(full).existsSync();
    } catch (_) {
      return false;
    }
  }

  final withDate = '$baseName$suffix$date$ext';
  if (!exists(withDate)) return withDate;

  final withMinutes = '$baseName$suffix${date}_${_timeStamp(n)}$ext';
  if (!exists(withMinutes)) return withMinutes;

  final withSeconds =
      '$baseName$suffix${date}_${_timeStamp(n, seconds: true)}$ext';
  if (!exists(withSeconds)) return withSeconds;

  var counter = 2;
  while (true) {
    final candidate =
        '$baseName$suffix${date}_${_timeStamp(n, seconds: true)}_$counter$ext';
    if (!exists(candidate)) return candidate;
    counter++;
  }
}

/// Το όνομα που θα πάρει η **τρέχουσα** βάση όταν παραμεριστεί για νέα.
///
/// Μία πηγή αλήθειας: την καλεί και η μετονομασία και το UI που την ανακοινώνει
/// από πριν. Δύο χωριστοί υπολογισμοί θα μπορούσαν να αποκλίνουν, και το μήνυμα
/// θα υποσχόταν όνομα διαφορετικό από το πραγματικό.
String resolveRenamedOldDatabaseFileName({
  required String currentDatabasePath,
  DateTime? now,
  bool Function(String absolutePath)? fileExists,
}) {
  final trimmed = currentDatabasePath.trim();
  if (trimmed.isEmpty) return '';
  final ext = p.extension(trimmed);
  return resolveUniqueTimestampedFileName(
    directory: p.dirname(trimmed),
    baseName: p.basenameWithoutExtension(trimmed),
    suffix: '_old_',
    extension: ext.isEmpty ? '.db' : ext,
    now: now,
    fileExists: fileExists,
  );
}

String _dateStamp(DateTime value) {
  final d = value.day.toString().padLeft(2, '0');
  final m = value.month.toString().padLeft(2, '0');
  return '$d-$m-${value.year}';
}

String _timeStamp(DateTime value, {bool seconds = false}) {
  final h = value.hour.toString().padLeft(2, '0');
  final min = value.minute.toString().padLeft(2, '0');
  if (!seconds) return '$h-$min';
  final s = value.second.toString().padLeft(2, '0');
  return '$h-$min-$s';
}
