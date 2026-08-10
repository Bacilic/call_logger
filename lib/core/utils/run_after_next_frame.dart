import 'dart:async';

import 'package:flutter/scheduler.dart';

/// Εκτελεί το [action] μετά το επόμενο frame και επιστρέφει future που
/// ολοκληρώνεται όταν αυτό γίνει.
///
/// **Ζητά ρητά το frame.** Το `addPostFrameCallback` από μόνο του ΔΕΝ
/// προγραμματίζει frame: όταν ο καλών είναι ροή παρασκηνίου (χρονομετρητής,
/// αναβαλλόμενη ενέργεια) και η εφαρμογή είναι αδρανής, frame δεν έρχεται ποτέ
/// — και όποιος περιμένει το future κρέμεται για πάντα. Από widget/build
/// πλαίσιο το λάθος λανθάνει, γιατί frame υπάρχει έτσι κι αλλιώς.
///
/// Χρησιμοποιείται για ακυρώσεις providers που πρέπει να πέσουν **εκτός** φάσης
/// build (αλλιώς «locked widget tree» / «setState during build»).
Future<void> runAfterNextFrame(void Function() action) {
  final completer = Completer<void>();
  SchedulerBinding.instance.addPostFrameCallback((_) {
    try {
      action();
    } finally {
      if (!completer.isCompleted) completer.complete();
    }
  });
  SchedulerBinding.instance.ensureVisualUpdate();
  return completer.future;
}

/// Εκτελεί το [action] **τώρα** όταν είναι ασφαλές, αλλιώς μετά το τρέχον frame.
///
/// Το «ασφαλές» είναι ένα και μόνο ερώτημα: τρέχει αυτή τη στιγμή φάση
/// χτισίματος; Αν ναι, κάθε `setState` / `invalidate` / γραφή σε controller που
/// έχει ακροατές πετάει «setState() called during build» — και η εφαρμογή
/// κατεβαίνει στην οθόνη σφάλματος. Ο έλεγχος γράφεται **εδώ μία φορά**, ώστε
/// κανένας καλών να μη χρειάζεται να τον θυμάται.
///
/// Προτιμάται από το σκέτο [runAfterNextFrame] όταν ο καλών μπορεί να βρίσκεται
/// είτε μέσα είτε έξω από build: εκτός φάσης δεν χάνεται frame.
void runNowOrAfterFrame(void Function() action) {
  final phase = SchedulerBinding.instance.schedulerPhase;
  final safeNow =
      phase == SchedulerPhase.idle || phase == SchedulerPhase.postFrameCallbacks;
  if (safeNow) {
    action();
    return;
  }
  unawaited(runAfterNextFrame(action));
}
