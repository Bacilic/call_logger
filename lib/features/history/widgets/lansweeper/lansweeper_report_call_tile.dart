import 'package:flutter/material.dart';

import '../../../../core/widgets/linkable_text.dart';
import 'lansweeper_report_row_metrics.dart';
import 'lansweeper_state_badge.dart';

/// Μία γραμμή κλήσης στη λίστα αναφοράς Lansweeper (checkbox, μεταδεδομένα, κατάσταση).
class LansweeperReportCallTile extends StatelessWidget {
  const LansweeperReportCallTile({
    required this.checked,
    required this.onCheckedChanged,
    required this.dateLabel,
    required this.durationLabel,
    required this.lansweeperState,
    this.tooltip,
    this.inlineMeta,
    this.ticketId,
    required this.ticketViewUrlTemplate,
    required this.notes,
    this.solution = '',
    required this.isSyncLoading,
    required this.onBadgePressed,
    this.ticketLinkEnabled = true,
    this.bodyHeight,
    super.key,
  });

  final bool checked;
  final ValueChanged<bool?> onCheckedChanged;
  final String dateLabel;
  final String durationLabel;

  /// Πλήρη στοιχεία της κλήσης, στην υπόδειξη της χρονοσφραγίδας.
  final String? tooltip;

  /// Μεταδεδομένα που δεν ανέβηκαν στην κεφαλίδα της ομάδας (εξοπλισμός, και
  /// τμήμα όταν η ομάδα δεν έχει κοινό).
  final String? inlineMeta;

  final String lansweeperState;
  final String? ticketId;
  final String ticketViewUrlTemplate;
  final String notes;

  /// Απόσπασμα της Λύσης· κενό σημαίνει «εκκρεμεί» και δεν πιάνει χώρο.
  final String solution;

  final bool isSyncLoading;
  final VoidCallback? onBadgePressed;
  final bool ticketLinkEnabled;

  /// Το ύψος που δεσμεύει το κείμενο, μετρημένο από τη λίστα.
  ///
  /// Έρχεται απ' έξω επίτηδες: η λίστα το χρειάζεται ήδη για να πει στον
  /// κύλινδρο πόσο ψηλή είναι η κάρτα, και ένας δεύτερος υπολογισμός εδώ θα
  /// μπορούσε να διαφωνήσει με τον πρώτο. `null` σημαίνει «όσο χρειάζεται».
  final double? bodyHeight;

  @override
  Widget build(BuildContext context) {
    // Τα μεταδεδομένα κάποτε κολλούσαν στο τέλος της Περιγραφής και
    // μοιράζονταν το ίδιο όριο γραμμών: όποτε η περιγραφή ήταν μεγάλη,
    // εξοπλισμός και τμήμα κόβονταν σιωπηλά. Πλέον ζουν στη δική τους θέση,
    // πάνω, και το κείμενο κρατά μόνο όσο χώρο του χρειάζεται.
    final notesStyle = Theme.of(context).textTheme.bodySmall;
    final timestampText = Text(
      '$dateLabel • $durationLabel',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: notesStyle,
    );
    final tooltipMessage = (tooltip ?? '').trim();
    final timestamp = tooltipMessage.isEmpty
        ? timestampText
        : Tooltip(
            message: tooltipMessage,
            waitDuration: const Duration(milliseconds: 400),
            showDuration: const Duration(seconds: 6),
            child: timestampText,
          );
    final bodyStyle = notesStyle?.copyWith(height: 1.25);
    final trimmedSolution = solution.trim();
    final bodyLines = <Widget>[
      if (notes.trim().isNotEmpty)
        LinkableText(
          text: notes,
          maxLines: LansweeperReportRowMetrics.maxIssueLines,
          overflow: TextOverflow.ellipsis,
          style: bodyStyle,
        ),
      if (trimmedSolution.isNotEmpty)
        LinkableText(
          text: trimmedSolution,
          maxLines: LansweeperReportRowMetrics.maxSolutionLines,
          overflow: TextOverflow.ellipsis,
          // Η Λύση ξεχωρίζει από την Περιγραφή με το χρώμα της κατάστασης
          // «λύθηκε»: δύο κείμενα στη σειρά χωρίς διάκριση διαβάζονται ως ένα.
          style: bodyStyle?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
    ];
    final Widget? notesBlock = bodyLines.isEmpty
        ? null
        : SizedBox(
            height: bodyHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: bodyLines,
            ),
          );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            value: checked,
            onChanged: onCheckedChanged,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Και τα δύο κείμενα υποχωρούν σε στενό παράθυρο: η
                    // χρονοσφραγίδα ελαστικά, τα μεταδεδομένα γεμίζοντας ό,τι
                    // περισσεύει ώστε η κατάσταση να μένει δεξιά. Σταθερό
                    // πλάτος εδώ σημαίνει σφάλμα διάταξης μόλις στενέψει η
                    // λίστα — ό,τι κόβεται το λέει ούτως ή άλλως η υπόδειξη.
                    Flexible(child: timestamp),
                    if (inlineMeta != null) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.computer_outlined,
                        size: 13,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          inlineMeta!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ] else
                      const Spacer(),
                    const SizedBox(width: 6),
                    LansweeperStateBadge(
                      state: lansweeperState,
                      ticketId: ticketId,
                      ticketViewUrlTemplate: ticketViewUrlTemplate,
                      onPressed: isSyncLoading ? null : onBadgePressed,
                      inline: true,
                      ticketLinkEnabled: ticketLinkEnabled,
                    ),
                  ],
                ),
                if (notesBlock != null) ...[
                  const SizedBox(height: 2),
                  notesBlock,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
