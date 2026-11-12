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

/// Τι ξέρει αυτός ο σταθμός για την ώρα του τελευταίου αντιγράφου.
class BackupClockReading {
  const BackupClockReading({this.measureFrom, this.futureStamp});

  /// Από πότε μετρούν η ελάχιστη απόσταση και η μέγιστη αναμονή.
  final DateTime? measureFrom;

  /// Η ώρα του τελευταίου αντιγράφου, όταν απέχει από το «τώρα» αυτού του
  /// σταθμού περισσότερο από την ανοχή προς το μέλλον — κάποιος σταθμός
  /// έχει λάθος ρολόι, και η οθόνη οφείλει να το πει.
  final DateTime? futureStamp;
}

/// Το «χρονόμετρο του σταθμού»: πόσος χρόνος πέρασε από το τελευταίο
/// αντίγραφο, όταν η ώρα που γράφει δεν γίνεται να είναι αληθινή.
///
/// Η ώρα του τελευταίου αντιγράφου ζει στις **κοινές** ρυθμίσεις και τη
/// γράφει το ρολόι του σταθμού που το πήρε. Αν εκείνο πάει μπροστά, οι άλλοι
/// βλέπουν ώρα στο μέλλον, και η αφαίρεση «τώρα − τελευταίο» βγαίνει αρνητική
/// ώσπου να φτάσει εκείνη η ώρα: κανένα αυτόματο αντίγραφο για όλους.
///
/// Σωστό ρολόι δεν υπάρχει για να το ρωτήσουμε, αλλά η διάρκεια δεν
/// χρειάζεται σωστό ρολόι: ο σταθμός θυμάται πότε **είδε** για πρώτη φορά
/// αυτό το αντίγραφο, και μετρά από εκεί. Οι σταθμοί ελέγχουν κάθε λεπτό,
/// άρα η καθυστέρηση της πρώτης ματιάς είναι το πολύ ένα λεπτό.
///
/// Μία μνήμη ανά διεργασία ([instance]): ο χρονιστής και οι οθόνες πρέπει
/// να μετρούν από το ίδιο σημείο, αλλιώς η πρόβλεψη «επόμενο στις» θα
/// διαφωνούσε με όσα κάνει ο χρονιστής.
class BackupElapsedReference {
  BackupElapsedReference();

  static final BackupElapsedReference instance = BackupElapsedReference();

  /// Λίγα λεπτά διαφοράς ανάμεσα σε σταθμούς είναι φυσιολογικά και δεν
  /// αξίζουν συναγερμό (ίδια ανοχή με τον έλεγχο ταυτότητας των Windows).
  static const Duration warningTolerance = Duration(minutes: 5);

  /// Πότε είδε αυτός ο σταθμός για πρώτη φορά κάθε τρέχουσα σφραγίδα.
  final Map<DateTime, DateTime> _firstSeenAt = {};

  /// Το αυτόματο και το χειροκίνητο αντίγραφο κρίνονται **χωριστά**: αν η
  /// μελλοντική ώρα είναι του χειροκίνητου, ένα κατοπινό αυτόματο με σωστή
  /// ώρα πρέπει να μηδενίσει την απόσταση — το «πιο πρόσφατο από τα δύο»
  /// θα έδειχνε για πάντα το μελλοντικό.
  BackupClockReading readFor(DatabaseBackupSettings settings, DateTime now) =>
      read([settings.lastBackupAttempt, settings.lastManualBackupAttempt], now);

  BackupClockReading read(Iterable<DateTime?> stamps, DateTime now) {
    final current = stamps.whereType<DateTime>().toSet();
    _firstSeenAt.removeWhere((stamp, _) => !current.contains(stamp));

    DateTime? measureFrom;
    DateTime? futureStamp;
    for (final stamp in current) {
      final seen = _firstSeenAt.putIfAbsent(stamp, () => now);
      final DateTime from;
      if (!stamp.isAfter(now)) {
        from = stamp;
      } else {
        // Το δικό μας ρολόι γύρισε πίσω μετά την πρώτη ματιά: ξεκινάμε από
        // τώρα, αλλιώς η μέτρηση θα ξανάβγαινε αρνητική.
        from = seen.isAfter(now) ? now : seen;
        _firstSeenAt[stamp] = from;
        if (stamp.difference(now) > warningTolerance &&
            (futureStamp == null || stamp.isAfter(futureStamp))) {
          futureStamp = stamp;
        }
      }
      if (measureFrom == null || from.isAfter(measureFrom)) measureFrom = from;
    }
    return BackupClockReading(
      measureFrom: measureFrom,
      futureStamp: futureStamp,
    );
  }
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
  ///
  /// Ο χρόνος από το τελευταίο αντίγραφο μετριέται μέσω του [reference]
  /// (προεπιλογή η κοινή μνήμη της διεργασίας), ώστε ώρα στο μέλλον να μη
  /// σταματά τα αντίγραφα.
  static BackupTriggerDecision evaluate({
    required DatabaseBackupSettings settings,
    required int pendingChanges,
    required DateTime now,
    BackupElapsedReference? reference,
  }) {
    if (!settings.backupOnExit) {
      return const BackupTriggerDecision._(false, BackupTriggerReason.disabled);
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

    final last = (reference ?? BackupElapsedReference.instance)
        .readFor(settings, now)
        .measureFrom;
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
