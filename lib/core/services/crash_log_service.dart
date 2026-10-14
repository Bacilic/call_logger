import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'log_file_names.dart';
import 'log_record.dart';
import 'log_retention.dart';
import 'operator_presence_heartbeat.dart';
import 'session_liveness_keeper.dart';
import 'session_liveness_mark.dart';
import 'station_name.dart';
import 'station_shutdown_request.dart';

/// Καταγραφή σφαλμάτων, εκκινήσεων και κλεισιμάτων σε ημερήσια αρχεία δίπλα
/// στη βάση — μία εγγραφή [LogRecord] ανά γραμμή.
///
/// **Το μοναδικό σημείο που γράφει στα αρχεία καταγραφής.** Εδώ σφραγίζεται
/// κάθε εγγραφή με τον σταθμό και την έκδοση: ο φάκελος είναι κοινός όταν η
/// βάση είναι κοινή, και μια εγγραφή χωρίς σταθμό δεν ξεχωρίζει από τις
/// εγγραφές των συναδέλφων.
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
///
/// **Ο μοναδικός κάτοχος του φακέλου `logs`:** αυτός κρίνει τη διαθεσιμότητα,
/// αυτός μετακομίζει ([retargetTo]). Τρεις συνεργάτες δουλεύουν πάντα μέσα από
/// αυτόν — [LogFileNames] (πώς λέγεται κάθε αρχείο), [LogRetention] (τι
/// σβήνεται) και [SessionLivenessKeeper] (το ίχνος «τρέχω τώρα» και ο παλμός).
class CrashLogService {
  CrashLogService({
    required this.logsDirectory,
    this.appVersion = 'unknown',
    DateTime Function()? now,
    String? databaseFileName,
    String? instanceId,
    this._maxDetailedRepeats = 20,
    this._repeatSummaryInterval = 100,
  }) : _now = now ?? DateTime.now,
       databaseFileName = databaseFileName?.trim(),
       instanceId = (instanceId ?? OperatorPresenceHeartbeat.instanceId).trim();

  /// **Το όνομα αρχείου** της βάσης που κρατά αυτή η εκτέλεση.
  ///
  /// Το ίχνος το κουβαλά ώστε ο φρουρός της αναβάθμισης να ξεχωρίζει ποιος
  /// κρατά **αυτή** τη βάση από ποιον δουλεύει στη διπλανή: ο φάκελος `logs`
  /// είναι ένας για όλες τις βάσεις του ίδιου καταλόγου.
  String? databaseFileName;

  /// Ποιο ανοιχτό αντίγραφο της εφαρμογής είναι αυτό.
  ///
  /// Μένει σταθερό από εκκίνηση σε εκκίνηση (διαδρομή εκτελέσιμου + προφίλ),
  /// ώστε το ίχνος να **ξαναγράφεται** αντί να συσσωρεύεται — και να διαφέρει
  /// ανάμεσα στην κανονική και τη δοκιμαστική έκδοση του ίδιου υπολογιστή.
  final String instanceId;

  /// Το όνομα του ίχνους «τρέχω τώρα» μιας εκτέλεσης — δες
  /// [LogFileNames.sessionLockFileNameFor].
  static String sessionLockFileNameFor(
    String station, [
    String instance = '',
  ]) => LogFileNames.sessionLockFileNameFor(station, instance);

  /// Δες [LogFileNames.instanceSlug].
  static String instanceSlug(String instanceId) =>
      LogFileNames.instanceSlug(instanceId);

  /// Δες [LogFileNames.legacySharedSessionLockFileName].
  static const String legacySharedSessionLockFileName =
      LogFileNames.legacySharedSessionLockFileName;

  static const String abnormalTerminationMessage =
      'Η προηγούμενη εκτέλεση δεν τερμάτισε ομαλά (πιθανή κατάρρευση χωρίς ίχνη).';

