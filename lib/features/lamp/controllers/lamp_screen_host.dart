// Συμβόλαιο πρόσβασης στην κατάσταση της οθόνης Λάμπας για controllers και dialogs.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/old_database/lamp_issue_resolution_service.dart';
import '../../../core/database/old_database/lamp_old_db_validator.dart';
import '../../../core/database/old_database/lamp_settings_store.dart';
import '../../../core/database/old_database/old_equipment_repository.dart';
import '../../../core/database/old_database/old_excel_importer.dart';
import '../services/lamp_migration_service.dart';
import '../widgets/lamp_result_card.dart';

/// Κοινή κατάσταση και υπηρεσίες που μοιράζονται οι controllers της Λάμπας.
class LampScreenShared {
  LampScreenShared({
    required this.settings,
    required this.repository,
    required this.issueResolutionService,
    required this.migrationService,
    required this.importer,
  });

  final LampSettingsStore settings;
  final OldEquipmentRepository repository;
  final LampIssueResolutionService issueResolutionService;
  final LampMigrationService migrationService;
  final OldExcelImporter importer;
}

/// Διεπαφή πρόσβασης στην οθόνη για callbacks UI (snackbar, dialogs, setState).
abstract class LampScreenHost {
  BuildContext get context;

  WidgetRef get ref;

  bool get mounted;

  void notifyState();

  void showSnack(
    String message, {
    bool isError = false,
    Duration duration = const Duration(seconds: 5),
  });

  Future<void> showLampErrorDialog(String message);

  LampOldDbCheckResult? get readPathCheck;

  bool get lampSettingsDialogOpen;

  set lampSettingsDialogOpen(bool value);

  StateSetter? get lampSettingsDialogSetState;

  set lampSettingsDialogSetState(StateSetter? value);

  String? get lampDialogFeedback;

  set lampDialogFeedback(String? value);

  bool get lampDialogFeedbackIsError;

  set lampDialogFeedbackIsError(bool value);

  void clearLampDialogFeedback();

  void setLampDialogFeedback(String message, {bool isError = false});

  Future<void> runLiveSearch();

  Future<void> loadIssues();

  LampScreenShared get shared;
}

extension InfoSectionTypeRepository on InfoSectionType {
  OldEquipmentSectionType toRepositorySectionType() {
    return switch (this) {
      InfoSectionType.equipment => OldEquipmentSectionType.equipment,
      InfoSectionType.model => OldEquipmentSectionType.model,
      InfoSectionType.contract => OldEquipmentSectionType.contract,
      InfoSectionType.owner => OldEquipmentSectionType.owner,
      InfoSectionType.department => OldEquipmentSectionType.department,
    };
  }
}
