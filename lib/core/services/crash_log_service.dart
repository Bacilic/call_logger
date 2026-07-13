import 'dart:io';

import 'package:path/path.dart' as p;

/// Καταγραφή σφαλμάτων και καταρρεύσεων σε ημερήσια αρχεία δίπλα στη βάση.
class CrashLogService {
  CrashLogService({
    required this.logsDirectory,
    this.appVersion = 'unknown',
    DateTime Function()? now,
    int maxDetailedRepeats = 20,
    int repeatSummaryInterval = 100,
  })  : _now = now ?? DateTime.now,
        _maxDetailedRepeats = maxDetailedRepeats,
        _repeatSummaryInterval = repeatSummaryInterval;

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

  final String logsDirectory;
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
  }) async {
    try {
      final logsDir = logsDirectoryForDatabasePath(databasePath);
      final service = CrashLogService(
        logsDirectory: logsDir,
        appVersion: appVersion,
      );
      _instance = service;
      await service.onStartup(retentionCount: retentionCount);
    } catch (_) {}
  }

  Future<void> onStartup({required int retentionCount}) async {
    try {
      await Directory(logsDirectory).create(recursive: true);
      await _purgeOldLogFiles(retentionCount);
      if (await _sessionLockFile().exists()) {
        _logPlainMessage(abnormalTerminationMessage, fatal: true);
      }
      await _sessionLockFile().writeAsString('1', flush: true);
    } catch (_) {}
  }

  Future<void> onShutdown() async {
    try {
      _flushPendingRepeatSummaries();
      if (await _sessionLockFile().exists()) {
        await _sessionLockFile().delete();
      }
    } catch (_) {}
  }

  void logError(
    Object error,
    StackTrace stack, {
    required bool fatal,
  }) {
    try {
      _logErrorInternal(error, stack, fatal: fatal);
    } catch (_) {}
  }

  void _logErrorInternal(
    Object error,
    StackTrace stack, {
    required bool fatal,
  }) {
    Directory(logsDirectory).createSync(recursive: true);
    final key = _dedupKey(error, stack);
    final state = _dedupStates.putIfAbsent(key, _DedupState.new);

    if (state.detailedCount < _maxDetailedRepeats) {
      _writeDetailedEntry(
        message: error.toString(),
        stack: stack,
        fatal: fatal,
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
  }) {
    final buffer = StringBuffer()
      ..writeln(_formatHeader(fatal: fatal))
      ..writeln(message);
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
    final stamp = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    final severity = fatal ? 'ΜΟΙΡΑΙΟ' : 'ΜΗ-ΜΟΙΡΑΙΟ';
    return '[$stamp] v$appVersion $severity';
  }

  void _appendToDailyLog(String chunk) {
    final file = File(
      p.join(logsDirectory, dailyLogFileName(_now())),
    );
    file.writeAsStringSync(chunk, mode: FileMode.append, flush: true);
  }

  Future<void> _purgeOldLogFiles(int retentionCount) async {
    final dir = Directory(logsDirectory);
    if (!await dir.exists()) return;

    final files = await dir
        .list()
        .where((entity) =>
            entity is File &&
            p.basename(entity.path).startsWith('errors_') &&
            p.basename(entity.path).endsWith('.log'))
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

  File _sessionLockFile() => File(p.join(logsDirectory, sessionLockFileName));

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
