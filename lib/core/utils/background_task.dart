import 'dart:async';

import '../database/database_helper.dart';
import '../services/crash_log_service.dart';

/// Τρέχει εργασία παρασκηνίου — φόρτωση ρύθμισης, ανάγνωση που δεν ζήτησε ο
/// χρήστης — **χωρίς ποτέ να ρίξει την εφαρμογή**.
///
/// **Το πρόβλημα που λύνει:** οι φορτώσεις ρυθμίσεων ξεκινούσαν «στον αέρα»
/// (`Future<void>(_hydrateFromDb)`), χωρίς κανέναν να περιμένει το αποτέλεσμα.
/// Όταν η βάση δεν απαντούσε για λίγο (στιγμιαία διακοπή δικτύου, κλείδωμα από
/// άλλον σταθμό), το σφάλμα δεν είχε πού να πάει παρά στην κορυφή — και η
/// εφαρμογή έδειχνε ολόκληρη την οθόνη «Σφάλμα εφαρμογής» για κάτι που ο
/// χειριστής ούτε ζήτησε ούτε χρειαζόταν εκείνη τη στιγμή (23/09/2026, μία
/// ρύθμιση του Lansweeper μέσα σε διακοπή τριών λεπτών).
///
/// **Το συμβόλαιο:** ό,τι τρέχει μόνο του στο παρασκήνιο δεν ρίχνει την
/// εφαρμογή· η αποτυχία του γράφεται στο ημερολόγιο ως **μη κρίσιμη** (δες
/// [logBackgroundFailure]), και η οθόνη κρατά την τιμή που είχε.
///
/// Ο χρόνος εκκίνησης της εργασίας δεν αλλάζει: ο καλών τη δημιουργεί όπως
/// πριν (`Future<void>(f)` για «μετά το τρέχον χτίσιμο», `f()` για «τώρα»)· εδώ
/// απλώς δένεται το δίχτυ.
void runBackgroundTask(Future<void> task) {
  final connection = currentConnectionGeneration();
  unawaited(
    task.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) =>
          logBackgroundFailure(error, stack, startedOnConnection: connection),
    ),
  );
}

/// Ποια σύνδεση με τη βάση ισχύει τώρα — αλλάζει σε **κάθε** κλείσιμο.
int currentConnectionGeneration() =>
    DatabaseHelper.instance.connectionGeneration;

/// Γράφει την αποτυχία μιας εργασίας παρασκηνίου ως **μη κρίσιμη** — εκτός
/// αν στο μεταξύ έκλεισε η σύνδεση στην οποία ξεκίνησε.
///
/// **Γιατί η εξαίρεση.** Τη σύνδεση την κλείνουν το κλείσιμο της εφαρμογής, η
/// αλλαγή βάσης, η επαναφορά αντιγράφου, το «ξεκίνα από την αρχή». Μια
/// εργασία που ήταν στη μέση εκείνη τη στιγμή δεν **απέτυχε** — διακόπηκε, και
/// η δουλειά της ακυρώνεται ούτως ή άλλως. Γραμμένη ως σφάλμα θόλωνε κάθε
/// εξαγωγή διαγνωστικών (05/10/2026: `database_closed` στο κλείσιμο του
/// PICINIO, από ανανέωση της κοινής βάσης που την πρόλαβε το κλείσιμο).
///
/// [startedOnConnection]: η [currentConnectionGeneration] τη στιγμή που
/// ξεκίνησε η εργασία.
void logBackgroundFailure(
  Object error,
  StackTrace stack, {
  required int startedOnConnection,
}) {
  if (currentConnectionGeneration() != startedOnConnection) return;
  CrashLogService.instanceOrNull?.logError(error, stack, fatal: false);
}
