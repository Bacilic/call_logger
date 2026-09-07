import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Καταγραφή σφαλμάτων και καταρρεύσεων σε ημερήσια αρχεία δίπλα στη βάση.
///
/// **Ο φάκελος μπορεί να είναι στο δίκτυο.** Ζει δίπλα στη βάση, και η βάση
/// ζει συχνά σε κοινόχρηστο φάκελο· όταν εκείνος δεν απαντά, κάθε πράξη
/// αρχείου πάνω του περιμένει τα Windows επ' αόριστον. Επειδή το στήσιμο
/// τρέχει **πριν** από την πρώτη οθόνη, μια τέτοια αναμονή δεν φαίνεται ως
/// καθυστέρηση αλλά ως **λευκό παράθυρο χωρίς διέξοδο**.
///
/// Γι' αυτό κάθε πράξη έχει όριο χρόνου, και η αποτυχία δεν είναι μοιραία:
/// η υπηρεσία περνά σε λειτουργία **χωρίς δίσκο** ([isDiskAvailable] false)
/// και δεν ξαναγγίζει τη διαδρομή — ούτε στη σύγχρονη καταγραφή σφαλμάτων,
/// που τρέχει στο νήμα της διεπαφής και θα την πάγωνε σε κάθε σφάλμα.
class CrashLogService {
  CrashLogService({
    required this.logsDirectory,
    this.appVersion = 'unknown',
    DateTime Function()? now,
    this._maxDetailedRepeats = 20,
    this._repeatSummaryInterval = 100,
  }) : _now = now ?? DateTime.now;

  static const String sessionLockFileName = 'session.lock';
  static const String abnormalTerminationMessage =
      'Η προηγούμενη εκτέλεση δεν τερμάτισε ομαλά (πιθανή κατάρρευση χωρίς ίχνη).';

  static CrashLogService? _instance;

  static CrashLogService? get instanceOrNull => _instance;

  static CrashLogService get instance {
    final current = _instance;
    if (current == null) {
      throw StateError('CrashLogService δεν έχει αρχικοποιηθεί.');
    }
    return current;
  }

  /// Μέγιστη αναμονή για κάθε πράξη αρχείου του ημερολογίου.
  ///
  /// Ίδιο μέγεθος με τους υπόλοιπους κριτές δικτύου της εφαρμογής: πέρα από
  /// τρία δευτερόλεπτα η σιωπή δεν διαβάζεται πια ως καθυστέρηση.
  static const Duration diskProbeTimeout = Duration(seconds: 3);

  /// Ο φάκελος των ημερήσιων αρχείων. Αλλάζει μόνο μέσω [retargetTo].
  String logsDirectory;
  bool _diskAvailable = true;
  String? _diskUnavailableReason;

  /// False όταν ο φάκελος δεν απάντησε: τίποτα δεν γράφεται στον δίσκο.
  bool get isDiskAvailable => _diskAvailable;

  /// Γιατί σίγησε το ημερολόγιο — για την αναφορά της εκκίνησης.
  String? get diskUnavailableReason => _diskUnavailableReason;

  final String appVersion;
  final DateTime Function() _now;
  final int _maxDetailedRepeats;
  final int _repeatSummaryInterval;

  final Map<String, _DedupState> _dedupStates = {};

  static String logsDirectoryForDatabasePath(String databasePath) {
    return p.join(p.dirname(p.normalize(databasePath)), 'logs');
  }

  static String dailyLogFileName(DateTime dateTime) {
    final y = dateTime.year.toString().padLeft(4, '0');
    final m = dateTime.month.toString().padLeft(2, '0');
    final d = dateTime.day.toString().padLeft(2, '0');
    return 'errors_$y-$m-$d.log';
  }

  static Future<void> initialize({
    required String databasePath,
    required String appVersion,
    required int retentionCount,
    Duration timeout = diskProbeTimeout,
    Future<void> Function(String directory)? createDirectory,
  }) async {
    // Δεν καταπίνουμε αποτυχίες του initialize: ο καλών πρέπει να δει την
    // πρωτογενή αιτία (π.χ. logs φάκελος/δικαιώματα). Η υπηρεσία όμως έχει
    // ήδη περάσει σε λειτουργία χωρίς δίσκο, ώστε η εκκίνηση να συνεχίσει.
    final logsDir = logsDirectoryForDatabasePath(databasePath);
    final service = CrashLogService(
      logsDirectory: logsDir,
      appVersion: appVersion,
    );
    _instance = service;
    await service.onStartup(
      retentionCount: retentionCount,
      timeout: timeout,
      createDirectory: createDirectory,
    );
  }

