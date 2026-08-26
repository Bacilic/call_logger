import 'package:intl/intl.dart';

import '../../../core/utils/conflict_actor_text.dart';
import '../models/task.dart';

/// Τι λέει ο διάλογος διένεξης, υπολογισμένο χωρίς οθόνη.
///
/// Η σύνθεση ζει εδώ και όχι μέσα στο widget, ώστε οι κανόνες («πότε λέμε
/// *ολοκλήρωσε* και πότε *άλλαξε*», «τι σβήνεται αν γράψω από πάνω») να
/// ελέγχονται με unit τεστ και να μην ξαναγραφτούν σε δεύτερο σημείο.
class TaskConflictSummary {
  const TaskConflictSummary._({
    required this.headline,
    required this.currentStateLine,
    required this.overwriteWarning,
    this.freshSolution,
  });

  /// «Ο Βλάσης ολοκλήρωσε αυτή την εκκρεμότητα στις 18:00.»
  final String headline;

  /// «Κατάσταση τώρα στη βάση: ολοκληρωμένη»
  final String currentStateLine;

  /// Τι χάνεται αν ο χρήστης γράψει τη δική του εικόνα από πάνω.
  final String overwriteWarning;

  /// Η λύση που υπάρχει **τώρα** στη βάση, αν υπάρχει.
  final String? freshSolution;

  /// Η ώρα γραμμένη όπως τη διαβάζει άνθρωπος: σκέτη ώρα για σήμερα, με
  /// ημερομηνία για παλιότερα. Το «στις 18:00» για κάτι που έγινε προχθές
  /// είναι παραπλανητικό.
  static String describeMoment(DateTime moment, {required DateTime now}) {
    final sameDay =
        moment.year == now.year &&
        moment.month == now.month &&
        moment.day == now.day;
    return sameDay
        ? DateFormat('HH:mm').format(moment)
        : DateFormat('dd/MM HH:mm').format(moment);
  }

  static TaskConflictSummary of({
    required Task attempted,
    required Task fresh,
    String? changedBy,
    DateTime? changedAt,
    DateTime? now,
  }) {
    final moment = now ?? DateTime.now();
    final who = conflictActorName(changedBy);
    final when = changedAt == null
        ? ''
        : ' στις ${describeMoment(changedAt, now: moment)}';

    final freshStatus = TaskStatusX.fromString(fresh.status);
    final attemptedStatus = TaskStatusX.fromString(attempted.status);
    final justClosed = freshStatus == TaskStatus.closed;

    final String verb;
    if (justClosed && attemptedStatus == TaskStatus.closed) {
      // Και οι δύο πήγαν να την κλείσουν — ο άλλος πρόλαβε.
      verb = 'πρόλαβε και ολοκλήρωσε';
    } else if (justClosed) {
      verb = 'ολοκλήρωσε';
    } else {
      verb = 'άλλαξε';
    }

    final solution = fresh.solutionNotes?.trim();
    final hasSolution = solution != null && solution.isNotEmpty;

    final losses = <String>[];
    if (freshStatus != attemptedStatus) {
      losses.add('η κατάσταση «${freshStatus.displayLabelEl}»');
    }
    if (hasSolution && (attempted.solutionNotes?.trim() ?? '') != solution) {
      losses.add('η λύση που γράφτηκε');
    }
    if (fresh.assignedOperatorId != attempted.assignedOperatorId) {
      losses.add('η ανάθεση');
    }

    return TaskConflictSummary._(
      headline: '$who $verb αυτή την εκκρεμότητα$when.',
      currentStateLine:
          'Κατάσταση τώρα στη βάση: ${freshStatus.displayLabelEl}',
      freshSolution: hasSolution ? solution : null,
      overwriteWarning: losses.isEmpty
          ? 'Αν κρατήσετε τη δική σας εικόνα, η ξένη αλλαγή θα αντικατασταθεί.'
          : 'Αν κρατήσετε τη δική σας εικόνα, θα χαθεί ${losses.join(' και ')}.',
    );
  }
}
