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
    if (!createdAt.isBefore(moment)) return false;
    if (endedAt != null && endedAt.isBefore(moment)) return false;
    final due = dueInForceAt(moment, currentDue: currentDue, snoozes: snoozes);
    return due != null && due.isBefore(moment);
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
