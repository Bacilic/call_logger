// Προειδοποίηση στην επεξεργασία κλήσης που έχει ήδη φύγει στο Lansweeper.
//
// Το μήνυμα ονομάζει την πραγματική κατάσταση — ποιο ticket — και όχι τη λογική
// συνθήκη που το ενεργοποίησε. Παλιότερα έγραφε «έχει Lansweeper ticket ή
// κατάσταση sent», δηλαδή τον τελεστή `||` του κώδικα: ο χρήστης δεν μπορούσε
// να ξέρει ποιο σκέλος ίσχυσε, ούτε ποιο ticket να ανοίξει.
//
// Η συνέπεια μένει σκόπιμα γενική. Ποια πεδία της κλήσης φτάνουν στο ticket
// αλλάζει καθώς εξελίσσεται ο μηχανισμός αποστολής· μια λίστα πεδίων εδώ θα
// ξεσυγχρονιζόταν σιωπηλά και θα έλεγε ψέματα.

import 'package:flutter/material.dart';

import 'lansweeper_ticket_link.dart';

/// Τι δεν κάνει η αποθήκευση — ίδιο κείμενο σε κάθε περίπτωση.
const String kLansweeperEditWarningConsequence =
    'Οι αλλαγές εδώ δεν ενημερώνουν αυτόματα το Lansweeper.';

/// Η πρώτη φράση της προειδοποίησης.
///
/// Με αριθμό ticket η φράση τελειώνει σε «ticket» **χωρίς τελεία**, γιατί ο
/// αριθμός ακολουθεί ως σύνδεσμος. Χωρίς αριθμό είναι πλήρης πρόταση.
String lansweeperEditWarningHeadline({String? ticketId}) {
  final id = ticketId?.trim() ?? '';
  if (id.isEmpty) {
    return 'Η κλήση είναι σημειωμένη ως καταχωρημένη στο Lansweeper.';
  }
  return 'Η κλήση έχει καταχωρηθεί στο Lansweeper — ticket';
}

class LansweeperEditWarning extends StatelessWidget {
  const LansweeperEditWarning({
    super.key,
    required this.ticketId,
    required this.ticketViewUrlTemplate,
    required this.onClone,
    required this.cloneBusy,
  });

  final String? ticketId;

  /// Πρότυπο URL προβολής ticket από τις ρυθμίσεις Lansweeper. Όταν λείπει ή
  /// είναι άκυρο, ο αριθμός εμφανίζεται ως απλό κείμενο — καλύτερα ορατός
  /// αριθμός χωρίς σύνδεσμο παρά σύνδεσμος που δεν οδηγεί πουθενά.
  final String? ticketViewUrlTemplate;

  final VoidCallback onClone;
  final bool cloneBusy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final id = ticketId?.trim() ?? '';
    final headline = lansweeperEditWarningHeadline(ticketId: id);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (id.isEmpty)
            Text(headline, style: theme.textTheme.bodyMedium)
          else
            LansweeperTicketRichText(
              leadingText: '$headline ',
              ticketId: id,
              ticketViewUrlTemplate: ticketViewUrlTemplate,
              style: theme.textTheme.bodyMedium,
            ),
          const SizedBox(height: 8),
          Text(kLansweeperEditWarningConsequence),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: cloneBusy ? null : onClone,
              icon: cloneBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.copy_all_outlined),
              label: const Text('Κλωνοποίηση ως νέα κλήση'),
            ),
          ),
        ],
      ),
    );
  }
}
