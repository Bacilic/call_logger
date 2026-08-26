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
///
/// Με [registered] `false` η κλήση **δεν** μετριέται ως καταχωρημένη, αλλά
/// κρατά τον αριθμό ενός αιτήματος: η «Επαναφορά σε ακαταχώρητη» με
/// «Διατήρηση id». Η παλιά διατύπωση («έχει καταχωρηθεί») έλεγε το αντίθετο
/// από τη λίστα δίπλα, που δείχνει σωστά «καμία σύνδεση» — και αποθάρρυνε από
/// την επαναποστολή που ο χρήστης μόλις είχε ζητήσει.
String lansweeperEditWarningHeadline({
  String? ticketId,
  bool registered = true,
}) {
  final id = ticketId?.trim() ?? '';
  if (!registered) {
    if (id.isEmpty) {
      return 'Η κλήση δεν είναι σημειωμένη ως καταχωρημένη στο Lansweeper.';
    }
    return 'Η κλήση δεν είναι σημειωμένη ως καταχωρημένη. Κρατείται ο αριθμός '
        'αιτήματος';
  }
  if (id.isEmpty) {
    return 'Η κλήση είναι σημειωμένη ως καταχωρημένη στο Lansweeper.';
  }
  return 'Η κλήση έχει καταχωρηθεί στο Lansweeper — ticket';
}

/// Το κείμενο **μετά** τον αριθμό — μόνο για την ακαταχώρητη με κρατημένο id.
///
/// Λέει το πράγμα που καθορίζει την επόμενη κίνηση: ο φυλαγμένος αριθμός δεν
/// είναι ανάμνηση, είναι οδηγία. Χωρίς αυτόν η επόμενη αποστολή θα άνοιγε
/// **δεύτερο** αίτημα για την ίδια κλήση.
String lansweeperEditWarningTrailing({bool registered = true}) {
  if (registered) return '';
  return ' — η επόμενη αποστολή θα ενημερώσει αυτό το αίτημα αντί να ανοίξει '
      'νέο.';
}

class LansweeperEditWarning extends StatelessWidget {
  const LansweeperEditWarning({
    super.key,
    required this.ticketId,
    required this.ticketViewUrlTemplate,
    required this.onClone,
    required this.cloneBusy,
    this.registered = true,
    this.warnings = const <String>[],
  });

  final String? ticketId;

  /// Μετριέται η κλήση ως καταχωρημένη; `false` όταν επαναφέρθηκε σε
  /// ακαταχώρητη κρατώντας τον αριθμό του αιτήματος.
  final bool registered;

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
    final headline = lansweeperEditWarningHeadline(
      ticketId: id,
      registered: registered,
    );
    // Κόκκινο μόνο για δουλειά που έχει ήδη φύγει και δεν παίρνει πίσω. Η
    // ακαταχώρητη με κρατημένο αριθμό είναι πληροφορία για την επόμενη κίνηση,
    // όχι συναγερμός — και το κόκκινο εκεί αποθάρρυνε την επαναποστολή.
    final accent = registered
        ? theme.colorScheme.error
        : theme.colorScheme.tertiary;
    final surface = registered
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.surfaceContainerHighest;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
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
              trailingText: lansweeperEditWarningTrailing(
                registered: registered,
              ),
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
                    Icon(Icons.warning_amber_rounded, size: 16, color: accent),
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
