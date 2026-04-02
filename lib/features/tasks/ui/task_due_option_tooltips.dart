import 'package:flutter/material.dart';

String _formatHm(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Κείμενα υπόδειξης (Tooltip) για τις επιλογές προεπιλεγμένης ή γρήγορης λήξης.
abstract final class TaskDueOptionTooltips {
  static String formatHm(TimeOfDay t) => _formatHm(t);

  /// +1 ώρα — νέα εκκρεμότητα ή αναβολή (ίδιος υπολογισμός).
  static String plusOneHour() =>
      'Όποια ώρα κι αν δημιουργηθεί η εκκρεμότητα ή εφαρμοστεί αναβολή, η λήξη '
      'μετατίθεται κατά μία ώρα μετά τη στιγμή αναφοράς.';

  /// «Μέσα στο ωράριο» — [start] = έναρξη ωραρίου, [end] = τελευταία εκκρεμότητα.
  static String withinSchedule(TimeOfDay start, TimeOfDay end) {
    final a = _formatHm(start);
    final b = _formatHm(end);
    return 'Κατά τη δημιουργία νέας εκκρεμότητας ή την αναβολή υπάρχουσας: αν η '
        'στιγμή αναφοράς είναι από τις $a έως τις $b (συμπεριλαμβανομένων), η λήξη '
        'μετατίθεται κατά μία ώρα. Διαφορετικά, η λήξη ορίζεται για την επόμενη '
        'εργάσιμη ημέρα στις $a.';
  }

  /// Επόμενη εργάσιμη στην ώρα έναρξης ωραρίου.
  static String nextBusiness(TimeOfDay start) {
    final a = _formatHm(start);
    return 'Η λήξη ορίζεται για την επόμενη εργάσιμη ημέρα στις $a.';
  }
}
