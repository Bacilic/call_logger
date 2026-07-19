import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'crash_log_service.dart';
import 'shutdown_coordinator.dart';

/// Ιχνηλάτης βημάτων κλεισίματος σε αρχείο κειμένου (με άμεσο flush).
class ShutdownTraceService {
  ShutdownTraceService({
    required this.logsDirectory,
    required this.enabled,
    required this.retentionCount,
    DateTime Function()? now,
    void Function(ShutdownStepEvent event)? onEventWritten,
  })  : _now = now ?? DateTime.now,
        _onEventWritten = onEventWritten;

  final String logsDirectory;
  final bool enabled;
  final int retentionCount;
  final DateTime Function() _now;
  final void Function(ShutdownStepEvent event)? _onEventWritten;

  File? _file;
  StreamSubscription<ShutdownStepEvent>? _subscription;

  static String logsDirectoryForDatabasePath(String databasePath) {
    return CrashLogService.logsDirectoryForDatabasePath(databasePath);
  }

  static String traceFileName(DateTime dateTime) {
    final y = dateTime.year.toString().padLeft(4, '0');
    final m = dateTime.month.toString().padLeft(2, '0');
    final d = dateTime.day.toString().padLeft(2, '0');
    final h = dateTime.hour.toString().padLeft(2, '0');
    final min = dateTime.minute.toString().padLeft(2, '0');
    final s = dateTime.second.toString().padLeft(2, '0');
    return 'shutdown_trace_$y-$m-$d'
        '_$h-$min-$s.log';
  }

  File? get currentFile => _file;

  /// Ανοίγει νέο αρχείο ιχνηλάτησης (αν είναι ενεργός) και καθαρίζει παλιά.
  Future<void> beginSession() async {
    if (!enabled) return;
    try {
      await Directory(logsDirectory).create(recursive: true);
      final file = File(p.join(logsDirectory, traceFileName(_now())));
      _file = file;
      _appendLine('=== shutdown trace start ===');
      await _purgeOldTraceFiles(retentionCount);
    } catch (_) {}
  }

  /// Συνδέει τον ιχνηλάτη στο stream γεγονότων του συντονιστή.
  void listenTo(Stream<ShutdownStepEvent> events) {
    if (!enabled) return;
    _subscription?.cancel();
    _subscription = events.listen(recordEvent);
  }

  void recordEvent(ShutdownStepEvent event) {
    if (!enabled) return;
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
      final errorPart =
          event.error == null ? '' : ' error=${event.error}';
      _appendLine(
        'step=${event.stepIndex} "${event.label}" $phaseLabel'
        '$durationPart$errorPart',
      );
      _onEventWritten?.call(event);
    } catch (_) {}
  }

  Future<void> endSession() async {
    await _subscription?.cancel();
    _subscription = null;
    try {
      if (_file != null) {
        _appendLine('=== shutdown trace end ===');
      }
    } catch (_) {}
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
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
  }

  Future<void> _purgeOldTraceFiles(int keepCount) async {
    final dir = Directory(logsDirectory);
    if (!await dir.exists()) return;

    final files = await dir
        .list()
        .where(
          (entity) =>
              entity is File &&
              p.basename(entity.path).startsWith('shutdown_trace_') &&
              p.basename(entity.path).endsWith('.log'),
        )
        .cast<File>()
        .toList();
    if (files.length <= keepCount) return;

    files.sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    for (final file in files.skip(keepCount)) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }
}
