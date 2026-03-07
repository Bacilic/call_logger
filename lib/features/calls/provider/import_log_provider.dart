import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/import_types.dart';

/// Μία γραμμή log με επίπεδο (για χρώμα).
class ImportLogEntry {
  const ImportLogEntry(this.message, [this.level = ImportLogLevel.info]);

  final String message;
  final ImportLogLevel level;
}

/// Κατάσταση λογών για το Live Console του Import.
class ImportLogNotifier extends Notifier<List<ImportLogEntry>> {
  @override
  List<ImportLogEntry> build() => [];

  void addLog(String message, [ImportLogLevel level = ImportLogLevel.info]) {
    state = [...state, ImportLogEntry(message, level)];
  }

  void clearLogs() {
    state = [];
  }
}

final importLogProvider =
    NotifierProvider<ImportLogNotifier, List<ImportLogEntry>>(ImportLogNotifier.new);
