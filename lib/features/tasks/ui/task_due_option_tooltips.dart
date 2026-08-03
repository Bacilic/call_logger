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

