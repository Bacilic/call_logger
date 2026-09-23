import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/operator_presence_repository.dart';
import '../../../core/services/crash_log_service.dart';
import '../../../core/services/operator_presence_heartbeat.dart';
import '../../../core/services/session_liveness_mark.dart';
import '../../../core/services/station_name.dart';
import '../services/active_sessions.dart';

/// Ποιες ανοιχτές εφαρμογές κρατούν τη βάση αυτή τη στιγμή.
///
/// **Συνάρτηση, όχι μόνο provider.** Ο φρουρός της συντήρησης τη χρειάζεται
/// μέσα σε διάλογο που μπορεί να ζήσει περισσότερο από την οθόνη που τον
/// άνοιξε· ένας `autoDispose` provider που διαβάζεται εκεί θα πέθαινε στο πρώτο
/// `await`. Η κάρτα, που είναι ζωντανό widget, χρησιμοποιεί τον provider από
/// κάτω — ίδια λογική, μία φορά γραμμένη.
///
/// **Η απάντηση δεν εξαρτάται από το αν άνοιξε η βάση.** Δύο πηγές, με σειρά:
/// 1. **Η βάση**, όταν είναι ήδη ανοιχτή — η πλουσιότερη (ονόματα ανθρώπων,
///    ένα ίχνος ανά εφαρμογή).
/// 2. **Τα ίχνη «τρέχω τώρα»** στον φάκελο logs δίπλα στη βάση, όταν η βάση
///    δεν είναι ανοιχτή ή δεν απάντησε. Ο φρουρός ρωτά συχνότερα από όλα σε
///    οθόνες όπου η βάση **απέτυχε** να ανοίξει — π.χ. αναβάθμιση σχήματος
///    στην εκκίνηση, το πιο επικίνδυνο σημείο για τους συναδέλφους. Όσο
///    διάβαζε μόνο τη βάση, εκεί έβλεπε πάντα κενή λίστα και σώπαινε.
///
/// **Ποτέ δεν ανοίγει σύνδεση.** Ένα άνοιγμα από εδώ θα άλλαζε κατάσταση
/// ακριβώς εκεί που ο χρήστης προσπαθεί να τη διορθώσει, και μέσα σε
/// `testWidgets` δεν ολοκληρώνεται ποτέ. Τα ίχνη είναι απλά αρχεία.
///
/// Όταν ούτε τα ίχνη απαντούν (φάκελος που χάθηκε), κενή λίστα: η άγνοια
/// πέφτει στην πλευρά που δεν ισχυρίζεται τίποτα.
///
/// [logsDirectory]: ο φάκελος των ιχνών — προεπιλογή ο φάκελος του
/// ημερολογίου της εφαρμογής, που ανοίγει δίπλα στη βάση **πριν** από αυτήν.
Future<List<ActiveSession>> loadActiveSessions({
  DateTime? now,
  String? logsDirectory,
}) async {
  final at = now ?? DateTime.now();
  try {
    final db = DatabaseHelper.instance.openDatabaseOrNull;
    if (db != null) {
      final marks = await OperatorPresenceRepository(db).getAllWithNames();
      return activeSessions(
        marks: marks,
        now: at,
        myInstance: OperatorPresenceHeartbeat.instanceId,
      );
    }
  } catch (_) {
    // Η βάση δεν απάντησε — τα ίχνη μπορεί ακόμη να απαντούν.
  }
  return _activeSessionsFromLivenessMarks(
    now: at,
    logsDirectory: logsDirectory ?? _defaultLogsDirectory(),
  );
}

Future<List<ActiveSession>> _activeSessionsFromLivenessMarks({
  required DateTime now,
  required String? logsDirectory,
}) async {
  if (logsDirectory == null || logsDirectory.trim().isEmpty) return const [];
  return activeSessionsFromLivenessMarks(
    marks: await readSessionLivenessMarks(logsDirectory),
    now: now,
    myStation: StationName.current,
  );
}

/// Ο φάκελος του ημερολογίου — αν ο ίδιος έχει ήδη διαπιστώσει ότι ο δίσκος
/// δεν απαντά, δεν τον ξαναρωτάμε: ένας φάκελος δικτύου που χάθηκε κοστίζει
/// δευτερόλεπτα αναμονής για απάντηση που ξέρουμε ήδη.
String? _defaultLogsDirectory() {
  final log = CrashLogService.instanceOrNull;
  if (log == null || !log.isDiskAvailable) return null;
  return log.logsDirectory;
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
