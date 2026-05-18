import 'package:flutter/material.dart';

import '../../models/lansweeper_sync_state.dart';

class LansweeperStateBadge extends StatelessWidget {
  const LansweeperStateBadge({
    required this.state,
    this.ticketId,
    this.onPressed,
    super.key,
  });

  final String state;
  final String? ticketId;
  final VoidCallback? onPressed;

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
    final ticketSuffix = normalizedTicket.isNotEmpty
        ? ' • #$normalizedTicket'
        : '';
    final tooltip = onPressed == null
        ? null
        : state == LansweeperSyncState.sent
        ? 'Κλικ για ακαταχώρητη'
        : normalizedTicket.isNotEmpty
        ? 'Αποθηκευμένο ticket #$normalizedTicket — κλικ για καταχώρηση'
        : 'Κλικ για καταχώρηση';

    final chip = ActionChip(
      label: Text('$label$ticketSuffix'),
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

    if (tooltip == null) return chip;
    return Tooltip(message: tooltip, child: chip);
  }
}
