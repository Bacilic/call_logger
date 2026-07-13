import 'package:flutter/material.dart';

import '../../../core/database/audit_service.dart';

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
  if (a == AuditActions.modifyPhone.toUpperCase()) {
    return (icon: Icons.phone_outlined, color: scheme.primary);
  }
  if (a == AuditActions.modifyCategory.toUpperCase()) {
    return (icon: Icons.category_outlined, color: scheme.primary);
  }
  if (a == AuditActions.modifyEquipment.toUpperCase()) {
    return (icon: Icons.computer_outlined, color: scheme.primary);
  }
  if (a == AuditActions.modifyUser.toUpperCase()) {
    return (icon: Icons.person_outline, color: scheme.primary);
  }
  if (a == AuditActions.modifyDepartment.toUpperCase()) {
    return (icon: Icons.apartment_outlined, color: scheme.primary);
  }
  if (a == AuditActions.modifyCall.toUpperCase()) {
    return (icon: Icons.call_outlined, color: scheme.primary);
  }
  if (a == AuditActions.modifyTask.toUpperCase()) {
    return (icon: Icons.task_alt_outlined, color: scheme.primary);
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
  if (a.contains('ΕΠΙΔΙΟΡΘΩΣΗ') && a.contains('ΑΚΕΡΑΙΟΤΗΤΑΣ')) {
    return (icon: Icons.build_circle_outlined, color: Colors.orange.shade800);
  }
  return (icon: Icons.history, color: scheme.onSurfaceVariant);
}
