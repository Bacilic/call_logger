import '../database/database_init_result.dart';

/// Πρωτογενής αποτυχία εκκίνησης της μηχανής SQLite (π.χ. λείπει sqlite3.dll).
class StartupEngineFailure {
  const StartupEngineFailure({required this.error, this.stack});

  final Object error;
  final StackTrace? stack;
}

StartupEngineFailure? _startupEngineFailure;

/// Καταγράφει μόνο την πρώτη αποτυχία μηχανής· οι επόμενες αγνοούνται.
void recordStartupEngineFailure(Object error, StackTrace? stack) {
  _startupEngineFailure ??= StartupEngineFailure(error: error, stack: stack);
}

StartupEngineFailure? get startupEngineFailureOrNull => _startupEngineFailure;

/// Εκκαθάριση για απομόνωση τεστ.
void clearStartupEngineFailure() {
  _startupEngineFailure = null;
}

/// Ταξινομημένο αποτέλεσμα της καταγεγραμμένης αποτυχίας μηχανής, ή `null` αν
/// η μηχανή SQLite φορτώθηκε κανονικά.
///
/// Χρησιμοποιείται ως φρουρός ΠΡΙΝ από κάθε έλεγχο βάσης: όταν λείπει η μηχανή,
/// οι έλεγχοι αρχείου πετυχαίνουν και παράγουν παραπλανητικά διαγνωστικά.
DatabaseInitResult? startupEngineFailureResultOrNull({String? pathHint}) {
  final failure = _startupEngineFailure;
  if (failure == null) return null;
  return DatabaseInitResult.fromException(
    failure.error,
    pathHint,
    failure.stack,
  );
}

/// Επιλέγει ποιο σφάλμα θα δει ο χρήστης: την καταγεγραμμένη αιτία μηχανής,
/// αλλιώς το δευτερογενές [fallbackError].
DatabaseInitResult resolveStartupFailureResult({
  required Object fallbackError,
  StackTrace? fallbackStack,
  String? pathHint,
}) {
  final failure = _startupEngineFailure;
  if (failure == null) {
    return DatabaseInitResult.fromException(
      fallbackError,
      pathHint,
      fallbackStack,
    );
  }

  final primary = DatabaseInitResult.fromException(
    failure.error,
    pathHint,
    failure.stack,
  );
  final secondaryLine = 'Δευτερογενές σφάλμα: $fallbackError';
  final existing = primary.details?.trim();
  final mergedDetails = (existing == null || existing.isEmpty)
      ? secondaryLine
      : '$existing\n$secondaryLine';
  return primary.copyWith(details: mergedDetails);
}
