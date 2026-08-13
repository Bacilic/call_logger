import 'dart:async';

/// Περιοδικός φρουρός: μαθαίνει νωρίς ότι το αρχείο βάσης αντικαταστάθηκε.
///
/// Ο φρουρός **δεν ξέρει** πώς ανιχνεύεται η αντικατάσταση ούτε τι γίνεται μετά
/// — παίρνει και τα δύο από έξω. Έτσι ελέγχεται χωρίς αρχεία, χωρίς βάση και
/// χωρίς δέντρο widget: του δίνεις μια ψεύτικη ανίχνευση και μετράς πότε
/// φώναξε.
///
/// Τρεις κανόνες που κρατούν την κοινόχρηστη λειτουργία ήσυχη:
///
/// 1. **Ποτέ δύο έλεγχοι μαζί.** Σε αργό δικτυακό φάκελο ένας έλεγχος μπορεί να
///    διαρκέσει περισσότερο από το διάστημα· ο επόμενος παραλείπεται αντί να
///    στοιβαχτεί.
/// 2. **Φωνάζει μία φορά.** Μετά την ανίχνευση ο φρουρός σταματά· η επανεκκίνηση
///    ανήκει σε όποιον χειρίστηκε το περιστατικό.
/// 3. **Η αποτυχία είναι σιωπή.** Ό,τι πετάξει η ανίχνευση αγνοείται — ένας
///    φρουρός που κρασάρει την εφαρμογή είναι χειρότερος από κανέναν φρουρό.
class DatabaseReplacementWatchdog {
  DatabaseReplacementWatchdog({
    required this.detect,
    required this.onDetected,
    this.interval = const Duration(seconds: 60),
  });

  /// Απαντά «αντικαταστάθηκε το αρχείο;». Οφείλει να είναι fail-open: σε
  /// άγνοια επιστρέφει `false`.
  final Future<bool> Function() detect;

  /// Καλείται ακριβώς μία φορά, όταν η ανίχνευση επιβεβαιωθεί.
  final Future<void> Function() onDetected;

  /// Πόσο συχνά ρωτάει. Αραιά επίτηδες: το περιστατικό είναι σπάνιο και η
  /// ερώτηση ταξιδεύει στο δίκτυο.
  final Duration interval;

  Timer? _timer;
  bool _busy = false;
  bool _fired = false;

  bool get isRunning => _timer != null;

  /// True όταν η ανίχνευση έχει ήδη χτυπήσει σε αυτή τη συνεδρία.
  bool get hasFired => _fired;

  void start() {
    if (_timer != null || _fired) return;
    _timer = Timer.periodic(interval, (_) => unawaited(checkNow()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Ένας έλεγχος τώρα, εκτός σειράς.
  Future<void> checkNow() async {
    if (_busy || _fired) return;
    _busy = true;
    try {
      final replaced = await detect();
      if (!replaced || _fired) return;
      _fired = true;
      stop();
      await onDetected();
    } catch (_) {
      // Σιωπή: η άγνοια δεν είναι εύρημα.
    } finally {
      _busy = false;
    }
  }

  void dispose() => stop();
}
