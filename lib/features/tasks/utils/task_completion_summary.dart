import 'package:intl/intl.dart';

import '../models/task.dart';
import 'task_duration_format.dart';

/// Τα στοιχεία της τελευταίας ολοκλήρωσης μιας εκκρεμότητας, έτοιμα για προβολή.
///
/// Ζει έξω από τα widgets ώστε η κάρτα και ο διάλογος επεξεργασίας να δείχνουν
/// τα ίδια νούμερα: η μία προβολή δεν μπορεί να ξεμείνει πίσω από την άλλη.
class TaskCompletionSummary {
  const TaskCompletionSummary._({
    this.completedAtLabel,
    this.durationLabel,
    this.sinceLastSnoozeLabel,
    this.solution,
  });

  /// Στιγμή ολοκλήρωσης, π.χ. «07/08/2026 17:36».
  final String? completedAtLabel;

  /// Πόσο κράτησε από τη δημιουργία ως την ολοκλήρωση.
  final String? durationLabel;

  /// Πόσο κράτησε από την τελευταία αναβολή ως την ολοκλήρωση.
  final String? sinceLastSnoozeLabel;

  /// Το κείμενο της λύσης, χωρίς κενά στις άκρες.
  final String? solution;

  /// `true` όταν υπάρχει έστω κάτι να δείξουμε για την προηγούμενη ολοκλήρωση.
  bool get hasAnything => completedAtLabel != null || solution != null;

  /// Μία γραμμή «στιγμή (διάρκεια)» — ό,τι χωράει σε επικεφαλίδα.
  String? get momentLine {
    final moment = completedAtLabel;
    if (moment == null) return null;
    final duration = durationLabel;
    return duration == null ? moment : '$moment ($duration)';
  }

  static TaskCompletionSummary of(Task task) {
    final completedAt = task.completedAtDateTime;
    final createdAt = task.createdAtDateTime;
    final snoozeEntries = task.snoozeEntries;
    final lastSnoozeAt = snoozeEntries.isNotEmpty
        ? snoozeEntries.last.snoozedAt
        : null;
    final solution = task.solutionNotes?.trim();

    return TaskCompletionSummary._(
      completedAtLabel: completedAt != null
          ? DateFormat('dd/MM/yyyy HH:mm').format(completedAt)
          : null,
      durationLabel: completedAt != null && createdAt != null
          ? durationSince(createdAt, completedAt)
          : null,
      sinceLastSnoozeLabel: completedAt != null && lastSnoozeAt != null
          ? durationSince(lastSnoozeAt, completedAt)
          : null,
      solution: (solution?.isNotEmpty ?? false) ? solution : null,
    );
  }
}
