import 'package:flutter/material.dart';

import '../../../core/models/building_map_floor.dart';
import '../../../core/services/lookup_service.dart';
import '../../../core/utils/lamp_floor_resolver.dart';
import '../../../core/utils/homoglyph_text_normalizer.dart';
import '../../../core/utils/phone_list_parser.dart';
import '../../../core/utils/search_text_normalizer.dart';
import 'lamp_migration_service.dart';

/// Μία γραμμή προεπισκόπησης — αντλείται από [TransferFieldPlan].
class LampTransferPreviewField {
  const LampTransferPreviewField({
    required this.formKey,
    required this.label,
    required this.action,
    required this.lampValue,
    required this.destinationValue,
    this.items = const <TransferItemPlan>[],
    this.hasWarning = false,
    this.warningMessage,
  });

  final String formKey;
  final String label;
  final TransferFieldAction action;
  final String? lampValue;
  final String? destinationValue;
  final List<TransferItemPlan> items;
  final bool hasWarning;
  final String? warningMessage;

  static LampTransferPreviewField fromPlan<TKey extends Enum>(
    String formKey,
    String label,
    TransferFieldPlan<TKey> plan,
  ) {
    return LampTransferPreviewField(
      formKey: formKey,
      label: label,
      action: plan.action,
      lampValue: plan.lampValue,
      destinationValue: plan.destinationValue,
      items: plan.items,
      hasWarning: plan.hasWarning,
      warningMessage: plan.warningMessage,
    );
  }
}

/// Μεταδεδομένα πεδίου φόρμας μετανάστευσης (σειρά εμφάνισης).
class LampTransferFormFieldSpec {
  const LampTransferFormFieldSpec({
    required this.formKey,
    required this.label,
    this.required = false,
    this.maxLines = 1,
    this.keyboardType = TextInputType.text,
  });

  final String formKey;
  final String label;
  final bool required;
  final int maxLines;
  final TextInputType keyboardType;
}

/// Αποτέλεσμα προεπισκόπησης μεταφοράς (χωρίς εγγραφή στη βάση).
class LampTransferPreview {
  const LampTransferPreview({
    required this.result,
    required this.fields,
  });

  final TransferResult result;
  final List<LampTransferPreviewField> fields;

  bool get hasAnyWarning =>
      result.hasAnyWarning ||
      fields.any((field) => field.hasWarning) ||
      fields.any(
        (field) => field.items.any((item) => item.hasWarning),
      );
}

extension DepartmentTransferFieldDisplay on DepartmentTransferField {
  String get displayLabel => switch (this) {
    DepartmentTransferField.name => 'Τμήμα',
    DepartmentTransferField.building => 'Κτίριο',
    DepartmentTransferField.level => 'Όροφος',
    DepartmentTransferField.phones => 'Τηλέφωνα',
    DepartmentTransferField.notes => 'Σημειώσεις',
  };
}

extension OwnerTransferFieldDisplay on OwnerTransferField {
  String get displayLabel => switch (this) {
    OwnerTransferField.firstName => 'Όνομα',
    OwnerTransferField.lastName => 'Επώνυμο',
    OwnerTransferField.phones => 'Τηλέφωνα',
    OwnerTransferField.equipmentCodes => 'Εξοπλισμός',
    OwnerTransferField.departmentName => 'Τμήμα',
    OwnerTransferField.location => 'Τοποθεσία',
    OwnerTransferField.notes => 'Σημειώσεις',
  };
}

extension EquipmentTransferFieldDisplay on EquipmentTransferField {
  String get displayLabel => switch (this) {
    EquipmentTransferField.codeEquipment => 'Κωδικός',
    EquipmentTransferField.type => 'Τύπος/Περιγραφή',
    EquipmentTransferField.departmentName => 'Τμήμα',
    EquipmentTransferField.ownerName => 'Κάτοχος',
    EquipmentTransferField.location => 'Τοποθεσία',
    EquipmentTransferField.notes => 'Σημειώσεις',
  };
}

String transferFieldActionLabel(TransferFieldAction action) => switch (action) {
  TransferFieldAction.unchanged => 'Αμετάβλητο',
  TransferFieldAction.linked => 'Σύνδεση',
  TransferFieldAction.created => 'Δημιουργία',
  TransferFieldAction.updated => 'Ενημέρωση',
  TransferFieldAction.unlinked => 'Αποσύνδεση',
};

