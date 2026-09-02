import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/lansweeper_submit_progress.dart';

/// Πού βρίσκεται η τρέχουσα αποστολή ticket — και πόση ώρα τρέχει.
///
/// Χωριστά από τον [lansweeperSyncProvider] που εκτελεί την αποστολή: εκείνος
/// απαντά «τελείωσε ή όχι», αυτός «τι κάνεις τώρα». Η οθόνη χρειάζεται και τα
/// δύο, αλλά ξαναχτίζεται πολύ πιο συχνά για το δεύτερο.
///
/// **Το ρολόι είναι ΕΝΑ και ζει εδώ.** Η οθόνη δεν κρατά δικό της χρονόμετρο —
/// απλώς ρωτά κάθε λίγο τι ώρα δείχνει αυτό. Δύο ρολόγια για το ίδιο γεγονός
/// αποκλίνουν, και ο χρήστης βλέπει δύο διαφορετικούς αριθμούς για τον ίδιο
/// χρόνο.
class LansweeperSubmitProgressNotifier
    extends Notifier<LansweeperSubmitProgress> {
  final Stopwatch _stopwatch = Stopwatch();

  @override
  LansweeperSubmitProgress build() => LansweeperSubmitProgress.idle;

  /// Ο χρόνος που τρέχει αυτή τη στιγμή, σε χιλιοστά.
  ///
  /// Όσο η αποστολή τρέχει, διαβάζεται από το ρολόι· όταν τελειώσει, από το
  /// σφραγισμένο σύνολο — έτσι ο αριθμός στην οθόνη δεν «παγώνει» σε άλλη τιμή
  /// από αυτήν που δείχνει η τελική γραμμή.
  int get elapsedMilliseconds {
    if (state.isRunning) return _stopwatch.elapsedMilliseconds;
    return state.totalMilliseconds ?? 0;
  }

  /// Ξεκινά νέα πορεία με τα προβλεπόμενα [stepKeys].
  ///
  /// Το [creatingTicket] αλλάζει μόνο την ετικέτα του βήματος του αιτήματος
  /// («δημιουργία» ή «ενημέρωση»).
  void begin(
    List<String> stepKeys, {
    bool creatingTicket = true,
    List<int> callIds = const <int>[],
  }) {
    _stopwatch
      ..reset()
      ..start();
    state = LansweeperSubmitProgress(
      steps: [
        for (final key in stepKeys)
          LansweeperSubmitStep(
            key: key,
            label: lansweeperSubmitStepLabel(key, creating: creatingTicket),
          ),
      ],
      outcome: LansweeperSubmitOutcome.running,
      callIds: callIds,
    );
  }

  /// Το βήμα [key] ξεκίνησε τώρα· ό,τι έτρεχε πριν θεωρείται ολοκληρωμένο.
  void stepStarted(String key) {
    if (!state.isRunning) return;
    state = state.startStep(key, _stopwatch.elapsedMilliseconds);
  }

  /// Κλείνει την πορεία και σφραγίζει τον συνολικό χρόνο.
  ///
  /// Η [summary] μένει μόνιμα στην οθόνη μέχρι την επόμενη αποστολή: ο χρήστης
  /// θέλει να βλέπει τι έγινε και πόσο κράτησε χωρίς να προλάβει μήνυμα που
  /// φεύγει σε τέσσερα δευτερόλεπτα.
  void finish({required bool success, String? summary}) {
    if (state.isIdle) return;
    _stopwatch.stop();
    state = state.finish(
      success: success,
      totalMilliseconds: _stopwatch.elapsedMilliseconds,
      summary: summary,
    );
  }

  /// Καθαρίζει την εικόνα — καλείται κάθε φορά που ανοίγει η Αναφορά, ώστε το
  /// αποτέλεσμα της χθεσινής αποστολής να μη σε υποδέχεται σήμερα.
  ///
  /// **Ποτέ πάνω σε αποστολή που τρέχει:** ο διάλογος μπορεί να κλείσει και να
  /// ξανανοίξει όσο στέλνει, και μια ένδειξη που μηδενίζεται εκεί θα έλεγε
  /// «τίποτα δεν γίνεται» ενώ γίνεται.
  void reset() {
    if (state.isRunning) return;
    _stopwatch
      ..stop()
      ..reset();
    state = LansweeperSubmitProgress.idle;
  }
}

final lansweeperSubmitProgressProvider =
    NotifierProvider<
      LansweeperSubmitProgressNotifier,
      LansweeperSubmitProgress
    >(LansweeperSubmitProgressNotifier.new);
