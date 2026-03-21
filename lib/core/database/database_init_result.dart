import 'dart:io';

/// Κατάσταση αρχικοποίησης / ελέγχου βάσης δεδομένων (fail-fast).
enum DatabaseStatus {
  success,
  fileNotFound,
  accessDenied,
  corruptedOrInvalid,

  /// Σφάλμα εκτός βάσης (Flutter, plugins, δίκτυο κ.λπ.).
  applicationError,
}

/// Αποτέλεσμα αρχικοποίησης ή ελέγχου υγείας βάσης δεδομένων.
/// Χρησιμοποιείται για φιλικά μηνύματα σφαλμάτων στο UI.
class DatabaseInitResult {
  const DatabaseInitResult({
    required this.status,
    this.message,
    this.details,
    this.path,
    this.originalExceptionText,
    this.stackTraceText,
    this.technicalCode,
  });

  final DatabaseStatus status;
  final String? message;
  final String? details;
  final String? path;
  final String? originalExceptionText;
  final String? stackTraceText;
  final String? technicalCode;

  bool get isSuccess => status == DatabaseStatus.success;

  /// Πλήρες κείμενο για αντιγραφή (μήνυμα, διαδρομή, αρχικό σφάλμα, κωδικός, stack).
  String buildClipboardReport({String? dbPathFallback}) {
    final pathShown = path ?? dbPathFallback;
    final buf = StringBuffer()
      ..writeln('Κατάσταση: $status')
      ..writeln('---')
      ..writeln('Μήνυμα: ${message ?? '—'}');
    if (details != null && details!.trim().isNotEmpty) {
      buf.writeln('Λεπτομέρειες: ${details!.trim()}');
    }
    if (pathShown != null && pathShown.trim().isNotEmpty) {
      buf.writeln('Διαδρομή αρχείου/πόρος: ${pathShown.trim()}');
    }
    if (technicalCode != null && technicalCode!.trim().isNotEmpty) {
      buf.writeln('Κωδικός/αναγνωριστικό: ${technicalCode!.trim()}');
    }
    if (originalExceptionText != null &&
        originalExceptionText!.trim().isNotEmpty) {
      buf.writeln('---');
      buf.writeln('Αρχικό μήνυμα σφάλματος (runtime):');
      buf.writeln(originalExceptionText!.trim());
    }
    if (stackTraceText != null && stackTraceText!.trim().isNotEmpty) {
      buf.writeln('---');
      buf.writeln('Stack trace:');
      buf.writeln(stackTraceText!.trim());
    }
    return buf.toString();
  }