/// Σύντομη ετικέτα chip στη φόρμα μετανάστευσης.
String transferFieldActionShortLabel(TransferFieldAction action) =>
    switch (action) {
      TransferFieldAction.unchanged => 'Αμετάβλητο',
      TransferFieldAction.linked => 'Συνδεδεμένο',
      TransferFieldAction.created => 'Νέο',
      TransferFieldAction.updated => 'Τροποποίηση',
      TransferFieldAction.unlinked => 'Αποσύνδεση',
    };

bool isTransferFieldReadOnly(
  TransferFieldAction action, {
  String? currentValue,
  String? destinationValue,
}) {
  if (action == TransferFieldAction.linked) return true;
  if (action == TransferFieldAction.unchanged) {
    final currentEmpty = currentValue?.trim().isEmpty ?? true;
    final destinationEmpty = destinationValue?.trim().isEmpty ?? true;
    // Κενό προαιρετικό πεδίο: επιτρέπεται συμπλήρωση χωρίς να αλλάξει η ενέργεια.
    if (currentEmpty && destinationEmpty) return false;
    return true;
  }
  return false;
}

List<LampTransferFormFieldSpec> lampTransferFormFieldSpecs(
  LampTransferTarget target,
) {
  return switch (target) {
    LampTransferTarget.department => const [
      LampTransferFormFieldSpec(
        formKey: 'name',
        label: 'Τμήμα',
        required: true,
      ),
      LampTransferFormFieldSpec(formKey: 'building', label: 'Κτίριο'),
      LampTransferFormFieldSpec(
        formKey: 'level',
        label: 'Όροφος',
        keyboardType: TextInputType.number,
      ),
      LampTransferFormFieldSpec(formKey: 'phones', label: 'Τηλέφωνα'),
      LampTransferFormFieldSpec(
        formKey: 'notes',
        label: 'Σημειώσεις',
        maxLines: 3,
      ),
    ],
    LampTransferTarget.owner => const [
      LampTransferFormFieldSpec(formKey: 'last_name', label: 'Επώνυμο'),
      LampTransferFormFieldSpec(formKey: 'first_name', label: 'Όνομα'),
      LampTransferFormFieldSpec(formKey: 'phones', label: 'Τηλέφωνα'),
      LampTransferFormFieldSpec(
        formKey: 'equipment_codes',
        label: 'Εξοπλισμός',
      ),
      LampTransferFormFieldSpec(formKey: 'department_name', label: 'Τμήμα'),
      LampTransferFormFieldSpec(formKey: 'location', label: 'Τοποθεσία'),
      LampTransferFormFieldSpec(
        formKey: 'notes',
        label: 'Σημειώσεις',
        maxLines: 3,
      ),
    ],
    LampTransferTarget.equipment => const [
      LampTransferFormFieldSpec(
        formKey: 'code_equipment',
        label: 'Κωδικός',
        required: true,
      ),
      LampTransferFormFieldSpec(
        formKey: 'type',
        label: 'Τύπος/Περιγραφή',
      ),
      LampTransferFormFieldSpec(
        formKey: 'department_name',
        label: 'Τμήμα',
      ),
      LampTransferFormFieldSpec(formKey: 'owner_name', label: 'Κάτοχος'),
      LampTransferFormFieldSpec(formKey: 'location', label: 'Τοποθεσία'),
      LampTransferFormFieldSpec(
        formKey: 'notes',
        label: 'Σημειώσεις',
        maxLines: 3,
      ),
    ],
  };
}

String buildTransferActionSummary(LampTransferPreview preview) {
  final counts = <TransferFieldAction, int>{};
  void tally(TransferFieldAction action) {
    counts[action] = (counts[action] ?? 0) + 1;
  }

  for (final field in preview.fields) {
    tally(field.action);
    for (final item in field.items) {
      tally(item.action);
    }
  }

  final parts = <String>[];
  void addPart(TransferFieldAction action, String label) {
    final count = counts[action];
    if (count == null || count == 0) return;
    parts.add(count == 1 ? '1 $label' : '$count $label');
  }

  addPart(TransferFieldAction.created, 'νέα');
  addPart(TransferFieldAction.updated, 'τροποποιήσεις');
  addPart(TransferFieldAction.linked, 'συνδέσεις');
  addPart(TransferFieldAction.unlinked, 'αποσυνδέσεις');
  addPart(TransferFieldAction.unchanged, 'αμετάβλητα');

  final entityLead = switch (preview.result.mainEntityMode) {
    TransferEntityMode.newEntry =>
      'Νέο ${lampTransferTargetLabel(preview.result.target).toLowerCase()}',
    TransferEntityMode.updateExisting =>
      'Ενημέρωση ${preview.result.mainEntityLabel ?? ''}'.trim(),
  };

  if (parts.isEmpty) {
    return 'Έτοιμο για αποθήκευση: $entityLead';
  }
  return 'Έτοιμο για αποθήκευση: $entityLead · ${parts.join(', ')}';
}

