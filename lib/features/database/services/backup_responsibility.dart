import '../../../core/database/database_helper.dart';
import '../../../core/database/operator_presence_repository.dart';
import '../../../core/database/operator_repository.dart';
import '../../../core/models/operator.dart';

/// «Είμαι ο πρώτος διαθέσιμος;» — η προτεραιότητα του εφεδρικού μηχανισμού
/// (Φάση 4): ο **παρών** διαχειριστής προηγείται· ο εφεδρικός (χρήστης με
/// ρητό τικ πλήρους αντιγράφου) ενεργεί μόνο όταν κανένας διαχειριστής δεν
/// είναι συνδεδεμένος.
///
/// Η «παρουσία» είναι ίχνος, όχι βεβαιότητα (βλ. `OperatorPresence`): μετά
/// από κρασάρισμα του διαχειριστή, ο εφεδρικός αναλαμβάνει μόλις παλιώσει το
/// ίχνος (~3΄). Δύο εφεδρικοί μεταξύ τους δεν έχουν σειρά — τους χωρίζει η
/// ατομική δέσμευση της κοινής ρύθμισης, όχι αυτό το ερώτημα.
abstract final class BackupResponsibility {
  /// True όταν ο [current] οφείλει να παραχωρήσει το αντίγραφο σε παρόντα
  /// διαχειριστή. Ο διαχειριστής δεν παραχωρεί ποτέ· χωρίς ταυτότητα, όλα
  /// όπως πριν από τα προφίλ (κανένας δισταγμός).
  static Future<bool> shouldDeferToPresentAdmin({
    required Operator? current,
    required DateTime now,
  }) async {
    if (current == null) return false;
    if (current.isAdmin) return false;

    final db = await DatabaseHelper.instance.database;
    final presences = await OperatorPresenceRepository(db).getAll();
    final onlineIds = <int>{
      for (final p in presences)
        if (p.isOnlineAt(now)) p.operatorId,
    };
    if (onlineIds.isEmpty) return false;

    final operators = await OperatorRepository(db).getAll();
    return operators.any(
      (op) => op.isAdmin && op.id != null && onlineIds.contains(op.id),
    );
  }
}