  /// Μετακομίζει το ημερολόγιο δίπλα σε **άλλη** βάση.
  ///
  /// Χρειάζεται όταν η εκκίνηση κατέληξε σε διαφορετική βάση από τη
  /// ρυθμισμένη (π.χ. ο χρήστης δέχτηκε την τοπική επειδή το δίκτυο δεν
  /// απαντούσε): χωρίς αυτό, το ημερολόγιο θα έμενε σιωπηλό για όλη τη
  /// συνεδρία, δείχνοντας ακόμη στον φάκελο που δεν απάντησε.
  Future<void> retargetTo({
    required String databasePath,
    required int retentionCount,
    Duration timeout = diskProbeTimeout,
    Future<void> Function(String directory)? createDirectory,
  }) async {
    final next = logsDirectoryForDatabasePath(databasePath);
    if (next == logsDirectory && _diskAvailable) return;
    logsDirectory = next;
    _diskAvailable = true;
    _diskUnavailableReason = null;
    try {
      await onStartup(
        retentionCount: retentionCount,
        timeout: timeout,
        createDirectory: createDirectory,
      );
    } catch (_) {
      // Η κατάσταση «χωρίς δίσκο» έχει ήδη μπει· η μετακόμιση είναι
      // νοικοκυριό και δεν επιτρέπεται να ρίξει τη ροή που την κάλεσε.
    }
  }

  /// Το [createDirectory] υπάρχει για τα τεστ — αλλιώς ρωτιέται το πραγματικό
  /// σύστημα αρχείων.
  Future<void> onStartup({
    required int retentionCount,
    Duration timeout = diskProbeTimeout,
    Future<void> Function(String directory)? createDirectory,
  }) async {
    // Δεν καταπίνουμε αποτυχίες του onStartup: αν δεν δημιουργηθεί το
    // ημερολόγιο, οι σημειώσεις εκκίνησης πρέπει να μείνουν διαθέσιμες.
    // Πριν ξαναπεταχτούν όμως, σβήνει ο δίσκος: ό,τι ακολουθεί σε αυτή τη
    // συνεδρία δεν έχει λόγο να ξαναπεριμένει την ίδια διαδρομή.
    final create =
        createDirectory ??
        (String directory) => Directory(directory).create(recursive: true);
    try {
      await create(logsDirectory).timeout(timeout);
      await _purgeOldLogFiles(retentionCount).timeout(timeout);
      final lock = _sessionLockFile();
      if (await lock.exists().timeout(timeout)) {
        _logPlainMessage(abnormalTerminationMessage, fatal: true);
      }
      await lock.writeAsString('1', flush: true).timeout(timeout);
    } catch (error) {
      _disableDisk(error);
      rethrow;
    }
  }

  void _disableDisk(Object reason) {
    _diskAvailable = false;
    _diskUnavailableReason = reason is TimeoutException
        ? 'Ο φάκελος «$logsDirectory» δεν απάντησε μέσα σε '
              '${diskProbeTimeout.inSeconds} δευτερόλεπτα.'
        : reason.toString();
  }

  Future<void> onShutdown() async {
    if (!_diskAvailable) return;
    try {
      _flushPendingRepeatSummaries();
      final lock = _sessionLockFile();
      if (await lock.exists().timeout(diskProbeTimeout)) {
        await lock.delete().timeout(diskProbeTimeout);
      }
    } catch (_) {}
  }

  /// Καταγράφει ένα σφάλμα.
  ///
  /// Το [diagnostics] είναι για τα σφάλματα που **δεν φέρνουν ίχνος**: τα
  /// σφάλματα διάταξης δεν έχουν στοίβα κλήσεων, έχουν όμως την αλυσίδα των
  /// widget που τα γέννησε. Χωρίς αυτήν, η εγγραφή είναι μία γραμμή που λέει
  /// «κάτι ξεχείλισε» και δεν οδηγεί πουθενά.
  void logError(
    Object error,
    StackTrace stack, {
    required bool fatal,
    String? diagnostics,
  }) {
    try {
      _logErrorInternal(error, stack, fatal: fatal, diagnostics: diagnostics);
    } catch (_) {}
  }

