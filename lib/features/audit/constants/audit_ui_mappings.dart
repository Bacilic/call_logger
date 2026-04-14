import 'package:flutter/material.dart';

/// Εικονίδιο + χρώμα ανά ενέργεια (εμφάνιση λίστας).
({IconData icon, Color? color}) auditStyleForAction(
  String? action,
  ColorScheme scheme,
) {
  final a = action?.trim().toUpperCase() ?? '';
  if (a.contains('ΔΙΑΓΡΑΦΗ') || a.contains('ΜΑΖΙΚΗ')) {
    return (icon: Icons.delete_outline, color: scheme.error);
  }
  if (a.contains('ΕΠΑΝΑΦΟΡΑ')) {
    return (icon: Icons.restore, color: Colors.teal);
  }
  if (a.contains('ΤΡΟΠΟΠΟΙΗΣΗ') || a.contains('UPDATE')) {
    return (icon: Icons.edit_note, color: scheme.primary);
  }
  if (a.contains('ΔΗΜΙΟΥΡΓΙΑ') || a.contains('CREATE')) {
    return (icon: Icons.add_circle_outline, color: Colors.green.shade700);
  }
  if (a.contains('ΣΥΣΧ') && a.contains('ΚΛΗΣΗ')) {
    return (icon: Icons.link, color: scheme.primary);
  }
  return (icon: Icons.history, color: scheme.onSurfaceVariant);
}
