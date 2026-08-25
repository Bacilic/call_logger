import 'package:flutter/material.dart';

import '../../../core/widgets/stale_write_conflict_dialog.dart';
import '../services/lansweeper_registration_conflict.dart';

/// Ρωτά τι να γίνει όταν κάποιος άλλος κούνησε την κατάσταση Lansweeper.
///
/// Επιστρέφει `true` **μόνο** όταν ο χρήστης επιλέξει ρητά να συνεχίσει. Το
/// Escape μετρά ως ακύρωση: ένα κατά λάθος πάτημα δεν πρέπει να αφήσει ορφανό
/// το αίτημα του συναδέλφου στο Lansweeper.
Future<bool> showLansweeperRegistrationConflictDialog(
  BuildContext context,
  LansweeperRegistrationConflict conflict, {
  DateTime? now,
}) async {
  final registered = conflict.otherRegistered;
  final overwrite = await showStaleWriteConflictDialog(
    context,
    title: registered ? 'Η κλήση καταχωρήθηκε στο μεταξύ' : 'Κάποιος πρόλαβε',
    headline: conflict.headline(now: now),
    warning: conflict.overwriteWarning,
    changedFields: conflict.changedFields,
    keepMineLabel: 'Συνέχισε ούτως ή άλλως',
    takeTheirsLabel: registered
        ? 'Κράτα την καταχώρηση'
        : 'Άφησε τη δική του',
  );
  return overwrite ?? false;
}

/// Πώς τελείωσε μια χειροκίνητη αλλαγή κατάστασης Lansweeper.
///
/// Τα δύο «δεν έγινε» χωρίζονται επίτηδες: «το άφησα γιατί το είχε καταχωρήσει
/// άλλος» και «δεν πέτυχε» θέλουν διαφορετικό μήνυμα. Ένα κοινό `false` θα
/// έλεγε στον χρήστη ότι πρόλαβε συνάδελφος, ενώ η αιτία ήταν σφάλμα εγγραφής.
enum LansweeperChangeOutcome {
  /// Γράφτηκε.
  applied,

  /// Ο χρήστης είδε τη διένεξη και επέλεξε να μην πειράξει την ξένη δουλειά.
  skippedByUser,

  /// Δεν γράφτηκε για άλλον λόγο — σφάλμα ή ήδη ενεργή αποστολή.
  failed,
}

extension LansweeperChangeOutcomeX on LansweeperChangeOutcome {
  bool get isApplied => this == LansweeperChangeOutcome.applied;
}

/// Εκτελεί μια αλλαγή κατάστασης Lansweeper και ρωτά αν κάποιος πρόλαβε.
///
/// Γραμμένο μία φορά για όλες τις χειροκίνητες μεταβάσεις — σήμανση,
/// επαναφορά, εξαίρεση — και για τις δύο οθόνες που τις προσφέρουν (Αναφορά,
/// Ιστορικό). Όσο ήταν γραμμένο ανά ροή, η επόμενη ροή ξεχνούσε τον διάλογο
/// και η εγγραφή περνούσε αθόρυβα.
///
/// Το [write] καλείται ξανά με `force: true` **μόνο** αν ο χρήστης επιμείνει.
Future<LansweeperChangeOutcome> applyLansweeperChangeWithConflictPrompt(
  BuildContext context, {
  required Future<bool> Function({required bool force}) write,
  DateTime? now,
}) async {
  try {
    return await write(force: false)
        ? LansweeperChangeOutcome.applied
        : LansweeperChangeOutcome.failed;
  } on LansweeperRegistrationStaleException catch (stale) {
    if (!context.mounted) return LansweeperChangeOutcome.skippedByUser;
    final proceed = await showLansweeperRegistrationConflictDialog(
      context,
      stale.conflict,
      now: now,
    );
    if (!proceed) return LansweeperChangeOutcome.skippedByUser;
    return await write(force: true)
        ? LansweeperChangeOutcome.applied
        : LansweeperChangeOutcome.failed;
  }
}