  void _logErrorInternal(
    Object error,
    StackTrace stack, {
    required bool fatal,
    String? diagnostics,
  }) {
    // Ο φάκελος μπορεί να είναι σε δίκτυο που δεν απαντά. Η δημιουργία είναι
    // σύγχρονη και τρέχει στο νήμα της διεπαφής: χωρίς αυτή τη γραμμή, ένα
    // χαμένο δίκτυο θα πάγωνε την εφαρμογή σε **κάθε** σφάλμα που καταγράφεται.
    if (!_diskAvailable) return;
    Directory(logsDirectory).createSync(recursive: true);
    final key = _dedupKey(error, stack);
    final state = _dedupStates.putIfAbsent(key, _DedupState.new);

    if (state.detailedCount < _maxDetailedRepeats) {
      _writeDetailedEntry(
        message: error.toString(),
        stack: stack,
        fatal: fatal,
        diagnostics: diagnostics,
      );
      state.detailedCount++;
      return;
    }

    state.suppressedCount++;
    if (state.suppressedCount % _repeatSummaryInterval == 0) {
      _writeRepeatSummary(state.suppressedCount, key);
      state.suppressedCount = 0;
    }
  }

  void _flushPendingRepeatSummaries() {
    for (final entry in _dedupStates.entries) {
      final suppressed = entry.value.suppressedCount;
      if (suppressed <= 0) continue;
      _writeRepeatSummary(suppressed, entry.key);
      entry.value.suppressedCount = 0;
    }
  }

  void _logPlainMessage(String message, {required bool fatal}) {
    _writeDetailedEntry(message: message, stack: null, fatal: fatal);
  }

  void _writeDetailedEntry({
    required String message,
    StackTrace? stack,
    required bool fatal,
    String? diagnostics,
  }) {
    final buffer = StringBuffer()
      ..writeln(_formatHeader(fatal: fatal))
      ..writeln(message);
    if (diagnostics != null && diagnostics.trim().isNotEmpty) {
      buffer.writeln(diagnostics.trim());
    }
    if (stack != null) {
      buffer.write(stack);
    }
    buffer.writeln('\n');
    _appendToDailyLog(buffer.toString());
  }

  void _writeRepeatSummary(int count, String dedupKey) {
    final preview = dedupKey.split('\n').first;
    final buffer = StringBuffer()
      ..writeln(_formatHeader(fatal: false))
      ..writeln('επαναλήφθηκε $count φορές — $preview')
      ..writeln();
    _appendToDailyLog(buffer.toString());
  }

  String _formatHeader({required bool fatal}) {
    final now = _now();
    final stamp =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    final severity = fatal ? 'ΜΟΙΡΑΙΟ' : 'ΜΗ-ΜΟΙΡΑΙΟ';
    return '[$stamp] v$appVersion $severity';
  }

  void _appendToDailyLog(String chunk) {
    final file = File(p.join(logsDirectory, dailyLogFileName(_now())));
    file.writeAsStringSync(chunk, mode: FileMode.append, flush: true);
  }

  Future<void> _purgeOldLogFiles(int retentionCount) async {
    final dir = Directory(logsDirectory);
    if (!await dir.exists()) return;

    final files = await dir
        .list()
        .where(
          (entity) =>
              entity is File &&
              p.basename(entity.path).startsWith('errors_') &&
              p.basename(entity.path).endsWith('.log'),
        )
        .cast<File>()
        .toList();
    if (files.length <= retentionCount) return;

    files.sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    for (final file in files.skip(retentionCount)) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  File _sessionLockFile() =>
      File(p.join(logsDirectory, sessionLockFileName));

  static String _dedupKey(Object error, StackTrace stack) {
    final firstStackLine = stack
        .toString()
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    return '${error.toString()}\n$firstStackLine';
  }
}

class _DedupState {
  int detailedCount = 0;
  int suppressedCount = 0;
}
