import 'dart:async';
import 'dart:developer' as developer;

import '../../../core/providers/pending_deferred_actions_provider.dart';

/// Το παράθυρο αναίρεσης των αναβαλλόμενων διαγραφών (και διάρκεια snackbar).
const Duration kDeferredDeletionUndoWindow = Duration(seconds: 5);

/// Αναβαλλόμενη εκτέλεση διαγραφής με παράθυρο αναίρεσης.
///
/// Η βάση δεν αγγίζεται μέχρι τη λήξη του παραθύρου· η [undo] απλώς ακυρώνει,
/// χωρίς καμία λογική επαναφοράς. Η ενέργεια καταχωρείται στο μητρώο
/// αναβαλλόμενων ενεργειών ώστε τυχόν εναλλαγή βάσης να την οριστικοποιήσει
/// πρώτα, πάνω στην ανοιχτή βάση.
///
/// Η εκτέλεση ΔΕΝ εξαρτάται από τη ζωή κανενός widget: ό,τι υποσχέθηκε το
/// snackbar θα γίνει, ακόμη κι αν ο χρήστης άλλαξε οθόνη στο μεταξύ. Η
/// ενέργεια ξεγράφεται από το μητρώο μόνο μετά από εκτέλεση ή αναίρεση.
class DeferredDeletionRunner {
  DeferredDeletionRunner._(
    this._deferredActions,
    this._execute,
    this._label,
    this._onFinished,
  );

  /// Προγραμματίζει τη διαγραφή: εκτελείται μετά το [undoWindow], εκτός αν
  /// προλάβει η [undo] ή η οριστικοποίηση λόγω εναλλαγής βάσης.
  ///
  /// Το [onFinished] καλείται ΜΕΤΑ την εκτέλεση (επιτυχή ή μη) — εκεί κλείνει
  /// το snackbar της αντίστροφης μέτρησης, ώστε η προσφορά «Αναίρεση» να μη
  /// ζει ούτε δευτερόλεπτο αφότου η διαγραφή έγινε πράξη.
  factory DeferredDeletionRunner.schedule({
    required PendingDeferredActionsNotifier deferredActions,
    required String label,
    required Future<void> Function() execute,
    Duration undoWindow = kDeferredDeletionUndoWindow,
    void Function(bool success)? onFinished,
  }) {
    final runner = DeferredDeletionRunner._(
      deferredActions,
      execute,
      label,
      onFinished,
    );
    runner._token = deferredActions.register(
      label: label,
      settle: runner._settleNow,
    );
    runner._timer = Timer(undoWindow, runner._onWindowElapsed);
    return runner;
  }

  final PendingDeferredActionsNotifier _deferredActions;
  final Future<void> Function() _execute;
  final String _label;
  final void Function(bool success)? _onFinished;
  late final int _token;
  Timer? _timer;
  bool _finished = false;

  /// Ακύρωση μέσα στο παράθυρο — η βάση δεν αγγίχτηκε ποτέ.
  void undo() {
    if (_finished) return;
    _finished = true;
    _timer?.cancel();
    _deferredActions.unregister(_token);
  }

  void _onWindowElapsed() {
    if (_finished) return;
    _finished = true;
    _deferredActions.unregister(_token);
    unawaited(_runExecute());
  }

  /// Καλείται από το `settleAll` της εναλλαγής βάσης — η ενέργεια έχει ήδη
  /// αφαιρεθεί από το μητρώο εκεί, εδώ μόνο εκτελούμε.
  Future<void> _settleNow() async {
    if (_finished) return;
    _finished = true;
    _timer?.cancel();
    var success = false;
    try {
      await _execute();
      success = true;
    } finally {
      _onFinished?.call(success);
    }
  }

  Future<void> _runExecute() async {
    var success = false;
    try {
      await _execute();
      success = true;
    } catch (e, st) {
      developer.log(
        'Αποτυχία αναβαλλόμενης διαγραφής: $_label',
        name: 'deferred_deletion',
        error: e,
        stackTrace: st,
      );
    } finally {
      _onFinished?.call(success);
    }
  }
}
