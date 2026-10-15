import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'shutdown_coordinator.dart';

/// Χειριστής κλεισίματος που δανείζει το UI όσο ζει (με οθόνη προόδου).
typedef WindowCloseUiHandler = void Function();

/// Πού βρίσκεται το κλείσιμο της εφαρμογής — ό,τι χρειάζεται το στρώμα πάνω
/// από όλη την εφαρμογή.
@immutable
class AppClosingState {
  const AppClosingState({
    this.isClosing = false,
    this.coordinator,
    this.progressRevealed = false,
  });

  /// Αληθές από τη στιγμή που ξεκινά το κλείσιμο ως το τέλος της διεργασίας.
  final bool isClosing;

  /// Τα βήματα του κλεισίματος, όταν υπάρχει οθόνη προόδου.
  final ShutdownCoordinator? coordinator;

  /// Πέρασε το κατώφλι του μισού δευτερολέπτου: η οθόνη προόδου φαίνεται.
  final bool progressRevealed;

  AppClosingState copyWith({
    bool? isClosing,
    ShutdownCoordinator? coordinator,
    bool? progressRevealed,
  }) => AppClosingState(
    isClosing: isClosing ?? this.isClosing,
    coordinator: coordinator ?? this.coordinator,
    progressRevealed: progressRevealed ?? this.progressRevealed,
  );
}

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
  bool _asking = false;

  /// Η ερώτηση πριν το κλείσιμο από τον χρήστη: `true` = να προχωρήσει.
  ///
  /// Τη δίνει η εφαρμογή στην εκκίνηση (ανοιχτός διάλογος ⇒ ερώτηση). Ισχύει
  /// **μόνο** για το «Χ»/Alt+F4: ένα κλείσιμο που έχει ήδη αποφασιστεί — το
  /// αίτημα συναδέλφου που δέχτηκες — δεν ξαναρωτά.
  Future<bool> Function()? confirmUserClose;

  /// Η κατάσταση του κλεισίματος. Την ακούει το στρώμα πάνω από όλη την
  /// εφαρμογή, που από τη στιγμή που ξεκινά το κλείσιμο δεν αφήνει κανένα
  /// κλικ ή πλήκτρο να φτάσει σε οθόνη ή διάλογο.
  ValueListenable<AppClosingState> get closingState => _state;
  final ValueNotifier<AppClosingState> _state = ValueNotifier<AppClosingState>(
    const AppClosingState(),
  );

  /// Ξεκίνησε το κλείσιμο;
  bool get isClosing => _state.value.isClosing;

  /// Το κλείσιμο ξεκίνησε με αυτόν τον συντονιστή — η οθόνη προόδου στήνεται
  /// αόρατη, ώστε να μη χάσει κανένα γεγονός.
  void publishProgress(ShutdownCoordinator coordinator) {
    _state.value = _state.value.copyWith(coordinator: coordinator);
  }

  /// Πέρασε το κατώφλι: η οθόνη προόδου φαίνεται.
  void revealProgress() {
    _state.value = _state.value.copyWith(progressRevealed: true);
  }

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
    unawaited(handleUserCloseRequest());
  }

  /// Το «Χ», το Alt+F4, το κλείσιμο από τη γραμμή εργασιών: ρωτά πρώτα, αν
  /// υπάρχει ερώτηση. Ένα δεύτερο «Χ» όσο φαίνεται η ερώτηση αγνοείται.
  ///
  /// Αποτυχία της ερώτησης δεν κρατά ποτέ τον χρήστη μέσα: το κλείσιμο
  /// προχωρά.
  Future<void> handleUserCloseRequest() async {
    if (_closing || _asking) return;
    final confirm = confirmUserClose;
    if (confirm != null) {
      _asking = true;
      var proceed = true;
      try {
        proceed = await confirm();
      } catch (_) {
        proceed = true;
      } finally {
        _asking = false;
      }
      if (!proceed) return;
    }
    handleCloseRequest();
  }

  /// Απαντά στο αίτημα κλεισίματος — με δανεισμένο χειριστή αν υπάρχει,
  /// αλλιώς με το ίδιο graceful κλείσιμο χωρίς οθόνη προόδου.
  ///
  /// Χωρίς ερώτηση: το καλεί όποιος έχει ήδη αποφασίσει (και το «Χ», μετά
  /// την ερώτησή του).
  void handleCloseRequest() {
    if (_closing) return;
    _closing = true;
    _state.value = _state.value.copyWith(isClosing: true);

    final handler = _uiHandler;
    if (handler != null) {
      handler();
      return;
    }
    unawaited(_runShutdown());
  }

  /// Αφήνει όσους ακούν την κατάσταση κλεισίματος. Στην εφαρμογή ο ελεγκτής
  /// ζει όσο η διεργασία· το χρειάζονται τα τεστ που στήνουν δικό τους.
  @visibleForTesting
  void dispose() {
    _state.dispose();
  }

  /// Μόνο για τεστ: επαναφορά καθαρής κατάστασης.
  void resetForTesting() {
    _uiHandler = null;
    _installed = false;
    _closing = false;
    _asking = false;
    confirmUserClose = null;
    _state.value = const AppClosingState();
  }
}

Future<void> _defaultRunShutdown() => ShutdownCoordinator().run();

/// Καθολικό στιγμιότυπο της διεργασίας.
final AppCloseController appCloseController = AppCloseController();
