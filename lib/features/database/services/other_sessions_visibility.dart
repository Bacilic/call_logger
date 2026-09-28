import '../../../core/database/database_helper.dart';
import '../../../core/services/crash_log_service.dart';

/// Μπορούμε να δούμε ποιοι άλλοι σταθμοί κρατούν τη βάση;
///
/// **Η άγνοια δεν είναι «κανείς».** Τα ίχνη παρουσίας ζουν στον φάκελο `logs`
/// δίπλα στη βάση. Όταν εκείνος δεν απαντά, η λίστα βγαίνει κενή — και ένας
/// φρουρός που διαβάζει «κενή» ως «είσαι μόνος» αφήνει να περάσει ακριβώς η
/// ενέργεια που υπάρχει για να σταματήσει.
///
/// Επιστρέφει `false` μόνο όταν **καμία** από τις δύο πηγές δεν είναι
/// διαθέσιμη: ούτε η ανοιχτή βάση (που κρατά τα ίχνη σε πίνακα), ούτε ο
/// φάκελος των ιχνών.
bool canObserveOtherSessions() {
  if (DatabaseHelper.instance.openDatabaseOrNull != null) return true;
  final log = CrashLogService.instanceOrNull;
  return log != null && log.isDiskAvailable;
}
