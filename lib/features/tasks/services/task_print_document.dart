import 'package:intl/intl.dart';

import '../models/task.dart';
import '../utils/task_completion_summary.dart';

/// Μια γραμμή «ετικέτα — τιμή» στο φύλλο.
class TaskPrintField {
  const TaskPrintField(this.label, this.value, {this.emphasized = false});

  final String label;
  final String value;

  /// Τυπώνεται μεγαλύτερο. Το τηλέφωνο είναι το μόνο που το χρειάζεται: όταν
  /// φτάσετε στο τμήμα και δεν βρείτε κανέναν, αυτό ψάχνετε πρώτο.
  final bool emphasized;
}

/// Μία αναβολή, όπως διαβάζεται στο χαρτί.
class TaskPrintSnooze {
  const TaskPrintSnooze({
    required this.order,
    required this.movedAt,
    this.newDueAt,
    this.note,
  });

  /// Πολλοστή αναβολή, από το 1.
  final int order;

  final String movedAt;
  final String? newDueAt;
  final String? note;
}

/// Τι γράφεται στο φύλλο μιας εκκρεμότητας — **ανεξάρτητα από το πού πάει**.
///
/// Ο εκτυπωτής και το αρχείο PDF χτίζονται από αυτή τη μία δομή. Αν καθένα
/// ρωτούσε μόνο του την εκκρεμότητα, τα δύο χαρτιά θα άρχιζαν να λένε
/// διαφορετικά πράγματα — και η απόκλιση θα φαινόταν μόνο όταν κάποιος τα
/// έβαζε δίπλα-δίπλα.
///
/// Όλες οι τιμές είναι **έτοιμο κείμενο**: οι ημερομηνίες και οι διάρκειες
/// μορφοποιούνται μία φορά εδώ, με τους ίδιους κανόνες που βλέπει ο χρήστης
/// στην οθόνη.
class TaskPrintDocument {
  const TaskPrintDocument({
    required this.heading,
    required this.createdAtLabel,
    required this.title,
    required this.dueLabel,
    required this.description,
    required this.fields,
    required this.snoozes,
    this.previousSolution,
    this.completionLine,
    this.sinceLastSnoozeLine,
    this.linkLine,
  });

  /// «Εκκρεμότητα #204» — ο αριθμός είναι ο μόνος τρόπος να ξαναβρεθεί.
  final String heading;

  final String createdAtLabel;
  final String title;

  /// «Προθεσμία: 02/09/2026 11:32»· κενό όταν η εκκρεμότητα δεν έχει έγκυρη.
  final String dueLabel;

  final String description;

  /// Ποιος, πού, τηλέφωνο, εξοπλισμός — ό,τι από αυτά υπάρχει.
  final List<TaskPrintField> fields;

  /// Το ιστορικό αναβολών, με σειρά. Κενό όταν δεν αναβλήθηκε ποτέ.
  final List<TaskPrintSnooze> snoozes;

  /// Η λύση της τελευταίας ολοκλήρωσης· `null` όταν δεν έχει κλείσει ποτέ.
  final String? previousSolution;

  /// «Ολοκληρώθηκε 07/08/2026 17:36 (2 ημέρες)».
  final String? completionLine;

  /// «Από την τελευταία αναβολή: 4 ώρες».
  final String? sinceLastSnoozeLine;

  /// «Από κλήση #444 · αίτημα Lansweeper #60011» — ό,τι από τα δύο υπάρχει.
  final String? linkLine;

  bool get hasSnoozes => snoozes.isNotEmpty;
  bool get hasClosure => previousSolution != null || completionLine != null;
}

/// Το όνομα αρχείου που προτείνεται στο «Αποθήκευση ως PDF».
String taskPrintFileName(Task task) => 'εκκρεμότητα-${task.id ?? 0}.pdf';

/// Χτίζει το φύλλο της [task].
///
/// **Ό,τι λείπει, λείπει και από το χαρτί.** Μια κενή γραμμή με ετικέτα και
/// παύλα δεν λέει τίποτα· κόβει μόνο τον χώρο που θα χρησιμοποιούσε ο χρήστης
/// για να γράψει.
TaskPrintDocument buildTaskPrintDocument(Task task) {
  final dateTime = DateFormat('dd/MM/yyyy HH:mm');
  final completion = TaskCompletionSummary.of(task);

  String? clean(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  final callId = task.callId;
  final ticket = clean(task.lansweeperMainTicketId);
  final linkParts = <String>[
    if (callId != null) 'Από κλήση #$callId',
    if (ticket != null) 'Αίτημα Lansweeper #$ticket',
  ];

  final due = task.dueDateTime;
  return TaskPrintDocument(
    heading: 'Εκκρεμότητα #${task.id ?? 0}',
    createdAtLabel: task.createdAtDateTime != null
        ? dateTime.format(task.createdAtDateTime!)
        : '',
    title: clean(task.title) ?? 'Χωρίς τίτλο',
    dueLabel: due != null ? 'Προθεσμία: ${dateTime.format(due)}' : '',
    description: clean(task.description) ?? '',
    fields: [
      if (clean(task.userText) != null)
        TaskPrintField('Ποιος', task.userText!.trim()),
      if (clean(task.departmentText) != null)
        TaskPrintField('Πού', task.departmentText!.trim()),
      if (clean(task.phoneText) != null)
        TaskPrintField('Τηλέφωνο', task.phoneText!.trim(), emphasized: true),
      if (clean(task.equipmentText) != null)
        TaskPrintField('Εξοπλισμός', task.equipmentText!.trim()),
    ],
    snoozes: [
      for (final (index, entry) in task.snoozeEntries.indexed)
        TaskPrintSnooze(
          order: index + 1,
          movedAt: dateTime.format(entry.snoozedAt),
          newDueAt: entry.dueAt != null ? dateTime.format(entry.dueAt!) : null,
          note: clean(entry.note),
        ),
    ],
    previousSolution: completion.solution,
    completionLine: completion.momentLine != null
        ? 'Ολοκληρώθηκε ${completion.momentLine}'
        : null,
    sinceLastSnoozeLine: completion.sinceLastSnoozeLabel != null
        ? 'Από την τελευταία αναβολή: ${completion.sinceLastSnoozeLabel}'
        : null,
    linkLine: linkParts.isEmpty ? null : linkParts.join(' · '),
  );
}
