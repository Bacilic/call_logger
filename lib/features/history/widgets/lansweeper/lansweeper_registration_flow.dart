import 'lansweeper_registration_dialogs.dart';

/// Η λογική της καταχώρησης κλήσεων στο Lansweeper, χωρίς UI: ο κανόνας του
/// διπλού ticket και το μήνυμα του αποτελέσματος.
///
/// Ζει χωριστά από τους διαλόγους επειδή τη μοιράζονται και οι τρεις ροές
/// (μεμονωμένη καταχώρηση, χειροκίνητη σήμανση, μαζική) — όσο ήταν γραμμένη
/// τρεις φορές, κάθε αλλαγή έπρεπε να γίνει τρεις φορές και η τρίτη ξεχνιόταν.

/// Καθαρίζει έναν υποψήφιο αριθμό ticket από διπλοεγγραφή, πριν σημανθεί
/// οποιαδήποτε κλήση ως καταχωρημένη.
///
/// Όσο ο χρήστης επιλέγει «Αλλαγή id», ζητείται νέος αριθμός και ξαναγίνεται ο
/// έλεγχος· η ροή σταματά μόλις προκύψει αποδεκτός αριθμός.
///
/// Επιστρέφει:
/// - τον αριθμό που πέρασε τον έλεγχο (κενό = καταχώρηση χωρίς ticket, που δεν
///   ελέγχεται ποτέ για διπλό),
/// - `null` όταν ο χρήστης ακύρωσε — τότε **καμία** σήμανση δεν πρέπει να γίνει.
///
/// Δεν αγγίζει UI: οι δύο κλήσεις-πίσω κάνουν τη δουλειά των διαλόγων και είναι
/// υπεύθυνες για τον δικό τους έλεγχο ζωής του widget (επιστρέφουν ακύρωση όταν
/// η οθόνη έχει φύγει).
Future<String?> resolveTicketIdWithoutDuplicate({
  required String candidate,
  required Future<DuplicateTicketAction> Function(String ticketId)
  checkDuplicate,
  required Future<String?> Function(String currentTicketId) askForDifferentId,
}) async {
  var ticketId = candidate.trim();
  while (true) {
    if (ticketId.isEmpty) return ticketId;

    final action = await checkDuplicate(ticketId);
    switch (action) {
      case DuplicateTicketAction.cancel:
        return null;
      case DuplicateTicketAction.proceed:
        return ticketId;
      case DuplicateTicketAction.changeId:
        final next = await askForDifferentId(ticketId);
        if (next == null) return null;
        ticketId = next.trim();
    }
  }
}

/// Το μήνυμα που ανακοινώνει την επιτυχημένη σήμανση [count] κλήσεων.
///
/// Κενό [ticketId] = καταχώρηση χωρίς αριθμό· τότε ο αριθμός παραλείπεται αντί
/// να εμφανιστεί κενή παρένθεση.
String registrationSuccessMessage({
  required int count,
  required String ticketId,
}) {
  final suffix = ticketId.isEmpty ? '' : ' (ticket #$ticketId)';
  return count == 1
      ? 'Η κλήση επισημάνθηκε ως καταχωρημένη$suffix.'
      : '$count κλήσεις επισημάνθηκαν ως καταχωρημένες$suffix.';
}