String transferEntityModeLabel(TransferEntityMode mode) => switch (mode) {
  TransferEntityMode.newEntry => 'Νέα εγγραφή',
  TransferEntityMode.updateExisting => 'Ενημέρωση υπάρχουσας',
};

String lampTransferTargetLabel(LampTransferTarget target) => switch (target) {
  LampTransferTarget.department => 'Τμήμα',
  LampTransferTarget.owner => 'Κάτοχος',
  LampTransferTarget.equipment => 'Εξοπλισμός',
};

bool lampDepartmentExistsByName(
  String? name, {
  bool Function(String normalizedName)? existsCheck,
}) {
  final trimmed = name?.trim() ?? '';
  if (trimmed.isEmpty) return false;
  final key = SearchTextNormalizer.normalizeForSearch(trimmed);
  if (existsCheck != null) return existsCheck(key);
  for (final department in LookupService.instance.departments) {
    if (department.isDeleted || department.id == null) continue;
    if (SearchTextNormalizer.normalizeForSearch(department.name) == key) {
      return true;
    }
  }
  return false;
}

LampTransferPreview buildLampTransferPreview({
  required LampMigrationDraft draft,
  required Map<String, String> currentFormValues,
  required int? selectedCandidateId,
  bool Function(String normalizedDepartmentName)? departmentExistsCheck,
}) {
  final destinationMap = selectedCandidateId == null
      ? null
      : draft.candidateFormValues[selectedCandidateId];
  final lampValues = draft.newRecordFormValues;
  final mode = selectedCandidateId == null
      ? TransferEntityMode.newEntry
      : TransferEntityMode.updateExisting;
  final matchedLabel = selectedCandidateId == null
      ? null
      : draft.candidates
            .where((candidate) => candidate.id == selectedCandidateId)
            .map((candidate) => candidate.label)
            .firstOrNull;

  final fields = switch (draft.target) {
    LampTransferTarget.department => _departmentPreviewFields(
      lampValues: lampValues,
      currentFormValues: currentFormValues,
      destinationMap: destinationMap,
      departmentExistsCheck: departmentExistsCheck,
      buildingMapFloors: draft.buildingMapFloors,
    ),
    LampTransferTarget.owner => _ownerPreviewFields(
      lampValues: lampValues,
      currentFormValues: currentFormValues,
      destinationMap: destinationMap,
      departmentExistsCheck: departmentExistsCheck,
    ),
    LampTransferTarget.equipment => _equipmentPreviewFields(
      lampValues: lampValues,
      currentFormValues: currentFormValues,
      destinationMap: destinationMap,
      departmentExistsCheck: departmentExistsCheck,
    ),
  };

  final mainLabel = matchedLabel ?? _defaultMainEntityLabel(
    draft.target,
    currentFormValues,
  );

  return LampTransferPreview(
    result: TransferResult(
      target: draft.target,
      mainEntityMode: mode,
      mainEntityId: selectedCandidateId,
      mainEntityLabel: mainLabel,
      operations: _previewWarningOperations(draft.target, fields),
    ),
    fields: fields,
  );
}

