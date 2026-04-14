import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Όταν true, εμφανίζεται «Ιστορικό Εφαρμογής» αντί για ιστορικό κλήσεων.
class HistoryApplicationAuditViewNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;

  void setFalse() => state = false;
}

final historyApplicationAuditViewProvider =
    NotifierProvider<HistoryApplicationAuditViewNotifier, bool>(
  HistoryApplicationAuditViewNotifier.new,
);
