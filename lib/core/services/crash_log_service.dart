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
/// και δεν ξαναγγίζει τη διαδρομή.
///
/// **Καμία εγγραφή δεν γίνεται στο νήμα της οθόνης.** Όλες περνούν από μία
/// ουρά ([_enqueueWrite]): μία-μία, στο παρασκήνιο, με όριο χρόνου. Μετρημένο
/// 14/10/2026 με σβηστό διακομιστή: μία σύγχρονη εγγραφή πάγωσε την εφαρμογή
/// για πάνω από 45 δευτερόλεπτα, με μαύρο παράθυρο και «Δεν αποκρίνεται».
/// Η πρώτη αποτυχία σιγεί το ημερολόγιο, και ο παλμός του λεπτού δοκιμάζει
/// να το ξαναζωντανέψει ([tryResumeDisk]) μόλις ο φάκελος απαντήσει ξανά.
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
    LogFileWriter? writeFile,
    this._writeTimeout = backgroundWriteTimeout,
  }) : _now = now ?? DateTime.now,
       _writeFile = writeFile ?? _writeToDisk,
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
    _instance?.dispose();
    _instance = null;
  }

  /// Σταματά τον παλμό και αφήνει όσους ακούν τη διαθεσιμότητα του δίσκου.
  ///
  /// Στην εφαρμογή το ημερολόγιο ζει όσο η διεργασία· το χρειάζονται τα τεστ,
  /// που στήνουν δικό τους σε κάθε έλεγχο.
  void dispose() {
    stopLivenessHeartbeat();
    _diskAvailability.dispose();
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

  /// Μέγιστη αναμονή για μια εγγραφή **της ουράς**, αφού η οθόνη έχει ανοίξει.
  ///
  /// Μεγαλύτερο από το [diskProbeTimeout] επίτηδες: εδώ δεν περιμένει κανείς,
  /// οπότε το όριο κρίνει μόνο πότε λέμε «ο φάκελος χάθηκε». Μετρημένο
  /// 14/10/2026: στην εκκίνηση, η αντιγραφή του στιγμιότυπου της βάσης (16 MB
  /// από τον POPINIO) καθυστέρησε μια εγγραφή πάνω από τρία δευτερόλεπτα, και
  /// το ημερολόγιο σίγησε για 47 δευτερόλεπτα με τον φάκελο ζωντανό.
  static const Duration backgroundWriteTimeout = Duration(seconds: 15);

  /// Ο φάκελος των ημερήσιων αρχείων. Αλλάζει μόνο μέσω [retargetTo].
  String logsDirectory;
  bool _diskAvailable = true;
  String? _diskUnavailableReason;

  /// False όταν ο φάκελος δεν απάντησε: τίποτα δεν γράφεται στον δίσκο.
  bool get isDiskAvailable => _diskAvailable;

  /// Το [isDiskAvailable] για όποιον πρέπει να δει την αλλαγή τη στιγμή που
  /// γίνεται — η ένδειξη «Χωρίς καταγραφή» ανάβει και σβήνει μόνη της.
  ValueListenable<bool> get diskAvailability => _diskAvailability;
  final ValueNotifier<bool> _diskAvailability = ValueNotifier<bool>(true);

  /// Σίγησε στη μέση της δουλειάς, άρα ο παλμός δοκιμάζει να συνεχίσει.
  ///
  /// Η σιωπή της **εκκίνησης** μένει για όλη τη συνεδρία, όπως πάντα: εκεί
  /// δεν γράφτηκε ποτέ το ίχνος «τρέχω τώρα», και μια συνέχεια χωρίς αυτό θα
  /// έδειχνε στους συναδέλφους εκτέλεση που δεν ανακοινώθηκε ποτέ.
  bool _canResume = false;
  DateTime? _silentSince;
  bool _resuming = false;

  final LogFileWriter _writeFile;
  final Duration _writeTimeout;

  /// Η ουρά των εγγραφών: η επόμενη ξεκινά όταν τελειώσει η προηγούμενη.
  Future<void> _queue = Future<void>.value();

  /// Αλλάζει σε κάθε μετακόμιση: μια εγγραφή του παλιού φακέλου που αποτύχει
  /// αργότερα δεν σιγεί τον καινούργιο.
  int _generation = 0;

  /// Ολοκληρώνεται όταν γραφτεί ό,τι έχει ήδη μπει στην ουρά.
  Future<void> get pendingWrites => _queue;

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
      await appendRecord(
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
    _generation++;
    _setDiskAvailable();
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
      await appendRecord(
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
    _canResume = false;
    _diskUnavailableReason = reason is TimeoutException
        ? 'Ο φάκελος «$logsDirectory» δεν απάντησε μέσα σε '
              '${(reason.duration ?? _writeTimeout).inSeconds} δευτερόλεπτα.'
        : reason.toString();
    _diskAvailability.value = false;
  }

  /// Μια εγγραφή στη μέση της δουλειάς δεν απάντησε: σιωπή, με δυνατότητα
  /// συνέχειας.
  void _suspendDisk(Object reason) {
    if (!_diskAvailable) return;
    _disableDisk(reason);
    _canResume = true;
    _silentSince = _now();
  }

  void _setDiskAvailable() {
    _diskAvailable = true;
    _canResume = false;
    _silentSince = null;
    _diskUnavailableReason = null;
    _diskAvailability.value = true;
  }

  /// Μία εγγραφή στην ουρά. Η διαδρομή κρίνεται **τώρα**, όχι όταν έρθει η
  /// σειρά της: μια μετακόμιση στο μεταξύ δεν τη στέλνει σε άλλον φάκελο.
  ///
  /// Δεν πετά ποτέ· η αποτυχία της σιγεί το ημερολόγιο ([_suspendDisk]).
  /// Επιστρέφει αν η εγγραφή έφτασε πράγματι στον δίσκο.
  Future<bool> _enqueueWrite(
    String path,
    String content, {
    required bool append,
  }) {
    if (!_diskAvailable) return Future<bool>.value(false);
    final generation = _generation;
    final next = _queue.then((_) async {
      if (!_diskAvailable && generation == _generation) return false;
      Future<void>? write;
      try {
        write = _writeFile(path, content, append: append);
        await write.timeout(_writeTimeout);
        return true;
      } catch (error) {
        if (generation != _generation) return false;
        _suspendDisk(error);
        if (error is TimeoutException && write != null) {
          _resumeIfLateWriteLands(write, generation);
        }
        return false;
      }
    });
    _queue = next;
    return next;
  }

  /// Μια εγγραφή που απλώς άργησε δεν σημαίνει χαμένο φάκελο: αν τελικά
  /// πετύχει, η καταγραφή συνεχίζει αμέσως, χωρίς να περιμένει τον παλμό.
  void _resumeIfLateWriteLands(Future<void> write, int generation) {
    unawaited(
      write.then((_) {
        if (generation == _generation && _canResume) _resume();
      }, onError: (Object _) {}),
    );
  }

  /// Γράφει το ίχνος «τρέχω τώρα» μέσα από την ουρά.
  Future<void> writeLivenessMark(String path, String content) =>
      _enqueueWrite(path, content, append: false);

  /// Ο φάκελος απαντά ξανά; Δοκιμάζει γράφοντας το ίχνος «τρέχω τώρα».
  ///
  /// Μόνο μετά από σιωπή στη μέση της δουλειάς — δες [_canResume]. Ποτέ δύο
  /// δοκιμές μαζί: σε σβηστό διακομιστή η μία κρατά ως το όριο των Windows —
  /// στο παρασκήνιο, χωρίς να περιμένει τίποτα η οθόνη.
  Future<bool> tryResumeDisk(
    String livenessPath,
    String livenessContent,
  ) async {
    if (_diskAvailable) return true;
    if (!_canResume || _resuming) return false;
    _resuming = true;
    final generation = _generation;
    try {
      await _writeFile(
        livenessPath,
        livenessContent,
        append: false,
      ).timeout(_writeTimeout);
    } catch (_) {
      return false;
    } finally {
      _resuming = false;
    }
    if (generation != _generation || _diskAvailable) return _diskAvailable;
    _resume();
    return true;
  }

  /// Η καταγραφή συνεχίζει, και το ημερολόγιο λέει από πότε σιωπούσε.
  void _resume() {
    final silentSince = _silentSince;
    _setDiskAvailable();
    unawaited(
      appendRecord(
        _sessionRecord(
          'Η καταγραφή συνεχίζει — ο φάκελος δεν απαντούσε'
          '${silentSince == null ? '' : ' από ${_clockTime(silentSince)}'}',
          data: {
            'phase': 'resumed',
            if (silentSince != null)
              'silent_since': silentSince.toIso8601String(),
          },
        ),
      ),
    );
  }

  static String _clockTime(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  Future<void> onShutdown() async {
    stopLivenessHeartbeat();
    if (!_diskAvailable) return;
    _flushPendingRepeatSummaries();
    await pendingWrites;
    if (!_diskAvailable) return;
    try {
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
    // Χωρίς δίσκο ούτε μετριούνται οι επαναλήψεις: η σύνοψή τους θα έλεγε
    // «επαναλήφθηκε» για εγγραφές που δεν γράφτηκαν ποτέ.
    if (!_diskAvailable) return;
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
  Future<void> recordLostRun(SessionLivenessMark? previous) {
    return _appendToDailyLog(
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

  Future<bool> _appendToDailyLog(LogRecord record) {
    final stamped = record.stamped(
      station: StationName.current,
      version: appVersion,
    );
    return _enqueueWrite(
      p.join(logsDirectory, dailyLogFileName(stamped.time)),
      '${stamped.toJsonLine()}\n',
      append: true,
    );
  }

  /// Η πραγματική εγγραφή: ασύγχρονη, ώστε το όριο χρόνου να την πιάνει.
  static Future<void> _writeToDisk(
    String path,
    String content, {
    required bool append,
  }) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      content,
      mode: append ? FileMode.append : FileMode.write,
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
  /// Η αποτυχία δεν πετιέται: ο καταγραφέας δεν ρίχνει ποτέ αυτό που
  /// καταγράφει — ούτε την εκκίνηση, ούτε το κλείσιμο. Επιστρέφει όμως **αν η
  /// εγγραφή γράφτηκε**: όποιος σβήνει την πηγή της αφού την καταγράψει (το
  /// ίχνος κλεισίματος) οφείλει να ξέρει ότι έφτασε — αλλιώς ένα ημερολόγιο
  /// που σιωπά παίρνει μαζί του και το μόνο αντίγραφο.
  Future<bool> appendRecord(LogRecord record) {
    if (!_diskAvailable) return Future<bool>.value(false);
    try {
      return _appendToDailyLog(record);
    } catch (_) {
      return Future<bool>.value(false);
    }
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

/// Πώς γράφεται ένα αρχείο του ημερολογίου — αντικαθίσταται στα τεστ με
/// φάκελο που δεν απαντά.
typedef LogFileWriter =
    Future<void> Function(String path, String content, {required bool append});

class _DedupState {
  int detailedCount = 0;
  int suppressedCount = 0;
}
