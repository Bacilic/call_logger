import 'dart:math' as math;

import 'package:flutter/material.dart';

String _formatHm(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Κείμενα υπόδειξης (Tooltip) για τις επιλογές προεπιλεγμένης ή γρήγορης λήξης.
abstract final class TaskDueOptionTooltips {
  static String formatHm(TimeOfDay t) => _formatHm(t);

  /// +1 ώρα — νέα εκκρεμότητα ή αναβολή (ίδιος υπολογισμός).
  static String plusOneHour() =>
      'Η λήξη ορίζεται μία ώρα μετά τη στιγμή δημιουργίας ή αναβολής της '
      'εκκρεμότητας.';

  /// «Μέσα στο ωράριο» — [start] = έναρξη ωραρίου, [end] = τελευταία εκκρεμότητα.
  static String withinSchedule(TimeOfDay start, TimeOfDay end) {
    final a = _formatHm(start);
    final b = _formatHm(end);
    return 'Αν η στιγμή δημιουργίας ή αναβολής είναι από $a έως $b, η λήξη '
        'μετατίθεται κατά μία ώρα. Εκτός ωραρίου, μεταφέρεται στην επόμενη '
        'εργάσιμη στις $a.';
  }

  /// Επόμενη εργάσιμη στην ώρα έναρξης ωραρίου.
  static String nextBusiness(TimeOfDay start) {
    final a = _formatHm(start);
    return 'Η λήξη ορίζεται για την επόμενη εργάσιμη ημέρα στις $a.';
  }
}

/// Συμπαγής υπόδειξη για τις επιλογές λήξης μέσα στη φόρμα ρυθμίσεων.
class TaskDueOptionTooltip extends StatelessWidget {
  const TaskDueOptionTooltip({
    super.key,
    required this.message,
    required this.child,
  });

  final String message;
  final Widget child;

  double _maxTooltipWidth(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    return math.min(360, math.max(220, screenWidth * 0.32));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: message,
      constraints: BoxConstraints(maxWidth: _maxTooltipWidth(context)),
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      preferBelow: false,
      verticalOffset: 12,
      waitDuration: const Duration(milliseconds: 250),
      showDuration: const Duration(seconds: 6),
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
