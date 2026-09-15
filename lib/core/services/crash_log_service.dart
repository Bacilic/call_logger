import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'session_liveness_mark.dart';
import 'station_name.dart';

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

  /// Το όνομα του ίχνους «τρέχω τώρα» **αυτού** του σταθμού.
  ///
  /// Ο σταθμός μπαίνει στο όνομα επειδή ο φάκελος ζει δίπλα στη βάση, και η
  /// βάση είναι συχνά κοινόχρηστη: ένα κοινό αρχείο θα σήμαινε ότι το άνοιγμα
  /// του ενός υπολογιστή διαβάζει το ίχνος του άλλου ως δική του κατάρρευση —
  /// και ότι το σβήνει, χάνοντας την ανίχνευση της πραγματικής.
  static String sessionLockFileNameFor(String station) =>
      'session_$station.lock';

  /// Το κοινό αρχείο της παλιάς εποχής, όταν όλοι οι σταθμοί μοιράζονταν ένα
  /// ίχνος. **Δεν το αγγίζουμε**: σε φάκελο όπου κάποιος σταθμός τρέχει ακόμη
  /// παλιότερη έκδοση, το αρχείο αυτό είναι ζωντανό ίχνος εκείνου. Σβήνει
  /// μόνο του, από τον τελευταίο μη αναβαθμισμένο σταθμό που θα κλείσει.
  static const String legacySharedSessionLockFileName = 'session.lock';

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

  /// Το ίχνος αυτής της εκτέλεσης, όπως γράφτηκε τελευταία φορά.
  SessionLivenessMark? _currentMark;
  Timer? _livenessTimer;

  static String logsDirectoryForDatabasePath(String databasePath) {
    return p.join(p.dirname(p.normalize(databasePath)), 'logs');
  }

  static String dailyLogFileName(DateTime dateTime) {
    return '$_errorLogPrefix${_dateStamp(dateTime)}$_logSuffix';
  }

  /// Το ημερήσιο αρχείο συνεδριών: εκκινήσεις και προβληματικά κλεισίματα της
  /// ημέρας, με τη σειρά που συνέβησαν.
  static String sessionLogFileName(DateTime dateTime) {
    return '$sessionLogPrefix${_dateStamp(dateTime)}$_logSuffix';
  }

  static String _dateStamp(DateTime dateTime) {
    final y = dateTime.year.toString().padLeft(4, '0');
    final m = dateTime.month.toString().padLeft(2, '0');
    final d = dateTime.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static const String sessionLogPrefix = 'session_';
  static const String _errorLogPrefix = 'errors_';
  static const String _logSuffix = '.log';

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
    // Το ίχνος ανήκει στη συνεδρία, όχι στον φάκελο: αν μείνει πίσω στον
    // παλιό, η επόμενη εκκίνηση που θα δει εκείνον τον φάκελο θα αναφέρει
    // κατάρρευση που δεν έγινε ποτέ.
    if (_diskAvailable) {
      try {
        await _removeLivenessMark();
      } catch (_) {}
    }
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
      await _reportAndReplaceLivenessMark(timeout);
    } catch (error) {
      _disableDisk(error);
      rethrow;
    }
  }

  /// Αναφέρει την εκτέλεση που χάθηκε, αν χάθηκε, και αφήνει το ίχνος της νέας.
  ///
  /// Το ίχνος που βρίσκεται εδώ είναι **μόνο** δικό μας: το όνομα του αρχείου
  /// φέρει τον σταθμό. Ίχνη άλλων σταθμών δεν διαβάζονται και δεν σβήνονται —
  /// ανήκουν σε εκτελέσεις που ίσως τρέχουν αυτή τη στιγμή.
  Future<void> _reportAndReplaceLivenessMark(Duration timeout) async {
    final lock = _sessionLockFile();
    if (await lock.exists().timeout(timeout)) {
      final previous = SessionLivenessMark.decode(
        await lock.readAsString().timeout(timeout),
      );
      // Ίχνος που δεν διαβάζεται (αλλοιωμένο, ή γραμμένο από έκδοση που δεν
      // κρατούσε τίποτα) εξακολουθεί να είναι είδηση: κάτι χάθηκε. Λέμε ό,τι
      // ξέρουμε, χωρίς να εφευρίσκουμε λεπτομέρειες.
      _logPlainMessage(
        previous?.describeLostRun() ?? abnormalTerminationMessage,
        fatal: true,
      );
    }
    _currentMark = SessionLivenessMark(
      station: StationName.current,
      version: appVersion,
      startedAt: _now(),
      lastSeen: _now(),
    );
    await lock
        .writeAsString(_currentMark!.encode(), flush: true)
        .timeout(timeout);
  }

  /// Ξεκινά το περιοδικό σημάδι ζωής.
  ///
  /// **Ρητό, όχι αυτόματο στο [onStartup]:** τα τεστ στήνουν την υπηρεσία
  /// συνεχώς, και ένας χρονιστής που ξεκινά μόνος του θα κρεμούσε ελέγχους με
  /// πλαστό ρολόι ή θα διέρρεε πέρα από το τέλος τους. Στην εφαρμογή καλείται
  /// μία φορά, αμέσως μετά το άνοιγμα του ημερολογίου.
  void startLivenessHeartbeat() {
    stopLivenessHeartbeat();
    if (!_diskAvailable) return;
    _livenessTimer = Timer.periodic(livenessInterval, (_) => _markAlive());
  }

  void stopLivenessHeartbeat() {
    _livenessTimer?.cancel();
    _livenessTimer = null;
  }

  /// Ανανεώνει το «μέχρι πότε ζούσα». Σιωπηλή αποτυχία: το σημάδι ζωής είναι
  /// διαγνωστική άνεση και δεν επιτρέπεται να διακόψει τη δουλειά του χρήστη.
  void _markAlive() {
    if (!_diskAvailable) return;
    final mark = _currentMark?.seenAt(_now());
    if (mark == null) return;
    try {
      _sessionLockFile().writeAsStringSync(mark.encode(), flush: true);
      _currentMark = mark;
    } catch (_) {}
  }

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
      await _removeLivenessMark();
    } catch (_) {}
  }

  Future<void> _removeLivenessMark() async {
    final lock = _sessionLockFile();
    if (await lock.exists().timeout(diskProbeTimeout)) {
      await lock.delete().timeout(diskProbeTimeout);
    }
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
    final severity = fatal ? 'ΚΡΙΣΙΜΟ' : 'ΜΗ-ΚΡΙΣΙΜΟ';
    return '[$stamp] v$appVersion $severity';
  }

  void _appendToDailyLog(String chunk) {
    final file = File(p.join(logsDirectory, dailyLogFileName(_now())));
    file.writeAsStringSync(chunk, mode: FileMode.append, flush: true);
  }

  /// Προσαρτά κείμενο στο **ημερήσιο αρχείο συνεδριών**.
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
  void appendSessionText(String text) {
    if (!_diskAvailable) return;
    if (text.isEmpty) return;
    try {
      Directory(logsDirectory).createSync(recursive: true);
      final file = File(p.join(logsDirectory, sessionLogFileName(_now())));
      file.writeAsStringSync(text, mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  /// Κρατά τα [retentionCount] πιο πρόσφατα αρχεία **ανά οικογένεια** — τα
  /// σφάλματα και οι συνεδρίες μετρούν χωριστά, ώστε μια πολυήμερη σειρά
  /// σφαλμάτων να μη σβήνει το ιστορικό εκκινήσεων.
  ///
  /// Μαζεύει επίσης τα αρχεία ιχνηλάτησης κλεισίματος της παλιάς εποχής, όταν
  /// το κάθε περιστατικό έπαιρνε δικό του αρχείο. Πλέον προσαρτώνται στο
  /// αρχείο συνεδρίας της ημέρας τους, οπότε όσα έμειναν δεν τα διαβάζει
  /// κανείς — και χωρίς αυτή τη γραμμή δεν θα τα έσβηνε ποτέ κανείς.
  Future<void> _purgeOldLogFiles(int retentionCount) async {
    final dir = Directory(logsDirectory);
    if (!await dir.exists()) return;

    final entries = await dir
        .list()
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    await _purgeFamily(entries, _errorLogPrefix, retentionCount);
    await _purgeFamily(entries, sessionLogPrefix, retentionCount);
    await _purgeLegacyShutdownTraces(entries);
  }

  Future<void> _purgeFamily(
    List<File> entries,
    String prefix,
    int retentionCount,
  ) async {
    final files = entries
        .where(
          (file) =>
              p.basename(file.path).startsWith(prefix) &&
              p.basename(file.path).endsWith(_logSuffix),
        )
        .toList();
    if (files.length <= retentionCount) return;

    files.sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    for (final file in files.skip(retentionCount)) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  /// Σβήνει **μόνο** τα αρχεία περιστατικών της παλιάς εποχής — αυτά που
  /// φέρουν ημερομηνία στο όνομά τους.
  ///
  /// Τα προσωρινά ίχνη εργασίας δεν αγγίζονται ποτέ, ούτε τα δικά μας ούτε
  /// άλλου σταθμού: όταν υπάρχουν, είτε ανήκουν σε κλείσιμο που πέθανε στη
  /// μέση και περιμένει να προαχθεί, είτε — σε κοινόχρηστο φάκελο — σε
  /// υπολογιστή που **αυτή τη στιγμή** κλείνει.
  Future<void> _purgeLegacyShutdownTraces(List<File> entries) async {
    for (final file in entries) {
      if (!_legacyIncidentFileName.hasMatch(p.basename(file.path))) continue;
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  static final RegExp _legacyIncidentFileName = RegExp(
    '^$legacyShutdownTracePrefix'
    r'\d{4}-\d{2}-\d{2}(_[\d-]+)?'
    r'\.log$',
  );

  /// Το πρόθεμα των αρχείων ιχνηλάτησης κλεισίματος. Ζει εδώ επειδή η
  /// εκκαθάριση είναι το μόνο σημείο που τα χρειάζεται μαζί με τα υπόλοιπα
  /// αρχεία του φακέλου· ο ίδιος ο ιχνηλάτης χτίζει πάνω του το δικό του όνομα.
  static const String legacyShutdownTracePrefix = 'shutdown_trace_';

  File _sessionLockFile() =>
      File(p.join(logsDirectory, sessionLockFileNameFor(StationName.fileSafe)));

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
