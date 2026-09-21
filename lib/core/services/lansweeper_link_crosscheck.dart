import '../database/calls_lansweeper_repository.dart';
import '../database/tasks_lansweeper_repository.dart';

/// Ποια οντότητα βρέθηκε να κρατά ήδη αίτημα.
enum LansweeperLinkSide {
  /// Η κλήση από την οποία γεννήθηκε η εκκρεμότητα.
  call,

  /// Μια εκκρεμότητα που γεννήθηκε από την κλήση.
  task,
}

/// Η άλλη άκρη του δεσμού κρατά ήδη αίτημα στο Lansweeper.
class LansweeperLinkFinding {
  const LansweeperLinkFinding({
    required this.side,
    required this.entityId,
    required this.ticketId,
    required this.label,
  });

  final LansweeperLinkSide side;

  /// Το αναγνωριστικό της κλήσης ή της εκκρεμότητας που κρατά το αίτημα.
  final int entityId;

  final String ticketId;

  /// Πώς αναφέρεται στον χρήστη: «την κλήση #344», «την εκκρεμότητα «Δεν
  /// τυπώνει»». Φτιάχνεται εδώ ώστε το μήνυμα να είναι ένα, όποια κατεύθυνση
  /// κι αν το ζήτησε.
  final String label;
}

/// Ο **αμφίδρομος** έλεγχος: κρατά ήδη αίτημα η άλλη άκρη του δεσμού;
///
/// Μία υλοποίηση για δύο ερωτήσεις που είναι η ίδια ερώτηση από τις δύο
/// πλευρές της. Γραμμένες χωριστά, θα απαντούσαν διαφορετικά μέσα σε λίγες
/// αλλαγές — και τότε η μία πύλη θα προειδοποιούσε ενώ η άλλη θα άνοιγε
/// σιωπηλά δεύτερο αίτημα για το ίδιο πρόβλημα.
class LansweeperLinkCrosscheck {
  LansweeperLinkCrosscheck({required this.calls, required this.tasks});

  final CallsLansweeperRepository calls;
  final TasksLansweeperRepository tasks;

  /// Πάω να στείλω **εκκρεμότητα**: έχει αίτημα η κλήση που τη γέννησε;
  ///
  /// `null` σημαίνει «προχώρα ελεύθερα» — είτε η εκκρεμότητα δεν κρατά δεσμό
  /// με κλήση, είτε η κλήση δεν έχει σταλεί ποτέ.
  Future<LansweeperLinkFinding?> forTask({required int? linkedCallId}) async {
    if (linkedCallId == null) return null;
    final ticketId = await calls.ticketIdOf(linkedCallId);
    if (ticketId == null) return null;
    return LansweeperLinkFinding(
      side: LansweeperLinkSide.call,
      entityId: linkedCallId,
      ticketId: ticketId,
      label: 'την κλήση #$linkedCallId',
    );
  }

  /// Πάω να στείλω **κλήση**: έχει αίτημα κάποια εκκρεμότητά της;
  ///
  /// Επιστρέφει την πρώτη που βρέθηκε. Περισσότερες από μία είναι σπάνιο και
  /// δεν αλλάζουν την απόφαση: η ερώτηση προς τον χρήστη είναι «υπάρχει ήδη
  /// αίτημα για αυτή τη δουλειά;», και μία αρκεί για να είναι «ναι».
  Future<LansweeperLinkFinding?> forCall({required int callId}) async {
    final ticketed = await tasks.ticketedTasksForCall(callId);
    if (ticketed.isEmpty) return null;
    final first = ticketed.first;
    final title = first.title;
    return LansweeperLinkFinding(
      side: LansweeperLinkSide.task,
      entityId: first.taskId,
      ticketId: first.ticketId,
      label: title.isEmpty
          ? 'την εκκρεμότητα #${first.taskId}'
          : 'την εκκρεμότητα «$title»',
    );
  }
}

/// Τι αποφάσισε ο χρήστης μπροστά στον δεσμό.
enum LansweeperLinkChoice {
  /// Καμία αποστολή.
  cancel,

  /// Άνοιγμα του υπάρχοντος αιτήματος στον περιηγητή· η αποστολή ακυρώνεται.
  openExisting,

  /// Η δουλειά προσγράφεται στο υπάρχον αίτημα — σημείωση αντί για νέο ticket.
  attachToExisting,

  /// Ξεχωριστό, νέο αίτημα.
  createNew,
}
