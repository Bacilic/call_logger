import 'package:flutter/material.dart';

import '../../../core/widgets/stale_write_conflict_dialog.dart';
import '../services/operator_save_conflict.dart';

/// Η απόφαση του διαχειριστή μπροστά σε διένεξη καρτέλας χρήστη.
enum OperatorConflictChoice {
  /// Ακύρωση — η καρτέλα μένει όπως τη σώζει ο άλλος.
  keepTheirs,

  /// Η δική μου εικόνα γράφεται από πάνω, εν γνώσει μου.
  overwrite,
}

/// Ρωτά τι να γίνει όταν η καρτέλα χρήστη άλλαξε από άλλον διαχειριστή.
///
/// Δεν αποφασίζει μόνος του: το «γράψε από πάνω» είναι θεμιτή επιλογή, αρκεί ο
/// άνθρωπος να βλέπει **τι** σβήνει πριν το διαλέξει. Επιστρέφει `null` όταν ο
/// διάλογος κλείσει χωρίς επιλογή — ισοδύναμο με ακύρωση, ώστε ένα κατά λάθος
/// Escape να μη σβήνει δικαιώματα.
Future<OperatorConflictChoice?> showOperatorConflictDialog(
  BuildContext context,
  OperatorSaveConflict conflict, {
  DateTime? now,
}) async {
  final overwrite = await showStaleWriteConflictDialog(
    context,
    headline: conflict.headline(now: now),
    warning: conflict.overwriteWarning,
    changedFields: conflict.changedFields,
  );
  if (overwrite == null) return null;
  return overwrite
      ? OperatorConflictChoice.overwrite
      : OperatorConflictChoice.keepTheirs;
}
