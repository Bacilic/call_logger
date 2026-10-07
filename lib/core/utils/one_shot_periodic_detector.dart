import 'dart:async';

/// Περιοδικός ανιχνευτής μιας φοράς: ρωτά ανά διάστημα «συνέβη;» και, μόλις η
/// απάντηση γίνει «ναι», φωνάζει μία φορά και σταματά.
///
/// Ο ανιχνευτής **δεν ξέρει** τι ανιχνεύει ούτε τι γίνεται μετά — παίρνει και
/// τα δύο από έξω. Έτσι ελέγχεται χωρίς αρχεία, χωρίς βάση και χωρίς δέντρο
/// widget: του δίνεις μια ψεύτικη ανίχνευση και μετράς πότε φώναξε.
///
/// Χρήσεις: ο φρουρός αντικατάστασης του αρχείου βάσης
/// (`databaseReplacementWatchdogProvider`) και ο φρουρός επανόδου της
/// δικτυακής βάσης (`networkDatabaseReturnedProvider`).
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
class OneShotPeriodicDetector {
  OneShotPeriodicDetector({
    required this.detect,
    required this.onDetected,
    this.interval = const Duration(seconds: 60),
  });

  /// Απαντά «συνέβη;». Οφείλει να είναι fail-open: σε άγνοια επιστρέφει
  /// `false`.
  final Future<bool> Function() detect;

  /// Καλείται ακριβώς μία φορά, όταν η ανίχνευση επιβεβαιωθεί.
  final Future<void> Function() onDetected;

  /// Πόσο συχνά ρωτάει. Αραιά επίτηδες: τα περιστατικά είναι σπάνια και η
  /// ερώτηση συνήθως ταξιδεύει στο δίκτυο.
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
      final happened = await detect();
      if (!happened || _fired) return;
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
