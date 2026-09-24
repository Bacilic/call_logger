import 'package:sqflite_common/sqlite_api.dart';

import '../database/database_helper.dart';
import '../database/operator_repository.dart';
import '../models/operator.dart';
import 'crash_log_service.dart';
import 'current_operator.dart';

/// Άλλαξε κάτι που **φαίνεται στην οθόνη ή κρίνει δικαίωμα**;
///
/// Η σύγκριση είναι ο πυρήνας της ανανέωσης, όχι βελτιστοποίησή της. Το
/// [Operator] δεν έχει ισότητα: κάθε ανάγνωση από τη βάση δίνει καινούργιο
/// αντικείμενο, οπότε μια ανανέωση χωρίς σύγκριση θα ειδοποιούσε **κάθε φορά**
/// που τρέχει ο κύκλος φρεσκάδας — και θα έσερνε μαζί της ακύρωση καθολικών
/// caches κάθε μισό λεπτό, σε δικτυακή βάση.
///
/// Το `createdAt` μένει απ' έξω επίτηδες: δεν αλλάζει ποτέ, και μια διαφορά
/// του θα σήμαινε ότι μιλάμε για άλλο προφίλ — αυτό το πιάνει το `id`.
bool operatorVisibleStateChanged(Operator before, Operator after) {
  if (before.id != after.id) return true;
  if (before.displayName != after.displayName) return true;
  if (before.windowsAccount != after.windowsAccount) return true;
  if (before.isAdmin != after.isAdmin) return true;
  if (before.isActive != after.isActive) return true;
  if (before.avatarKey != after.avatarKey) return true;
  return !_sameOverrides(before.permissionOverrides, after.permissionOverrides);
}

bool _sameOverrides(Map<String, bool> a, Map<String, bool> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

/// Ξαναδιαβάζει το προφίλ του συνδεδεμένου χρήστη από την κοινόχρηστη βάση.
///
/// **Γιατί υπάρχει:** τα δικαιώματα ζουν πάνω σε στιγμιότυπο που γέμισε η
/// αναγνώριση ταυτότητας. Όταν ο διαχειριστής άλλαζε κάτι από άλλον σταθμό, ο
/// συνάδελφος δεν το μάθαινε ποτέ — ούτε όταν του **αφαιρούσε** πρόσβαση. Η
/// προστασία υπήρχε και δεν ίσχυε.
///
/// Επιστρέφει `true` **μόνο** όταν άλλαξε κάτι πραγματικό· τότε μόνο μιλά ο
/// [CurrentOperator], και τότε μόνο ξαναχτίζεται οτιδήποτε.
///
/// **Τρεις σιωπές, και οι τρεις σκόπιμες:**
/// 1. **Κανείς δεν είναι συνδεδεμένος** — δεν υπάρχει τι να ανανεωθεί.
/// 2. **Το προφίλ δεν έχει `id`** — δεν γράφτηκε ποτέ στη βάση.
/// 3. **Το προφίλ δεν βρέθηκε.** Διαγράφηκε, ή η βάση δεν απάντησε. Ό,τι κι αν
///    ισχύει, η ταυτότητα **μένει ως έχει**: ένα `activate(null)` θα έκανε τον
///    χρήστη ανώνυμο, και τότε τα δικαιώματα επιτρέπουν τα πάντα ενώ το
///    Ιστορικό αρχίζει να σφραγίζεται με παύλα. Η αποτυχία της ανάγνωσης δεν
///    επιτρέπεται να δώσει περισσότερα δικαιώματα απ' όσα υπήρχαν.
Future<bool> refreshCurrentOperatorProfile(DatabaseExecutor db) async {
  final active = CurrentOperator.active;
  final id = active?.id;
  if (active == null || id == null) return false;

  final fresh = await OperatorRepository(db).findById(id);
  if (fresh == null) return false;

  if (!operatorVisibleStateChanged(active, fresh)) return false;

  CurrentOperator.refreshActive(fresh);
  return true;
}

/// Η ίδια ανανέωση, **χωρίς ποτέ να σταματήσει τον κύκλο φρεσκάδας**.
///
/// Τρέχει πρώτη μέσα στον κύκλο, οπότε μια αποτυχία της θα έκοβε τη φρεσκάδα
/// όλων των υπολοίπων — τμημάτων, καταλόγου, κλήσεων. Η ταυτότητα είναι ένα
/// από τα πολλά που ανανεώνονται· δεν είναι φύλακας κανενός από αυτά.
///
/// Το σφάλμα δεν χάνεται: γράφεται στο ημερολόγιο ως **μη μοιραίο**.
Future<void> refreshCurrentOperatorProfileSafely() async {
  try {
    final db = await DatabaseHelper.instance.database;
    await refreshCurrentOperatorProfile(db);
  } catch (error, stack) {
    CrashLogService.instanceOrNull?.logError(error, stack, fatal: false);
  }
}
