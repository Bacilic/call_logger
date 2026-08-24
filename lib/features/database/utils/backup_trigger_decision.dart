import '../models/database_backup_settings.dart';

/// Γιατί (δεν) οφείλεται αυτόματο αντίγραφο αυτή τη στιγμή.
enum BackupTriggerReason {
  /// Τα αυτόματα αντίγραφα είναι απενεργοποιημένα.
  disabled,

  /// Δεν έχει οριστεί φάκελος προορισμού.
  noDestination,

  /// Καμία αφύλακτη αλλαγή — δεν υπάρχει τίποτα να προστατευτεί.
  noPendingChanges,

  /// Δεν έχει περάσει η ελάχιστη απόσταση από το τελευταίο αντίγραφο.
  spacingNotElapsed,

  /// Υπάρχουν αλλαγές αλλά ούτε το κατώφλι ούτε η μέγιστη αναμονή ήρθαν.
  belowThreshold,

  /// Πρώτο αντίγραφο: υπάρχουν αλλαγές και κανένα προηγούμενο σημάδι.
  dueFirstBackup,

  /// Μαζεύτηκαν τουλάχιστον όσες αλλαγές ορίζει το κατώφλι.
  dueThreshold,

  /// Πέρασε η μέγιστη αναμονή με αφύλακτες αλλαγές.
  dueMaxWait,
}

/// Η απόφαση του χρονιστή για ένα τικ — καθαρός υπολογισμός, χωρίς ρολόγια
/// και βάση: ό,τι χρειάζεται έρχεται ως όρισμα, ώστε τα τεστ να ορίζουν και
/// τις δύο άκρες του χρόνου.
class BackupTriggerDecision {
  const BackupTriggerDecision._(this.due, this.reason);

  final bool due;
  final BackupTriggerReason reason;

  /// Αξιολόγηση των πυλών του αυτόματου αντιγράφου, με τη σειρά του
  /// εγκεκριμένου διαγράμματος: ενεργό → προορισμός → υπάρχει αλλαγή; →
  /// πέρασε η ελάχιστη απόσταση; → κατώφλι ή μέγιστη αναμονή;
  ///
  /// Το δικαίωμα και η προτεραιότητα παρουσίας (εφεδρικός) ελέγχονται από τον
  /// καλούντα — δεν είναι ιδιότητες των ρυθμίσεων.
  static BackupTriggerDecision evaluate({
    required DatabaseBackupSettings settings,
    required int pendingChanges,
    required DateTime now,
  }) {
    if (!settings.backupOnExit) {
      return const BackupTriggerDecision._(
        false,
        BackupTriggerReason.disabled,
      );
    }
    if (settings.destinationDirectory.trim().isEmpty) {
      return const BackupTriggerDecision._(
        false,
        BackupTriggerReason.noDestination,
      );
    }
    if (pendingChanges <= 0) {
      return const BackupTriggerDecision._(
        false,
        BackupTriggerReason.noPendingChanges,
      );
    }

    final last = settings.lastAnyBackupAt;
    if (last == null) {
      return const BackupTriggerDecision._(
        true,
        BackupTriggerReason.dueFirstBackup,
      );
    }

    final minutesSince = now.difference(last).inMinutes;
    if (minutesSince < settings.minSpacingMinutes) {
      return const BackupTriggerDecision._(
        false,
        BackupTriggerReason.spacingNotElapsed,
      );
    }
    if (pendingChanges >= settings.changeThreshold) {
      return const BackupTriggerDecision._(
        true,
        BackupTriggerReason.dueThreshold,
      );
    }
    if (minutesSince >= settings.effectiveMaxWaitMinutes) {
      return const BackupTriggerDecision._(
        true,
        BackupTriggerReason.dueMaxWait,
      );
    }
    return const BackupTriggerDecision._(
      false,
      BackupTriggerReason.belowThreshold,
    );
  }

  /// Αντίγραφο στο κλείσιμο: μόνο «υπάρχουν αφύλακτες αλλαγές;» — χωρίς
  /// κατώφλι, απόσταση ή αναμονή. Το κλείσιμο είναι η τελευταία ευκαιρία
  /// προστασίας όσων γράφτηκαν· λίγες αλλαγές δεν είναι λόγος να χαθούν.
  static bool shouldRunOnClose({
    required DatabaseBackupSettings settings,
    required int pendingChanges,
  }) {
    if (!settings.backupOnExit) return false;
    if (!settings.backupOnCloseIfPending) return false;
    if (settings.destinationDirectory.trim().isEmpty) return false;
    return pendingChanges > 0;
  }
}