  /// Κάθε πότε ανανεώνεται το σημάδι ζωής.
  ///
  /// Ίδιο με τον χτύπο παρουσίας χρήστη — ένας ορισμός του «πρόσφατου» σε όλη
  /// την εφαρμογή. Το κόστος είναι μικρότερο από εκείνον: ένα μικρό αρχείο
  /// αντί για εγγραφή στη βάση.
  static const Duration livenessInterval = Duration(minutes: 1);

  static CrashLogService? _instance;

  static CrashLogService? get instanceOrNull => _instance;

  /// Ξεχνά το καθολικό στιγμιότυπο. **Μόνο για τα τεστ.**
  ///
  /// Χωρίς αυτό, ένας έλεγχος που στήνει το ημερολόγιο το αφήνει στημένο για
  /// όλους τους επόμενους του αρχείου — και η συμπεριφορά «τι γίνεται όταν το
  /// ημερολόγιο ΛΕΙΠΕΙ» γίνεται αδύνατο να ελεγχθεί χωρίς να εξαρτάται από τη
  /// σειρά εκτέλεσης.
  @visibleForTesting
  static void resetForTest() {
    _instance?.stopLivenessHeartbeat();
    _instance = null;
  }

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

  /// Το ρολόι της υπηρεσίας — το ίδιο για κάθε συνεργάτη, ώστε τα τεστ να
  /// ορίζουν τον χρόνο σε ένα σημείο.
  DateTime clock() => _now();

  final Map<String, _DedupState> _dedupStates = {};

  late final SessionLivenessKeeper _liveness = SessionLivenessKeeper(this);

  /// Δες [LogFileNames.logsDirectoryForDatabasePath].
  static String logsDirectoryForDatabasePath(String databasePath) =>
      LogFileNames.logsDirectoryForDatabasePath(databasePath);

  /// Δες [LogFileNames.dailyLogFileName].
  static String dailyLogFileName(DateTime dateTime) =>
      LogFileNames.dailyLogFileName(dateTime);

  /// Δες [LogFileNames.isDailyLogFileName].
  static bool isDailyLogFileName(String fileName) =>
      LogFileNames.isDailyLogFileName(fileName);

  /// Δες [LogFileNames.dayOfLogFile].
  static DateTime? dayOfLogFile(String fileName) =>
      LogFileNames.dayOfLogFile(fileName);

  static const String logFilePrefix = LogFileNames.logFilePrefix;
  static const String logFileSuffix = LogFileNames.logFileSuffix;
  static const String legacyErrorLogPrefix = LogFileNames.legacyErrorLogPrefix;
  static const String legacySessionLogPrefix =
      LogFileNames.legacySessionLogPrefix;

  /// Δες [LogFileNames.isLegacyDailyLogFileName].
  static bool isLegacyDailyLogFileName(String fileName) =>
      LogFileNames.isLegacyDailyLogFileName(fileName);

