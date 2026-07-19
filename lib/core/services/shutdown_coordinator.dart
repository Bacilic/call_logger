import 'dart:async';
import 'dart:ffi';
import 'dart:io' show Platform, exit;

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../features/database/services/database_exit_backup.dart';
import '../database/database_helper.dart';
import 'crash_log_service.dart';
import 'desktop_window_service.dart';

/// Φάση γεγονότος ενός βήματος κλεισίματος.
enum ShutdownStepPhase {
  started,
  completed,
  failed,
  interrupted,
}

/// Γεγονός προόδου από τον [ShutdownCoordinator].
class ShutdownStepEvent {
  const ShutdownStepEvent({
    required this.stepIndex,
    required this.label,
    required this.phase,
    this.durationMs,
    this.error,
  });

  final int stepIndex;
  final String label;
  final ShutdownStepPhase phase;
  final int? durationMs;
  final Object? error;

  bool get isTerminal =>
      phase == ShutdownStepPhase.completed ||
      phase == ShutdownStepPhase.failed ||
      phase == ShutdownStepPhase.interrupted;
}

/// Συντονιστής διαδοχικών βημάτων κλεισίματος με γεγονότα προόδου.
///
/// ΙΣΤΟΡΙΚΟ / ΓΙΑΤΙ (μη το «διορθώσεις» ως κακή πρακτική):
/// Παλαιότερα το κλείσιμο κατέληγε σε `windowManager.destroy()`, που στα Windows
/// είναι σκέτο `PostQuitMessage(0)`. Η επακόλουθη αποδόμηση του FlutterViewController
/// κατέρρεε ΣΤΑΘΕΡΑ με access violation 0xc0000005 στο flutter_windows.dll
/// (σύμβολο `FlutterWindowsView::OnHighContrastChanged`) — γνωστό bug της μηχανής
/// Flutter, ανεξάρτητο από τον κώδικά μας, παρόν και στο τελευταίο stable. Το crash
/// στο τέλος του κλεισίματος ενεργοποιούσε την αυτόματη επανεκκίνηση των Windows
/// και «ανάσταινε» την εφαρμογή (ο διάλογος «Αυτόματη επανεκκίνηση» στο Χ).
///
/// ΓΙ' ΑΥΤΟ: εσκεμμένα ΔΕΝ καλούμε `windowManager.destroy()`. Ο τερματισμός γίνεται
/// μέσω [terminate] (προεπιλογή `exit(0)`), που σκοτώνει τη διεργασία ΠΡΙΝ φτάσει
/// το σαθρό teardown της μηχανής. Η βάση και το ημερολόγιο έχουν ήδη κλείσει με τη
/// σειρά στα βήματα, οπότε η άμεση έξοδος είναι ασφαλής για τα δεδομένα.
class ShutdownCoordinator {
  ShutdownCoordinator({
    Future<void> Function()? persistWindowBounds,
    Future<void> Function()? walCheckpoint,
    Future<void> Function()? exitBackup,
    Future<void> Function()? closeConnection,
    Future<void> Function()? closeCrashLog,
    FutureOr<void> Function()? terminate,
    this.safetyTimeout = defaultSafetyTimeout,
    DateTime Function()? now,
    Future<void> Function(Duration duration)? delay,
  })  : _persistWindowBounds =
            persistWindowBounds ?? _defaultPersistWindowBounds,
        _walCheckpoint = walCheckpoint ?? _defaultWalCheckpoint,
        _exitBackup = exitBackup ?? _defaultExitBackup,
        _closeConnection = closeConnection ?? _defaultCloseConnection,
        _closeCrashLog = closeCrashLog ?? _defaultCloseCrashLog,
        _terminate = terminate ?? _defaultTerminate,
        _now = now ?? DateTime.now,
        _delay = delay ?? Future<void>.delayed,
        _useCancellableSafetyTimer = delay == null;

  static const Duration defaultSafetyTimeout = Duration(seconds: 20);

  /// Καθυστέρηση πριν εμφανιστεί η οθόνη προόδου στο UI.
  static const Duration progressRevealDelay = Duration(milliseconds: 500);

  static const List<String> stepLabels = [
    'Αποθήκευση θέσης παραθύρου',
    'Συγχώνευση αρχείων βάσης',
    'Αντίγραφο ασφαλείας εξόδου',
    'Κλείσιμο σύνδεσης βάσης',
    'Κλείσιμο ημερολογίου καταγραφής',
  ];

  final Future<void> Function() _persistWindowBounds;
  final Future<void> Function() _walCheckpoint;
  final Future<void> Function() _exitBackup;
  final Future<void> Function() _closeConnection;
  final Future<void> Function() _closeCrashLog;
  final FutureOr<void> Function() _terminate;
  final Duration safetyTimeout;
  final DateTime Function() _now;
  final Future<void> Function(Duration duration) _delay;
  final bool _useCancellableSafetyTimer;

  final StreamController<ShutdownStepEvent> _eventsController =
      StreamController<ShutdownStepEvent>.broadcast(sync: true);

  int? _currentStepIndex;
  bool _stepInFlight = false;
  bool _timedOut = false;
  bool _terminateCalled = false;
  bool _stepsFinished = false;

  Stream<ShutdownStepEvent> get events => _eventsController.stream;

  int? get currentStepIndex => _currentStepIndex;

  bool get terminateCalled => _terminateCalled;

  List<Future<void> Function()> get _actions => [
        _persistWindowBounds,
        _walCheckpoint,
        _exitBackup,
        _closeConnection,
        _closeCrashLog,
      ];

