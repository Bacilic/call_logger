import 'package:flutter/material.dart';

/// Κάρτα ενότητας στον διάλογο «Ρυθμίσεις Lansweeper»:
/// εικονίδιο + τίτλος (+ προαιρετικό trailing) και περιεχόμενο.
class LansweeperSettingsCard extends StatelessWidget {
  const LansweeperSettingsCard({
    required this.icon,
    required this.title,
    required this.children,
    this.trailing,
    super.key,
  });

  final IconData icon;
  final String title;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Material (όχι DecoratedBox): τα ListTile/διακόπτες μέσα στην κάρτα
    // ζωγραφίζουν φόντο και splashes στο πλησιέστερο Material.
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Πλαίσιο αποτελέσματος ελέγχου (πράσινο = επιτυχία, κόκκινο = αποτυχία).
class LansweeperProbeResultBanner extends StatelessWidget {
  const LansweeperProbeResultBanner({
    required this.ok,
    required this.message,
    super.key,
  });

  final bool ok;
  final String message;

  @override
  Widget build(BuildContext context) {
    final accent = ok ? Colors.green : Colors.red;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              ok ? Icons.check_circle_outline : Icons.error_outline,
              color: ok ? Colors.green.shade800 : Colors.red.shade800,
              size: 22,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
