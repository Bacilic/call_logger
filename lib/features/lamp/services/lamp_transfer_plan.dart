import '../../../core/utils/search_text_normalizer.dart';

/// Το σχέδιο μεταφοράς Λάμπα → Κατάλογος: για κάθε πεδίο, τι θα γίνει
/// (μένει, δημιουργείται, ενημερώνεται, αποσυνδέεται). Καθαρός υπολογισμός,
/// χωρίς βάση — τον χρησιμοποιούν η υπηρεσία μεταφοράς και η προεπισκόπηση.

enum LampTransferTarget { equipment, owner, department }

enum TransferFieldAction { unchanged, linked, created, updated, unlinked }

class TransferItemPlan {
  const TransferItemPlan({
    required this.value,
    required this.action,
    this.hasWarning = false,
    this.warningMessage,
  });

  final String value;
  final TransferFieldAction action;
  final bool hasWarning;
  final String? warningMessage;
}

class TransferFieldPlan<TKey extends Enum> {
  const TransferFieldPlan({
    required this.fieldKey,
    required this.action,
    required this.lampValue,
    required this.destinationValue,
    this.items = const <TransferItemPlan>[],
    this.hasWarning = false,
    this.warningMessage,
  });

  final TKey fieldKey;
  final TransferFieldAction action;
  final String? lampValue;
  final String? destinationValue;
  final List<TransferItemPlan> items;
  final bool hasWarning;
  final String? warningMessage;
}

enum DepartmentTransferField { name, building, level, phones, notes }

enum OwnerTransferField {
  firstName,
  lastName,
  phones,
  equipmentCodes,
  departmentName,
  location,
  notes,
}

enum EquipmentTransferField {
  codeEquipment,
  type,
  departmentName,
  ownerName,
  location,
  notes,
}

extension DepartmentTransferFieldFormKey on DepartmentTransferField {
  String get formKey => switch (this) {
    DepartmentTransferField.name => 'name',
    DepartmentTransferField.building => 'building',
    DepartmentTransferField.level => 'level',
    DepartmentTransferField.phones => 'phones',
    DepartmentTransferField.notes => 'notes',
  };
}

extension OwnerTransferFieldFormKey on OwnerTransferField {
  String get formKey => switch (this) {
    OwnerTransferField.firstName => 'first_name',
    OwnerTransferField.lastName => 'last_name',
    OwnerTransferField.phones => 'phones',
    OwnerTransferField.equipmentCodes => 'equipment_codes',
    OwnerTransferField.departmentName => 'department_name',
    OwnerTransferField.location => 'location',
    OwnerTransferField.notes => 'notes',
  };
}

extension EquipmentTransferFieldFormKey on EquipmentTransferField {
  String get formKey => switch (this) {
    EquipmentTransferField.codeEquipment => 'code_equipment',
    EquipmentTransferField.type => 'type',
    EquipmentTransferField.departmentName => 'department_name',
    EquipmentTransferField.ownerName => 'owner_name',
    EquipmentTransferField.location => 'location',
    EquipmentTransferField.notes => 'notes',
  };
}

enum TransferEntityMode { newEntry, updateExisting }

class TransferEntityPlan<TKey extends Enum> {
  const TransferEntityPlan({
    required this.target,
    required this.mode,
    required this.matchedEntityId,
    required this.matchedEntityLabel,
    required this.fields,
  });

  final LampTransferTarget target;
  final TransferEntityMode mode;
  final int? matchedEntityId;
  final String? matchedEntityLabel;
  final List<TransferFieldPlan<TKey>> fields;
}

enum TransferEntityKind { user, department, equipment, phone }

enum TransferOperationKind { created, updated, linked, unlinked }

class TransferOperationResult {
  const TransferOperationResult({
    required this.kind,
    required this.entityKind,
    required this.label,
    this.entityId,
    this.hasWarning = false,
    this.warningMessage,
  });

  final TransferOperationKind kind;
  final TransferEntityKind entityKind;
  final String label;
  final int? entityId;
  final bool hasWarning;
  final String? warningMessage;
}

