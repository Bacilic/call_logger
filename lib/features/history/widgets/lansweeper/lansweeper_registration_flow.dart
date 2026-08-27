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

/// Το μήνυμα μιας σήμανσης όπου κάποιες κλήσεις **δεν** σημάνθηκαν.
///
/// Σε μαζική καταχώρηση ο συνάδελφος μπορεί να έχει προλάβει σε μερικές μόνο.
/// Ένα σκέτο «επιτυχής» εκεί θα ήταν ψέμα, και ένα σκέτο «απέτυχε» επίσης: ο
/// χρήστης πρέπει να μάθει και τα δύο νούμερα για να ξέρει τι μένει.
///
/// Το [skipped] (τις άφησα εγώ, τις είχε καταχωρήσει άλλος) και το [failed]
/// (δεν πέτυχε η εγγραφή) μένουν χωριστά: μπερδεμένα, ένα σφάλμα βάσης θα
/// παρουσιαζόταν ως δουλειά συναδέλφου και κανείς δεν θα το κοίταζε ποτέ.
/// Το [failureReason] είναι η αιτία της πρώτης αποτυχίας, όταν την ξέρουμε:
/// χωρίς αυτήν ο χειριστής βλέπει «δεν ολοκληρώθηκε» και δεν έχει τρόπο να
/// καταλάβει αν φταίει η βάση, το δίκτυο ή η ίδια η κλήση.
String registrationOutcomeMessage({
  required int registered,
  required int skipped,
  required int failed,
  required String ticketId,
  String? failureReason,
}) {
  final parts = <String>[];
  if (registered > 0) {
    parts.add(registrationSuccessMessage(count: registered, ticketId: ticketId));
  }
  if (skipped > 0) {
    parts.add(
      skipped == 1
          ? (registered > 0
                ? '1 παραλείφθηκε — την είχε ήδη καταχωρήσει άλλος.'
                : 'Καμία σήμανση — την κλήση την είχε ήδη καταχωρήσει άλλος.')
          : (registered > 0
                ? '$skipped παραλείφθηκαν — τις είχε ήδη καταχωρήσει άλλος.'
                : 'Καμία σήμανση — τις κλήσεις τις είχε ήδη καταχωρήσει άλλος.'),
    );
  }
  if (failed > 0) {
    final reason = (failureReason ?? '').trim();
    // Η αιτία αντικαθιστά το «η εγγραφή δεν ολοκληρώθηκε» αντί να προστίθεται:
    // δύο προτάσεις που λένε το ίδιο κουράζουν, και η δεύτερη είναι η χρήσιμη.
    final tail = reason.isEmpty ? 'η εγγραφή δεν ολοκληρώθηκε.' : reason;
    parts.add(
      failed == 1
          ? '1 κλήση δεν σημάνθηκε — $tail'
          : '$failed κλήσεις δεν σημάνθηκαν — $tail',
    );
  }
  return parts.join(' ');
}
