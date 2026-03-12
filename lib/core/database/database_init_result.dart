/// Κατάσταση αρχικοποίησης / ελέγχου βάσης δεδομένων (fail-fast).
enum DatabaseStatus {
  success,
  fileNotFound,
  accessDenied,
  corruptedOrInvalid,
}

/// Αποτέλεσμα αρχικοποίησης ή ελέγχου υγείας βάσης δεδομένων.
/// Χρησιμοποιείται για φιλικά μηνύματα σφαλμάτων στο UI.
class DatabaseInitResult {
  const DatabaseInitResult({
    required this.status,
    this.message,
    this.details,
    this.path,
  });

  final DatabaseStatus status;
  final String? message;
  final String? details;
  /// Διαδρομή αρχείου βάσης (για προβολή στο UI).
  final String? path;

  bool get isSuccess => status == DatabaseStatus.success;

  /// Από exception (SQLite / IO) → κατάλληλο status (accessDenied ή corruptedOrInvalid).
  factory DatabaseInitResult.fromException(Object error, [String? path]) {
    final msg = error.toString().toLowerCase();
    final pathInfo = path != null && path.isNotEmpty ? ' Διαδρομή: $path' : '';

    if (msg.contains('database is locked') ||
        msg.contains('locked') ||
        msg.contains('busy') ||
        msg.contains('access denied') ||
        msg.contains('permission denied') ||
        msg.contains('denied') ||
        msg.contains('readonly') ||
        msg.contains('read-only')) {
      return DatabaseInitResult(
        status: DatabaseStatus.accessDenied,
        message: 'Αδυναμία πρόσβασης ή εγγραφής στο αρχείο βάσης.',
        details: 'Ελέγξτε δικαιώματα ή ότι το αρχείο δεν είναι κλειδωμένο.$pathInfo',
        path: path,
      );
    }
    if (msg.contains('no such file') || msg.contains('cannot open')) {
      return DatabaseInitResult(
        status: DatabaseStatus.fileNotFound,
        message: 'Δεν βρέθηκε αρχείο βάσης.',
        details: path != null && path.isNotEmpty ? 'Διαδρομή: $path' : null,
        path: path,
      );
    }
    return DatabaseInitResult(
      status: DatabaseStatus.corruptedOrInvalid,
      message: 'Η βάση φαίνεται κατεστραμμένη ή μη έγκυρη.',
      details: 'Επιβεβαιώστε ότι το αρχείο είναι SQLite βάση.$pathInfo',
      path: path,
    );
  }

  /// Επιτυχής αρχικοποίηση.
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
      path: dbPath,
    );
  }

  /// Αρχείο βάσης δεν βρέθηκε.
  factory DatabaseInitResult.fileNotFound(String dbPath) {
    return DatabaseInitResult(
      status: DatabaseStatus.fileNotFound,
      message: dbPath.isNotEmpty
          ? 'Δεν βρέθηκε αρχείο βάσης στη διαδρομή.'
          : 'Δεν βρέθηκε αρχείο βάσης στη διαδρομή.',
      details: dbPath.isNotEmpty ? 'Διαδρομή: $dbPath' : null,
      path: dbPath.isNotEmpty ? dbPath : null,
    );
  }

  /// Αδυναμία πρόσβασης (δικαιώματα, κλειδωμένο).
  factory DatabaseInitResult.accessDenied(String? dbPath, [String? extraMessage]) {
    return DatabaseInitResult(
      status: DatabaseStatus.accessDenied,
      message: extraMessage ?? 'Δεν έχετε δικαίωμα ανάγνωσης/εγγραφής του αρχείου βάσης.',
      details: dbPath != null && dbPath.isNotEmpty ? 'Διαδρομή: $dbPath' : null,
      path: dbPath,
    );
  }

  /// Βάση κατεστραμμένη ή μη έγκυρο αρχείο (π.χ. λείπει πίνακας calls).
  factory DatabaseInitResult.corruptedOrInvalid(String? dbPath, [String? extraMessage]) {
    return DatabaseInitResult(
      status: DatabaseStatus.corruptedOrInvalid,
      message: extraMessage ?? 'Η βάση φαίνεται κατεστραμμένη ή μη έγκυρη.',
      details: dbPath != null && dbPath.isNotEmpty
          ? 'Επιβεβαιώστε ότι το αρχείο είναι SQLite βάση. Διαδρομή: $dbPath'
          : 'Επιβεβαιώστε ότι το αρχείο είναι SQLite βάση.',
      path: dbPath,
    );
  }

  /// Exception που μεταφέρει αποτέλεσμα αρχικοποίησης (για fail-fast από DatabaseHelper).
  static DatabaseInitException toException(DatabaseInitResult result) {
    return DatabaseInitException(result);
  }

  DatabaseInitResult copyWith({
    DatabaseStatus? status,
    String? message,
    String? details,
    String? path,
  }) {
    return DatabaseInitResult(
      status: status ?? this.status,
      message: message ?? this.message,
      details: details ?? this.details,
      path: path ?? this.path,
    );
  }
}

/// Exception που φέρει [DatabaseInitResult] όταν η αρχικοποίηση αποτύχει (fail-fast).
class DatabaseInitException implements Exception {
  const DatabaseInitException(this.result);

  final DatabaseInitResult result;

  @override
  String toString() => result.message ?? 'DatabaseInitException: ${result.status}';
}
