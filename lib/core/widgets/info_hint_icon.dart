import 'package:flutter/material.dart';

/// Μικρό εικονίδιο πληροφοριών με tooltip περιορισμένου πλάτους (~1/3 οθόνης).
class InfoHintIcon extends StatelessWidget {
  const InfoHintIcon({
    super.key,
    required this.message,
    this.size = 18,
  });

  final String message;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxW = (MediaQuery.sizeOf(context).width / 3).clamp(260.0, 440.0);
    final textStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onInverseSurface,
    );

    return Tooltip(
      waitDuration: const Duration(milliseconds: 300),
      showDuration: const Duration(seconds: 8),
      richMessage: WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: Text(message, style: textStyle),
        ),
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.help,
        child: Icon(
          Icons.info_outline,
          size: size,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
