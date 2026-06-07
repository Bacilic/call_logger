import 'dart:io';

import 'package:flutter/foundation.dart';

/// Κατηγορία σφάλματος εφαρμογής (εκτός ροής αρχικοποίησης βάσης).
enum AppErrorKind {
  uiLayoutError,
  pluginError,
  windowManagerError,
  networkError,
  unknownError,
}

/// Αποτέλεσμα ταξινόμησης runtime σφάλματος εφαρμογής για global handlers.
class AppErrorResult {
  const AppErrorResult({
    required this.kind,
    required this.friendlyTitle,
    required this.technicalSummary,
    this.originalExceptionText,
    this.stackTraceText,
    required this.timestamp,
  });

  final AppErrorKind kind;
  final String friendlyTitle;
  final String technicalSummary;
  final String? originalExceptionText;
  final String? stackTraceText;
  final DateTime timestamp;

  static String kindLabel(AppErrorKind kind) {
    switch (kind) {
      case AppErrorKind.uiLayoutError:
        return 'Σφάλμα διάταξης (layout)';
      case AppErrorKind.pluginError:
        return 'Σφάλμα εφαρμογής / plugin';
      case AppErrorKind.windowManagerError:
        return 'Σφάλμα διαχείρισης παραθύρου';
      case AppErrorKind.networkError:
        return 'Σφάλμα δικτύου';
      case AppErrorKind.unknownError:
        return 'Άγνωστο σφάλμα εφαρμογής';
    }
  }

  factory AppErrorResult.fromException(Object error, [StackTrace? stack]) {
    final raw = error.toString();
    final lower = raw.toLowerCase();
    final stackStr = stack?.toString() ?? '';
    final timestamp = DateTime.now();

    String original = raw;
    if (error is FlutterError) {
      final msg = error.message.trim();
      if (msg.isNotEmpty) {
        original = msg;
      }
    }

    AppErrorResult build({
      required AppErrorKind kind,
      required String friendlyTitle,
      required String technicalSummary,
    }) {
      return AppErrorResult(
        kind: kind,
        friendlyTitle: friendlyTitle,
        technicalSummary: technicalSummary,
        originalExceptionText: original,
        stackTraceText: stackStr.isEmpty ? null : stackStr,
        timestamp: timestamp,
      );
    }

    if (error is FlutterError) {
      final msgLower = original.toLowerCase();
      if (msgLower.contains('overflowed') ||
          msgLower.contains('renderflex') ||
          msgLower.contains('renderbox')) {
        return build(
          kind: AppErrorKind.uiLayoutError,
          friendlyTitle: 'Σφάλμα διάταξης (layout)',
          technicalSummary: original,
        );
      }
      return build(
        kind: AppErrorKind.pluginError,
        friendlyTitle: 'Σφάλμα εφαρμογής',
        technicalSummary: original,
      );
    }

    if (lower.contains('window_manager') ||
        (lower.contains('hwnd') && lower.contains('window'))) {
      return build(
        kind: AppErrorKind.windowManagerError,
        friendlyTitle: 'Σφάλμα διαχείρισης παραθύρου',
        technicalSummary: original,
      );
    }

    if (error is SocketException ||
        lower.contains('connection refused') ||
        lower.contains('host unreachable')) {
      return build(
        kind: AppErrorKind.networkError,
        friendlyTitle: 'Σφάλμα δικτύου',
        technicalSummary: original,
      );
    }

    return build(
      kind: AppErrorKind.unknownError,
      friendlyTitle: 'Σφάλμα εφαρμογής (${error.runtimeType})',
      technicalSummary: original,
    );
  }

  String buildClipboardReport() {
    final buf = StringBuffer()
      ..writeln('Κατηγορία σφάλματος: ${kindLabel(kind)}')
      ..writeln('---')
      ..writeln('Τίτλος: $friendlyTitle')
      ..writeln('---')
      ..writeln('Περίληψη: $technicalSummary');
    if (originalExceptionText != null &&
        originalExceptionText!.trim().isNotEmpty) {
      buf
        ..writeln('---')
        ..writeln('Αρχικό μήνυμα σφάλματος (runtime):')
        ..writeln(originalExceptionText!.trim());
    }
    if (stackTraceText != null && stackTraceText!.trim().isNotEmpty) {
      buf
        ..writeln('---')
        ..writeln('Stack trace:')
        ..writeln(stackTraceText!.trim());
    }
    buf
      ..writeln('---')
      ..writeln(
        'Χρονική στιγμή: ${timestamp.toIso8601String()}',
      );
    return buf.toString();
  }
}
