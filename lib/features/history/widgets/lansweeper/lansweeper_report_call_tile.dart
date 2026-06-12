import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    final bodyText = (details ?? '').trim().isNotEmpty
        ? '$notes\n${details!.trim()}'
        : notes;

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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$dateLabel • $durationLabel'),
                      if (bodyText.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          bodyText,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                LansweeperStateBadge(
                  state: lansweeperState,
                  ticketId: ticketId,
                  ticketViewUrlTemplate: ticketViewUrlTemplate,
                  onPressed: isSyncLoading ? null : onBadgePressed,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