List<LampTransferPreviewField> _departmentPreviewFields({
  required Map<String, String> lampValues,
  required Map<String, String> currentFormValues,
  required Map<String, String>? destinationMap,
  bool Function(String normalizedDepartmentName)? departmentExistsCheck,
  required List<BuildingMapFloor> buildingMapFloors,
}) {
  return DepartmentTransferField.values
      .map((fieldKey) {
        final formKey = fieldKey.formKey;
        final destinationValue = destinationMap == null
            ? null
            : _nullableValue(destinationMap[formKey]);
        if (fieldKey == DepartmentTransferField.phones) {
          final currentItems = PhoneListParser.splitPhones(
            currentFormValues[formKey],
          );
          final lampItems = PhoneListParser.splitPhones(lampValues[formKey]);
          final destinationItems = destinationMap == null
              ? const <String>[]
              : PhoneListParser.splitPhones(destinationMap[formKey]);
          final items = evaluateItemsField<DepartmentTransferField>(
            fieldKey: fieldKey,
            currentItems: currentItems,
            lampItems: lampItems,
            destinationItems: destinationItems,
          );
          final aggregateAction = _aggregateItemsAction(items);
          return LampTransferPreviewField(
            formKey: formKey,
            label: fieldKey.displayLabel,
            action: aggregateAction,
            lampValue: lampValues[formKey],
            destinationValue: destinationMap?[formKey],
            items: items,
          );
        }
        final targetExists = fieldKey == DepartmentTransferField.name
            ? lampDepartmentExistsByName(
                currentFormValues[formKey],
                existsCheck: departmentExistsCheck,
              )
            : false;
        final plan = evaluateField<DepartmentTransferField>(
          fieldKey: fieldKey,
          currentValue: currentFormValues[formKey],
          lampValue: lampValues[formKey],
          destinationValue: destinationValue,
          targetExists: targetExists,
          valuesEquivalent: fieldKey == DepartmentTransferField.building
              ? (left, right) =>
                    HomoglyphTextNormalizer.normalizeForComparison(left ?? '') ==
                    HomoglyphTextNormalizer.normalizeForComparison(right ?? '')
              : null,
          warningCheck: fieldKey == DepartmentTransferField.level
              ? (current, lamp, destination) {
                  final level = (current ?? '').trim();
                  if (level.isEmpty) return null;
                  final matched = LampFloorResolver.resolveFloorId(
                    levelText: level,
                    floors: buildingMapFloors,
                  );
                  if (matched != null) return null;
                  return LampFloorResolver.unmatchedLevelWarning(level);
                }
              : null,
        );
        return LampTransferPreviewField.fromPlan(
          formKey,
          fieldKey.displayLabel,
          plan,
        );
      })
      .toList(growable: false);
}

List<LampTransferPreviewField> _ownerPreviewFields({
  required Map<String, String> lampValues,
  required Map<String, String> currentFormValues,
  required Map<String, String>? destinationMap,
  bool Function(String normalizedDepartmentName)? departmentExistsCheck,
}) {
  return OwnerTransferField.values.map((fieldKey) {
    final formKey = fieldKey.formKey;
    final destinationValue = destinationMap == null
        ? null
        : _nullableValue(destinationMap[formKey]);
    if (fieldKey == OwnerTransferField.phones ||
        fieldKey == OwnerTransferField.equipmentCodes) {
      final currentItems = fieldKey == OwnerTransferField.phones
          ? PhoneListParser.splitPhones(currentFormValues[formKey])
          : LampMigrationService.parseEquipmentCodes(
              currentFormValues[formKey],
            );
      final lampItems = fieldKey == OwnerTransferField.phones
          ? PhoneListParser.splitPhones(lampValues[formKey])
          : LampMigrationService.parseEquipmentCodes(lampValues[formKey]);
      final destinationItems = destinationMap == null
          ? const <String>[]
          : fieldKey == OwnerTransferField.phones
          ? PhoneListParser.splitPhones(destinationMap[formKey])
          : LampMigrationService.parseEquipmentCodes(destinationMap[formKey]);
      final items = evaluateItemsField<OwnerTransferField>(
        fieldKey: fieldKey,
        currentItems: currentItems,
        lampItems: lampItems,
        destinationItems: destinationItems,
      );
      final hasItemWarning = items.any((item) => item.hasWarning);
      final itemWarning = items
          .map((item) => item.warningMessage)
          .whereType<String>()
          .where((message) => message.isNotEmpty)
          .join(' · ');
      final aggregateAction = _aggregateItemsAction(items);
      return LampTransferPreviewField(
        formKey: formKey,
        label: fieldKey.displayLabel,
        action: aggregateAction,
        lampValue: lampValues[formKey],
        destinationValue: destinationMap?[formKey],
        items: items,
        hasWarning: hasItemWarning,
        warningMessage: hasItemWarning && itemWarning.isNotEmpty
            ? itemWarning
            : null,
      );
    }

    final targetExists = fieldKey == OwnerTransferField.departmentName
        ? lampDepartmentExistsByName(
            currentFormValues[formKey],
            existsCheck: departmentExistsCheck,
          )
        : false;
    final plan = evaluateField<OwnerTransferField>(
      fieldKey: fieldKey,
      currentValue: currentFormValues[formKey],
      lampValue: lampValues[formKey],
      destinationValue: destinationValue,
      targetExists: targetExists,
    );
    return LampTransferPreviewField.fromPlan(
      formKey,
      fieldKey.displayLabel,
      plan,
    );
  }).toList(growable: false);
}

