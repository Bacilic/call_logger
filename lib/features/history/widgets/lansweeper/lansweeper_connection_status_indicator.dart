import 'package:flutter/material.dart';

import '../../models/lansweeper_connection_status.dart';

/// Μικρή ένδειξη κατάστασης σύνδεσης Lansweeper (checking / available / unavailable).
class LansweeperConnectionStatusIndicator extends StatelessWidget {
  const LansweeperConnectionStatusIndicator({
    required this.status,
    super.key,
  });

  final LansweeperConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurfaceVariant = theme.colorScheme.onSurfaceVariant;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: switch (status) {
          LansweeperConnectionChecking() =>
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          LansweeperConnectionAvailable() =>
            Colors.green.withValues(alpha: 0.1),
          LansweeperConnectionUnavailable() => Colors.red.withValues(alpha: 0.1),
        },
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: switch (status) {
            LansweeperConnectionChecking() =>
              theme.colorScheme.outline.withValues(alpha: 0.35),
            LansweeperConnectionAvailable() =>
              Colors.green.withValues(alpha: 0.45),
            LansweeperConnectionUnavailable() =>
              Colors.red.withValues(alpha: 0.45),
          },
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            switch (status) {
              LansweeperConnectionChecking() => SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                ),
              LansweeperConnectionAvailable() => Icon(
                  Icons.check_circle_outline,
                  size: 20,
                  color: Colors.green.shade800,
                ),
              LansweeperConnectionUnavailable() => Icon(
                  Icons.error_outline,
                  size: 20,
                  color: Colors.red.shade800,
                ),
            },
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                switch (status) {
                  LansweeperConnectionChecking() => 'Έλεγχος σύνδεσης Lansweeper…',
                  LansweeperConnectionAvailable() =>
                    'Η σύνδεση με το Lansweeper είναι διαθέσιμη.',
                  LansweeperConnectionUnavailable(:final reason) => reason,
                },
                style: theme.textTheme.bodySmall?.copyWith(
                  color: switch (status) {
                    LansweeperConnectionChecking() => onSurfaceVariant,
                    LansweeperConnectionAvailable() => Colors.green.shade900,
                    LansweeperConnectionUnavailable() => Colors.red.shade900,
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