  Future<void> run() async {
    _timedOut = false;
    _terminateCalled = false;
    _stepsFinished = false;
    _currentStepIndex = null;
    _stepInFlight = false;

    final timeoutTrigger = Completer<void>();
    final stepsFuture = _runAllSteps();

    // Χρησιμοποιούμε Timer όταν το delay είναι το προεπιλεγμένο, ώστε να
    // ακυρώνεται και να μην μένουν pending timers στα τεστ.
    Timer? safetyTimer;
    if (_useCancellableSafetyTimer) {
      safetyTimer = Timer(safetyTimeout, () {
        if (!_stepsFinished && !timeoutTrigger.isCompleted) {
          _timedOut = true;
          timeoutTrigger.complete();
        }
      });
    } else {
      unawaited(_delay(safetyTimeout).then((_) {
        if (!_stepsFinished && !timeoutTrigger.isCompleted) {
          _timedOut = true;
          timeoutTrigger.complete();
        }
      }));
    }

    await Future.any([
      stepsFuture.then((_) {
        _stepsFinished = true;
        safetyTimer?.cancel();
      }),
      timeoutTrigger.future,
    ]);
    safetyTimer?.cancel();

    if (_timedOut) {
      final index = _currentStepIndex;
      if (index != null && _stepInFlight) {
        _emit(
          ShutdownStepEvent(
            stepIndex: index,
            label: stepLabels[index],
            phase: ShutdownStepPhase.interrupted,
          ),
        );
      }
      await _callTerminate();
      await _closeEvents();
      return;
    }

    await stepsFuture;
    await _callTerminate();
    await _closeEvents();
  }

  Future<void> _runAllSteps() async {
    final actions = _actions;
    for (var i = 0; i < actions.length; i++) {
      if (_timedOut) return;
      await _runStep(i, actions[i]);
      if (_timedOut) return;
    }
    _stepsFinished = true;
  }

  Future<void> _runStep(int index, Future<void> Function() action) async {
    _currentStepIndex = index;
    _stepInFlight = true;
    final label = stepLabels[index];
    _emit(
      ShutdownStepEvent(
        stepIndex: index,
        label: label,
        phase: ShutdownStepPhase.started,
      ),
    );

    final startedAt = _now();
    try {
      await action();
      if (_timedOut) return;
      final durationMs = _now().difference(startedAt).inMilliseconds;
      _emit(
        ShutdownStepEvent(
          stepIndex: index,
          label: label,
          phase: ShutdownStepPhase.completed,
          durationMs: durationMs < 0 ? 0 : durationMs,
        ),
      );
    } catch (error) {
      if (_timedOut) return;
      final durationMs = _now().difference(startedAt).inMilliseconds;
      _emit(
        ShutdownStepEvent(
          stepIndex: index,
          label: label,
          phase: ShutdownStepPhase.failed,
          durationMs: durationMs < 0 ? 0 : durationMs,
          error: error,
        ),
      );
      // Συνέχεια στο επόμενο βήμα (ίδια λογική με το παλιό catch-all).
    } finally {
      _stepInFlight = false;
    }
  }

  void _emit(ShutdownStepEvent event) {
    if (!_eventsController.isClosed) {
      _eventsController.add(event);
    }
  }

  Future<void> _callTerminate() async {
    if (_terminateCalled) return;
    _terminateCalled = true;
    await _terminate();
  }

  Future<void> _closeEvents() async {
    if (!_eventsController.isClosed) {
      await _eventsController.close();
    }
  }

  static Future<void> _defaultPersistWindowBounds() async {
    try {
      await DesktopWindowService().persistWindowBounds(windowManager);
    } on MissingPluginException catch (_) {}
  }

  static Future<void> _defaultWalCheckpoint() async {
    await DatabaseHelper.instance.tryWalCheckpoint(mode: 'FULL');
  }

  static Future<void> _defaultExitBackup() async {
    await DatabaseExitBackup.runIfEnabled();
  }

  static Future<void> _defaultCloseConnection() async {
    await DatabaseHelper.instance.closeConnection();
  }

  static Future<void> _defaultCloseCrashLog() async {
    await CrashLogService.instanceOrNull?.onShutdown();
  }

  static FutureOr<void> _defaultTerminate() {
    // ΓΙΑΤΙ φαίνεται διπλό (καλείται ΚΑΙ στο windows/runner/main.cpp): το exit(0)
    // παρακάτω σκοτώνει τη διεργασία επιτόπου και ο βρόχος μηνυμάτων του runner
    // ΔΕΝ επιστρέφει ποτέ στο σημείο όπου εκείνος καλεί UnregisterApplicationRestart.
    // Άρα σε αυτή τη διαδρομή πρέπει να το ακυρώσουμε ΕΜΕΙΣ εδώ, μέσω FFI, αλλιώς
    // το Windows Error Reporting θα «ανάσταινε» την εφαρμογή αν κάτι κατέρρεε στην
    // έξοδο. Δεν είναι περιττή επανάληψη — καλύπτει διαφορετική διαδρομή εξόδου.
    if (Platform.isWindows) {
      try {
        final kernel32 = DynamicLibrary.open('kernel32.dll');
        final unregister = kernel32
            .lookupFunction<Int32 Function(), int Function()>(
          'UnregisterApplicationRestart',
        );
        unregister();
      } catch (_) {}
    }
    // exit(0) αντί για ομαλό teardown: παράκαμψη του crash 0xc0000005 της μηχανής
    // Flutter (δες την τεκμηρίωση της κλάσης). Ποτέ μέσα σε τεστ — εκεί περνά fake
    // terminate μέσω του constructor.
    exit(0);
  }
}
