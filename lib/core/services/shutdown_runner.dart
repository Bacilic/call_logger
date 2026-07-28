import 'dart:async';

import 'shutdown_coordinator.dart';
import 'shutdown_trace_service.dart';

/// Ό,τι χρειάζεται ο [ShutdownRunner] από το UI — και τίποτα παραπάνω.
///
/// Ο χρονιστής αποκάλυψης της οθόνης προόδου ΔΕΝ ζει εδώ: είναι καθαρά θέμα
/// παρουσίασης και ανήκει στον υλοποιητή αυτής της διεπαφής.
abstract class ShutdownUiPresenter {
  /// Το κλείσιμο ξεκίνησε — το UI παρουσιάζει τον [coordinator].
  void onShutdownStarted(ShutdownCoordinator coordinator);

  /// Ένα frame, ώστε η οθόνη προόδου να συνδεθεί στο stream γεγονότων πριν
  /// ξεκινήσουν τα βήματα.
  Future<void> awaitNextFrame();

  /// Το κλείσιμο ολοκληρώθηκε ή απέτυχε — το UI καθαρίζει.
  void onShutdownFinished();
}

/// Ενορχηστρώνει τον τερματισμό: συντονιστής, ιχνηλάτηση, σειρά βημάτων.
///
/// Ζούσε μέσα στο `_AppShortcutsState`. Βγήκε έξω γιατί η σειρά των βημάτων
/// τερματισμού δεν είναι δουλειά widget — και επειδή έτσι τεσταρίζεται χωρίς
/// να στηθεί ολόκληρο δέντρο widgets.
class ShutdownRunner {
  ShutdownRunner({
    required this.createCoordinator,
    required this.createTrace,
    required this.presenter,
  });

  final ShutdownCoordinator Function() createCoordinator;
  final Future<ShutdownTraceService?> Function() createTrace;
  final ShutdownUiPresenter presenter;

  bool _running = false;

  bool get isRunning => _running;

  Future<void> run() async {
    if (_running) return;
    _running = true;

    // ΣΗΜΕΙΩΣΗ (μη το εκλάβεις ως ξεχασμένο κλείσιμο παραθύρου): δεν καλείται
    // `windowManager.destroy()`. Ο ShutdownCoordinator.run() εκτελεί τα βήματα
    // καθαρισμού και τερματίζει ο ίδιος με exit(0), παρακάμπτοντας το teardown
    // της μηχανής Flutter που κατέρρεε (0xc0000005). Το παράθυρο μένει σκόπιμα
    // ορατό, δείχνοντας την οθόνη προόδου.
    final coordinator = createCoordinator();
    presenter.onShutdownStarted(coordinator);

    final trace = await createTrace();
    if (trace != null) {
      await trace.beginSession();
      trace.listenTo(coordinator.events);
    }

    try {
      await presenter.awaitNextFrame();
      await coordinator.run();
    } finally {
      presenter.onShutdownFinished();
      await trace?.endSession();
    }
  }
}
