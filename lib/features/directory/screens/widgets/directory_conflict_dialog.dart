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
