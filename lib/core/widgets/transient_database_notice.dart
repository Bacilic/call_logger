import 'package:flutter/material.dart';

/// Ο «ταχυδρόμος» μηνυμάτων της εφαρμογής, δεμένος στο `MaterialApp`.
///
/// Υπάρχει για μηνύματα που γεννιούνται **έξω** από οθόνη — π.χ. στον
/// καθολικό χειριστή σφαλμάτων — όπου δεν υπάρχει `BuildContext` να ρωτήσει.
final GlobalKey<ScaffoldMessengerState> appScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Το μήνυμα όταν μια ενέργεια χάθηκε επειδή η βάση δεν απάντησε για λίγο.
///
/// Δεν υπόσχεται ότι «θα γίνει»: μια αποθήκευση που δεν πρόλαβε, δεν έγινε.
/// Λέει στον χειριστή να κοιτάξει και να ξαναδοκιμάσει.
const String kTransientDatabaseFailureMessage =
    'Η βάση δεδομένων δεν απάντησε για λίγο — μια ενέργεια ίσως δεν '
    'ολοκληρώθηκε. Αν κάτι λείπει, ξαναδοκίμασε.';

/// Πόσο σωπαίνει το μήνυμα αφού εμφανιστεί.
///
/// Μία διακοπή δικτύου γεννά **πολλά** σφάλματα μαζί (23/09/2026: οκτώ μέσα σε
/// τρία λεπτά). Ένα μήνυμα ανά διακοπή πληροφορεί· οκτώ στη σειρά είναι θόρυβος
/// που κρύβει τη δουλειά.
const Duration kTransientDatabaseNoticeQuietPeriod = Duration(seconds: 60);

/// Αποφασίζει **αν** ένα νέο σφάλμα αξίζει μήνυμα — χωρίς οθόνη, ελέγξιμο.
class TransientDatabaseNoticeThrottle {
  TransientDatabaseNoticeThrottle({
    this.quietPeriod = kTransientDatabaseNoticeQuietPeriod,
  });

  final Duration quietPeriod;
  DateTime? _lastShownAt;

  /// `true` όταν πρέπει να εμφανιστεί μήνυμα τώρα (και το καταγράφει).
  bool shouldShow(DateTime now) {
    final last = _lastShownAt;
    if (last != null && now.difference(last) < quietPeriod) return false;
    _lastShownAt = now;
    return true;
  }
}

final TransientDatabaseNoticeThrottle _throttle =
    TransientDatabaseNoticeThrottle();

/// Δείχνει το μικρό μήνυμα κάτω-κάτω — **αντί** για την πλήρη οθόνη σφάλματος.
///
/// Χωρίς κουμπί ενέργειας επίτηδες: ένα SnackBar με ενέργεια δεν κλείνει ποτέ
/// μόνο του.
void announceTransientDatabaseFailure() {
  if (!_throttle.shouldShow(DateTime.now())) return;
  final messenger = appScaffoldMessengerKey.currentState;
  if (messenger == null) return;
  messenger.showSnackBar(
    const SnackBar(
      content: Text(kTransientDatabaseFailureMessage),
      duration: Duration(seconds: 8),
    ),
  );
}
