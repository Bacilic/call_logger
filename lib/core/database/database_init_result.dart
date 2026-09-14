import 'dart:async';
import 'dart:io';

import 'database_file_identity.dart';
import 'schema_downgrade_compatibility.dart';

/// Ο διαχωριστής ανάμεσα στη **συμβουλή** προς τον χρήστη και στην **τεχνική
/// απόδειξη** μέσα στο `details`.
///
/// Υπάρχει ως σταθερά ώστε αυτός που τα ενώνει και αυτός που τα χωρίζει για
/// την οθόνη να μη συμφωνούν κατά τύχη.
const String kDiagnosticsSectionMarker = '--- Diagnostics ---';

/// Ο δείκτης του εντοπισμού κλειδώματος — γραφόταν με το χέρι σε δύο
/// διαφορετικά αρχεία. Ένα τυπογραφικό στο ένα από τα δύο θα άφηνε το
/// διαγνωστικό να τυπωθεί μέσα στη συμβουλή, χωρίς κανένα σφάλμα πουθενά.
const String kLockDiagnosticsSectionMarker = '--- Lock diagnostics ---';

/// Ο δείκτης των σημειώσεων εκκίνησης.
const String kStartupNoticesSectionMarker = '--- Προειδοποιήσεις εκκίνησης ---';

/// Κάθε δείκτης που χωρίζει τεχνικό υλικό μέσα στο `details`.
///
/// Ζουν μαζί επίτηδες: όποιος προσθέσει καινούριο τμήμα και ξεχάσει να το
/// γράψει εδώ, θα το δει να τυπώνεται αυτούσιο μέσα στη συμβουλή προς τον
/// χειριστή.
const List<String> kDetailsSectionMarkers = <String>[
  kDiagnosticsSectionMarker,
  kLockDiagnosticsSectionMarker,
  kStartupNoticesSectionMarker,
];

/// Τι διαβάζει ο χειριστής και τι ο τεχνικός, από το ίδιο πεδίο `details`.
///
/// **Το πρόβλημα που λύνει (14/09/2026):** το `details` κουβαλά δύο εντελώς
/// διαφορετικά πράγματα — τη συμβουλή προς τον χειριστή και τα διαγνωστικά
/// που μαζεύτηκαν στον δρόμο. Η οθόνη σφάλματος της εκκίνησης τα τύπωνε
/// **όλα μαζί**, οπότε μέσα στη συμβουλή φαίνονταν αυτούσιοι οι δείκτες
/// («--- Diagnostics ---») και η ωμή εντολή SQL. Ο διάλογος έκανε τον
/// διαχωρισμό μόνος του, γνωρίζοντας έναν μόνο δείκτη από τους τρεις.
///
/// Γι' αυτό ο διαχωρισμός ζει **εδώ**, δίπλα σε αυτόν που ενώνει: ένας
/// κώδικας ξέρει όλους τους δείκτες, και οι δύο οθόνες ρωτούν αυτόν.
({String advice, String diagnostics}) splitDatabaseDetails(String? details) {
  final text = details?.trim() ?? '';
  if (text.isEmpty) return (advice: '', diagnostics: '');

  var cut = -1;
  var cutMarker = '';
  for (final marker in kDetailsSectionMarkers) {
    final index = text.indexOf(marker);
    if (index < 0) continue;
    if (cut < 0 || index < cut) {
      cut = index;
      cutMarker = marker;
    }
  }
  if (cut < 0) return (advice: text, diagnostics: '');

  // Ο πρώτος δείκτης φεύγει: η οθόνη βάζει τη δική της επικεφαλίδα από πάνω.
  // Όσοι ακολουθούν μένουν — εκείνοι χωρίζουν τα τμήματα μεταξύ τους.
  return (
    advice: text.substring(0, cut).trim(),
    diagnostics: text.substring(cut + cutMarker.length).trim(),
  );
}

/// Κατάσταση αρχικοποίησης / ελέγχου βάσης δεδομένων (fail-fast).
enum DatabaseStatus {
  success,
  fileNotFound,
  accessDenied,
  corruptedOrInvalid,

  /// Σφάλμα εκτός βάσης (Flutter, plugins, δίκτυο κ.λπ.).
  applicationError,
}

/// Δομημένη πληροφορία ανάκαμψης για την οθόνη σφάλματος εκκίνησης.
/// Προτιμάται έναντι ταιριάσματος ελληνικών φράσεων στο μήνυμα.
enum DatabaseInitRecoveryKind {
  wrongDatabaseLamp,
  wrongDatabaseUnknown,
  corruptedOrMigration,
  locked,
  timeout,
  missingApplicationFile,

