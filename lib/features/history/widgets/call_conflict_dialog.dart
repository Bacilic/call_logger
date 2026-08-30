import 'package:flutter/material.dart';

import '../../../core/widgets/stale_write_conflict_dialog.dart';
import '../../calls/services/call_save_conflict.dart';

/// Η απόφαση του χρήστη μπροστά σε διένεξη κλήσης.
enum CallConflictChoice {
  /// Ακύρωση — η κλήση μένει όπως τη σώζει ο άλλος.
  keepTheirs,

  /// Η δική μου εικόνα γράφεται από πάνω, εν γνώσει μου.
  overwrite,
}

/// Ρωτά τι να γίνει όταν η κλήση άλλαξε από άλλον χρήστη.
///
/// Όταν ο συνάδελφος **καταχώρησε** την κλήση στο Lansweeper στο μεταξύ, το
/// πέρασμα από πάνω δεν χάνει κείμενο: ανοίγει δεύτερο αίτημα σε σύστημα που η
/// εφαρμογή δεν μπορεί να καθαρίσει. Γι' αυτό τότε ο τίτλος το λέει ρητά, και
/// η ασφαλής επιλογή είναι η προεπιλεγμένη.
Future<CallConflictChoice?> showCallConflictDialog(
  BuildContext context,
  CallSaveConflict conflict, {
  DateTime? now,
}) async {
  final registered = conflict.otherRegisteredInLansweeper;
  final overwrite = await showStaleWriteConflictDialog(
    context,
    title: registered ? 'Η κλήση καταχωρήθηκε στο μεταξύ' : 'Κάποιος πρόλαβε',
    headline: conflict.headline(now: now),
    warning: conflict.overwriteWarning,
    changedFields: conflict.changedFields,
    takeTheirsLabel: registered
        ? 'Κράτα την καταχώρηση'
        : 'Ακύρωσε την αλλαγή μου',
  );
  if (overwrite == null) return null;
  return overwrite
      ? CallConflictChoice.overwrite
      : CallConflictChoice.keepTheirs;
}
