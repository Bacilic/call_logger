import '../database/database_init_result.dart';
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
