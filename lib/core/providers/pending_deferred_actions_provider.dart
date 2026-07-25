import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Αναβαλλόμενη ενέργεια που πρέπει να οριστικοποιηθεί πριν από εναλλαγή βάσης.
class PendingDeferredAction {
  const PendingDeferredAction({
    required this.token,
    required this.label,
    required this.settle,
  });

  final int token;

  /// Ονομαστική περιγραφή για τον χρήστη (π.χ. snackbar «Ολοκληρώθηκαν πρώτα»).
  final String label;

  /// Οριστικοποιεί ΤΩΡΑ αυτό που θα γινόταν αργότερα, πάνω στην ανοιχτή βάση.
  final Future<void> Function() settle;
}

/// Μητρώο αναβαλλόμενων ενεργειών (μη-autoDispose).
class PendingDeferredActionsNotifier
    extends Notifier<List<PendingDeferredAction>> {
  int _nextToken = 1;

  @override
  List<PendingDeferredAction> build() => const <PendingDeferredAction>[];

  /// Καταχωρεί ενέργεια και επιστρέφει μοναδικό token για [unregister].
  int register({
    required String label,
    required Future<void> Function() settle,
  }) {
    final token = _nextToken++;
    state = [
      ...state,
      PendingDeferredAction(token: token, label: label, settle: settle),
    ];
    return token;
  }

  void unregister(int token) {
    state = [
      for (final action in state)
        if (action.token != token) action,
    ];
  }

  /// Εκτελεί όλα τα [PendingDeferredAction.settle] με τη σειρά, αδειάζει τη λίστα
  /// και επιστρέφει τα labels όσων ολοκληρώθηκαν χωρίς εξαίρεση.
  Future<List<String>> settleAll() async {
    final pending = List<PendingDeferredAction>.of(state);
    state = const <PendingDeferredAction>[];
    final labels = <String>[];
    for (final action in pending) {
      try {
        await action.settle();
        labels.add(action.label);
      } catch (e, st) {
        developer.log(
          'Αποτυχία οριστικοποίησης αναβαλλόμενης ενέργειας: ${action.label}',
          name: 'pending_deferred_actions',
          error: e,
          stackTrace: st,
        );
      }
    }
    return labels;
  }
}

final pendingDeferredActionsProvider = NotifierProvider<
    PendingDeferredActionsNotifier, List<PendingDeferredAction>>(
  PendingDeferredActionsNotifier.new,
);
