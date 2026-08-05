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
