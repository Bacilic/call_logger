import '../models/task.dart';

/// Αν μια εκκρεμότητα ήταν καθυστερημένη στο τέλος μιας περασμένης μέρας.
///
/// Κρίνεται με ό,τι ίσχυε **τότε**, όχι με ό,τι ισχύει σήμερα: μια εκκρεμότητα
/// που έκλεισε ή διαγράφηκε αργότερα μετρά τις μέρες που ήταν ακόμη ανοιχτή, και
/// μια αναβολή μεταγενέστερη της μέρας δεν της αλλάζει προθεσμία αναδρομικά.
abstract final class TaskOverdueTimeline {
  /// [endedAt]: η στιγμή που έπαψε να εκκρεμεί (ολοκλήρωση ή διαγραφή)·
  /// κενή όσο εκκρεμεί ακόμη.
  static bool wasOverdueAt(
    DateTime moment, {
    required DateTime createdAt,
    required DateTime? endedAt,
    required DateTime? currentDue,
    required List<TaskSnoozeEntry> snoozes,
  }) {
    if (!wasOpenAt(moment, createdAt: createdAt, endedAt: endedAt)) {
      return false;
    }
    final due = dueInForceAt(moment, currentDue: currentDue, snoozes: snoozes);
    return due != null && due.isBefore(moment);
  }

  /// Αν η εκκρεμότητα ήταν ανοιχτή στη στιγμή [moment]: υπήρχε ήδη και δεν είχε
  /// ακόμη ολοκληρωθεί ή διαγραφεί. Κρίνεται με ό,τι ίσχυε τότε — μια
  /// εκκρεμότητα που έκλεισε αργότερα ήταν ανοιχτή όσο ακόμη εκκρεμούσε.
  ///
  /// [endedAt]: η στιγμή που έπαψε να εκκρεμεί· κενή όσο εκκρεμεί ακόμη.
  static bool wasOpenAt(
    DateTime moment, {
    required DateTime createdAt,
    required DateTime? endedAt,
  }) {
    if (!createdAt.isBefore(moment)) return false;
    return endedAt == null || !endedAt.isBefore(moment);
  }

  /// Αν η εκκρεμότητα έμεινε **ανοιχτή μετά από κάποια προθεσμία της** — δηλαδή
  /// άργησε, έστω κι αν αναβλήθηκε ή έκλεισε αργότερα.
  ///
  /// Κάθε προθεσμία που είχε κρίνεται ξεχωριστά: η αρχική (και οι ενδιάμεσες)
  /// χάθηκαν αν είχαν περάσει πριν την αναβολή που τις αντικατέστησε, η
  /// τελευταία αν πέρασε πριν η εκκρεμότητα τελειώσει. Αναβολή που έγινε
  /// **πριν** περάσει η προθεσμία δεν δημιουργεί καθυστέρηση. Εκκρεμότητα που
  /// έκλεισε πριν από την προθεσμία της δεν άργησε, όσο παλιά κι αν είναι η
  /// προθεσμία σήμερα.
  ///
  /// [endedAt]: ολοκλήρωση· κενή όσο εκκρεμεί ακόμη, οπότε κρίνεται ως το [now].
  static bool wasEverOverdue({
    required DateTime now,
    required DateTime? endedAt,
    required DateTime? currentDue,
    required List<TaskSnoozeEntry> snoozes,
  }) {
    final end = endedAt ?? now;
    for (var i = 0; i <= snoozes.length; i++) {
      final isLast = i == snoozes.length;
      final due = isLast
          ? currentDue
          : (snoozes[i].replacedDueAt ?? currentDue);
      if (due == null || !due.isBefore(end)) continue;
      if (!isLast && !due.isBefore(snoozes[i].snoozedAt)) continue;
      return true;
    }
    return false;
  }

  /// Η προθεσμία που ίσχυε τη στιγμή [moment]: αυτήν που αντικατέστησε η
  /// πρώτη αναβολή που έγινε **μετά**. Αναβολή παλιότερη από την καταγραφή της
  /// αντικατεστημένης προθεσμίας δεν τη γνωρίζει — τότε μένει η τρέχουσα.
  static DateTime? dueInForceAt(
    DateTime moment, {
    required DateTime? currentDue,
    required List<TaskSnoozeEntry> snoozes,
  }) {
    for (final snooze in snoozes) {
      if (!snooze.snoozedAt.isBefore(moment)) {
        return snooze.replacedDueAt ?? currentDue;
      }
    }
    return currentDue;
  }
}
