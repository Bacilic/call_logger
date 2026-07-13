import 'package:flutter/material.dart';

import '../../../../core/widgets/linkable_text.dart';
import 'lansweeper_state_badge.dart';

/// Μία γραμμή κλήσης στη λίστα αναφοράς Lansweeper (checkbox, μεταδεδομένα, κατάσταση).
class LansweeperReportCallTile extends StatelessWidget {
  const LansweeperReportCallTile({
    required this.checked,
    required this.onCheckedChanged,
    required this.dateLabel,
    required this.durationLabel,
    required this.lansweeperState,
    this.ticketId,
    required this.ticketViewUrlTemplate,
    required this.notes,
    this.details,
    required this.isSyncLoading,
    required this.onBadgePressed,
    this.ticketLinkEnabled = true,
    this.fixedNotesHeight = false,
    super.key,
  });

  final bool checked;
  final ValueChanged<bool?> onCheckedChanged;
  final String dateLabel;
  final String durationLabel;
  final String lansweeperState;
  final String? ticketId;
  final String ticketViewUrlTemplate;
  final String notes;
  final String? details;
  final bool isSyncLoading;
  final VoidCallback? onBadgePressed;
  final bool ticketLinkEnabled;
  final bool fixedNotesHeight;

  @override
  Widget build(BuildContext context) {
    final bodyText = (details ?? '').trim().isNotEmpty
        ? '$notes\n${details!.trim()}'
        : notes;
    final notesStyle = Theme.of(context).textTheme.bodySmall;
    final notesBlock = fixedNotesHeight
        ? SizedBox(
            height: 42,
            child: LinkableText(
              text: bodyText,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: notesStyle?.copyWith(height: 1.25),
            ),
          )
        : bodyText.trim().isEmpty
        ? null
        : LinkableText(
            text: bodyText,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: notesStyle,
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
                    Expanded(
                      child: Text(
                        '$dateLabel • $durationLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
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