List<LampTransferPreviewField> _equipmentPreviewFields({
  required Map<String, String> lampValues,
  required Map<String, String> currentFormValues,
  required Map<String, String>? destinationMap,
  bool Function(String normalizedDepartmentName)? departmentExistsCheck,
}) {
  return EquipmentTransferField.values.map((fieldKey) {
    final formKey = fieldKey.formKey;
    final destinationValue = destinationMap == null
        ? null
        : _nullableValue(destinationMap[formKey]);
    final targetExists = fieldKey == EquipmentTransferField.departmentName
        ? lampDepartmentExistsByName(
            currentFormValues[formKey],
            existsCheck: departmentExistsCheck,
          )
        : false;
    final plan = evaluateField<EquipmentTransferField>(
      fieldKey: fieldKey,
      currentValue: currentFormValues[formKey],
      lampValue: lampValues[formKey],
      destinationValue: destinationValue,
      targetExists: targetExists,
    );
    return LampTransferPreviewField.fromPlan(
      formKey,
      fieldKey.displayLabel,
      plan,
    );
  }).toList(growable: false);
}

TransferFieldAction _aggregateItemsAction(List<TransferItemPlan> items) {
  if (items.isEmpty) return TransferFieldAction.unchanged;
  if (items.any((item) => item.action == TransferFieldAction.unlinked)) {
    return TransferFieldAction.unlinked;
  }
  if (items.any((item) => item.action == TransferFieldAction.created)) {
    return TransferFieldAction.created;
  }
  if (items.any((item) => item.action == TransferFieldAction.updated)) {
    return TransferFieldAction.updated;
  }
  if (items.every((item) => item.action == TransferFieldAction.unchanged)) {
    return TransferFieldAction.unchanged;
  }
  return TransferFieldAction.updated;
}

List<TransferOperationResult> _previewWarningOperations(
  LampTransferTarget target,
  List<LampTransferPreviewField> fields,
) {
  final entityKind = switch (target) {
    LampTransferTarget.department => TransferEntityKind.department,
    LampTransferTarget.owner => TransferEntityKind.user,
    LampTransferTarget.equipment => TransferEntityKind.equipment,
  };
  final operations = <TransferOperationResult>[];
  for (final field in fields) {
    if (field.hasWarning && (field.warningMessage?.isNotEmpty ?? false)) {
      operations.add(
        TransferOperationResult(
          kind: _operationKindForFieldAction(field.action),
          entityKind: entityKind,
          label: field.label,
          hasWarning: true,
          warningMessage: field.warningMessage,
        ),
      );
    }
    for (final item in field.items.where((entry) => entry.hasWarning)) {
      operations.add(
        TransferOperationResult(
          kind: _operationKindForFieldAction(item.action),
          entityKind: entityKind,
          label: '${field.label}: ${item.value}',
          hasWarning: true,
          warningMessage: item.warningMessage,
        ),
      );
    }
  }
  return operations;
}

TransferOperationKind _operationKindForFieldAction(TransferFieldAction action) {
  return switch (action) {
    TransferFieldAction.created => TransferOperationKind.created,
    TransferFieldAction.updated => TransferOperationKind.updated,
    TransferFieldAction.linked => TransferOperationKind.linked,
    TransferFieldAction.unlinked => TransferOperationKind.unlinked,
    TransferFieldAction.unchanged => TransferOperationKind.updated,
  };
}

String? _nullableValue(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

String _defaultMainEntityLabel(
  LampTransferTarget target,
  Map<String, String> currentFormValues,
) {
  return switch (target) {
    LampTransferTarget.department => currentFormValues['name']?.trim() ?? '',
    LampTransferTarget.owner => [
      currentFormValues['first_name']?.trim() ?? '',
      currentFormValues['last_name']?.trim() ?? '',
    ].where((part) => part.isNotEmpty).join(' '),
    LampTransferTarget.equipment =>
      currentFormValues['code_equipment']?.trim() ?? '',
  };
}
