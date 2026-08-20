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
    this.warnings = const <String>[],
  });

  final String? ticketId;

  /// Τι χρειάστηκε προσοχή όταν έφυγε η κλήση — π.χ. ότι ο αιτών δεν βρέθηκε
  /// στο Lansweeper και το αίτημα καταχωρήθηκε στο όνομα του πράκτορα.
  ///
  /// Το μήνυμα ειπώθηκε μία φορά σε ένα snackbar την ώρα της αποστολής και
  /// μετά χανόταν. Εδώ είναι το σημείο όπου κάποιος ρωτά «τι έγινε με αυτό το
  /// ticket;», οπότε εδώ ξαναβρίσκεται. Κενή λίστα = καθαρή καταχώρηση.
  final List<String> warnings;

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
          // Οι δύο γραμμές από πάνω είναι ζευγάρι — τι είναι η κλήση και τι
          // δεν κάνει η αποθήκευση. Οι προειδοποιήσεις είναι τρίτο, ξεχωριστό
          // πράγμα (τι συνέβη κατά την αποστολή) και μπαίνουν από κάτω τους.
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final warning in warnings)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(warning, style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
          ],
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
