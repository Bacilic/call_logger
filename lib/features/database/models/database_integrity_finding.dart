import 'package:flutter/foundation.dart';

enum IntegritySeverity { warning, critical }

enum IntegrityCategory {
  searchIndex,
  referential,
  technicalFlow,
  temporal,
}

@immutable
class DatabaseIntegrityFinding {
  const DatabaseIntegrityFinding({
    required this.severity,
    required this.category,
    required this.title,
    required this.description,
    this.affectedId,
    this.affectedEntity,
  });

  final IntegritySeverity severity;
  final IntegrityCategory category;
  final String title;
  final String description;
  final int? affectedId;
  final String? affectedEntity;
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
