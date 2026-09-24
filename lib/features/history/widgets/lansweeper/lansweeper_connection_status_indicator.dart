import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/lansweeper_connection_status.dart';
import '../../providers/lansweeper_connection_probe_provider.dart';

/// Μικρή ένδειξη κατάστασης σύνδεσης Lansweeper (checking / available / unavailable).
///
/// **Είναι και κουμπί:** ένα κλικ ξαναρωτά τον διακομιστή. Χωρίς αυτό, η μόνη
/// διέξοδος από μια κολλημένη ή αποτυχημένη σύνδεση ήταν να κλείσει και να
/// ξανανοίξει ο χειριστής ολόκληρη την Αναφορά.
class LansweeperConnectionStatusIndicator extends ConsumerWidget {
  const LansweeperConnectionStatusIndicator({required this.status, super.key});

  final LansweeperConnectionStatus status;

  bool get _busy => status is LansweeperConnectionChecking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final onSurfaceVariant = theme.colorScheme.onSurfaceVariant;

    final body = DecoratedBox(
      decoration: BoxDecoration(
        color: switch (status) {
          LansweeperConnectionChecking() =>
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          LansweeperConnectionAvailable() => Colors.green.withValues(
            alpha: 0.1,
          ),
          LansweeperConnectionUnavailable() => Colors.red.withValues(
            alpha: 0.1,
          ),
        },
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: switch (status) {
            LansweeperConnectionChecking() =>
              theme.colorScheme.outline.withValues(alpha: 0.35),
            LansweeperConnectionAvailable() => Colors.green.withValues(
              alpha: 0.45,
            ),
            LansweeperConnectionUnavailable() => Colors.red.withValues(
              alpha: 0.45,
            ),
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
                  LansweeperConnectionChecking() =>
                    'Έλεγχος σύνδεσης Lansweeper…',
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
            if (!_busy) ...[
              const SizedBox(width: 6),
              Icon(Icons.refresh_rounded, size: 18, color: onSurfaceVariant),
            ],
          ],
        ),
      ),
    );

    // Όσο τρέχει ο έλεγχος δεν δέχεται δεύτερο: το κλικ θα ακύρωνε τον πρώτο
    // και θα ξεκινούσε τον ίδιο έλεγχο από την αρχή.
    if (_busy) return body;

    return Tooltip(
      message: 'Επανάληψη ελέγχου σύνδεσης',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => unawaited(
          ref.read(lansweeperConnectionProbeProvider.notifier).check(),
        ),
        child: body,
      ),
    );
  }
}
