import 'dart:async';

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'shutdown_coordinator.dart';

/// Χειριστής κλεισίματος που δανείζει το UI όσο ζει (με οθόνη προόδου).
typedef WindowCloseUiHandler = void Function();

/// Κάτοχος του `preventClose` σε επίπεδο **διεργασίας**.
///
/// Το `preventClose` λέει στα Windows «μην κλείσεις μόνος σου, θα το χειριστώ
/// εγώ». Όσο είναι οπλισμένο πρέπει να υπάρχει ΠΑΝΤΑ ενεργός χειριστής — αλλιώς
/// το X και το Alt+F4 στέλνουν σήματα που δεν απαντά κανείς και το παράθυρο
/// παγιδεύεται.
///
/// Παλαιότερα το `preventClose` το όπλιζε το `AppShortcuts` και ο μοναδικός
/// χειριστής ζούσε μέσα του. Κάθε οθόνη που αντικαθιστούσε το κέλυφος (σφάλμα
/// βάσης, φόρτωση, εκκρεμής επαναφορά, μοιραίο σφάλμα) έμενε με οπλισμένο μπλόκο
/// και κανέναν χειριστή. Εδώ η ιδιοκτησία περνά στη διεργασία: το UI απλώς
/// **δανείζει** τον πλούσιο χειριστή του όσο υπάρχει.
class AppCloseController with WindowListener {
  AppCloseController({Future<void> Function()? runShutdown})
    : _runShutdown = runShutdown ?? _defaultRunShutdown;

  final Future<void> Function() _runShutdown;

  WindowCloseUiHandler? _uiHandler;
  bool _installed = false;
  bool _closing = false;

  /// True όσο κάποια οθόνη έχει δανείσει χειριστή κλεισίματος.
  bool get hasUiHandler => _uiHandler != null;

  bool get isInstalled => _installed;

  /// Εγκατάσταση μία φορά στην εκκίνηση: αναλαμβάνει το `preventClose` για όλη
  /// τη ζωή της διεργασίας.
  Future<void> install() async {
    if (_installed) return;
    _installed = true;
    try {
      windowManager.addListener(this);
      await windowManager.setPreventClose(true);
    } on MissingPluginException catch (_) {
      // Περιβάλλον χωρίς plugin (τεστ): το παράθυρο κλείνει με τη φυσική οδό.
    }
  }

  /// Το UI δανείζει τον χειριστή του (οθόνη προόδου, ιχνηλάτηση κ.λπ.).
  void registerUiHandler(WindowCloseUiHandler handler) {
    _uiHandler = handler;
  }

  /// Αποσύρεται μόνο ο ίδιος χειριστής — ποτέ ο αντικαταστάτης του.
  void unregisterUiHandler(WindowCloseUiHandler handler) {
    if (identical(_uiHandler, handler)) _uiHandler = null;
  }

  @override
  void onWindowClose() {
    handleCloseRequest();
  }

  /// Απαντά στο αίτημα κλεισίματος — με δανεισμένο χειριστή αν υπάρχει,
  /// αλλιώς με το ίδιο graceful κλείσιμο χωρίς οθόνη προόδου.
  void handleCloseRequest() {
    if (_closing) return;
    _closing = true;

    final handler = _uiHandler;
    if (handler != null) {
      handler();
      return;
    }
    unawaited(_runShutdown());
  }

  /// Μόνο για τεστ: επαναφορά καθαρής κατάστασης.
  void resetForTesting() {
    _uiHandler = null;
    _installed = false;
    _closing = false;
  }
}

Future<void> _defaultRunShutdown() => ShutdownCoordinator().run();

/// Καθολικό στιγμιότυπο της διεργασίας.
final AppCloseController appCloseController = AppCloseController();
