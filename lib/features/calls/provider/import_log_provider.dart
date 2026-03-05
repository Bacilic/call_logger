import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Κατάσταση λογών για το Live Console του Import.
class ImportLogNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => [];

  void addLog(String message) {
    state = [...state, message];
  }

  void clearLogs() {
    state = [];
  }
}

final importLogProvider =
    NotifierProvider<ImportLogNotifier, List<String>>(ImportLogNotifier.new);
