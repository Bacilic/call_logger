import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Immersive προβολή «Ιστορικό Εφαρμογής» (πλήρες πλάτος, χωρίς NavigationRail).
class HistoryAuditImmersiveNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setTrue() => state = true;

  void setFalse() => state = false;
}

final historyAuditImmersiveProvider =
    NotifierProvider<HistoryAuditImmersiveNotifier, bool>(
  HistoryAuditImmersiveNotifier.new,
);
