import 'package:flutter/material.dart';

import '../../../../core/widgets/stale_write_conflict_dialog.dart';
import '../../services/directory_save_conflict.dart';

/// Ρωτά τι να γίνει όταν η καρτέλα Καταλόγου άλλαξε από άλλον χρήστη.
///
/// Επιστρέφει `true` **μόνο** όταν ο χρήστης επιλέξει ρητά να γράψει τη δική
/// του εικόνα από πάνω. Το Escape μετρά ως ακύρωση.
Future<bool> showDirectoryConflictDialog(
  BuildContext context,
  DirectorySaveConflict conflict, {
  DateTime? now,
}) async {
  final overwrite = await showStaleWriteConflictDialog(
    context,
    headline: conflict.headline(now: now),
    warning: conflict.overwriteWarning,
    changedFields: conflict.changedFields,
  );
  return overwrite ?? false;
}

/// Αποθηκεύει καρτέλα Καταλόγου και ρωτά αν κάποιος πρόλαβε.
///
/// Γραμμένο μία φορά για τις τρεις καρτέλες — υπάλληλος, τμήμα, εξοπλισμός.
/// Το [save] καλείται ξανά με `force: true` **μόνο** αν ο χρήστης επιμείνει.
/// Επιστρέφει `true` όταν η αποθήκευση όντως έγινε.
Future<bool> saveDirectoryRecordWithConflictPrompt(
  BuildContext context, {
  required Future<void> Function({required bool force}) save,
  DateTime? now,
}) async {
  try {
    await save(force: false);
    return true;
  } on DirectoryStaleException catch (stale) {
    if (!context.mounted) return false;
    final overwrite = await showDirectoryConflictDialog(
      context,
      stale.conflict,
      now: now,
    );
    if (!overwrite) return false;
    await save(force: true);
    return true;
  }
}

/// Η απάντηση στην ερώτηση διένεξης που γίνεται **πριν** από τις εγγραφές.
enum DirectoryConflictAnswer {
  /// Κανείς δεν άλλαξε την καρτέλα — η αποθήκευση συνεχίζει κανονικά.
  noConflict,

  /// «Κράτα τη δική μου αλλαγή» — η καρτέλα γράφεται από πάνω.
  keepMine,

  /// «Ακύρωσε την αλλαγή μου» — δεν γράφεται τίποτα.
  keepTheirs,
}

/// Ρωτά «Κάποιος πρόλαβε» **πριν** γράψει οτιδήποτε η αποθήκευση.
///
/// Για τις καρτέλες που γράφουν κι άλλα πριν από την ίδια την καρτέλα (ό,τι
/// μένει πίσω στο παλιό τμήμα, νέο τμήμα, συγκρούσεις τηλεφώνου): χωρίς αυτό
/// η ερώτηση ερχόταν αφού εκείνα είχαν ήδη γραφτεί, και το «Η αποθήκευση
/// ακυρώθηκε» έλεγε ψέματα. Το [probe] μόνο διαβάζει.
///
/// Ο φρουρός της ίδιας της εγγραφής ([saveDirectoryRecordWithConflictPrompt])
/// μένει στη θέση του για το ελάχιστο διάστημα ανάμεσα στον έλεγχο και στην
/// εγγραφή.
Future<DirectoryConflictAnswer> askDirectoryConflictBeforeWrites(
  BuildContext context, {
  required Future<DirectorySaveConflict?> Function() probe,
  DateTime? now,
}) async {
  final conflict = await probe();
  if (conflict == null) return DirectoryConflictAnswer.noConflict;
  if (!context.mounted) return DirectoryConflictAnswer.keepTheirs;
  final overwrite = await showDirectoryConflictDialog(
    context,
    conflict,
    now: now,
  );
  return overwrite
      ? DirectoryConflictAnswer.keepMine
      : DirectoryConflictAnswer.keepTheirs;
}

/// «Η αποθήκευση ακυρώθηκε» — ίδιο κείμενο για τις τρεις καρτέλες.
void showDirectorySaveCancelledSnackBar(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'Η αποθήκευση ακυρώθηκε — η καρτέλα κρατά τα στοιχεία του '
        'συναδέλφου. Κλείστε την και ανοίξτε την ξανά για να τα δείτε.',
      ),
    ),
  );
}
