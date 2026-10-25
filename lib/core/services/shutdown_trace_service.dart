import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:path_provider/path_provider.dart';

import 'crash_log_service.dart';
import 'log_record.dart';
import 'operator_presence_heartbeat.dart';
import 'shutdown_coordinator.dart';
import 'shutdown_trace_incident.dart';
import 'station_name.dart';

/// Σιωπηλός φρουρός του κλεισίματος.
///
/// ΓΙΑΤΙ ΕΤΣΙ (μη το «απλοποιήσεις» σε σκέτη καταγραφή): ο ιχνηλάτης έγραφε
/// αρχείο σε ΚΑΘΕ κλείσιμο. Σε 29 καταγεγραμμένα κλεισίματα δεν βρέθηκε ούτε
/// μία ανωμαλία — μόνο θόρυβος. Πλέον το ίχνος γράφεται πάντα σε **προσωρινό**
/// αρχείο (με άμεσο flush, ώστε να επιβιώνει ακόμη κι αν η διεργασία σκοτωθεί),
/// αλλά **διατηρείται μόνο όταν κάτι πήγε στραβά**:
///
/// 1. κάποιο βήμα απέτυχε ή διακόπηκε από το όριο ασφαλείας,
/// 2. το κλείσιμο ξεπέρασε το [slowThreshold],
/// 3. η προηγούμενη εκτέλεση δεν πρόλαβε καν να κλείσει το αρχείο της
///    (ορφανό προσωρινό = η εφαρμογή πέθανε στη μέση του κλεισίματος).
///
/// Σε φυσιολογικό κλείσιμο το προσωρινό σβήνεται και ο φάκελος logs μένει
/// καθαρός. Το κατώφλι είναι το ΙΔΙΟ με αυτό που αποκαλύπτει την οθόνη
/// προόδου — ένας ορισμός του «αργό» σε όλη την εφαρμογή.
///
/// Όταν το ίχνος αξίζει, **δεν γίνεται δικό του αρχείο**: γίνεται μία εγγραφή
/// στο ημερήσιο αρχείο, μετά την εκκίνηση της ίδιας ημέρας. Έτσι η
/// συνεδρία διαβάζεται ολόκληρη — «άνοιξα στις 8:12 και άργησε η βάση, έκλεισα
/// στις 16:40 και κόλλησε το αντίγραφο» — αντί για δύο ξένα μεταξύ τους αρχεία.
class ShutdownTraceService {
  ShutdownTraceService({
    required this.workingDirectory,
    required this.appendRecord,
    this.slowThreshold = ShutdownCoordinator.progressRevealDelay,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Πού ζει το **προσωρινό** ίχνος όσο γράφεται — τοπικά, ποτέ στο δίκτυο.
  ///
  /// Κάθε γραμμή είναι ξεχωριστή σύγχρονη εγγραφή που περιμένει να πατήσει
  /// δίσκο, αλλιώς ένα ίχνος που σκοτώθηκε στη μέση δεν θα έλεγε τίποτα. Σε
  /// δικτυακό φάκελο αυτό κόστισε **6,2 δευτερόλεπτα για οκτώ γραμμές** σε
  /// μετρημένο κλείσιμο — περισσότερο από όλη τη δουλειά που κατέγραφαν. Το
  /// τελικό ίχνος φεύγει κανονικά στο κοινό ημερήσιο αρχείο, μία φορά, μέσω
  /// του [appendRecord]: αλλάζει μόνο πού περιμένει ενδιάμεσα.
  final String workingDirectory;

  /// Πού καταλήγει το ίχνος όταν αξίζει να κρατηθεί — το ημερήσιο αρχείο
  /// του [CrashLogService], που κατέχει τον φάκελο, τον φρουρό του δίσκου και
  /// τη σφραγίδα του σταθμού.
  final Future<bool> Function(LogRecord record) appendRecord;

  /// Πάνω από αυτό το συνολικό όριο το κλείσιμο θεωρείται αργό.
  final Duration slowThreshold;

  final DateTime Function() _now;

  File? _file;
  StreamSubscription<ShutdownStepEvent>? _subscription;

  int _totalMs = 0;
  String _slowestStepLabel = '';
  int _slowestStepMs = -1;
  bool _hadFailure = false;
  bool _wasInterrupted = false;
  bool _keptIncident = false;

  /// Το προσωρινό ίχνος του κλεισίματος **αυτού** του σταθμού.
  ///
  /// Ο σταθμός μπαίνει στο όνομα για τον ίδιο λόγο που μπαίνει και στο ίχνος
  /// «τρέχω τώρα»: ο φάκελος είναι κοινός όταν η βάση είναι κοινή. Με κοινό
  /// όνομα, ένας υπολογιστής που ανοίγει την ώρα που ένας άλλος κλείνει θα
  /// έβρισκε το **ζωντανό** ίχνος εκείνου και θα το ανακοίνωνε ως διακοπέν
  /// κλείσιμο — σβήνοντάς το κιόλας.
  /// Η **εκτέλεση** μπαίνει κι αυτή στο όνομα, ένα επίπεδο πιο μέσα: δύο
  /// αντίγραφα στον ίδιο υπολογιστή (η κανονική έκδοση και η δοκιμαστική) θα
  /// μοιραζόταν ένα αρχείο τώρα που ο φάκελος είναι τοπικός. Η ταυτότητα μένει
  /// σταθερή από άνοιγμα σε άνοιγμα, οπότε το ίχνος που έμεινε στη μέση το
  /// βρίσκει η επόμενη εκκίνηση του ίδιου αντιγράφου.
  static String get workingFileName =>
      '${CrashLogService.legacyShutdownTracePrefix}'
      '${StationName.fileSafe}_'
      '${CrashLogService.instanceSlug(OperatorPresenceHeartbeat.instanceId)}'
      '${ShutdownTraceIncident.fileNameSuffix}';

  /// Ο τοπικός φάκελος του προσωρινού ίχνους: `%AppData%\…\shutdown`.
  static Future<String> localWorkingDirectory() async {
    final support = await getApplicationSupportDirectory();
    return p.join(support.path, 'shutdown');
  }

  /// Στήνει τον ιχνηλάτη πάνω στο ημερολόγιο που ήδη κατέχει τον φάκελο.
  ///
  /// Το ερώτημα είναι «κρατιούνται οι εγγραφές κάπου;», όχι «απαντά ο
  /// φάκελος;»: με σιωπηλό φάκελο το τελικό ίχνος πηγαίνει στην τοπική αναμονή
  /// του ημερολογίου, χωρίς να περιμένει τίποτα. `null` μόνο όταν δεν υπάρχει
  /// ημερολόγιο ή οι εγγραφές δεν έχουν πού να πάνε.
  static Future<ShutdownTraceService?> forCrashLog({
    CrashLogService? service,
    Future<String> Function()? localDirectory,
  }) async {
    final log = service ?? CrashLogService.instanceOrNull;
    if (log == null || !log.keepsRecords) return null;
    String working;
    try {
      working = await (localDirectory ?? localWorkingDirectory)();
    } catch (_) {
      // Χωρίς τοπικό φάκελο, το προσωρινό γράφεται όπου έγραφε πάντα — αργά,
      // αλλά καλύτερα από καθόλου ίχνος. Ποτέ όμως σε φάκελο που σιωπά: κάθε
      // γραμμή περιμένει τον δίσκο, και σε σβηστό διακομιστή θα πάγωνε το
      // κλείσιμο.
      if (!log.isDiskAvailable) return null;
      working = log.logsDirectory;
    }
    return ShutdownTraceService(
      workingDirectory: working,
      appendRecord: log.appendRecord,
    );
  }

  /// Ανακοινώνει στην εκκίνηση το κλείσιμο που έμεινε στη μέση — δες
  /// [promoteOrphanedTrace].
  ///
  /// Ίδιο ερώτημα με τον [forCrashLog]: αρκεί οι εγγραφές να κρατιούνται
  /// κάπου. Με σιωπηλό φάκελο το ίχνος πάει στην τοπική αναμονή, και η ένδειξη
  /// των Ρυθμίσεων μαθαίνει **τώρα** ότι η εφαρμογή σκοτώθηκε — όχι στην
  /// επόμενη εκκίνηση που θα βρει τον διακομιστή ανοιχτό.
  static Future<bool> promoteOrphanIfLogKeepsRecords(
    CrashLogService? log, {
    String? workingDirectory,
  }) async {
    if (log == null || !log.keepsRecords) return false;
    return promoteOrphanedTrace(
      workingDirectory: workingDirectory ?? await localWorkingDirectory(),
      appendRecord: log.appendRecord,
    );
  }

  /// Αληθές όταν το ίχνος του τρέχοντος κλεισίματος κρατήθηκε.
  bool get keptIncident => _keptIncident;

  /// Αληθές όταν το τρέχον κλείσιμο δικαιολογεί καταγραφή.
  bool get isIncident =>
      _hadFailure ||
      _wasInterrupted ||
      _totalMs >= slowThreshold.inMilliseconds;

  /// Ανοίγει το προσωρινό αρχείο του τρέχοντος κλεισίματος.
  Future<void> beginSession() async {
    try {
      await Directory(workingDirectory).create(recursive: true);
      final file = File(p.join(workingDirectory, workingFileName));
      // Ίχνος που η εκκίνηση δεν πρόλαβε να γράψει (το ημερολόγιο σιωπούσε
      // τότε) έχει τώρα μια δεύτερη ευκαιρία, πριν το νέο ίχνος πάρει τη θέση
      // του.
      await _promoteOne(file, appendRecord: appendRecord, clock: _now);
      if (await file.exists()) await file.delete();
      _file = file;
      _appendLine('=== shutdown trace start ===');
    } catch (_) {}
  }

  /// Συνδέει τον ιχνηλάτη στο stream γεγονότων του συντονιστή.
  void listenTo(Stream<ShutdownStepEvent> events) {
    _subscription?.cancel();
    _subscription = events.listen(recordEvent);
  }

  void recordEvent(ShutdownStepEvent event) {
    try {
      final phaseLabel = switch (event.phase) {
        ShutdownStepPhase.started => 'START',
        ShutdownStepPhase.completed => 'OK',
        ShutdownStepPhase.failed => 'FAIL',
        ShutdownStepPhase.interrupted => 'INTERRUPTED',
      };
      final durationPart = event.durationMs == null
          ? ''
          : ' durationMs=${event.durationMs}';
      final errorPart = event.error == null ? '' : ' error=${event.error}';
      _appendLine(
        'step=${event.stepIndex} "${event.label}" $phaseLabel'
        '$durationPart$errorPart',
      );
      _accumulate(event);
    } catch (_) {}
  }

  /// Κρατά τα λίγα στοιχεία που χρειάζεται η απόφαση «αξίζει καταγραφή;» και η
  /// σύνοψη προς τον χρήστη — χωρίς να ξαναδιαβάσει ποτέ το αρχείο.
  void _accumulate(ShutdownStepEvent event) {
    switch (event.phase) {
      case ShutdownStepPhase.started:
        // Κρατιέται ως «τελευταίο γνωστό βήμα»: αν το κλείσιμο διακοπεί
        // χωρίς τερματικό γεγονός, αυτό είναι το βήμα που κόλλησε.
        if (_slowestStepMs < 0) _slowestStepLabel = event.label;
      case ShutdownStepPhase.completed:
      case ShutdownStepPhase.failed:
        final ms = event.durationMs ?? 0;
        _totalMs += ms;
        if (ms > _slowestStepMs) {
          _slowestStepMs = ms;
          _slowestStepLabel = event.label;
        }
        if (event.phase == ShutdownStepPhase.failed) _hadFailure = true;
      case ShutdownStepPhase.interrupted:
        _wasInterrupted = true;
        _slowestStepLabel = event.label;
    }
  }

  /// Κλείνει τη συνεδρία: κρατά το ίχνος ως περιστατικό ή το σβήνει.
  Future<void> endSession() async {
    await _subscription?.cancel();
    _subscription = null;

    final file = _file;
    _file = null;
    if (file == null) return;

    try {
      if (!isIncident) {
        if (await file.exists()) await file.delete();
        return;
      }
      _keptIncident = await _appendTraceToLog(file, _buildIncident());
    } catch (_) {}
  }

  ShutdownTraceIncident _buildIncident() {
    return ShutdownTraceIncident(
      occurredAt: _now(),
      totalMs: _totalMs,
      slowestStepLabel: _slowestStepLabel,
      slowestStepMs: _slowestStepMs < 0 ? 0 : _slowestStepMs,
      hadFailure: _hadFailure,
      wasInterrupted: _wasInterrupted,
    );
  }

  /// Στέλνει το ίχνος στο ημερολόγιο και σβήνει το τοπικό **μόνο** αν
  /// γράφτηκε. Όταν το ημερολόγιο σιωπά (σβηστός διακομιστής), το ίχνος μένει
  /// με τη σύνοψή του μέσα, για να το καταγράψει η επόμενη εκκίνηση ως αυτό
  /// που ήταν — αργό ή αποτυχημένο κλείσιμο, όχι διακοπή.
  Future<bool> _appendTraceToLog(
    File file,
    ShutdownTraceIncident summary,
  ) async {
    final written = await appendRecord(
      summary.toRecord(trace: await file.readAsString()),
    );
    if (!written) {
      await file.writeAsString(
        '$_pendingIncidentPrefix${jsonEncode(summary.toJson())}\n',
        mode: FileMode.append,
        flush: true,
      );
      return false;
    }
    try {
      await file.delete();
    } catch (_) {}
    return true;
  }

  /// Σύνοψη περιστατικού που **δεν** γράφτηκε ακόμη στο ημερολόγιο: το
  /// κλείσιμο ολοκληρώθηκε, αλλά το ημερολόγιο δεν απάντησε.
  static const String _pendingIncidentPrefix = 'INCIDENT=';

  /// Προσωρινό αρχείο από προηγούμενη εκτέλεση = το κλείσιμο δεν ολοκληρώθηκε
  /// ποτέ (η διεργασία πέθανε στη μέση). Αυτό είναι από μόνο του περιστατικό:
  /// κρατιέται, με το τελευταίο βήμα που πρόλαβε να ξεκινήσει.
  ///
  /// Τρέχει στην **εκκίνηση**, όχι στο επόμενο κλείσιμο. Ένα διακοπέν κλείσιμο
  /// ανήκει χρονικά πριν από τη συνεδρία που ξεκινά τώρα — και, το κυριότερο,
  /// έτσι το βλέπει αμέσως η ένδειξη των Ρυθμίσεων. Όσο η προαγωγή γινόταν στο
  /// επόμενο κλείσιμο, ο χρήστης δεν μάθαινε ποτέ ότι η εφαρμογή σκοτώθηκε.
  ///
  /// Επιστρέφει `true` όταν βρήκε πράγματι ορφανό — ένα βήμα εκκίνησης που
  /// συνήθως δεν έχει δουλειά να κάνει.
  static Future<bool> promoteOrphanedTrace({
    required String workingDirectory,
    required Future<bool> Function(LogRecord record) appendRecord,
    DateTime Function()? now,
  }) {
    return _promoteOne(
      File(p.join(workingDirectory, workingFileName)),
      appendRecord: appendRecord,
      clock: now ?? DateTime.now,
    );
  }

  static Future<bool> _promoteOne(
    File orphan, {
    required Future<bool> Function(LogRecord record) appendRecord,
    required DateTime Function() clock,
  }) async {
    if (!await orphan.exists()) return false;
    try {
      final content = await orphan.readAsString();
      final lines = const LineSplitter().convert(content);
      final summary =
          _pendingIncidentIn(lines) ??
          ShutdownTraceIncident(
            occurredAt: _lastTimestampIn(lines) ?? clock(),
            totalMs: 0,
            slowestStepLabel: _lastStartedStepIn(lines),
            slowestStepMs: 0,
            hadFailure: false,
            wasInterrupted: true,
          );
      final trace = lines
          .where((line) => !line.startsWith(_pendingIncidentPrefix))
          .join('\n');
      // Ημερολόγιο που σιωπά: το ίχνος μένει για την επόμενη εκκίνηση.
      final written = await appendRecord(summary.toRecord(trace: trace));
      if (!written) return false;
      await orphan.delete();
      return true;
    } catch (_) {
      try {
        await orphan.delete();
      } catch (_) {}
      return false;
    }
  }

  /// Η σύνοψη που άφησε κλείσιμο του οποίου το ημερολόγιο δεν απάντησε.
  static ShutdownTraceIncident? _pendingIncidentIn(List<String> lines) {
    for (final line in lines.reversed) {
      if (!line.startsWith(_pendingIncidentPrefix)) continue;
      try {
        final data = jsonDecode(line.substring(_pendingIncidentPrefix.length));
        if (data is Map<String, Object?>) {
          return ShutdownTraceIncident.fromJson(
            data,
            fallbackTime: DateTime.now(),
          );
        }
      } catch (_) {}
    }
    return null;
  }

  /// Το τελευταίο βήμα που ξεκίνησε μέσα σε ορφανό αρχείο — εκεί κόλλησε.
  static String _lastStartedStepIn(List<String> lines) {
    for (final line in lines.reversed) {
      final match = RegExp(r'step=\d+ "([^"]*)"').firstMatch(line);
      if (match != null) return match.group(1) ?? '';
    }
    return 'άγνωστο βήμα';
  }

  static DateTime? _lastTimestampIn(List<String> lines) {
    for (final line in lines.reversed) {
      final match = RegExp(
        r'^\[(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})\]',
      ).firstMatch(line);
      if (match == null) continue;
      return DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
        int.parse(match.group(6)!),
      );
    }
    return null;
  }

  void _appendLine(String line) {
    final file = _file;
    if (file == null) return;
    final stamp = _formatTimestamp(_now());
    file.writeAsStringSync(
      '[$stamp] $line\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  static String _formatTimestamp(DateTime now) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year.toString().padLeft(4, '0')}-'
        '${two(now.month)}-${two(now.day)} '
        '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
  }
}
