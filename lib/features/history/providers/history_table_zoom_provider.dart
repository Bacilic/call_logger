import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Επίπεδο μεγέθυνσης πίνακα ιστορικού (0.5–2.0).
final historyTableZoomProvider =
    NotifierProvider.autoDispose<HistoryTableZoomNotifier, double>(
      HistoryTableZoomNotifier.new,
    );

class HistoryTableZoomNotifier extends Notifier<double> {
  @override
  double build() => 1.0;

  void zoomOut() {
    state = (state - 0.1).clamp(0.5, 2.0);
  }

  void zoomIn() {
    state = (state + 0.1).clamp(0.5, 2.0);
  }

  void reset() {
    state = 1.0;
  }
}
