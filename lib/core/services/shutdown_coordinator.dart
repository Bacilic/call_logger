import 'dart:async';
import 'dart:ffi';
import 'dart:io' show Platform, exit;

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../features/database/services/database_exit_backup.dart';
import '../database/database_helper.dart';
import 'crash_log_service.dart';
import 'desktop_window_service.dart';
import 'operator_presence_heartbeat.dart';

/// Φάση γεγονότος ενός βήματος κλεισίματος.
enum ShutdownStepPhase { started, completed, failed, interrupted }

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

/// Ένα βήμα με δικό του παράθυρο χρόνου το ξεπέρασε.
///
/// Είναι **αποτυχία βήματος**, όχι διακοπή του κλεισίματος: η ουρά συνεχίζει
/// στα επόμενα βήματα. Το μήνυμα γράφεται στο ίχνος, οπότε λέει τι συνέβη σε
/// γλώσσα που διαβάζεται — όχι «Future not completed».
class ShutdownStepBudgetExceeded implements Exception {
  const ShutdownStepBudgetExceeded(this.label, this.budget);

  final String label;
  final Duration budget;

  @override
  String toString() =>
      'Το βήμα «$label» ξεπέρασε το δικό του παράθυρο των '
      '${budget.inSeconds} δευτερολέπτων και δεν το περιμένουμε άλλο.';
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
    Future<void> Function()? releasePresence,
    Future<void> Function()? walCheckpoint,
    Future<void> Function()? exitBackup,
    Future<void> Function()? closeConnection,
    Future<void> Function()? closeCrashLog,
    FutureOr<void> Function()? terminate,
    this.safetyTimeout = defaultSafetyTimeout,
    DateTime Function()? now,
    Future<void> Function(Duration duration)? delay,
  }) : _persistWindowBounds =
           persistWindowBounds ?? _defaultPersistWindowBounds,
       _releasePresence = releasePresence ?? _defaultReleasePresence,
       _walCheckpoint = walCheckpoint ?? _defaultWalCheckpoint,
       _exitBackup = exitBackup ?? _defaultExitBackup,
       _closeConnection = closeConnection ?? _defaultCloseConnection,
       _closeCrashLog = closeCrashLog ?? _defaultCloseCrashLog,
       _terminate = terminate ?? _defaultTerminate,
       _now = now ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed,
       _useCancellableSafetyTimer = delay == null;

  static const Duration defaultSafetyTimeout = Duration(seconds: 20);

  /// Πόσο περιμένουμε το [beforeTerminate] πριν προχωρήσουμε στον τερματισμό.
  static const Duration beforeTerminateTimeout = Duration(seconds: 2);

  /// Καθυστέρηση πριν εμφανιστεί η οθόνη προόδου στο UI.
  static const Duration progressRevealDelay = Duration(milliseconds: 500);

  static const List<String> stepLabels = [
    'Αποθήκευση θέσης παραθύρου',
    'Παράδοση συνεδρίας',
    'Συγχώνευση αρχείων βάσης',
    'Αντίγραφο ασφαλείας εξόδου',
    'Κλείσιμο σύνδεσης βάσης',
    'Κλείσιμο ημερολογίου καταγραφής',
  ];

  /// Πόσο χρόνο **δικό του** παίρνει το αντίγραφο εξόδου.
  ///
  /// Με δικτυακή βάση το αντίγραφο ξαναγράφει τη βάση καθαρή στον προορισμό:
  /// 15 MB πάνω από δίκτυο θέλουν δεκαέξι δευτερόλεπτα σε μετρημένο κλείσιμο.
  /// Όσο μοιραζόταν το [safetyTimeout] με τα άλλα πέντε βήματα, έπαιρνε ό,τι
  /// περίσσευε — και ό,τι περίσσευε δεν αρκούσε.
  static const Duration exitBackupBudget = Duration(seconds: 20);

  /// Το δικό του παράθυρο κάθε βήματος, ή `null` όταν μοιράζεται το γενικό.
  ///
  /// Παράλληλη με τις [stepLabels] επίτηδες, με έλεγχο μήκους στο [run]: ένα
  /// βήμα που προστίθεται στη μία λίστα και ξεχνιέται στην άλλη σκάει αμέσως,
  /// αντί να κληρονομήσει σιωπηλά λάθος όριο.
  /// Η θέση του βήματος που σβήνει το σημάδι «τρέχω τώρα».
  ///
  /// Δεν χρειάζεται τη βάση — χρειάζεται μια στιγμή. Όσο περίμενε στην ουρά
  /// πίσω από το αντίγραφο, μια διακοπή το άφηνε ανεκτέλεστο: η επόμενη
  /// εκκίνηση ανήγγελλε μη ομαλό κλείσιμο, και ο φρουρός της αναβάθμισης έβλεπε
  /// στον διπλανό υπολογιστή σταθμό-φάντασμα επί τρία λεπτά. Γι' αυτό τρέχει
  /// εγγυημένα σε **κάθε** διαδρομή εξόδου — δες [_runGuaranteedSteps].
  static const int closeCrashLogStep = 5;

  static const List<Duration?> stepOwnBudgets = [
    null, // Αποθήκευση θέσης παραθύρου
    null, // Παράδοση συνεδρίας
    null, // Συγχώνευση αρχείων βάσης
    exitBackupBudget, // Αντίγραφο ασφαλείας εξόδου
    null, // Κλείσιμο σύνδεσης βάσης
    null, // Κλείσιμο ημερολογίου καταγραφής
  ];

  final Future<void> Function() _persistWindowBounds;
  final Future<void> Function() _releasePresence;
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

  /// Ο γενικός φρουρός, με προθεσμία που μετακινείται.
  ///
  /// Το [_guardGeneration] είναι απαραίτητο επειδή η προθεσμία επεκτείνεται εν
  /// κινήσει: το παλιό χρονόμετρο δεν πάντα ακυρώνεται (στα τεστ ο χρόνος
  /// έρχεται από έξω), οπότε ό,τι ξυπνά με παλιά γενιά αγνοείται.
  Timer? _safetyTimer;
  DateTime? _guardDeadline;
  int _guardGeneration = 0;
  Completer<void>? _timeoutTrigger;

  /// Ποια βήματα πρόλαβαν να τερματίσουν — με επιτυχία ή με αποτυχία.
  final Set<int> _finishedSteps = {};

  /// Ό,τι πρέπει να ΠΡΟΛΑΒΕΙ να ολοκληρωθεί πριν πεθάνει η διεργασία.
  ///
  /// Ο τερματισμός είναι `exit(0)` (δες την τεκμηρίωση της κλάσης): σκοτώνει
  /// τη διεργασία επιτόπου, οπότε ΤΙΠΟΤΑ μετά το [run] δεν εκτελείται — ούτε
  /// τα `finally` των καλούντων. Ό,τι οφείλει να προλάβει μπαίνει εδώ, και
  /// τρέχει σε ΚΑΘΕ διαδρομή εξόδου: κανονική ή από το όριο ασφαλείας.
  ///
  /// Ο [ShutdownRunner] βάζει εδώ το κλείσιμο της ιχνηλάτησης — αλλιώς το
  /// προσωρινό αρχείο έμενε ορφανό και η επόμενη εκκίνηση το προήγαγε σε
  /// «περιστατικό διακοπής» που ποτέ δεν συνέβη.
  Future<void> Function()? beforeTerminate;

  Stream<ShutdownStepEvent> get events => _eventsController.stream;

  int? get currentStepIndex => _currentStepIndex;

  bool get terminateCalled => _terminateCalled;

  List<Future<void> Function()> get _actions => [
    _persistWindowBounds,
    _releasePresence,
    _walCheckpoint,
    _exitBackup,
    _closeConnection,
    _closeCrashLog,
  ];

  Future<void> run() async {
    assert(
      stepOwnBudgets.length == stepLabels.length,
      'Κάθε βήμα κλεισίματος οφείλει να δηλώνει αν έχει δικό του παράθυρο.',
    );
    _timedOut = false;
    _terminateCalled = false;
    _stepsFinished = false;
    _currentStepIndex = null;
    _stepInFlight = false;
    _finishedSteps.clear();

    assert(
      stepLabels[closeCrashLogStep] == 'Κλείσιμο ημερολογίου καταγραφής',
      'Το εγγυημένο βήμα δείχνει σε άλλη θέση από αυτή που περιγράφει.',
    );

    final trigger = Completer<void>();
    _timeoutTrigger = trigger;
    // Ο φρουρός οπλίζεται ΠΡΙΝ ξεκινήσει το πρώτο βήμα: αλλιώς η πρώτη δουλειά
    // θα έτρεχε αφύλακτη, και είναι αυτή που αγγίζει πρώτη το δίκτυο.
    _armSafetyGuard(safetyTimeout);

    final stepsFuture = _runAllSteps();

    await Future.any([
      stepsFuture.then((_) {
        _stepsFinished = true;
        _cancelSafetyGuard();
      }),
      trigger.future,
    ]);
    _cancelSafetyGuard();

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
    final budget = stepOwnBudgets[index];
    // Πρώτα η προθεσμία, μετά το γεγονός έναρξης: το βήμα δεν επιτρέπεται να
    // τρέξει ούτε μια στιγμή με το ρολόι των άλλων.
    if (budget != null) _extendSafetyGuard(budget);
    _emit(
      ShutdownStepEvent(
        stepIndex: index,
        label: label,
        phase: ShutdownStepPhase.started,
      ),
    );

    final startedAt = _now();
    try {
      if (budget == null) {
        await action();
      } else {
        await _awaitWithin(action(), budget, label);
      }
      _finishedSteps.add(index);
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
      _finishedSteps.add(index);
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

  /// Περιμένει το [action] ως το [budget] — με το ΙΔΙΟ ρολόι που φυλάει το
  /// γενικό όριο, ώστε ένα τεστ να ορίζει και τις δύο άκρες του χρόνου.
  ///
  /// Η δουλειά **δεν** ακυρώνεται: μια αντιγραφή που τρέχει μέσα στη βάση δεν
  /// σταματά επειδή σταματήσαμε να την περιμένουμε. Ο τερματισμός τη σκοτώνει
  /// λίγο αργότερα — γι' αυτό το παράθυρο είναι γενναιόδωρο.
  Future<void> _awaitWithin(
    Future<void> action,
    Duration budget,
    String label,
  ) async {
    var settled = false;
    Object? failure;
    StackTrace? failureStack;
    final done = action.then<void>(
      (_) => settled = true,
      onError: (Object error, StackTrace stack) {
        settled = true;
        failure = error;
        failureStack = stack;
      },
    );

    final window = _sleep(budget);
    try {
      await Future.any([done, window.future]);
    } finally {
      window.cancel();
    }

    if (!settled) throw ShutdownStepBudgetExceeded(label, budget);
    final error = failure;
    if (error != null) {
      Error.throwWithStackTrace(error, failureStack ?? StackTrace.current);
    }
  }

  /// Μία αναμονή, ακυρώσιμη, στο ρολόι του κλεισίματος.
  ({Future<void> future, void Function() cancel}) _sleep(Duration duration) {
    final completer = Completer<void>();
    void wake() {
      if (!completer.isCompleted) completer.complete();
    }

    if (_useCancellableSafetyTimer) {
      final timer = Timer(duration, wake);
      return (future: completer.future, cancel: timer.cancel);
    }
    unawaited(_delay(duration).then((_) => wake()));
    return (future: completer.future, cancel: () {});
  }

  void _armSafetyGuard(Duration remaining) {
    _safetyTimer?.cancel();
    _safetyTimer = null;
    final generation = ++_guardGeneration;
    final window = remaining.isNegative ? Duration.zero : remaining;
    _guardDeadline = _now().add(window);
    if (_useCancellableSafetyTimer) {
      _safetyTimer = Timer(window, () => _fireSafetyGuard(generation));
    } else {
      unawaited(_delay(window).then((_) => _fireSafetyGuard(generation)));
    }
  }

  /// Μετακινεί την προθεσμία μπροστά κατά το παράθυρο ενός βήματος.
  ///
  /// Έτσι το γενικό όριο σταματά να μετρά δουλειά που έχει δικό της χρόνο: ό,τι
  /// απέμενε πριν από το βήμα, απομένει και μετά.
  void _extendSafetyGuard(Duration extra) {
    final deadline = _guardDeadline;
    if (deadline == null) return;
    final left = deadline.difference(_now());
    _armSafetyGuard((left.isNegative ? Duration.zero : left) + extra);
  }

  void _cancelSafetyGuard() {
    _guardGeneration++;
    _safetyTimer?.cancel();
    _safetyTimer = null;
    _guardDeadline = null;
  }

  void _fireSafetyGuard(int generation) {
    if (generation != _guardGeneration) return;
    if (_stepsFinished) return;
    final trigger = _timeoutTrigger;
    if (trigger == null || trigger.isCompleted) return;
    _timedOut = true;
    trigger.complete();
  }

  void _emit(ShutdownStepEvent event) {
    if (!_eventsController.isClosed) {
      _eventsController.add(event);
    }
  }

  Future<void> _callTerminate() async {
    if (_terminateCalled) return;
    _terminateCalled = true;
    await _runGuaranteedSteps();
    await _runBeforeTerminate();
    await _terminate();
  }

  /// Ό,τι δεν πρόλαβε η ουρά και δεν επιτρέπεται να χαθεί.
  ///
  /// Σφιχτό όριο, γιατί εδώ έχουμε ήδη αποφασίσει να πεθάνουμε: ένα βήμα που
  /// κρεμάει δεν παίρνει δεύτερη παράταση. Το βήμα είναι ακίνδυνο αν τρέξει
  /// δεύτερη φορά — σβήνει ένα αρχείο που μπορεί να μην υπάρχει πια.
  Future<void> _runGuaranteedSteps() async {
    if (_finishedSteps.contains(closeCrashLogStep)) return;
    try {
      await _awaitWithin(
        _closeCrashLog(),
        beforeTerminateTimeout,
        stepLabels[closeCrashLogStep],
      );
    } catch (_) {}
  }

  /// Ο τερματισμός δεν αναβάλλεται για κανέναν λόγο.
  ///
  /// Το όριο χρόνου φυλάει τα ασύγχρονα μέρη (μετονομασία, σάρωση φακέλου).
  /// **Δεν** μπορεί να διακόψει σύγχρονη εγγραφή σε παγωμένο δίκτυο — αλλά
  /// εκεί το κλείσιμο έχει ήδη κολλήσει πολύ νωρίτερα, στα ίδια τα βήματα.
  Future<void> _runBeforeTerminate() async {
    final hook = beforeTerminate;
    if (hook == null) return;
    try {
      await hook().timeout(beforeTerminateTimeout);
    } catch (_) {}
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

  /// Το ίχνος «είμαι εδώ» χάνει τον κάτοχό του όσο η σύνδεση ζει ακόμη.
  ///
  /// Πριν από το checkpoint και το αντίγραφο εξόδου επίτηδες: έτσι η
  /// παράδοση προλαβαίνει να μπει και στο αντίγραφο, αντί να γραφτεί σε βάση
  /// που ετοιμάζεται να κλείσει.
  static Future<void> _defaultReleasePresence() async {
    await OperatorPresenceHeartbeat.instance.releaseAndStop();
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
