import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Όταν αυξάνεται, η οθόνη Λάμπας ανοίγει το dialog ρυθμίσεων (από [MainShell]).
class LampOpenSettingsRequestNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void request() {
    state = state + 1;
  }
}

final lampOpenSettingsRequestProvider =
    NotifierProvider<LampOpenSettingsRequestNotifier, int>(
  LampOpenSettingsRequestNotifier.new,
);