class TransferResult {
  const TransferResult({
    required this.target,
    required this.mainEntityMode,
    required this.mainEntityId,
    required this.mainEntityLabel,
    required this.operations,
  });

  final LampTransferTarget target;
  final TransferEntityMode mainEntityMode;
  final int? mainEntityId;
  final String? mainEntityLabel;
  final List<TransferOperationResult> operations;

  bool get hasAnyWarning => operations.any((operation) => operation.hasWarning);
}

/// Το κλειδί με το οποίο δύο τιμές πεδίου θεωρούνται ίδιες στη μεταφορά:
/// χωρίς διάκριση πεζών/κεφαλαίων και τόνων.
String transferFieldTextKey(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return '';
  return SearchTextNormalizer.normalizeForSearch(trimmed);
}

bool _normalizedFieldTextValuesEquivalent(String? left, String? right) {
  return transferFieldTextKey(left) == transferFieldTextKey(right);
}

TransferFieldPlan<TKey> evaluateField<TKey extends Enum>({
  required TKey fieldKey,
  required String? currentValue,
  required String? lampValue,
  required String? destinationValue,
  bool targetExists = false,
  String? Function(
    String? currentValue,
    String? lampValue,
    String? destinationValue,
  )?
  warningCheck,
  bool Function(String? left, String? right)? valuesEquivalent,
}) {
  final currentTrimmed = currentValue?.trim() ?? '';
  final equivalent = valuesEquivalent ?? _normalizedFieldTextValuesEquivalent;
  final TransferFieldAction action;
  if (targetExists && currentTrimmed.isNotEmpty) {
    action = TransferFieldAction.linked;
  } else if (destinationValue == null && currentTrimmed.isNotEmpty) {
    action = TransferFieldAction.created;
  } else if (equivalent(currentValue, destinationValue)) {
    action = TransferFieldAction.unchanged;
  } else {
    action = TransferFieldAction.updated;
  }

  final warningMessage = warningCheck?.call(
    currentValue,
    lampValue,
    destinationValue,
  );
  return TransferFieldPlan<TKey>(
    fieldKey: fieldKey,
    action: action,
    lampValue: lampValue,
    destinationValue: destinationValue,
    hasWarning: warningMessage != null && warningMessage.isNotEmpty,
    warningMessage: warningMessage,
  );
}

List<TransferItemPlan> evaluateItemsField<TKey extends Enum>({
  required TKey fieldKey,
  required List<String> currentItems,
  required List<String> lampItems,
  required List<String> destinationItems,
  String? Function(String item, TransferFieldAction action)? conflictCheck,
}) {
  final destinationKeys = <String>{
    for (final item in destinationItems)
      if (transferFieldTextKey(item).isNotEmpty) transferFieldTextKey(item),
  };
  final lampKeys = <String>{
    for (final item in lampItems)
      if (transferFieldTextKey(item).isNotEmpty) transferFieldTextKey(item),
  };
  final currentKeys = <String>{
    for (final item in currentItems)
      if (transferFieldTextKey(item).isNotEmpty) transferFieldTextKey(item),
  };
  final plans = <TransferItemPlan>[];

  for (final item in currentItems) {
    final key = transferFieldTextKey(item);
    if (key.isEmpty) continue;
    final action = destinationKeys.contains(key)
        ? TransferFieldAction.unchanged
        : lampKeys.contains(key)
        ? TransferFieldAction.created
        : TransferFieldAction.created;
    final warningMessage = conflictCheck?.call(item, action);
    plans.add(
      TransferItemPlan(
        value: item,
        action: action,
        hasWarning: warningMessage != null && warningMessage.isNotEmpty,
        warningMessage: warningMessage,
      ),
    );
  }

  for (final item in destinationItems) {
    final key = transferFieldTextKey(item);
    if (key.isEmpty || currentKeys.contains(key)) continue;
    final warningMessage =
        conflictCheck?.call(item, TransferFieldAction.unlinked) ??
        'Θα αποσυνδεθεί';
    plans.add(
      TransferItemPlan(
        value: item,
        action: TransferFieldAction.unlinked,
        hasWarning: true,
        warningMessage: warningMessage,
      ),
    );
  }

  return plans;
}
