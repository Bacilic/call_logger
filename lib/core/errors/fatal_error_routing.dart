import 'package:sqflite_common/sqlite_api.dart' show DatabaseException;

import '../database/database_init_result.dart';
import '../database/timeout_database.dart' show DatabaseUnresponsiveException;
import 'app_error_result.dart';

/// Τι μοιραίο συνέβη — και ποια οθόνη ξέρει να το χειριστεί.
///
/// Η διάκριση δεν είναι καλλωπισμός: η γενική οθόνη σφάλματος προσφέρει μόνο
/// «Επαναδοκιμή», που σε χαλασμένη βάση ξαναβρίσκει το ίδιο πρόβλημα. Η οθόνη
/// σφάλματος βάσης ξέρει να προσφέρει επιλογή άλλου αρχείου, επαναφορά από
/// αντίγραφο και αναβάθμιση σχήματος.
sealed class FatalErrorState {
  const FatalErrorState();
}

/// Η βάση δεν ανοίγει — υπάρχουν πραγματικές διέξοδοι.
class DatabaseFatalError extends FatalErrorState {
  const DatabaseFatalError(this.result);

  final DatabaseInitResult result;
}

/// Οτιδήποτε άλλο: η γενική οθόνη με την πλήρη αναφορά.
class GeneralFatalError extends FatalErrorState {
  const GeneralFatalError(this.result);

  final AppErrorResult result;
}

/// Πόσο βαθιά ψάχνουμε για τυλιγμένο σφάλμα βάσης.
///
/// Η αρχικοποίηση καλείται μέσα από providers, που τυλίγουν ό,τι πετάει·
/// χωρίς το ξετύλιγμα, το ίδιο σφάλμα θα κατέληγε άλλοτε στη σωστή οθόνη και
/// άλλοτε στη γενική, ανάλογα με το ποιος το ζήτησε.
const int _maxUnwrapDepth = 5;

/// Είναι το [error] **παροδική** απώλεια της βάσης — δεν απάντησε εγκαίρως,
/// ήταν κλειδωμένη, ή το δίκτυο κόπηκε για λίγο;
///
/// Τέτοιο σφάλμα που φτάνει ως την κορυφή **δεν** δικαιολογεί την πλήρη οθόνη
/// «Σφάλμα εφαρμογής»: η βάση επανέρχεται μόνη της (επαληθευμένο με πραγματική
/// διακοπή δικτύου) και ο φύλακας δείχνει ήδη λωρίδα που εξηγεί τι συμβαίνει.
/// Η οθόνη πετούσε τον χειριστή έξω από τη δουλειά του για μια διακοπή λίγων
/// δευτερολέπτων — «το βλέπω συνέχεια στη δουλειά», 23/09/2026.
///
/// **Εκτός** μένει η αποτυχία ανοίγματος της βάσης ([DatabaseInitException]):
/// εκείνη έχει τη δική της οθόνη με πραγματικές διεξόδους.
///
/// Η αναγνώριση γίνεται από τον **τύπο** και τον **κωδικό** του SQLite, όχι
/// από το κείμενο: busy (5), locked (6), I/O (10, με όλες τις παραλλαγές του).
bool isTransientDatabaseFailure(Object error) {
  if (_findDatabaseFailure(error) != null) return false;
  Object? current = error;
  for (var depth = 0; depth < _maxUnwrapDepth && current != null; depth++) {
    if (current is DatabaseUnresponsiveException) return true;
    if (current is DatabaseException) {
      final code = current.getResultCode();
      if (code != null && _transientSqliteCodes.contains(code & 0xff)) {
        return true;
      }
    }
    current = _innerCause(current);
  }
  return false;
}

/// SQLITE_BUSY, SQLITE_LOCKED, SQLITE_IOERR — οι βασικοί κωδικοί (χαμηλό byte).
const Set<int> _transientSqliteCodes = {5, 6, 10};

/// Σε ποια οθόνη ανήκει το [error].
///
/// Η αναγνώριση γίνεται από τον **τύπο** της εξαίρεσης, ποτέ από το κείμενό
/// της: ένα μήνυμα που απλώς αναφέρει τη βάση δεν σημαίνει ότι η βάση φταίει.
FatalErrorState classifyFatalError(Object error, StackTrace stack) {
  final databaseFailure = _findDatabaseFailure(error);
  if (databaseFailure != null) {
    return DatabaseFatalError(databaseFailure);
  }
  return GeneralFatalError(AppErrorResult.fromException(error, stack));
}

DatabaseInitResult? _findDatabaseFailure(Object error) {
  var current = error;
  for (var depth = 0; depth < _maxUnwrapDepth; depth++) {
    if (current is DatabaseInitException) return current.result;
    final inner = _innerCause(current);
    if (inner == null) return null;
    current = inner;
  }
  return null;
}

/// Το αίτιο που κουβαλά μέσα του ένα σφάλμα, αν το εκθέτει.
///
/// Δεν υπάρχει κοινή διεπαφή «αιτίου» στο Dart, οπότε ρωτάμε δυναμικά τα δύο
/// ονόματα που χρησιμοποιούνται στην πράξη. Ό,τι δεν απαντά, δεν έχει αίτιο.
Object? _innerCause(Object error) {
  try {
    final dynamic dynamicError = error;
    final Object? cause = dynamicError.cause;
    if (cause != null && cause != error) return cause;
  } on NoSuchMethodError {
    // Δεν εκθέτει `cause` — δοκιμάζουμε το άλλο όνομα.
  }
  try {
    final dynamic dynamicError = error;
    final Object? inner = dynamicError.innerException;
    if (inner != null && inner != error) return inner;
  } on NoSuchMethodError {
    // Ούτε αυτό: το σφάλμα είναι το ίδιο το αίτιο.
  }
  return null;
}
