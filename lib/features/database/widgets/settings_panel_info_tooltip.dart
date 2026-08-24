import 'package:flutter/material.dart';

/// Στενό tooltip (i) που μένει εντός του διαλόγου ρυθμίσεων βάσης.
class SettingsPanelInfoTooltip extends StatelessWidget {
  const SettingsPanelInfoTooltip({
    super.key,
    required this.message,
    required this.iconColor,
    this.maxWidth = 280,
  });

  final String message;
  final Color iconColor;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: message,
      constraints: BoxConstraints(maxWidth: maxWidth),
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      preferBelow: false,
      verticalOffset: 10,
      waitDuration: const Duration(milliseconds: 350),
      showDuration: const Duration(seconds: 8),
      textStyle: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onInverseSurface,
        height: 1.4,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.inverseSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(Icons.info_outline, size: 18, color: iconColor),
      ),
    );
  }
}
