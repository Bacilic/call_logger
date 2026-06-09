import '../models/database_integrity_finding.dart';
import '../models/integrity_fix_models.dart';

/// Ανθρώπινα αναγνώσιμα `details` και old/new values για audit επιδιορθώσεων.
class IntegrityAuditDetailsBuilder {
  const IntegrityAuditDetailsBuilder();

  String userLabel({
    required int? id,
    String? firstName,
    String? lastName,
    bool deleted = false,
  }) {
    if (id == null) return 'άγνωστος υπάλληλος';
    final parts = <String>[
      if (lastName != null && lastName.trim().isNotEmpty) lastName.trim(),
      if (firstName != null && firstName.trim().isNotEmpty) firstName.trim(),
    ];
    final name = parts.join(' ');
    final status = deleted ? ' [Διαγραμμένο]' : ' [Ενεργό]';
    if (name.isNotEmpty) return '$name (ID $id)$status';
    return 'Υπάλληλος ID $id$status';
  }

  String departmentLabel({
    required int? id,
    String? name,
    bool deleted = false,
  }) {
    if (id == null) return 'άγνωστο τμήμα';
    final status = deleted ? ' [Διαγραμμένο]' : ' [Ενεργό]';
    final trimmed = name?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return 'Τμήμα $trimmed (ID $id)$status';
    }
    return 'Τμήμα ID $id$status';
  }

  String equipmentLabel({required int? id, String? code, bool deleted = false}) {
    if (id == null) return 'άγνωστος εξοπλισμός';
    final status = deleted ? ' [Διαγραμμένο]' : ' [Ενεργό]';
    final trimmed = code?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return '$trimmed (ID $id)$status';
    }
    return 'Εξοπλισμός ID $id$status';
  }

  String phoneLabel({required int? id, String? number}) {
    if (id == null) return 'άγνωστο τηλέφωνο';
    final trimmed = number?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return '$trimmed (ID $id)';
    }
    return 'Τηλέφωνο ID $id';
  }

  String categoryLabel({required int? id, String? name, bool deleted = false}) {
    if (id == null) return 'άγνωστη κατηγορία';
    final status = deleted ? ' [Διαγραμμένο]' : ' [Ενεργό]';
    final trimmed = name?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return '«$trimmed» (ID $id)$status';
    }
    return 'Κατηγορία ID $id$status';
  }

  ({String details, Map<String, dynamic> oldValues, Map<String, dynamic> newValues})
      userDepartmentChange({
    required String userLabel,
    required String? oldDepartmentLabel,
    required String? newDepartmentLabel,
    int? oldDepartmentId,
    int? newDepartmentId,
  }) {
    final oldText = oldDepartmentLabel ?? '—';
    final newText = newDepartmentLabel ?? '—';
    return (
      details: 'Μεταφορά $userLabel από $oldText στο $newText',
      oldValues: {
        'department_id': oldDepartmentId,
        'department_label': oldText,
      },
      newValues: {
        'department_id': newDepartmentId,
        'department_label': newText,
      },
    );
  }

  ({String details, Map<String, dynamic> oldValues, Map<String, dynamic> newValues})
      junctionCleanup({
    required DatabaseIntegrityFinding finding,
  }) {
    return (
      details: 'Εκκαθάριση ορφανής σύνδεσης: ${finding.description}',
      oldValues: Map<String, dynamic>.from(finding.context),
      newValues: const {'removed': true},
    );
  }

  ({String details, Map<String, dynamic> oldValues, Map<String, dynamic> newValues})
      fkChange({
    required String entityLabel,
    required String fieldLabel,
    required Object? oldValue,
    required Object? newValue,
    required String actionDescription,
  }) {
    return (
      details: '$actionDescription ($entityLabel · $fieldLabel)',
      oldValues: {fieldLabel: oldValue},
      newValues: {fieldLabel: newValue},
    );
  }

  ({String details, Map<String, dynamic> oldValues, Map<String, dynamic> newValues})
      simpleAction({
    required String details,
    Map<String, dynamic>? oldValues,
    Map<String, dynamic>? newValues,
  }) {
    return (
      details: details,
      oldValues: oldValues ?? const {},
      newValues: newValues ?? const {},
    );
  }

  String orphanPhoneActionDescription(IntegrityFixDecision decision) {
    return switch (decision) {
      IntegrityFixSoftDeletePhone() => 'Διαγραφή ορφανού τηλεφώνου',
      IntegrityFixLinkPhoneToDepartment(:final departmentId) =>
        'Σύνδεση ορφανού τηλεφώνου με τμήμα (ID $departmentId)',
      IntegrityFixLinkPhoneToUser(:final userId) =>
        'Σύνδεση ορφανού τηλεφώνου με υπάλληλο (ID $userId)',
      _ => 'Επιδιόρθωση ορφανού τηλεφώνου',
    };
  }
}
