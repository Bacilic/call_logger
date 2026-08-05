// Κοινά δομικά των δύο διαλόγων διαγραφής κλήσης (ατομικού και μαζικού).
//
// Ζουν χωριστά ώστε οι δύο διάλογοι να δείχνουν τις ίδιες συνδέσεις με τον ίδιο
// τρόπο: όσο ο καθένας έχτιζε τη δική του εκδοχή, ο ένας μιλούσε για εισιτήρια
// και ο άλλος σιωπούσε.

import 'package:flutter/material.dart';

import '../../../core/database/call_deletion_impact.dart';
import '../services/call_deletion_messages.dart';

/// Ύψος της κυλιόμενης λίστας συνδέσεων στη μαζική διαγραφή.
const double _kMaxRowsHeight = 260;

/// Τι κρέμεται από **μία** κλήση — στο πρότυπο της διαγραφής εξοπλισμού.
///
/// Ορατή από τη στιγμή που ανοίγει ο διάλογος, όχι μόνο όταν ζητηθεί οριστική
/// διαγραφή: ο χρήστης αποφασίζει **αν** θα διαγράψει με βάση το τι είναι η
/// κλήση, κι αυτό δεν αλλάζει με τη θέση ενός διακόπτη.
class CallConnectionsCard extends StatelessWidget {
  const CallConnectionsCard({super.key, required this.impact});

  final CallDeletionImpact impact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lansweeperLine = callLansweeperConnectionLine(impact);
    final tasksLine = callTasksConnectionLine(impact);
    final overflowLine = callTaskTitlesOverflowLine(impact);
    final mutedStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (lansweeperLine != null)
              Text(lansweeperLine, style: theme.textTheme.bodyMedium),
            if (tasksLine != null) ...[
              if (lansweeperLine != null) const SizedBox(height: 8),
              Text(tasksLine, style: theme.textTheme.bodyMedium),
              for (final title in callTaskTitleLines(impact))
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 12),
                  child: Text('• $title', style: mutedStyle),
                ),
              if (overflowLine != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 12),
                  child: Text(overflowLine, style: mutedStyle),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Ποια από τις επιλεγμένες κλήσεις κρύβει τι — μία γραμμή ανά κλήση.
///
/// Απαριθμεί **μόνο** τις κλήσεις που έχουν κάτι να δείξουν. Με 200 επιλεγμένες
/// κλήσεις όπου πέντε έχουν εισιτήριο, μια πλήρης λίστα θα έθαβε τις πέντε σε
/// γραμμές «χωρίς συνδέσεις» — και αυτές ακριβώς είναι το ερώτημα.
class CallConnectionRowsList extends StatelessWidget {
  const CallConnectionRowsList({super.key, required this.impact});

  final CallDeletionImpact impact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = callConnectionRows(impact);
    final overflowLine = callConnectionRowsOverflowLine(impact);
    final mutedStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: _kMaxRowsHeight),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: rows.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 132,
                        child: Text(
                          callConnectionRowTimestamp(rows[index]),
                          style: mutedStyle,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          callConnectionRowLabel(rows[index]),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (overflowLine != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(overflowLine, style: mutedStyle),
              ),
          ],
        ),
      ),
    );
  }
}

/// Μία επιλογή διαγραφής: τι κάνει στον τίτλο, τι ακριβώς σημαίνει από κάτω.
///
/// Ζει μέσα στο σώμα του διαλόγου και όχι στη γραμμή ενεργειών, γιατί εκεί δεν
/// χωράει δεύτερη γραμμή κειμένου — και χωρίς αυτήν ο χρήστης καλείται να
/// μαντέψει τη διαφορά ανάμεσα σε δύο κουμπιά που μοιάζουν.
class CallDeletionChoiceButton extends StatelessWidget {
  const CallDeletionChoiceButton({
    super.key,
    required this.label,
    required this.hint,
    required this.onPressed,
    this.emphasized = false,
  });

  final String label;
  final String hint;
  final VoidCallback? onPressed;

  /// Η προτεινόμενη επιλογή παίρνει γεμάτο κουμπί· η άλλη μένει τονικό.
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = ButtonStyle(
      alignment: Alignment.centerLeft,
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
    );
    final child = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: theme.textTheme.labelLarge),
        const SizedBox(height: 2),
        Text(hint, style: theme.textTheme.bodySmall),
      ],
    );
    return emphasized
        ? FilledButton(onPressed: onPressed, style: style, child: child)
        : FilledButton.tonal(onPressed: onPressed, style: style, child: child);
  }
}
