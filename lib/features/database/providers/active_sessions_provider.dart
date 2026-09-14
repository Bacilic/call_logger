import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/operator_presence_repository.dart';
import '../../../core/services/operator_presence_heartbeat.dart';
import '../services/active_sessions.dart';

/// Ποιες ανοιχτές εφαρμογές κρατούν τη βάση αυτή τη στιγμή.
///
/// **Συνάρτηση, όχι μόνο provider.** Ο φρουρός της συντήρησης τη χρειάζεται
/// μέσα σε διάλογο που μπορεί να ζήσει περισσότερο από την οθόνη που τον
/// άνοιξε· ένας `autoDispose` provider που διαβάζεται εκεί θα πέθαινε στο πρώτο
/// `await`. Η κάρτα, που είναι ζωντανό widget, χρησιμοποιεί τον provider από
/// κάτω — ίδια λογική, μία φορά γραμμένη.
///
/// **Διαβάζει μόνο βάση που είναι ήδη ανοιχτή — ποτέ δεν ανοίγει σύνδεση.**
/// Ο φρουρός τρέχει και σε οθόνες όπου η βάση έχει αποτύχει να ανοίξει (π.χ.
/// ανάκαμψη σχήματος στην εκκίνηση)· ένα άνοιγμα από εδώ θα άλλαζε κατάσταση
/// ακριβώς εκεί που ο χρήστης προσπαθεί να τη διορθώσει. Μέσα σε `testWidgets`
/// το άνοιγμα δεν ολοκληρώνεται ποτέ και η οθόνη θα κρεμούσε.
///
/// Επιστρέφει κενή λίστα όταν η βάση δεν απαντά: η άγνοια πέφτει στην πλευρά
/// που δεν ισχυρίζεται τίποτα, και μια αποτυχία δικτύου δεν επιτρέπεται να
/// μπλοκάρει τη συντήρηση με προειδοποίηση που δεν ξέρει τι λέει.
Future<List<ActiveSession>> loadActiveSessions({DateTime? now}) async {
  try {
    final db = DatabaseHelper.instance.openDatabaseOrNull;
    if (db == null) return const [];
    final marks = await OperatorPresenceRepository(db).getAllWithNames();
    return activeSessions(
      marks: marks,
      now: now ?? DateTime.now(),
      myInstance: OperatorPresenceHeartbeat.instanceId,
    );
  } catch (_) {
    return const [];
  }
}

/// Οι ανοιχτές συνεδρίες για την κάρτα στατιστικών.
///
/// `autoDispose` ώστε να ξαναρωτά όταν ξανανοίγει η οθόνη — η λίστα παλιώνει
/// μέσα σε λεπτά και μια μπαγιάτικη εικόνα εδώ είναι χειρότερη από καμία.
final activeSessionsProvider = FutureProvider.autoDispose<List<ActiveSession>>((
  ref,
) async {
  return loadActiveSessions();
});
