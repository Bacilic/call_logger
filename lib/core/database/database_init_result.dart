/// Κατάσταση αρχικοποίησης / ελέγχου βάσης δεδομένων.
enum DatabaseStatus {
  success,
  fileNotFound,
  notReadable,
  corrupted,
  locked,
  invalidPath,
  unknownError,
}

/// Αποτέλεσμα αρχικοποίησης ή ελέγχου υγείας βάσης δεδομένων.
/// Χρησιμοποιείται για φιλικά μηνύματα σφαλμάτων στο UI.
class DatabaseInitResult {
  const DatabaseInitResult({
    required this.status,
    this.message,
    this.details,
  });

  final DatabaseStatus status;
  final String? message;
  final String? details;

  bool get isSuccess => status == DatabaseStatus.success;

  /// Από exception (SQLite / IO) → κατάλληλο status και μήνυμα.
  factory DatabaseInitResult.fromException(Object error, [String? path]) {
    final msg = error.toString().toLowerCase();
    final pathInfo = path != null && path.isNotEmpty ? ' Διαδρομή: $path' : '';

    if (msg.contains('database is locked') ||
        msg.contains('locked') ||
        msg.contains('busy')) {
      return DatabaseInitResult(
        status: DatabaseStatus.locked,
        message: 'Η βάση είναι κλειδωμένη από άλλη διεργασία.',
        details: 'Περιμένετε ή κλείστε άλλες εφαρμογές που μπορεί να τη χρησιμοποιούν.$pathInfo',
      );
    }
    if (msg.contains('file is not a database') ||
        msg.contains('not a database') ||
        msg.contains('corrupted') ||
        msg.contains('sqlite_error')) {
      return DatabaseInitResult(
        status: DatabaseStatus.corrupted,
        message: 'Η βάση φαίνεται κατεστραμμένη ή μη έγκυρη.',
        details: 'Επιβεβαιώστε ότι το αρχείο είναι SQLite βάση.$pathInfo',
      );
    }
    if (msg.contains('no such file') ||
        msg.contains('cannot open') ||
        msg.contains('access denied') ||
        msg.contains('permission denied') ||
        msg.contains('denied')) {
      return DatabaseInitResult(
        status: DatabaseStatus.notReadable,
        message: 'Δεν έχετε δικαίωμα ανάγνωσης του αρχείου βάσης.',
        details: 'Ελέγξτε δικαιώματα ή διαδρομή.$pathInfo',
      );
    }
    if (msg.contains('invalid path') || msg.contains('path')) {
      return DatabaseInitResult(
        status: DatabaseStatus.invalidPath,
        message: 'Η διαδρομή της βάσης δεδομένων δεν είναι έγκυρη.',
        details: 'Επιλέξτε σωστή διαδρομή από Ρυθμίσεις.$pathInfo',
      );
    }

    return DatabaseInitResult(
      status: DatabaseStatus.unknownError,
      message: 'Προέκυψε άγνωστο σφάλμα με τη βάση δεδομένων.',
      details: '$error$pathInfo',
    );
  }

  /// Επιτυχής αρχικοποίηση. Αν δοθεί [dbPath], το μήνυμα περιλαμβάνει το όνομα αρχείου.
  factory DatabaseInitResult.success([String? dbPath]) {
    String message = 'Η σύνδεση με τη βάση δεδομένων πέτυχε.';
    if (dbPath != null && dbPath.trim().isNotEmpty) {
      final filename = dbPath.split(RegExp(r'[/\\]')).last.trim();
      if (filename.isNotEmpty) {
        message = 'Η σύνδεση με τη βάση δεδομένων: $filename πέτυχε.';
      }
    }
    return DatabaseInitResult(
      status: DatabaseStatus.success,
      message: message,
    );
  }

  /// Αρχείο βάσης δεν βρέθηκε.
  factory DatabaseInitResult.fileNotFound(String dbPath) {
    return DatabaseInitResult(
      status: DatabaseStatus.fileNotFound,
      message: dbPath.isNotEmpty
          ? 'Δεν βρέθηκε αρχείο βάσης στη διαδρομή: $dbPath'
          : 'Δεν βρέθηκε αρχείο βάσης στη διαδρομή.',
      details: dbPath.isNotEmpty ? 'Διαδρομή: $dbPath' : null,
    );
  }

  /// Αρχείο δεν είναι αναγνώσιμο (δικαιώματα).
  factory DatabaseInitResult.notReadable(String? dbPath) {
    return DatabaseInitResult(
      status: DatabaseStatus.notReadable,
      message: 'Δεν έχετε δικαίωμα ανάγνωσης του αρχείου βάσης.',
      details: dbPath != null && dbPath.isNotEmpty ? 'Διαδρομή: $dbPath' : null,
    );
  }

  DatabaseInitResult copyWith({
    DatabaseStatus? status,
    String? message,
    String? details,
  }) {
    return DatabaseInitResult(
      status: status ?? this.status,
      message: message ?? this.message,
      details: details ?? this.details,
    );
  }
}