  /// Από exception (SQLite, IO, δίκτυο, Windows κ.λπ.) → συγκεκριμένα ελληνικά μηνύματα.
  factory DatabaseInitResult.fromException(
    Object error, [
    String? pathHint,
    StackTrace? stack,
  ]) {
    final raw = error.toString();
    final lower = raw.toLowerCase();
    final stackStr = stack?.toString() ?? '';
    final original = raw;

    String? winCodeFromText = _parseWindowsErrorCodeFromText(raw);
    String? path = pathHint;
    int? osErrCode;

    if (error is FileSystemException) {
      path = (error.path != null && error.path!.trim().isNotEmpty)
          ? error.path
          : pathHint;
      osErrCode = error.osError?.errorCode;
    } else if (error is SocketException) {
      osErrCode = error.osError?.errorCode;
    }

    final codeLabel = _formatOsErrorCode(osErrCode, winCodeFromText);
    final pathLine = (path != null && path.trim().isNotEmpty)
        ? 'Πλήρης διαδρομή: ${path.trim()}'
        : null;

    DatabaseInitResult build({
      required DatabaseStatus status,
      required String message,
      String? details,
    }) {
      final detailParts = <String>[];
      if (details != null && details.trim().isNotEmpty) {
        detailParts.add(details.trim());
      }
      if (pathLine != null) detailParts.add(pathLine);
      if (codeLabel != null) detailParts.add(codeLabel);
      detailParts.add('Αρχικό μήνυμα (runtime): $original');
      return DatabaseInitResult(
        status: status,
        message: message,
        details: detailParts.join('\n'),
        path: path,
        originalExceptionText: original,
        stackTraceText: stackStr.isEmpty ? null : stackStr,
        technicalCode: codeLabel,
      );
    }

    if (_isDatabaseLocked(lower, osErrCode)) {
      return build(
        status: DatabaseStatus.accessDenied,
        message:
            'Το αρχείο της βάσης δεδομένων είναι κλειδωμένο από άλλη διεργασία ή δεν ολοκληρώθηκε προηγούμενη λειτουργία εγγραφής (SQLite: database is locked / busy).',
        details:
            'Κλείστε άλλα αντίγραφα της εφαρμογής ή προγράμματα που ανοίγουν το ίδιο αρχείο .db και δοκιμάστε ξανά.',
      );
    }

    if (_isDiskFull(lower, osErrCode)) {
      return build(
        status: DatabaseStatus.accessDenied,
        message:
            'Ο δίσκος είναι γεμάτος· δεν υπάρχει επαρκής ελεύθερος χώρος για εγγραφή (συμπεριλαμβανομένης της βάσης SQLite).',
        details:
            'Αδειάστε χώρο στον δίσκο όπου βρίσκεται το αρχείο βάσης και επαναλάβετε.',
      );
    }

    if (error is FileSystemException) {
      final op = error.message;
      if (osErrCode == 5 ||
          lower.contains('access is denied') ||
          lower.contains('permission denied')) {
        return build(
          status: DatabaseStatus.accessDenied,
          message:
              'Δεν έχετε δικαιώματα πρόσβασης ή εγγραφής στο αρχείο ή στον φάκελό του (Windows: Access is denied${osErrCode != null ? ', κωδικός $osErrCode' : ''}).',
          details:
              'Ελέγξτε δικαιώματα NTFS, αν το αρχείο είναι μόνο για ανάγνωση και αν χρειάζεται εκτέλεση ως διαχειριστής.${op.trim().isNotEmpty ? ' Λειτουργία συστήματος: $op' : ''}',
        );
      }
      if (osErrCode == 32 ||
          osErrCode == 33 ||
          lower.contains('sharing violation')) {
        return build(
          status: DatabaseStatus.accessDenied,
          message:
              'Το αρχείο χρησιμοποιείται ή είναι κλειδωμένο από άλλο πρόγραμμα (κοινή χρήση αρχείου Windows).',
          details:
              'Κλείστε άλλες εφαρμογές που μπορεί να κρατούν ανοιχτό το αρχείο βάσης.',
        );
      }
    }

    if (lower.contains('read-only database') ||
        lower.contains('readonly database') ||
        lower.contains('read only database')) {
      return build(
        status: DatabaseStatus.accessDenied,
        message:
            'Η βάση είναι ανοιχτή μόνο για ανάγνωση· δεν επιτρέπεται εγγραφή (SQLite read-only).',
        details:
            'Ελέγξτε αν το αρχείο .db έχει χαρακτηριστικό «μόνο ανάγνωση», αν βρίσκεται σε μέσο μόνο ανάγνωσης ή αν η διαδρομή δικτύου δεν επιτρέπει εγγραφή.',
      );
    }

    if (lower.contains('host unreachable') ||
        lower.contains('network is unreachable') ||
        lower.contains('no route to host')) {
      return build(
        status: DatabaseStatus.applicationError,
        message:
            'Αποτυχία δικτυακής σύνδεσης: ο προορισμός δεν είναι προσβάσιμος (host / δίκτυο μη διαθέσιμο).',
        details:
            'Αν χρησιμοποιείτε VNC ή απομακρυσμένη σύνδεση, ελέγξτε IP, τείχος προστασίας και ότι η υπηρεσία τρέχει.',
      );
    }

    if (lower.contains('connection refused') ||
        (lower.contains('connection reset') && lower.contains('socket'))) {
      return build(
        status: DatabaseStatus.applicationError,
        message:
            'Η σύνδεση απορρίφθηκε ή επανεκινήθηκε από τον απομακρυσμένο υπολογιστή (connection refused / reset).',
        details:
            'Ελέγξτε ότι ο διακομιστής / το εργαλείο απομακρυσμένης πρόσβασης ακούει στη σωστή θύρα και διεύθυνση.',
      );
    }

    if (lower.contains('vnc') &&
        (lower.contains('fail') ||
            lower.contains('error') ||
            lower.contains('unable'))) {
      return build(
        status: DatabaseStatus.applicationError,
        message:
            'Σφάλμα σύνδεσης VNC ή απομακρυσμένης επιφάνειας: αποτυχία κατά τη σύνδεση ή την εκτέλεση.',
        details:
            'Δείτε το αρχικό μήνυμα παρακάτω για λεπτομέρειες από το εργαλείο.',
      );
    }

    if (lower.contains('window_manager') ||
        lower.contains('hwnd') && lower.contains('window')) {
      return build(
        status: DatabaseStatus.applicationError,
        message:
            'Σφάλμα διαχείρισης παραθύρου (window_manager / επιφάνεια εργασίας Windows).',
        details:
            'Πιθανό πρόβλημα με το παράθυρο της εφαρμογής. Δοκιμάστε επανεκκίνηση της εφαρμογής ή ενημέρωση προγραμμάτων οδήγησης γραφικών.',
      );
    }

    if (lower.contains('not a database') ||
        lower.contains('file is encrypted') ||
        lower.contains('malformed') ||
        (lower.contains('corrupt') && lower.contains('database'))) {
      return build(
        status: DatabaseStatus.corruptedOrInvalid,
        message:
            'Το αρχείο δεν είναι έγκυρη βάση SQLite ή φαίνεται κατεστραμμένο.',
        details:
            'Επαληθεύστε ότι επιλέξατε σωστό αρχείο .db και ότι δεν είναι κρυπτογραφημένο/αλλοιωμένο.',
      );
    }

    if (lower.contains('no such file') ||
        lower.contains('cannot open file') ||
        lower.contains('system cannot find the file') ||
        lower.contains('path not found') ||
        (lower.contains('errno = 2') || lower.contains('errno=2'))) {
      return build(
        status: DatabaseStatus.fileNotFound,
        message: 'Δεν βρέθηκε το αρχείο βάσης ή η διαδρομή δεν υπάρχει.',
        details:
            'Ελέγξτε τις ρυθμίσεις διαδρομής βάσης και ότι το αρχείο δεν μετονομάστηκε ή δεν διαγράφηκε.',
      );
    }

    if (lower.contains('database is locked') == false &&
        (lower.contains('unable to open') && lower.contains('database'))) {
      return build(
        status: DatabaseStatus.accessDenied,
        message:
            'Δεν ήταν δυνατό το άνοιγμα του αρχείου βάσης δεδομένων (SQLite unable to open database file).',
        details:
            'Συχνά: λάθος διαδρομή, δικαιώματα, κλειδωμένο αρχείο ή δίκτυο μη διαθέσιμο για αρχείο σε share.',
      );
    }

    if (lower.contains('disk i/o error') ||
        lower.contains('i/o error') ||
        lower.contains('io error')) {
      return build(
        status: DatabaseStatus.accessDenied,
        message:
            'Σφάλμα εισόδου/εξόδου δίσκου κατά την πρόσβαση στη βάση (disk I/O).',
        details:
            'Ελέγξτε υγεία δίσκου, σύνδεση δικτύου αν η βάση είναι σε UNC και αν το μέσο είναι προσβάσιμο.',
      );
    }

    if (lower.contains('access denied') ||
        lower.contains('permission denied') ||
        lower.contains('eacces') ||
        osErrCode == 5) {
      return build(
        status: DatabaseStatus.accessDenied,
        message:
            'Άρνηση πρόσβασης· δεν επιτρέπεται η ζητούμενη λειτουργία στο αρχείο ή τη διαδρομή.',
        details:
            'Σε Windows ο κωδικός 5 σημαίνει συνήθως «Access is denied». Ελέγξτε δικαιώματα φακέλου και αν άλλη διεργασία κρατά το αρχείο.',
      );
    }

    if (error is SocketException) {
      final os = error.osError;
      final codePart = os != null ? ' (κωδικός OS: ${os.errorCode})' : '';
      return build(
        status: DatabaseStatus.applicationError,
        message:
            'Σφάλμα δικτύου (υποδοχή / TCP-IP): ${error.message.isNotEmpty ? error.message : 'αποτυχία σύνδεσης'}$codePart',
        details:
            'Ελέγξτε διεύθυνση, θύρα, τείχος προστασίας και διαθεσιμότητα του απομακρυσμένου host.',
      );
    }

    if (error is FileSystemException) {
      final op = error.message.trim();
      return build(
        status: DatabaseStatus.applicationError,
        message:
            'Σφάλμα πρόσβασης στο σύστημα αρχείων${op.isNotEmpty ? ': $op' : ''}.',
        details:
            'Η λειτουργία αφορά αρχείο ή φάκελο στο δίσκο ή στο δίκτυο (UNC). Ελέγξτε διαδρομή και δικαιώματα.',
      );
    }

    return DatabaseInitResult(
      status: DatabaseStatus.applicationError,
      message:
          'Προέκυψε σφάλμα (${error.runtimeType}). Δείτε τις λεπτομέρειες και το αρχικό μήνυμα παρακάτω.',
      details: [
        ?pathLine,
        ?codeLabel,
        'Αρχικό μήνυμα (runtime): $original',
      ].join('\n'),
      path: path,
      originalExceptionText: original,
      stackTraceText: stackStr.isEmpty ? null : stackStr,
      technicalCode: codeLabel,
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
  factory DatabaseInitResult.accessDenied(
    String? dbPath, [
    String? extraMessage,
  ]) {
    return DatabaseInitResult(
      status: DatabaseStatus.accessDenied,
      message:
          extraMessage ??
          'Δεν έχετε δικαίωμα ανάγνωσης/εγγραφής του αρχείου βάσης.',
      details: dbPath != null && dbPath.isNotEmpty ? 'Διαδρομή: $dbPath' : null,
      path: dbPath,
    );
  }

  /// Βάση κατεστραμμένη ή μη έγκυρο αρχείο (π.χ. λείπει πίνακας calls).
  factory DatabaseInitResult.corruptedOrInvalid(
    String? dbPath, [
    String? extraMessage,
  ]) {
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
    String? originalExceptionText,
    String? stackTraceText,
    String? technicalCode,
  }) {
    return DatabaseInitResult(
      status: status ?? this.status,
      message: message ?? this.message,
      details: details ?? this.details,
      path: path ?? this.path,
      originalExceptionText:
          originalExceptionText ?? this.originalExceptionText,
      stackTraceText: stackTraceText ?? this.stackTraceText,
      technicalCode: technicalCode ?? this.technicalCode,
    );
  }
}

String? _formatOsErrorCode(int? osCode, String? winFromText) {
  if (osCode != null) {
    return 'Κωδικός σφάλματος λειτουργικού (OS error code): $osCode';
  }
  if (winFromText != null && winFromText.isNotEmpty) {
    return 'Κωδικός από μήνυμα συστήματος: $winFromText';
  }
  return null;
}

String? _parseWindowsErrorCodeFromText(String raw) {
  final m = RegExp(
    r'(?:code|errno)\s*[=:]\s*(\d+)|\(code\s*(\d+)\)|0x([0-9a-fA-F]+)',
    caseSensitive: false,
  ).firstMatch(raw);
  if (m == null) return null;
  final a = m.group(1) ?? m.group(2);
  if (a != null) return a;
  final hex = m.group(3);
  if (hex != null) return '0x${hex.toUpperCase()}';
  return null;
}

bool _isDatabaseLocked(String lower, int? osErrCode) {
  if (lower.contains('database is locked')) return true;
  if (lower.contains('sqlite_busy')) return true;
  if (lower.contains('sqlite_busy_timeout')) return true;
  if (lower.contains('cannot start a transaction within a transaction') &&
      lower.contains('locked')) {
    return true;
  }
  return false;
}

bool _isDiskFull(String lower, int? osErrCode) {
  if (lower.contains('no space left on device')) return true;
  if (lower.contains('enospc')) return true;
  if (lower.contains('disk full')) return true;
  if (lower.contains('not enough space')) return true;
  if (osErrCode == 112) return true;
  return false;
}

/// Exception που φέρει [DatabaseInitResult] όταν η αρχικοποίηση αποτύχει (fail-fast).
class DatabaseInitException implements Exception {
  const DatabaseInitException(this.result);

  final DatabaseInitResult result;

  @override
  String toString() =>
      result.message ?? 'DatabaseInitException: ${result.status}';
}
