import 'package:sqflite_common/sqlite_api.dart';

import '../../../core/database/operator_presence_repository.dart';
import '../../../core/models/operator_presence.dart';
import '../../../core/services/crash_log_service.dart';

/// Τα ίχνη σύνδεσης, μαζί με το αν η ανάγνωση **πέτυχε**.
class PresenceRead {
  const PresenceRead({required this.marks, required this.unavailable});

  static const PresenceRead none = PresenceRead(
    marks: <OperatorPresence>[],
    unavailable: false,
  );

  final List<OperatorPresence> marks;

  /// Η ανάγνωση απέτυχε — δεν ξέρουμε ποιος είναι συνδεδεμένος.
  ///
  /// Διαφορετικό από «κανείς δεν είναι συνδεδεμένος»: εκεί η οθόνη μπορεί να
  /// μιλήσει, εδώ οφείλει να σωπάσει.
  final bool unavailable;
}

/// Διαβάζει τα ίχνη σύνδεσης με τη **διάκριση που λείπει** από ένα σκέτο catch.
///
/// **Ένα σπίτι για δύο οθόνες.** Η λίστα «Χρήστες» και ο επιλογέας ταυτότητας
/// έκαναν την ίδια ανάγνωση με το ίδιο αντιγραμμένο `catch (_)`. Ο κανόνας
/// έπρεπε να αλλάξει σε δύο σημεία για να ισχύσει — δηλαδή θα άλλαζε σε ένα.
///
/// Δύο πολύ διαφορετικές αποτυχίες φορούσαν το ίδιο πρόσωπο:
/// 1. **Λείπει ο πίνακας** — βάση από παλαιότερη έκδοση που δεν αναβαθμίστηκε
///    ακόμη. Αναμενόμενο και σιωπηλό· η οθόνη δείχνει κανονικά τα προφίλ.
/// 2. **Η ανάγνωση απέτυχε** — π.χ. ο κοινόχρηστος φάκελος έπεσε στη μέση.
///    Αυτό είναι συμβάν: γράφεται στο ημερολόγιο, και η οθόνη δεν επιτρέπεται
///    να το μεταφράσει σε «δεν έχει συνδεθεί ποτέ».
Future<PresenceRead> readOperatorPresence(DatabaseExecutor db) async {
  try {
    return PresenceRead(
      marks: await OperatorPresenceRepository(db).getAll(),
      unavailable: false,
    );
  } catch (e, stack) {
    if (_isMissingPresenceTable(e)) return PresenceRead.none;
    CrashLogService.instanceOrNull?.logError(e, stack, fatal: false);
    return const PresenceRead(marks: <OperatorPresence>[], unavailable: true);
  }
}

bool _isMissingPresenceTable(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('no such table') &&
      text.contains(OperatorPresenceRepository.tableName);
}
