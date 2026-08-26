import 'package:flutter/material.dart';

import '../services/settings_list_conflict.dart';
import 'stale_write_conflict_dialog.dart';

/// Ρωτά τι να γίνει όταν μια ρυθμιζόμενη λίστα άλλαξε από άλλον χρήστη.
///
/// Επιστρέφει `true` **μόνο** όταν ο χρήστης επιλέξει ρητά να γράψει τη δική
/// του λίστα από πάνω. Το Escape μετρά ως ακύρωση.
Future<bool> showSettingsListConflictDialog(
  BuildContext context,
  SettingsListConflict conflict, {
  String listLabel = 'λίστα',
  DateTime? now,
}) async {
  final overwrite = await showStaleWriteConflictDialog(
    context,
    title: 'Η $listLabel άλλαξε στο μεταξύ',
    headline: conflict.headline(now: now),
    warning: conflict.overwriteWarning,
    changedFieldsCaption: 'Τι άλλαξε ο άλλος:',
    changedFields: conflict.changeLines,
  );
  return overwrite ?? false;
}

/// Αποθηκεύει μια ρυθμιζόμενη λίστα και ρωτά αν κάποιος πρόλαβε.
///
/// Το [save] καλείται ξανά με `force: true` **μόνο** αν ο χρήστης επιμείνει —
/// τότε η δική του λίστα γράφεται εν γνώσει του. Επιστρέφει `true` όταν η
/// αποθήκευση όντως έγινε.
Future<bool> saveSettingsListWithConflictPrompt(
  BuildContext context, {
  required Future<void> Function({required bool force}) save,
  String listLabel = 'λίστα',
  DateTime? now,
}) async {
  try {
    await save(force: false);
    return true;
  } on SettingsListStaleException catch (stale) {
    if (!context.mounted) return false;
    final overwrite = await showSettingsListConflictDialog(
      context,
      stale.conflict,
      listLabel: listLabel,
      now: now,
    );
    if (!overwrite) return false;
    await save(force: true);
    return true;
  }
}
