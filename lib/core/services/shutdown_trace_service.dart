import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'crash_log_service.dart';
import 'shutdown_coordinator.dart';
import 'shutdown_trace_incident.dart';

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
class ShutdownTraceService {
  ShutdownTraceService({
    required this.logsDirectory,
    required this.retentionCount,
    this.slowThreshold = ShutdownCoordinator.progressRevealDelay,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final String logsDirectory;

  /// Πόσα αρχεία περιστατικών κρατιούνται. Ακολουθεί τη ρύθμιση των αρχείων
  /// καταγραφής σφαλμάτων — ένα νούμερο για όλα τα διαγνωστικά αρχεία.
  final int retentionCount;

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

  /// Το αρχείο περιστατικού που κρατήθηκε — `null` όσο δεν έχει κριθεί ότι
  /// αξίζει, και μετά από καθαρό κλείσιμο.
  File? _incidentFile;

  static const String workingFileName =
      '${ShutdownTraceIncident.fileNamePrefix}current'
      '${ShutdownTraceIncident.fileNameSuffix}';

  static String logsDirectoryForDatabasePath(String databasePath) {
    return CrashLogService.logsDirectoryForDatabasePath(databasePath);
  }

  /// Το αρχείο που κρατήθηκε ως περιστατικό (για τα τεστ και το UI).
  File? get incidentFile => _incidentFile;

  /// Αληθές όταν το τρέχον κλείσιμο δικαιολογεί αρχείο.
  bool get isIncident =>
      _hadFailure ||
      _wasInterrupted ||
      _totalMs >= slowThreshold.inMilliseconds;

  /// Ανοίγει το προσωρινό αρχείο και προάγει τυχόν ορφανό προηγούμενο.
  Future<void> beginSession() async {
    try {
      await Directory(logsDirectory).create(recursive: true);
      await _promoteOrphanedWorkingFile();
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

  /// Κρατά τα λίγα στοιχεία που χρειάζεται η απόφαση «αξίζει αρχείο;» και η
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

  /// Κλείνει τη συνεδρία: κρατά το αρχείο ως περιστατικό ή το σβήνει.
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
      _incidentFile = await _keepAsIncident(file, _buildIncident());
      await _purgeOldIncidentFiles();
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

  /// Γράφει τη σύνοψη και μετονομάζει σε αρχείο περιστατικού.
  Future<File> _keepAsIncident(File file, ShutdownTraceIncident summary) async {
    file.writeAsStringSync(
      '${summary.toSummaryLine()}\n',
      mode: FileMode.append,
      flush: true,
    );
    final target = File(
      p.join(logsDirectory, incidentFileName(summary.occurredAt)),
    );
    if (await target.exists()) await target.delete();
    return file.rename(target.path);
  }

  static String incidentFileName(DateTime dateTime) {
    String two(int value) => value.toString().padLeft(2, '0');
    final date =
        '${dateTime.year.toString().padLeft(4, '0')}-'
        '${two(dateTime.month)}-${two(dateTime.day)}';
    final time =
        '${two(dateTime.hour)}${two(dateTime.minute)}'
        '${two(dateTime.second)}';
    return '${ShutdownTraceIncident.fileNamePrefix}${date}_$time'
        '${ShutdownTraceIncident.fileNameSuffix}';
  }

  /// Προσωρινό αρχείο από προηγούμενη εκτέλεση = το κλείσιμο δεν ολοκληρώθηκε
  /// ποτέ (η διεργασία πέθανε στη μέση). Αυτό είναι από μόνο του περιστατικό:
  /// κρατιέται, με το τελευταίο βήμα που πρόλαβε να ξεκινήσει.
  Future<void> _promoteOrphanedWorkingFile() async {
    final orphan = File(p.join(logsDirectory, workingFileName));
    if (!await orphan.exists()) return;
    try {
      final lines = await orphan.readAsLines();
      // Αν έχει ήδη σύνοψη, κάποιος το άφησε μισοτελειωμένο — δεν το πειράζουμε
      // δεύτερη φορά, απλώς φεύγει από τη μέση.
      final alreadySummarised = lines.any(
        (line) => line.trim().startsWith(ShutdownTraceIncident.summaryPrefix),
      );
      if (alreadySummarised) {
        await orphan.delete();
        return;
      }
      await _keepAsIncident(
        orphan,
        ShutdownTraceIncident(
          filePath: '',
          occurredAt: _lastTimestampIn(lines) ?? _now(),
          totalMs: 0,
          slowestStepLabel: _lastStartedStepIn(lines),
          slowestStepMs: 0,
          hadFailure: false,
          wasInterrupted: true,
        ),
      );
      await _purgeOldIncidentFiles();
    } catch (_) {
      try {
        await orphan.delete();
      } catch (_) {}
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

  Future<void> _purgeOldIncidentFiles() async {
    final dir = Directory(logsDirectory);
    if (!await dir.exists()) return;

    final files = await dir
        .list()
        .where(
          (entity) =>
              entity is File &&
              ShutdownTraceIncident.isIncidentFile(entity.path) &&
              p.basename(entity.path) != workingFileName,
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
}
