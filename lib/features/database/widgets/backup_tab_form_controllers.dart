import 'package:flutter/material.dart';

import '../models/database_backup_settings.dart';

/// Τα πεδία κειμένου της καρτέλας αντιγράφων, με έναν κάτοχο.
///
/// Επτά controllers και επτά κόμβοι εστίασης ζούσαν σκόρπιοι μέσα στην
/// καρτέλα, μαζί με τον συγχρονισμό τους από τις ρυθμίσεις και τη διάθεσή
/// τους — τριάντα γραμμές τελετουργικού που έκρυβαν τη δουλειά της οθόνης.
///
/// Ο κανόνας που επιβάλλει: **πεδίο που έχει την εστίαση δεν ξαναγράφεται
/// ποτέ από τη ρύθμιση.** Αλλιώς η τιμή που πληκτρολογεί ο χρήστης θα
/// αντικαθίστατο στη μέση της πληκτρολόγησης.
class BackupTabFormControllers {
  BackupTabFormControllers();

  final TextEditingController destination = TextEditingController();
  final TextEditingController maxCopies = TextEditingController();
  final TextEditingController maxAge = TextEditingController();
  final TextEditingController fullCopies = TextEditingController();
  final TextEditingController threshold = TextEditingController();
  final TextEditingController minSpacing = TextEditingController();
  final TextEditingController maxWait = TextEditingController();

  final FocusNode destinationFocus = FocusNode();
  final FocusNode maxCopiesFocus = FocusNode();
  final FocusNode maxAgeFocus = FocusNode();
  final FocusNode fullCopiesFocus = FocusNode();
  final FocusNode thresholdFocus = FocusNode();
  final FocusNode minSpacingFocus = FocusNode();
  final FocusNode maxWaitFocus = FocusNode();

  void dispose() {
    destination.dispose();
    maxCopies.dispose();
    maxAge.dispose();
    fullCopies.dispose();
    threshold.dispose();
    minSpacing.dispose();
    maxWait.dispose();
    destinationFocus.dispose();
    maxCopiesFocus.dispose();
    maxAgeFocus.dispose();
    fullCopiesFocus.dispose();
    thresholdFocus.dispose();
    minSpacingFocus.dispose();
    maxWaitFocus.dispose();
  }

  /// Φέρνει τα πεδία σε συμφωνία με τις αποθηκευμένες ρυθμίσεις.
  ///
  /// Οι τρεις σημαίες αφορούν πεδία που μπορεί να άλλαξαν από αλλού (άλλη
  /// καρτέλα, άλλος χρήστης): συγχρονίζονται μόνο όταν η τιμή τους όντως
  /// άλλαξε, ώστε ένα άσχετο rebuild να μη διακόπτει την πληκτρολόγηση.
  void syncFromSettings(
    DatabaseBackupSettings s, {
    bool syncDestination = true,
    bool syncRetentionMaxCopies = true,
    bool syncRetentionMaxAgeDays = true,
  }) {
    if (syncDestination) {
      _assign(destination, destinationFocus, s.destinationDirectory);
    }
    if (syncRetentionMaxCopies) {
      _assign(maxCopies, maxCopiesFocus, '${s.retentionQuickMaxCopies}');
    }
    if (syncRetentionMaxAgeDays) {
      _assign(maxAge, maxAgeFocus, '${s.retentionQuickMaxAgeDays}');
    }
    _assign(fullCopies, fullCopiesFocus, '${s.retentionFullMaxCopies}');
    _assign(threshold, thresholdFocus, '${s.changeThreshold}');
    _assign(minSpacing, minSpacingFocus, '${s.minSpacingMinutes}');
    _assign(maxWait, maxWaitFocus, '${s.maxWaitMinutes}');
  }

  static void _assign(
    TextEditingController controller,
    FocusNode focus,
    String value,
  ) {
    if (focus.hasFocus || controller.text == value) return;
    controller.text = value;
  }
}

/// Αποθηκεύει το περιεχόμενο ενός αριθμητικού πεδίου και δείχνει τι ίσχυσε.
///
/// Η αποθήκευση μπορεί να ψαλιδίσει την τιμή (π.χ. ελάχιστο 15΄)· το πεδίο
/// πρέπει να δείξει ό,τι πραγματικά ισχύει, όχι ό,τι πληκτρολογήθηκε. Κενό ή
/// μη αριθμητικό κείμενο δεν αποθηκεύεται — αλλά το πεδίο επανέρχεται στην
/// ισχύουσα τιμή, ώστε να μη μείνει άδειο.
Future<void> persistIntField({
  required TextEditingController controller,
  required Future<void> Function(int value) save,
  required String Function() readApplied,
  required bool Function() stillMounted,
}) async {
  final raw = controller.text.trim();
  final parsed = raw.isEmpty ? null : int.tryParse(raw);
  if (parsed != null) {
    await save(parsed);
  }
  if (!stillMounted()) return;
  final applied = readApplied();
  if (controller.text != applied) controller.text = applied;
}
