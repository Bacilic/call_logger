import 'package:flutter/foundation.dart';

enum ResolutionLogLevel { info, success, warning, error }

class ResolutionLogEntry {
  const ResolutionLogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.proposalId,
    this.stepType,
  });

  factory ResolutionLogEntry.info(
    String message, {
    int? proposalId,
    String? stepType,
  }) {
    return ResolutionLogEntry(
      timestamp: DateTime.now(),
      level: ResolutionLogLevel.info,
      message: message,
      proposalId: proposalId,
      stepType: stepType,
    );
  }

  factory ResolutionLogEntry.success(
    String message, {
    int? proposalId,
    String? stepType,
  }) {
    return ResolutionLogEntry(
      timestamp: DateTime.now(),
      level: ResolutionLogLevel.success,
      message: message,
      proposalId: proposalId,
      stepType: stepType,
    );
  }

  factory ResolutionLogEntry.warning(
    String message, {
    int? proposalId,
    String? stepType,
  }) {
    return ResolutionLogEntry(
      timestamp: DateTime.now(),
      level: ResolutionLogLevel.warning,
      message: message,
      proposalId: proposalId,
      stepType: stepType,
    );
  }

  factory ResolutionLogEntry.error(
    String message, {
    int? proposalId,
    String? stepType,
  }) {
    return ResolutionLogEntry(
      timestamp: DateTime.now(),
      level: ResolutionLogLevel.error,
      message: message,
      proposalId: proposalId,
      stepType: stepType,
    );
  }

  final DateTime timestamp;
  final ResolutionLogLevel level;
  final String message;
  final int? proposalId;
  final String? stepType;

  String formatLine() {
    return '${_formatTime(timestamp)} [${_levelLabel(level)}] $message';
  }

  @override
  String toString() => formatLine();

  static String _formatTime(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    String three(int n) => n.toString().padLeft(3, '0');
    return '${two(value.hour)}:${two(value.minute)}:'
        '${two(value.second)}.${three(value.millisecond)}';
  }

  static String _levelLabel(ResolutionLogLevel level) {
    return switch (level) {
      ResolutionLogLevel.info => 'INFO',
      ResolutionLogLevel.success => 'SUCCESS',
      ResolutionLogLevel.warning => 'WARNING',
      ResolutionLogLevel.error => 'ERROR',
    };
  }
}

class ResolutionCancelToken {
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }
}

class ResolutionLogController extends ChangeNotifier {
  final List<ResolutionLogEntry> _entries = <ResolutionLogEntry>[];

  List<ResolutionLogEntry> get entries => List.unmodifiable(_entries);

  void add(ResolutionLogEntry entry) {
    _entries.add(entry);
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }
}