  /// Δες [LogFileNames.legacyShutdownTracePrefix].
  static const String legacyShutdownTracePrefix =
      LogFileNames.legacyShutdownTracePrefix;

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
      databaseFileName: p.basename(p.normalize(databasePath)),
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
    final previous = logsDirectory;
    // Η συνεδρία δεν τελειώνει — μετακομίζει. Ο παλιός φάκελος το μαθαίνει,
    // αλλιώς η εξαγωγή του τη δείχνει «κλεισμένη ομαλά».
    if (next != previous) {
      appendRecord(
        _sessionRecord(
          'η συνεδρία συνεχίζει δίπλα σε άλλη βάση',
          data: {'phase': 'moved', 'to': next},
        ),
      );
    }
    // Το ίχνος ανήκει στη συνεδρία, όχι στον φάκελο: αν μείνει πίσω στον
    // παλιό, η επόμενη εκκίνηση που θα δει εκείνον τον φάκελο θα αναφέρει
    // κατάρρευση που δεν έγινε ποτέ.
    if (_diskAvailable) {
      try {
        await _liveness.remove();
      } catch (_) {}
    }
    logsDirectory = next;
    // Η μετακόμιση αλλάζει ΚΑΙ τη βάση που κρατάμε: αν έμενε η προηγούμενη, το
    // νέο ίχνος θα δήλωνε αρχείο που δεν αγγίζουμε πια, και ο φρουρός της
    // αναβάθμισης θα έψαχνε λάθος συναδέλφους.
    databaseFileName = p.basename(p.normalize(databasePath));
    _diskAvailable = true;
    _diskUnavailableReason = null;
    try {
      await onStartup(
        retentionCount: retentionCount,
        timeout: timeout,
        createDirectory: createDirectory,
      );
      // Η αρχή της συνεδρίας γράφτηκε σε άλλον φάκελο (ή πουθενά, αν ο ίδιος
      // φάκελος δεν απαντούσε). Χωρίς αυτή την εγγραφή η εξαγωγή αυτού του
      // φακέλου δεν βρίσκει τη συνεδρία — και χάνει μαζί της το κλείσιμο και
      // τα σφάλματά της.
      appendRecord(
        _sessionRecord(
          'ΣΥΝΕΧΕΙΑ συνεδρίας v$appVersion — η καταγραφή συνεχίζει σε αυτόν '
          'τον φάκελο',
          data: {
            'phase': 'begin',
            'continued': true,
            if (next != previous) 'from': previous,
          },
        ),
      );
    } catch (_) {
      // Η κατάσταση «χωρίς δίσκο» έχει ήδη μπει· η μετακόμιση είναι
      // νοικοκυριό και δεν επιτρέπεται να ρίξει τη ροή που την κάλεσε.
    }
  }

  LogRecord _sessionRecord(
    String message, {
    required Map<String, Object?> data,
  }) => LogRecord(
    time: _now(),
    kind: LogKind.startup,
    severity: LogSeverity.info,
    message: message,
    data: data,
  );

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
      await LogRetention.purge(
        logsDirectory: logsDirectory,
        retentionCount: retentionCount,
        now: _now,
      ).timeout(timeout);
      await _liveness.reportAndReplace(timeout);
    } catch (error) {
      _disableDisk(error);
      rethrow;
    }
  }

  /// Ξεκινά το περιοδικό σημάδι ζωής — δες [SessionLivenessKeeper.start].
  void startLivenessHeartbeat() => _liveness.start();

  void stopLivenessHeartbeat() => _liveness.stop();

  /// Τι κάνει η εφαρμογή όταν κάποιος της ζητά να κλείσει — δες
  /// [SessionLivenessKeeper.onShutdownRequested].
  Future<void> Function(StationShutdownRequest request)?
  get onShutdownRequested => _liveness.onShutdownRequested;

  set onShutdownRequested(
    Future<void> Function(StationShutdownRequest request)? handler,
  ) => _liveness.onShutdownRequested = handler;

  /// Ένας παλμός κατά παραγγελία — τα τεστ δεν περιμένουν ένα λεπτό.
  @visibleForTesting
  Future<void> pulseForTest() => _liveness.pulse();

  /// Θέτει την κατάσταση «χωρίς δίσκο» χωρίς να χρειαστεί απρόσιτος φάκελος.
  @visibleForTesting
  void disableDiskForTest(Object reason) => _disableDisk(reason);

  void _disableDisk(Object reason) {
    _diskAvailable = false;
    _diskUnavailableReason = reason is TimeoutException
        ? 'Ο φάκελος «$logsDirectory» δεν απάντησε μέσα σε '
              '${diskProbeTimeout.inSeconds} δευτερόλεπτα.'
        : reason.toString();
  }

  Future<void> onShutdown() async {
    stopLivenessHeartbeat();
    if (!_diskAvailable) return;
    try {
      _flushPendingRepeatSummaries();
      await _liveness.remove();
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

  /// Η εκτέλεση που χάθηκε. Ίχνος που δεν διαβάζεται εξακολουθεί να είναι
  /// είδηση: λέμε ό,τι ξέρουμε, χωρίς να εφευρίσκουμε λεπτομέρειες.
  ///
  /// Την καλεί το [SessionLivenessKeeper] όταν βρίσκει ίχνος της προηγούμενης
  /// εκτέλεσης· η εγγραφή όμως γίνεται εδώ, από τον κάτοχο του φακέλου.
  void recordLostRun(SessionLivenessMark? previous) {
    _appendToDailyLog(
      LogRecord(
        time: _now(),
        kind: LogKind.abnormalEnd,
        severity: LogSeverity.critical,
        message: previous?.describeLostRun() ?? abnormalTerminationMessage,
        data: {
          if (previous != null) ...{
            'lost_version': previous.version,
            'started_at': previous.startedAt.toIso8601String(),
            'last_seen': previous.lastSeen.toIso8601String(),
          },
        },
      ),
    );
  }

  void _writeDetailedEntry({
    required String message,
    required StackTrace stack,
    required bool fatal,
    String? diagnostics,
  }) {
    final details = [
      if (diagnostics != null && diagnostics.trim().isNotEmpty)
        diagnostics.trim(),
      stack.toString().trimRight(),
    ].where((part) => part.isNotEmpty).join('\n');
    _appendToDailyLog(
      LogRecord(
        time: _now(),
        kind: LogKind.error,
        severity: fatal ? LogSeverity.critical : LogSeverity.nonCritical,
        message: message,
        details: details,
      ),
    );
  }

  void _writeRepeatSummary(int count, String dedupKey) {
    final preview = dedupKey.split('\n').first;
    _appendToDailyLog(
      LogRecord(
        time: _now(),
        kind: LogKind.repeat,
        severity: LogSeverity.nonCritical,
        message: 'επαναλήφθηκε $count φορές — $preview',
        // Το σφάλμα ως πεδίο, ώστε η εξαγωγή να προσθέτει τις επαναλήψεις στο
        // σωστό σφάλμα χωρίς να ψάχνει μέσα στη διατύπωση του μηνύματος.
        data: {'count': count, 'error': preview},
      ),
    );
  }

  void _appendToDailyLog(LogRecord record) {
    final stamped = record.stamped(
      station: StationName.current,
      version: appVersion,
    );
    final file = File(p.join(logsDirectory, dailyLogFileName(stamped.time)));
    file.writeAsStringSync(
      '${stamped.toJsonLine()}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  /// Προσαρτά μια εγγραφή άλλης πηγής (εκκίνηση, κλείσιμο) στο ημερήσιο
  /// αρχείο, σφραγισμένη με τον σταθμό και την έκδοση.
  ///
  /// Περνά από τον ίδιο φρουρό με τα σφάλματα: όταν ο φάκελος δεν απάντησε,
  /// τίποτα δεν αγγίζει τη διαδρομή. Ο λόγος που ο παραλήπτης ζει **εδώ** κι
  /// όχι σε δική του υπηρεσία είναι ότι ο φάκελος έχει έναν κάτοχο: αυτός
  /// κρίνει τη διαθεσιμότητα, αυτός σβήνει τα παλιά, και αυτός μετακομίζει
  /// όταν η εκκίνηση καταλήξει σε άλλη βάση από τη ρυθμισμένη ([retargetTo]).
  /// Δεύτερος κάτοχος θα ξανάκανε τα τρία, και κάποια στιγμή θα ξέχναγε το ένα.
  ///
  /// Η αποτυχία καταπίνεται σκόπιμα: ο καταγραφέας δεν ρίχνει ποτέ αυτό που
  /// καταγράφει — ούτε την εκκίνηση, ούτε το κλείσιμο.
  void appendRecord(LogRecord record) {
    if (!_diskAvailable) return;
    try {
      Directory(logsDirectory).createSync(recursive: true);
      _appendToDailyLog(record);
    } catch (_) {}
  }

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
