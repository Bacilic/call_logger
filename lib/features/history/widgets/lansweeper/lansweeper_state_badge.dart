import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/lansweeper_sync_state.dart';
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
    final ticketUrl = state == LansweeperSyncState.sent &&
            normalizedTicket.isNotEmpty
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

    final statusChip =
        tooltip == null ? chip : Tooltip(message: tooltip, child: chip);

    if (inline) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          statusChip,
          if (ticketUrl != null) ...[
            const SizedBox(width: 4),
            _TicketIdLink(
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
          _TicketIdLink(
            ticketId: normalizedTicket,
            url: ticketUrl,
            enabled: ticketLinkEnabled,
          ),
        ],
      ],
    );
  }
}

class _TicketIdLink extends StatelessWidget {
  const _TicketIdLink({
    required this.ticketId,
    required this.url,
    this.enabled = true,
  });

  final String ticketId;
  final String url;
  final bool enabled;

  static const String _disabledTooltip =
      'Δεν είναι εφυκτή η σύνδεση με το Lansweeper.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final linkColor = enabled
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface.withValues(alpha: 0.45);
    final tooltip = enabled
        ? 'Άνοιγμα ticket #$ticketId στον περιηγητή'
        : _disabledTooltip;

    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: InkWell(
          onTap: enabled
              ? () => unawaited(
                  launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                )
              : null,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
            child: Text(
              '#$ticketId',
              style: theme.textTheme.labelSmall?.copyWith(
                color: linkColor,
                decoration: enabled ? TextDecoration.underline : null,
                decorationColor: linkColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
