import 'package:flutter/foundation.dart';

enum IntegritySeverity { warning, critical }

enum IntegrityCategory {
  searchIndex,
  referential,
  technicalFlow,
  temporal,
}

/// Τύπος διαγνωστικού ελέγχου (1:1 με τα βήματα του [DatabaseIntegrityService]).
enum IntegrityCheckType {
  pragmaQuickCheck,
  orphanPhone,
  phoneInvalidDepartment,
  callsMissingSearchIndex,
  tasksMissingSearchIndex,
  usersWithoutDepartment,
  usersInvalidDepartment,
  tasksInvalidCall,
  departmentsInvalidNameKey,
  departmentInvalidFloor,
  orphanCallExternalLinks,
  orphanUserPhones,
  orphanDepartmentPhones,
  orphanUserEquipment,
  equipmentInvalidDepartment,
  callsDeletedLinkedEntities,
  tasksDeletedLinkedEntities,
  tasksTemporalInconsistency,
  auditMissingSearchText,
}

extension IntegrityCheckTypeLabels on IntegrityCheckType {
  String get displayNameEl => switch (this) {
        IntegrityCheckType.pragmaQuickCheck => 'Έλεγχος SQLite (PRAGMA)',
        IntegrityCheckType.orphanPhone => 'Ορφανά τηλέφωνα',
        IntegrityCheckType.phoneInvalidDepartment =>
          'Τηλέφωνα με ανύπαρκτο τμήμα',
        IntegrityCheckType.callsMissingSearchIndex => 'Κλήσεις χωρίς ευρετήριο',
        IntegrityCheckType.tasksMissingSearchIndex =>
          'Εκκρεμότητες χωρίς ευρετήριο',
        IntegrityCheckType.usersWithoutDepartment => 'Χρήστες χωρίς τμήμα',
        IntegrityCheckType.usersInvalidDepartment =>
          'Χρήστες σε διαγραμμένο/ανύπαρκτο τμήμα',
        IntegrityCheckType.tasksInvalidCall => 'Εκκρεμότητες με άκυρη κλήση',
        IntegrityCheckType.departmentsInvalidNameKey =>
          'Τμήματα χωρίς έγκυρο name_key',
        IntegrityCheckType.departmentInvalidFloor =>
          'Τμήματα με ανύπαρκτο όροφο χάρτη',
        IntegrityCheckType.orphanCallExternalLinks => 'Ορφανά call_external_links',
        IntegrityCheckType.orphanUserPhones =>
          'Ορφανές συσχετίσεις χρήστη–τηλεφώνου',
        IntegrityCheckType.orphanDepartmentPhones => 'Ορφανά department_phones',
        IntegrityCheckType.orphanUserEquipment =>
          'Ορφανές συσχετίσεις χρήστη–εξοπλισμού',
        IntegrityCheckType.equipmentInvalidDepartment =>
          'Εξοπλισμός με ανύπαρκτο τμήμα',
        IntegrityCheckType.callsDeletedLinkedEntities =>
          'Κλήσεις με ανύπαρκτες αναφορές',
        IntegrityCheckType.tasksDeletedLinkedEntities =>
          'Εκκρεμότητες με ανύπαρκτες αναφορές',
        IntegrityCheckType.tasksTemporalInconsistency =>
          'Εκκρεμότητες: created_at > updated_at',
        IntegrityCheckType.auditMissingSearchText => 'Audit χωρίς search_text',
      };
}

@immutable
class DatabaseIntegrityFinding {
  const DatabaseIntegrityFinding({
    required this.severity,
    required this.category,
    required this.checkType,
    required this.title,
    required this.description,
    this.affectedId,
    this.affectedEntity,
    this.context = const {},
  });

  final IntegritySeverity severity;
  final IntegrityCategory category;
  final IntegrityCheckType checkType;
  final String title;
  final String description;
  final int? affectedId;
  final String? affectedEntity;

  /// Μεταδεδομένα για στοχευμένη επιδιόρθωση (junction keys, invalidField κ.λπ.).
  final Map<String, Object?> context;

  /// Μοναδική ταυτότητα ευρήματος για αφαίρεση μετά τη διόρθωση.
  String get findingKey {
    final ctxParts = context.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final ctxStr = ctxParts.map((e) => '${e.key}=${e.value}').join('|');
    return '${checkType.name}|${affectedEntity ?? ''}|${affectedId ?? ''}|$ctxStr';
  }

  DatabaseIntegrityFinding copyWith({
    IntegritySeverity? severity,
    IntegrityCategory? category,
    IntegrityCheckType? checkType,
    String? title,
    String? description,
    int? affectedId,
    String? affectedEntity,
    Map<String, Object?>? context,
  }) {
    return DatabaseIntegrityFinding(
      severity: severity ?? this.severity,
      category: category ?? this.category,
      checkType: checkType ?? this.checkType,
      title: title ?? this.title,
      description: description ?? this.description,
      affectedId: affectedId ?? this.affectedId,
      affectedEntity: affectedEntity ?? this.affectedEntity,
      context: context ?? this.context,
    );
  }
}

@immutable
class DatabaseIntegrityProgress {
  const DatabaseIntegrityProgress({
    required this.currentStep,
    required this.totalSteps,
    required this.currentCheckName,
    required this.totalRowsChecked,
    this.tableScopeLabel,
  });

  final int currentStep;
  final int totalSteps;
  final String currentCheckName;
  final int totalRowsChecked;
  final String? tableScopeLabel;
}
