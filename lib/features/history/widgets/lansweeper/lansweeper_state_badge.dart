import 'package:flutter/material.dart';

import '../../models/lansweeper_sync_state.dart';

class LansweeperStateBadge extends StatelessWidget {
  const LansweeperStateBadge({
    required this.state,
    this.hasTicket = false,
    super.key,
  });

  final String state;
  final bool hasTicket;

  @override
  Widget build(BuildContext context) {
    final label = switch (state) {
      LansweeperSyncState.sent => 'Περασμένη',
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
    final suffix = hasTicket ? ' • Ticket' : '';
    return Chip(
      label: Text('$label$suffix'),
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      visualDensity: VisualDensity.compact,
    );
  }
}
