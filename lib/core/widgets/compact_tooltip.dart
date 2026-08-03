import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Κοινό πρότυπο υπόδειξης (Tooltip) με **περιορισμένο πλάτος**.
///
/// Το σκέτο [Tooltip] του framework απλώνεται σε όλο το πλάτος της οθόνης όταν
/// το κείμενο είναι μεγάλο — μια πρόταση γίνεται μονόγραμμη λωρίδα αδιάβαστη.
/// Κάθε υπόδειξη με κείμενο πρότασης ή μεγαλύτερο περνά από εδώ.
class CompactTooltip extends StatelessWidget {
  const CompactTooltip({
    super.key,
    required this.message,
    required this.child,
    this.waitDuration = const Duration(milliseconds: 250),
    this.showDuration = const Duration(seconds: 6),
  });

  final String message;
  final Widget child;
  final Duration waitDuration;
  final Duration showDuration;

  /// Πλάτος δεμένο στην οθόνη: ποτέ κάτω από 220, ποτέ πάνω από 360.
  static double maxWidthFor(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    return math.min(360, math.max(220, screenWidth * 0.32));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: message,
      constraints: BoxConstraints(maxWidth: maxWidthFor(context)),
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      preferBelow: false,
      verticalOffset: 12,
      waitDuration: waitDuration,
      showDuration: showDuration,
      textStyle: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onInverseSurface,
        height: 1.35,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.inverseSurface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }
}
