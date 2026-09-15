import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'crash_log_service.dart';
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
/// Όταν το ίχνος αξίζει, **δεν γίνεται δικό του αρχείο**: προσαρτάται στο
/// ημερήσιο αρχείο συνεδριών, κάτω από την εκκίνηση της ίδιας ημέρας. Έτσι η
/// συνεδρία διαβάζεται ολόκληρη — «άνοιξα στις 8:12 και άργησε η βάση, έκλεισα
/// στις 16:40 και κόλλησε το αντίγραφο» — αντί για δύο ξένα μεταξύ τους αρχεία.
class ShutdownTraceService {
  ShutdownTraceService({
    required this.logsDirectory,
    required this.appendToSessionLog,
    this.slowThreshold = ShutdownCoordinator.progressRevealDelay,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final String logsDirectory;

  /// Πού καταλήγει το ίχνος όταν αξίζει να κρατηθεί — το ημερήσιο αρχείο
  /// συνεδριών του [CrashLogService], που κατέχει τον φάκελο και τον φρουρό
  /// του δίσκου.
  final void Function(String text) appendToSessionLog;

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
  static String get workingFileName =>
      '${CrashLogService.legacyShutdownTracePrefix}'
      '${StationName.fileSafe}'
      '${ShutdownTraceIncident.fileNameSuffix}';

  static String logsDirectoryForDatabasePath(String databasePath) {
    return CrashLogService.logsDirectoryForDatabasePath(databasePath);
  }

  /// Στήνει τον ιχνηλάτη πάνω στο ημερολόγιο που ήδη κατέχει τον φάκελο.
  ///
  /// `null` όταν δεν υπάρχει ημερολόγιο ή ο φάκελος δεν απαντά: χωρίς δίσκο
  /// δεν υπάρχει τίποτα να ιχνηλατηθεί, και η αναμονή σε φάκελο που σιωπά
  /// είναι ακριβώς αυτό που δεν αντέχει η ώρα του κλεισίματος.
  static ShutdownTraceService? forCrashLog([CrashLogService? service]) {
    final log = service ?? CrashLogService.instanceOrNull;
    if (log == null || !log.isDiskAvailable) return null;
    return ShutdownTraceService(
      logsDirectory: log.logsDirectory,
      appendToSessionLog: log.appendSessionText,
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
      await Directory(logsDirectory).create(recursive: true);
      final file = File(p.join(logsDirectory, workingFileName));
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
      await _appendTraceToSessionLog(file, _buildIncident());
      _keptIncident = true;
    } catch (_) {}
  }

  ShutdownTraceIncident _buildIncident() {
    return ShutdownTraceIncident(
      filePath: '',
      occurredAt: _now(),
      totalMs: _totalMs,
      slowestStepLabel: _slowestStepLabel,
      slowestStepMs: _slowestStepMs < 0 ? 0 : _slowestStepMs,
      hadFailure: _hadFailure,
      wasInterrupted: _wasInterrupted,
    );
  }

  Future<void> _appendTraceToSessionLog(
    File file,
    ShutdownTraceIncident summary,
  ) async {
    await _writeTraceBlock(
      body: await file.readAsString(),
      summary: summary,
      append: appendToSessionLog,
    );
    try {
      await file.delete();
    } catch (_) {}
  }

  /// Το κοινό σχήμα του μπλοκ τερματισμού — μία μορφή, δύο καλούντες: το
  /// κλείσιμο που μόλις έγινε και το ορφανό της προηγούμενης εκτέλεσης.
  static Future<void> _writeTraceBlock({
    required String body,
    required ShutdownTraceIncident summary,
    required void Function(String text) append,
  }) async {
    final stamp = _formatTimestamp(summary.occurredAt);
    final buffer = StringBuffer()
      ..writeln('[$stamp] ══ ΤΕΡΜΑΤΙΣΜΟΣ — ΠΕΡΙΣΤΑΤΙΚΟ ══')
      ..write(body.endsWith('\n') || body.isEmpty ? body : '$body\n')
      ..writeln(summary.toSummaryLine())
      ..writeln();
    append(buffer.toString());
  }

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
    required String logsDirectory,
    required void Function(String text) appendToSessionLog,
    DateTime Function()? now,
  }) async {
    final clock = now ?? DateTime.now;
    final orphan = File(p.join(logsDirectory, workingFileName));
    if (!await orphan.exists()) return false;
    try {
      final content = await orphan.readAsString();
      final lines = const LineSplitter().convert(content);
      // Αν έχει ήδη σύνοψη, κάποιος το άφησε μισοτελειωμένο — δεν το
      // ξαναγράφουμε, απλώς φεύγει από τη μέση.
      final alreadySummarised = lines.any(
        (line) => line.trim().startsWith(ShutdownTraceIncident.summaryPrefix),
      );
      if (!alreadySummarised) {
        await _writeTraceBlock(
          body: content,
          summary: ShutdownTraceIncident(
            filePath: '',
            occurredAt: _lastTimestampIn(lines) ?? clock(),
            totalMs: 0,
            slowestStepLabel: _lastStartedStepIn(lines),
            slowestStepMs: 0,
            hadFailure: false,
            wasInterrupted: true,
          ),
          append: appendToSessionLog,
        );
      }
      await orphan.delete();
      return !alreadySummarised;
    } catch (_) {
      try {
        await orphan.delete();
      } catch (_) {}
      return false;
    }
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