  /// Απαιτείται συγκατάθεση πριν από μόνιμη αναβάθμιση σχήματος.
  schemaUpgradeConsent,

  /// Το αρχείο βάσης γράφτηκε από ΝΕΟΤΕΡΗ έκδοση της εφαρμογής.
  databaseNewerThanApp,

  /// Δικτυακή διαδρομή που δεν απαντά: κομμένο δίκτυο, σβηστός διακομιστής,
  /// ή κοινόχρηστος φάκελος που ζητά διαπιστευτήρια.
  networkUnreachable,
  generic,
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
    this.recoveryKind,
    this.schemaDowngrade,
  });

  final DatabaseStatus status;
  final String? message;
  final String? details;
  final String? path;
  final String? originalExceptionText;
  final String? stackTraceText;
  final String? technicalCode;
  final DatabaseInitRecoveryKind? recoveryKind;

  /// Μόνο για [DatabaseInitRecoveryKind.databaseNewerThanApp]: αν και γιατί
  /// (δεν) προσφέρεται υποβάθμιση της βάσης στην έκδοση της εφαρμογής.
  final SchemaDowngradeAssessment? schemaDowngrade;

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
    // Έτοιμο, διατυπωμένο αποτέλεσμα ΔΕΝ ξαναμεταφράζεται: χωρίς αυτό, ένα
    // σαφές ελληνικό μήνυμα (π.χ. «βάση νεότερης έκδοσης») που περνούσε από
    // εδώ κατέληγε «Προέκυψε σφάλμα (DatabaseInitException)» — μαζί με το
    // recoveryKind του, δηλαδή και τα κουμπιά διεξόδου του.
    if (error is DatabaseInitException) {
      final ready = error.result;
      return ready.copyWith(
        path: ready.path ?? pathHint,
        stackTraceText: ready.stackTraceText ?? stack?.toString(),
      );
    }

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

    DatabaseInitResult build({
      required DatabaseStatus status,
      required String message,
      String? details,
      DatabaseInitRecoveryKind? recoveryKind,
    }) {
      final advice = (details != null && details.trim().isNotEmpty)
          ? details.trim()
          : null;
      return DatabaseInitResult(
        status: status,
        message: message,
        details: advice,
        path: path,
        originalExceptionText: original,
        stackTraceText: stackStr.isEmpty ? null : stackStr,
        technicalCode: codeLabel,
        recoveryKind: recoveryKind,
      );
    }

    if (_isDatabaseLocked(lower, osErrCode)) {
      return build(
        status: DatabaseStatus.accessDenied,
        message:
            'Το αρχείο της βάσης δεδομένων είναι κλειδωμένο από άλλη διεργασία ή δεν ολοκληρώθηκε προηγούμενη λειτουργία εγγραφής (SQLite: database is locked / busy).',
        details:
            'Κλείστε άλλα αντίγραφα της εφαρμογής ή προγράμματα που ανοίγουν το ίδιο αρχείο .db και δοκιμάστε ξανά.',
        recoveryKind: DatabaseInitRecoveryKind.locked,
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
          recoveryKind: DatabaseInitRecoveryKind.locked,
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

    // Ασυνέπεια που δεν θεραπεύεται με επανασύνδεση: ο κατάλογος της βάσης
    // παραπέμπει σε σελίδες που λείπουν από το ίδιο το αρχείο. Χωριστά από τον
    // γενικό «κατεστραμμένο» παρακάτω, γιατί εδώ η αιτία είναι γνωστή και η
    // ενέργεια του χρήστη διαφορετική: δεν επισκευάζεται, ξανα-αντιγράφεται.
    if (looksLikeCopiedWhileInUseError(raw)) {
      return build(
        status: DatabaseStatus.corruptedOrInvalid,
        message:
            'Το αρχείο της βάσης είναι ασυνεπές: ο εσωτερικός του κατάλογος '
            'παραπέμπει σε σελίδες που δεν υπάρχουν μέσα στο αρχείο.',
        details:
            'Η τυπική αιτία είναι ότι το αρχείο αντιγράφηκε ΕΝΩ η βάση ήταν '
            'ανοιχτή. Τότε το αντίγραφο παίρνει κομμάτια από διαφορετικές '
            'στιγμές και δεν αντιστοιχεί σε καμία πραγματική κατάσταση της '
            'βάσης. Δεν επισκευάζεται: χρειάζεται νέο αντίγραφο με κλειστή '
            'την εφαρμογή, ή μέσα από τα Αντίγραφα Ασφαλείας που παράγουν '
            'πάντα συνεπές αρχείο.',
        recoveryKind: DatabaseInitRecoveryKind.corruptedOrMigration,
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
        recoveryKind: DatabaseInitRecoveryKind.corruptedOrMigration,
      );
    }

    if (DatabaseInitResult._isDatabaseLayerException(error) &&
        DatabaseInitResult._isMigrationError(lower)) {
      late final String msg;
      if (DatabaseInitResult._isNoSuchTableError(lower) ||
          DatabaseInitResult._isNoSuchColumnError(lower)) {
        msg = DatabaseInitResult._getUserFriendlyMessage(lower, raw);
      } else if (DatabaseInitResult._isSqliteLogicErrorCode1(lower)) {
        msg = 'Προέκυψε πρόβλημα κατά την αναβάθμιση της βάσης δεδομένων.';
      } else {
        msg =
            'Προέκυψε πρόβλημα κατά την αναβάθμιση του σχήματος της βάσης δεδομένων.';
      }
      // Η εντολή SQL που έσκασε ΔΕΝ μπαίνει εδώ: υπάρχει ήδη αυτούσια μέσα
      // στο «Αρχικό μήνυμα σφάλματος», που δείχνουν και οι δύο οθόνες. Ως
      // τις 14/09/2026 κολλιόταν στη συμβουλή, οπότε ο χειριστής διάβαζε
      // «ALTER TABLE audit_log ADD COLUMN entity_type TEXT» ως συνέχεια της
      // πρότασης που του έλεγε τι να κάνει.
      final suggested = DatabaseInitResult._getSuggestedAction(lower, raw);
      return build(
        status: DatabaseStatus.applicationError,
        message: msg,
        details: suggested.isEmpty ? null : suggested,
        recoveryKind: DatabaseInitRecoveryKind.corruptedOrMigration,
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

    if (error is TimeoutException || lower.contains('timed out')) {
      return build(
        status: DatabaseStatus.applicationError,
        message:
            'Η βάση δεδομένων δεν απάντησε έγκαιρα. Πιθανό προσωρινό πρόβλημα πρόσβασης ή κλειδώματος αρχείου στα Windows.',
        details:
            'Κλείστε εντελώς την εφαρμογή και ανοίξτε την ξανά. Αν το πρόβλημα συνεχιστεί, ελέγξτε αν άλλη διεργασία ή υπηρεσία κρατά ανοιχτό το αρχείο .db.',
        recoveryKind: DatabaseInitRecoveryKind.timeout,
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

    if (DatabaseInitResult._isDatabaseLayerException(error)) {
      return build(
        status: DatabaseStatus.applicationError,
        message:
            'Προέκυψε πρόβλημα κατά την πρόσβαση ή την ενημέρωση της βάσης δεδομένων (SQLite).',
        details:
            'Ελέγξτε τη διαδρομή στις ρυθμίσεις και τα δικαιώματα. '
            'Αν το αρχείο φαίνεται κατεστραμμένο ή ασύμβατο, δοκιμάστε νέα βάση από τις ρυθμίσεις.',
        recoveryKind: DatabaseInitRecoveryKind.generic,
      );
    }

    if (_isMissingApplicationFile(lower)) {
      final fileName = _extractMissingApplicationFileName(raw);
      final filePart = (fileName != null && fileName.isNotEmpty)
          ? ': $fileName'
          : '';
      return build(
        status: DatabaseStatus.applicationError,
        message:
            'Λείπει ή έχει αλλοιωθεί κρίσιμο αρχείο της εφαρμογής$filePart. '
            'Η επανεγκατάσταση της εφαρμογής θα διορθώσει το πρόβλημα.',
        details:
            'Μην διαγράφετε αρχεία μέσα στον φάκελο της εφαρμογής· επανεγκαταστήστε την.',
        recoveryKind: DatabaseInitRecoveryKind.missingApplicationFile,
      );
    }

    return DatabaseInitResult(
      status: DatabaseStatus.applicationError,
      message:
          'Προέκυψε σφάλμα (${error.runtimeType}). Δείτε διαδρομή, τεχνικά στοιχεία και αντιγραφή πλήρους αναφοράς αν χρειάζεται.',
      details: null,
      path: path,
      originalExceptionText: original,
      stackTraceText: stackStr.isEmpty ? null : stackStr,
      technicalCode: codeLabel,
      recoveryKind: DatabaseInitRecoveryKind.generic,
    );
  }

  static bool _isDatabaseLayerException(Object error) {
    final t = error.runtimeType.toString();
    final s = error.toString();
    if (t.contains('Sqflite') || t.contains('DatabaseException')) return true;
    if (s.contains('SqfliteFfiException')) return true;
    if (s.contains('SqliteException')) return true;
    if (s.contains('sqlite_error:')) return true;
    if (s.contains('DatabaseException(')) return true;
    if (s.contains('no such table:')) return true;
    if (s.contains('no such column:')) return true;
    return false;
  }

  static bool _isNoSuchTableError(String lower) =>
      lower.contains('no such table');

  static bool _isNoSuchColumnError(String lower) =>
      lower.contains('no such column');

  static bool _isMigrationError(String lower) {
    if (_isNoSuchTableError(lower) || _isNoSuchColumnError(lower)) {
      return true;
    }
    if (lower.contains('sql logic error') &&
        (lower.contains('alter table') ||
            lower.contains('duplicate column') ||
            lower.contains('cannot add a ') ||
            lower.contains('has no column named'))) {
      return true;
    }
    return false;
  }

  static String? _extractTableNameFromError(String raw) {
    final m = RegExp(
      r'no such table:\s*(\S+)',
      caseSensitive: false,
    ).firstMatch(raw);
    if (m != null) {
      var name = m.group(1)?.trim() ?? '';
      name = name.replaceAll(RegExp(r'[,;)\]]+$'), '');
      if (name.isNotEmpty) return name;
    }
    final m2 = RegExp(
      r'Causing statement:\s*ALTER\s+TABLE\s+(\S+)\s+',
      caseSensitive: false,
    ).firstMatch(raw);
    if (m2 != null) {
      var name = m2.group(1)?.trim() ?? '';
      name = name.replaceAll(RegExp(r'[,;)\]]+$'), '');
      if (name.isNotEmpty) return name;
    }
    return null;
  }

  static String? _extractColumnNameFromError(String raw) {
    final m = RegExp(
      r'no such column:\s*(\S+)',
      caseSensitive: false,
    ).firstMatch(raw);
    if (m == null) return null;
    var name = m.group(1)?.trim() ?? '';
    name = name.replaceAll(RegExp(r'[,;)\]]+$'), '');
    return name.isEmpty ? null : name;
  }

  static bool _isSqliteLogicErrorCode1(String lower) =>
      lower.contains('sql logic error') && lower.contains('code 1');

  static String _getUserFriendlyMessage(String lower, String raw) {
    if (_isNoSuchTableError(lower)) {
      final t = _extractTableNameFromError(raw);
      if (t != null && t.isNotEmpty) {
        return 'Η βάση δεδομένων είναι κατεστραμμένη ή βρίσκεται σε παλιά μορφή.\n'
            'Λείπει ο πίνακας «$t».';
      }
      return 'Η βάση δεδομένων είναι κατεστραμμένη ή βρίσκεται σε παλιά μορφή.\n'
          'Λείπει αναμενόμενος πίνακας.';
    }
    if (_isNoSuchColumnError(lower)) {
      final c = _extractColumnNameFromError(raw);
      if (c != null && c.isNotEmpty) {
        return 'Η βάση δεδομένων είναι κατεστραμμένη ή σε ασύμβατη μορφή.\n'
            'Λείπει η στήλη «$c».';
      }
      return 'Η βάση δεδομένων είναι κατεστραμμένη ή σε ασύμβατη μορφή.\n'
          'Λείπει αναμενόμενη στήλη.';
    }
    return 'Προέκυψε πρόβλημα κατά την αναβάθμιση της βάσης δεδομένων.';
  }

  /// Τι να κάνει ο χειριστής — με σειρά προτεραιότητας, από το αναστρέψιμο
  /// προς το οριστικό.
  ///
  /// **Γιατί δεν λέει «διαγράψτε» (14/09/2026):** ως τότε και οι δύο
  /// προτάσεις ζητούσαν διαγραφή του αρχείου βάσης ως ΠΡΩΤΗ ενέργεια, χωρίς
  /// καν προτροπή να κρατηθεί αντίγραφο. Η ίδια οθόνη όμως προσφέρει από
  /// κάτω κουμπί «Επαναφορά από αντίγραφο ασφαλείας» — δηλαδή τα λόγια
  /// αντίφασκαν με τα κουμπιά, και τα λόγια ήταν ο καταστροφικός δρόμος.
  ///
  /// Οι ενέργειες **δεν ονομάζονται με ετικέτες κουμπιών**: το ίδιο κείμενο
  /// εμφανίζεται και στον διάλογο «Η βάση δεν είναι έγκυρη», που έχει μόνο
  /// «Εντάξει». Ένα κουμπί που ονομάζεται και δεν υπάρχει είναι μήνυμα-ψέμα.
  static String _getSuggestedAction(String lower, String raw) {
    if (_isNoSuchTableError(lower) || _isNoSuchColumnError(lower)) {
      return 'Μην διαγράψετε το αρχείο της βάσης σας. Η ασφαλής σειρά είναι: '
          'πρώτα επαναφορά από αντίγραφο ασφαλείας· αν η σωστή βάση βρίσκεται '
          'αλλού, επιλογή εκείνου του αρχείου· και τελευταία, δημιουργία νέας '
          'άδειας βάσης, που ξεκινά από το μηδέν.';
    }
    if (_isSqliteLogicErrorCode1(lower) || _isMigrationError(lower)) {
      return 'Μην διαγράψετε το αρχείο της βάσης σας. Δοκιμάστε πρώτα '
          'επαναφορά από αντίγραφο ασφαλείας ή επιλογή άλλου αρχείου βάσης.';
    }
    return '';
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
          ? 'Δεν βρέθηκε το αρχείο της Βάσης Δεδομένων στη διαδρομή.'
          : 'Δεν βρέθηκε το αρχείο της Βάσης Δεδομένων στη διαδρομή.',
      details: dbPath.isNotEmpty ? 'Διαδρομή: $dbPath' : null,
      path: dbPath.isNotEmpty ? dbPath : null,
    );
  }

  /// Η δικτυακή διαδρομή της βάσης δεν απάντησε.
  ///
  /// Χωριστή από το «δεν βρέθηκε το αρχείο»: εκεί ξέρουμε ότι το αρχείο λείπει,
  /// εδώ δεν ξέρουμε τίποτα — το αρχείο μπορεί να είναι μια χαρά και απλώς να
  /// μη φτάνουμε σ' αυτό. Η διαφορά αλλάζει τη διέξοδο που έχει νόημα να
  /// προσφερθεί.
  factory DatabaseInitResult.networkUnreachable(String dbPath) {
    return DatabaseInitResult(
      status: DatabaseStatus.accessDenied,
      message: 'Δεν υπάρχει πρόσβαση στη διαδρομή της Βάσης Δεδομένων.',
      details:
          'Διαδρομή: $dbPath\n\n'
          'Ο κοινόχρηστος φάκελος δεν απάντησε. Συνήθεις αιτίες: δεν υπάρχει '
          'σύνδεση στο δίκτυο του νοσοκομείου, ο διακομιστής είναι σβηστός, ή '
          'τα Windows ζητούν διαπιστευτήρια για τον φάκελο.',
      path: dbPath,
      recoveryKind: DatabaseInitRecoveryKind.networkUnreachable,
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
          'Δεν έχετε δικαίωμα ανάγνωσης/εγγραφής του αρχείου της Βάσης Δεδομένων.',
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
    DatabaseInitRecoveryKind? recoveryKind,
    SchemaDowngradeAssessment? schemaDowngrade,
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
      recoveryKind: recoveryKind ?? this.recoveryKind,
      schemaDowngrade: schemaDowngrade ?? this.schemaDowngrade,
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

bool _isMissingApplicationFile(String lower) {
  // Δευτερογενές σύμπτωμα: το πραγματικό σφάλμα (π.χ. «Failed to load dynamic
  // library sqlite3.dll») καταπίνεται στο σιωπηλό catch του main.dart, οπότε το
  // ΜΟΝΟ που φτάνει εδώ όταν λείπει η μηχανή SQLite (sqlite3.dll ή
  // NativeAssetsManifest.json) είναι το «Bad state: databaseFactory not
  // initialized». Στην παραγωγική εκκίνηση το databaseFactory αρχικοποιείται
  // πάντα (main.dart:163-164)· αν λείπει, λείπει native υποδομή → κρίσιμο αρχείο.
  if (lower.contains('databasefactory not initialized')) return true;

  // Πρωτογενή σήματα (αν κάποια ροή τα διατηρεί χωρίς να τα καταπιεί).
  final nativeLib =
      lower.contains('failed to load dynamic library') ||
      (lower.contains('sqlite3') &&
          (lower.contains('could not be found') ||
              lower.contains('error code: 126') ||
              lower.contains('cannot open shared object')));
  if (nativeLib) return true;

  return lower.contains('unable to load asset') ||
      lower.contains('assetmanifest') ||
      lower.contains('nativeassetsmanifest') ||
      lower.contains('kernel_blob') ||
      lower.contains('flutter_assets');
}

String? _extractMissingApplicationFileName(String raw) {
  final matches = RegExp(
    r'''[\w.\-]+\.(?:dll|json|bin|so|dylib|blob)''',
    caseSensitive: false,
  ).allMatches(raw);
  if (matches.isEmpty) return null;
  return matches.last.group(0);
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
