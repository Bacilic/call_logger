import 'package:flutter/material.dart';

import '../../models/lansweeper_sync_state.dart';
import 'lansweeper_ticket_link.dart';
import 'lansweeper_url_rules.dart';

/// Στήλη κατάστασης Lansweeper: chip κατάστασης και προαιρετικός σύνδεσμος ticket.
class LansweeperStateBadge extends StatelessWidget {
  const LansweeperStateBadge({
    required this.state,
    this.ticketId,
    this.ticketViewUrlTemplate,
    this.onPressed,
    this.inline = false,
    this.ticketLinkEnabled = true,
    super.key,
  });

  final String state;
  final String? ticketId;
  final String? ticketViewUrlTemplate;
  final VoidCallback? onPressed;

  /// Σε [true], το chip εμφανίζεται οριζόντια (δίπλα σε ημερομηνία/διάρκεια).
  final bool inline;

  /// Όταν [false], ο σύνδεσμος ticket είναι αδρανής (χωρίς σύνδεση Lansweeper).
  final bool ticketLinkEnabled;

  @override
  Widget build(BuildContext context) {
    final label = switch (state) {
      LansweeperSyncState.sent => 'Καταχωρημένη',
      LansweeperSyncState.excluded => 'Εξαιρεσμένη',
      LansweeperSyncState.failed => 'Αποτυχημένη',
      _ => 'Ακαταχώρητη',
    };
    final color = switch (state) {
      LansweeperSyncState.sent => Colors.green,
      LansweeperSyncState.excluded => Colors.orange,
      LansweeperSyncState.failed => Colors.red,
      _ => Colors.blueGrey,
    };
    final normalizedTicket = (ticketId ?? '').trim();
    final ticketUrl =
        state == LansweeperSyncState.sent && normalizedTicket.isNotEmpty
        ? LansweeperUrlRules.buildTicketViewUrl(
            ticketViewUrlTemplate ?? '',
            normalizedTicket,
          )
        : null;
    final tooltip = onPressed == null
        ? null
        : state == LansweeperSyncState.sent
        ? 'Κλικ για ακαταχώρητη'
        : normalizedTicket.isNotEmpty
        ? 'Αποθηκευμένο ticket #$normalizedTicket — κλικ για καταχώρηση'
        : 'Κλικ για καταχώρηση';

    final chip = ActionChip(
      label: Text(label),
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      labelStyle: TextStyle(
        color: Color.alphaBlend(Colors.black.withValues(alpha: 0.55), color),
        fontSize: 12,
      ),
      onPressed: onPressed,
    );

    final statusChip = tooltip == null
        ? chip
        : Tooltip(message: tooltip, child: chip);

    if (inline) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          statusChip,
          if (ticketUrl != null) ...[
            const SizedBox(width: 4),
            LansweeperTicketLink(
              ticketId: normalizedTicket,
              url: ticketUrl,
              enabled: ticketLinkEnabled,
            ),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        statusChip,
        if (ticketUrl != null) ...[
          const SizedBox(height: 2),
          LansweeperTicketLink(
            ticketId: normalizedTicket,
            url: ticketUrl,
            enabled: ticketLinkEnabled,
          ),
        ],
      ],
    );
  }
}
