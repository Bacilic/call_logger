import 'package:flutter/material.dart';

import '../../../../core/services/lansweeper_link_crosscheck.dart';

/// Ρωτά τι να γίνει όταν η άλλη άκρη του δεσμού κρατά ήδη αίτημα.
///
/// **Ένας διάλογος για τις δύο κατευθύνσεις.** Το κείμενο αλλάζει μόνο στο
/// ποια οντότητα κατονομάζεται· οι επιλογές είναι οι ίδιες, γιατί η απόφαση
/// είναι η ίδια: ένα αίτημα για τη δουλειά, ή δύο.
///
/// Επιστρέφει `null` αν ο διάλογος έκλεισε χωρίς επιλογή — ο καλών το
/// αντιμετωπίζει ως ακύρωση.
Future<LansweeperLinkChoice?> showLansweeperLinkChoiceDialog(
  BuildContext context, {
  required LansweeperLinkFinding finding,
  required bool canOpenInBrowser,
}) {
  final subject = switch (finding.side) {
    LansweeperLinkSide.call => 'Η εκκρεμότητα συνδέεται με',
    LansweeperLinkSide.task => 'Η κλήση συνδέεται με',
  };

  return showDialog<LansweeperLinkChoice>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.link_rounded),
          SizedBox(width: 10),
          Expanded(child: Text('Υπάρχει ήδη αίτημα στον δεσμό')),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Text(
          '$subject ${finding.label}, που έχει ήδη σταλεί στο Lansweeper '
          'ως αίτημα #${finding.ticketId}.\n\n'
          'Θέλετε η δουλειά αυτή να μπει στο ίδιο αίτημα, ή να ανοίξει '
          'ξεχωριστό;',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(LansweeperLinkChoice.cancel),
          child: const Text('Άκυρο'),
        ),
        if (canOpenInBrowser)
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(LansweeperLinkChoice.openExisting),
            child: Text('Άνοιγμα του #${finding.ticketId}'),
          ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(LansweeperLinkChoice.attachToExisting),
          child: Text('Σημείωση στο #${finding.ticketId}'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(LansweeperLinkChoice.createNew),
          child: const Text('Νέο, ξεχωριστό αίτημα'),
        ),
      ],
    ),
  );
}
