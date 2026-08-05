import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/providers/pending_deferred_actions_provider.dart';
import '../services/deferred_deletion_runner.dart';

/// Προγραμματίζει αναβαλλόμενη διαγραφή με snackbar αντίστροφης μέτρησης και
/// «Αναίρεση»: η βάση αγγίζεται μόνο όταν λήξει το παράθυρο αναίρεσης.
///
/// Η ζωή του snackbar ελέγχεται ΑΠΟΚΛΕΙΣΤΙΚΑ από τον δρομέα — κλείνει στην
/// εκτέλεση ή στην αναίρεση, όχι με δικό του ρολόι που μπορεί να αποκλίνει
/// από το χρονόμετρο της διαγραφής (π.χ. το hover παγώνει τα snackbars).
///
/// Τα προαιρετικά [onFinished]/[onUndo] είναι για επιπλέον ενημέρωση UI του
/// καλούντος (π.χ. ανανέωση λίστας, ξεκλείδωμα κουμπιών) — ΟΧΙ για τη
/// διαγραφή: αυτή ζει ολόκληρη στο [execute].
DeferredDeletionRunner scheduleDeferredDeletionWithUndo({
  required ScaffoldMessengerState messenger,
  required PendingDeferredActionsNotifier deferredActions,
  required String label,
  required String Function(int secondsLeft) countdownMessage,
  required String completedMessage,
  required String failureMessage,
  required Future<void> Function() execute,
  void Function(bool success)? onFinished,
  VoidCallback? onUndo,
}) {
  late final DeferredDeletionRunner runner;
  late final ScaffoldFeatureController<SnackBar, SnackBarClosedReason> snackbar;
  runner = DeferredDeletionRunner.schedule(
    deferredActions: deferredActions,
    label: label,
    execute: execute,
    onFinished: (success) {
      snackbar.close();
      messenger.showSnackBar(
        SnackBar(content: Text(success ? completedMessage : failureMessage)),
      );
      onFinished?.call(success);
    },
  );
  messenger.hideCurrentSnackBar();
  snackbar = messenger.showSnackBar(
    SnackBar(
      duration: const Duration(minutes: 10),
      content: DeletionCountdownText(message: countdownMessage),
      action: SnackBarAction(
        label: 'Αναίρεση',
        onPressed: () {
          runner.undo();
          messenger.showSnackBar(
            const SnackBar(content: Text('Η διαγραφή αναιρέθηκε.')),
          );
          onUndo?.call();
        },
      ),
    ),
  );
  return runner;
}

/// Κείμενο snackbar με ζωντανή αντίστροφη μέτρηση των δευτερολέπτων που
/// απομένουν μέχρι να εκτελεστεί η διαγραφή.
class DeletionCountdownText extends StatefulWidget {
  const DeletionCountdownText({required this.message, super.key});

  final String Function(int secondsLeft) message;

  @override
  State<DeletionCountdownText> createState() => _DeletionCountdownTextState();
}

class _DeletionCountdownTextState extends State<DeletionCountdownText> {
  int _secondsLeft = kDeferredDeletionUndoWindow.inSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        _timer?.cancel();
        setState(() => _secondsLeft = 0);
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(widget.message(_secondsLeft));
  }
}
