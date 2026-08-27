import 'package:flutter/material.dart';

import '../../../core/widgets/stale_write_conflict_dialog.dart';
import '../services/lansweeper_registration_conflict.dart';
import '../services/lansweeper_write_failure.dart';

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
        : 'Ακύρωσε την αλλαγή μου',
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

/// Πώς τελείωσε η αλλαγή — **και γιατί**, όταν δεν τελείωσε καλά.
///
/// Το σκέτο [LansweeperChangeOutcome] έλεγε μόνο «δεν έγινε». Η αιτία υπήρχε
/// (η εγγραφή την ήξερε) αλλά σταματούσε εδώ, οπότε καμία οθόνη δεν μπορούσε
/// να την πει. Τώρα ταξιδεύει μαζί με το αποτέλεσμα.
class LansweeperChangeResult {
  const LansweeperChangeResult(this.outcome, {this.failure});

  final LansweeperChangeOutcome outcome;

  /// Τι πήγε στραβά· `null` όταν δεν επρόκειτο για σφάλμα εγγραφής — δηλαδή
  /// όταν πέτυχε, όταν το άφησε ο χρήστης, ή όταν έτρεχε ήδη άλλη αποστολή.
  final LansweeperWriteFailure? failure;

  bool get isApplied => outcome == LansweeperChangeOutcome.applied;
}

/// Εκτελεί μια αλλαγή κατάστασης Lansweeper και ρωτά αν κάποιος πρόλαβε.
///
/// Γραμμένο μία φορά για όλες τις χειροκίνητες μεταβάσεις — σήμανση,
/// επαναφορά, εξαίρεση — και για τις δύο οθόνες που τις προσφέρουν (Αναφορά,
/// Ιστορικό). Όσο ήταν γραμμένο ανά ροή, η επόμενη ροή ξεχνούσε τον διάλογο
/// και η εγγραφή περνούσε αθόρυβα.
///
/// Το [write] καλείται ξανά με `force: true` **μόνο** αν ο χρήστης επιμείνει.
///
/// Είναι και το **ένα σημείο** όπου η αιτία μιας αποτυχίας μπαίνει στο
/// αποτέλεσμα: κάθε χειροκίνητη αλλαγή κατάστασης περνά από εδώ, οπότε καμία
/// οθόνη —ούτε μελλοντική— δεν μπορεί να ξεχάσει να τη δείξει.
Future<LansweeperChangeResult> applyLansweeperChangeWithConflictPrompt(
  BuildContext context, {
  required Future<bool> Function({required bool force}) write,
  DateTime? now,
}) async {
  try {
    return await _attempt(write, force: false);
  } on LansweeperRegistrationStaleException catch (stale) {
    if (!context.mounted) {
      return const LansweeperChangeResult(
        LansweeperChangeOutcome.skippedByUser,
      );
    }
    final proceed = await showLansweeperRegistrationConflictDialog(
      context,
      stale.conflict,
      now: now,
    );
    if (!proceed) {
      return const LansweeperChangeResult(
        LansweeperChangeOutcome.skippedByUser,
      );
    }
    return _attempt(write, force: true);
  }
}

/// Μία απόπειρα εγγραφής, με την αιτία της αποτυχίας αν υπάρξει.
///
/// Η διένεξη ΔΕΝ πιάνεται εδώ: την περιμένει ο καλών για να ρωτήσει τον
/// άνθρωπο. Το `false` χωρίς εξαίρεση σημαίνει «δεν έτρεξε καν» (υπάρχει ήδη
/// ενεργή αποστολή) — αποτυχία χωρίς αιτία προς εμφάνιση.
Future<LansweeperChangeResult> _attempt(
  Future<bool> Function({required bool force}) write, {
  required bool force,
}) async {
  try {
    return LansweeperChangeResult(
      await write(force: force)
          ? LansweeperChangeOutcome.applied
          : LansweeperChangeOutcome.failed,
    );
  } on LansweeperWriteFailure catch (failure) {
    return LansweeperChangeResult(
      LansweeperChangeOutcome.failed,
      failure: failure,
    );
  }
}
