import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/building_map_repository.dart';
import '../../../core/database/department_repository.dart';
import '../../../core/database/directory_support.dart';
import '../../../core/database/equipment_repository.dart';
import '../../../core/database/phone_repository.dart';
import '../../../core/database/user_repository.dart';
import '../../../core/database/old_database/lamp_issue_resolution_service.dart';
import '../../../core/directory/phone_department_policy.dart';
import '../../../core/services/lookup_service.dart';
import '../../../core/models/building_map_floor.dart';
import '../../../core/utils/department_floor_sync.dart';
import '../../../core/utils/lamp_floor_resolver.dart';
import '../../../core/utils/name_parser.dart';
import '../../../core/utils/phone_list_parser.dart';
import '../../../core/utils/search_text_normalizer.dart';
import '../../../core/utils/user_identity_normalizer.dart';

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

typedef OwnerResolveOutcome = ({
  int ownerId,
  TransferOperationKind kind,
  String label,
});

String _normalizedFieldText(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return '';
  return SearchTextNormalizer.normalizeForSearch(trimmed);
}

bool _normalizedFieldTextValuesEquivalent(String? left, String? right) {
  return _normalizedFieldText(left) == _normalizedFieldText(right);
}


List<String> _splitFormListField(String key, String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return const <String>[];
  return switch (key) {
    'phones' => PhoneListParser.splitPhones(text),
    'equipment_codes' => LampMigrationService.parseEquipmentCodes(text),
    _ => text
        .split(RegExp(r'[,\n;]+'))
        .map((token) => token.trim())
        .where((token) => token.isNotEmpty)
        .toList(growable: false),
  };
}

String _joinFormListField(String key, List<String> items) {
  if (items.isEmpty) return '';
  return items.join(', ');
}

/// Αρχικό seed φόρμας ενημέρωσης: ένωση προορισμού με Λάμπα (μία φορά στο draft).
Map<String, String> _mergeExistingWithLamp({
  required Map<String, String> destination,
  required Map<String, String> lamp,
  required Set<String> listKeys,
  required Set<String> singleValueKeys,
}) {
  final merged = Map<String, String>.from(destination);

  for (final key in listKeys) {
    final seen = <String>{};
    final combined = <String>[];
    for (final item in _splitFormListField(key, destination[key])) {
      final normalized = _normalizedFieldText(item);
      if (normalized.isEmpty) continue;
      if (seen.add(normalized)) combined.add(item);
    }
    for (final item in _splitFormListField(key, lamp[key])) {
      final normalized = _normalizedFieldText(item);
      if (normalized.isEmpty) continue;
      if (seen.add(normalized)) combined.add(item);
    }
    merged[key] = _joinFormListField(key, combined);
  }

  for (final key in singleValueKeys) {
    if ((merged[key] ?? '').trim().isNotEmpty) continue;
    final lampValue = (lamp[key] ?? '').trim();
    if (lampValue.isNotEmpty) {
      merged[key] = lamp[key]!;
    }
  }

  return merged;
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
      if (_normalizedFieldText(item).isNotEmpty) _normalizedFieldText(item),
  };
  final lampKeys = <String>{
    for (final item in lampItems)
      if (_normalizedFieldText(item).isNotEmpty) _normalizedFieldText(item),
  };
  final currentKeys = <String>{
    for (final item in currentItems)
      if (_normalizedFieldText(item).isNotEmpty) _normalizedFieldText(item),
  };
  final plans = <TransferItemPlan>[];

  for (final item in currentItems) {
    final key = _normalizedFieldText(item);
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
    final key = _normalizedFieldText(item);
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

enum LampTransferTarget { equipment, owner, department }

class LampMigrationCandidate {
  const LampMigrationCandidate({
    required this.id,
    required this.label,
    required this.confidence,
    required this.isExact,
  });

  final int id;
  final String label;
  final int confidence;
  final bool isExact;
}

class LampMigrationDraft {
  const LampMigrationDraft({
    required this.target,
    required this.oldValues,
    required this.formValues,
    required this.newRecordFormValues,
    required this.candidateFormValues,
    required this.candidates,
    required this.selectedCandidateId,
    required this.updatesExistingRecord,
    this.hint,
    this.buildingMapFloors = const <BuildingMapFloor>[],
  });

  final LampTransferTarget target;
  final Map<String, String> oldValues;
  final Map<String, String> formValues;
  final Map<String, String> newRecordFormValues;
  final Map<int, Map<String, String>> candidateFormValues;
  final List<LampMigrationCandidate> candidates;
  final int? selectedCandidateId;
  final bool updatesExistingRecord;
  final String? hint;
  final List<BuildingMapFloor> buildingMapFloors;
}

class LampMigrationSaveResult {
  const LampMigrationSaveResult({
    required this.id,
    required this.updated,
    required this.message,
  });

  final int id;
  final bool updated;
  final String message;
}

enum LampOwnerConflictKind { phone, equipment }

enum LampOwnerConflictAction { transferToSelectedOwner, keepWithoutAssignment }

class LampOwnerConflict {
  const LampOwnerConflict({
    required this.conflictId,
    required this.kind,
    required this.value,
    required this.currentOwners,
  });

  final String conflictId;
  final LampOwnerConflictKind kind;
  final String value;
  final List<String> currentOwners;
}

class LampOwnerConflictDecision {
  const LampOwnerConflictDecision({
    required this.conflictId,
    required this.action,
  });

  final String conflictId;
  final LampOwnerConflictAction action;
}

enum LampPendingEntityKind { user, equipment }

class LampPendingEntityCreation {
  const LampPendingEntityCreation({
    required this.entityKind,
    required this.label,
  });

  final LampPendingEntityKind entityKind;
  final String label;
}

enum LampSoftDeletedDecisionAction { reactivate, createNew }

class LampSoftDeletedDecision {
  const LampSoftDeletedDecision({
    required this.action,
    required this.recordId,
  });

  final LampSoftDeletedDecisionAction action;
  final int recordId;
}

class LampSoftDeletedMatch {
  const LampSoftDeletedMatch({
    required this.id,
    required this.label,
  });

  final int id;
  final String label;
}

const String _kPendingEntityCreationError =
    'Απαιτείται επιβεβαίωση δημιουργίας νέας οντότητας.';

const String _kSoftDeletedDecisionError =
    'Υπάρχει διαγραμμένη όμοια εγγραφή· απαιτείται απόφαση.';

class _DepartmentPhoneApplyPlan {
  const _DepartmentPhoneApplyPlan({
    required this.phones,
    required this.transferPhones,
    required this.skipPhones,
  });

  final List<String> phones;
  final Set<String> transferPhones;
  final Set<String> skipPhones;
}

class LampMigrationService {
  /// Ελάχιστο ποσοστό confidence (%) για fuzzy αντιστοίχιση στις Top-3 προτάσεις.
  /// Ρυθμιζόμενο· οι ακριβείς ταυτίσεις ([LampMigrationCandidate.isExact]) το παρακάμπτουν.
  static const int kSuggestionConfidenceThreshold = 50;

  LampMigrationService({LampIssueResolutionService? resolutionService})
    : _resolutionService = resolutionService ?? LampIssueResolutionService();

  final LampIssueResolutionService _resolutionService;

  Future<LampMigrationDraft> buildDraft({
    required LampTransferTarget target,
    required Map<String, Object?> sourceRow,
  }) async {
    return switch (target) {
      LampTransferTarget.department => _buildDepartmentDraft(sourceRow),
      LampTransferTarget.owner => _buildOwnerDraft(sourceRow),
      LampTransferTarget.equipment => _buildEquipmentDraft(sourceRow),
    };
  }

  Future<LampMigrationSaveResult> save({
    required LampTransferTarget target,
    required Map<String, String> formValues,
    required int? selectedCandidateId,
    List<LampOwnerConflictDecision>? ownerConflictDecisions,
    bool confirmEntityCreations = false,
    LampSoftDeletedDecision? softDeletedDecision,
  }) async {
    return switch (target) {
      LampTransferTarget.department => _saveDepartment(
        formValues: formValues,
        selectedCandidateId: selectedCandidateId,
        ownerConflictDecisions: ownerConflictDecisions,
        softDeletedDecision: softDeletedDecision,
      ),
      LampTransferTarget.owner => _saveOwner(
        formValues: formValues,
        selectedCandidateId: selectedCandidateId,
        ownerConflictDecisions: ownerConflictDecisions,
        confirmEntityCreations: confirmEntityCreations,
        softDeletedDecision: softDeletedDecision,
      ),
      LampTransferTarget.equipment => _saveEquipment(
        formValues: formValues,
        selectedCandidateId: selectedCandidateId,
        ownerConflictDecisions: ownerConflictDecisions,
        confirmEntityCreations: confirmEntityCreations,
        softDeletedDecision: softDeletedDecision,
      ),
    };
  }

  /// Ανίχνευση soft-deleted εγγραφής που ταιριάζει με τη φόρμα (μόνο για νέα εγγραφή).
  Future<LampSoftDeletedMatch?> detectSoftDeletedMatch({
    required LampTransferTarget target,
    required Map<String, String> formValues,
    required int? selectedCandidateId,
  }) async {
    if (selectedCandidateId != null) return null;
    return switch (target) {
      LampTransferTarget.owner => _detectSoftDeletedOwnerMatch(formValues),
      LampTransferTarget.department => _detectSoftDeletedDepartmentMatch(formValues),
      LampTransferTarget.equipment => _detectSoftDeletedEquipmentMatch(formValues),
    };
  }

  Future<List<LampPendingEntityCreation>> detectPendingEntityCreations({
    required LampTransferTarget target,
    required Map<String, String> formValues,
    required int? selectedCandidateId,
  }) async {
    final pending = <LampPendingEntityCreation>[];
    switch (target) {
      case LampTransferTarget.equipment:
        final ownerName = (formValues['owner_name'] ?? '').trim();
        if (ownerName.isNotEmpty) {
          final existingOwnerId = await _lookupOwnerIdByName(ownerName);
          if (existingOwnerId == null) {
            pending.add(
              LampPendingEntityCreation(
                entityKind: LampPendingEntityKind.user,
                label: ownerName,
              ),
            );
          }
        }
      case LampTransferTarget.owner:
        final equipmentCodes = LampMigrationService.parseEquipmentCodes(
          formValues['equipment_codes'],
        );
        if (equipmentCodes.isNotEmpty) {
          final db = await DatabaseHelper.instance.database;
          final equipment = EquipmentRepository(db);
          final allEquipment = await equipment.getAllEquipment();
          for (final code in equipmentCodes) {
            final exists = allEquipment.any(
              (row) =>
                  (row['is_deleted'] as int?) != 1 &&
                  _norm(_text(row['code_equipment'])) == _norm(code),
            );
            if (!exists) {
              pending.add(
                LampPendingEntityCreation(
                  entityKind: LampPendingEntityKind.equipment,
                  label: code.trim(),
                ),
              );
            }
          }
        }
      case LampTransferTarget.department:
        break;
    }
    return pending;
  }

  Future<List<LampOwnerConflict>> detectOwnerConflicts({
    required Map<String, String> formValues,
    required int? selectedCandidateId,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final phones = PhoneListParser.splitPhones(formValues['phones']);
    final equipmentCodes = LampMigrationService.parseEquipmentCodes(
      formValues['equipment_codes'],
    );
    final conflicts = <LampOwnerConflict>[];

    if (phones.isNotEmpty) {
      final departmentName = (formValues['department_name'] ?? '').trim();
      int? targetDepartmentId;
      if (departmentName.isNotEmpty) {
        final deptKey = SearchTextNormalizer.normalizeForSearch(departmentName);
        for (final d in LookupService.instance.departments) {
          if ((d.isDeleted) || d.id == null) continue;
          if (SearchTextNormalizer.normalizeForSearch(d.name) == deptKey) {
            targetDepartmentId = d.id;
            break;
          }
        }
      }
      final policyConflicts =
          PhoneDepartmentPolicy.findConflictsForUserAssignment(
        phones: phones,
        targetDepartmentId: targetDepartmentId,
        editingUserId: selectedCandidateId,
      );
      for (final c in policyConflicts) {
        if (c.hasOtherUserOwners) {
          conflicts.add(
            LampOwnerConflict(
              conflictId: 'phone:${_norm(c.phone)}',
              kind: LampOwnerConflictKind.phone,
              value: c.phone,
              currentOwners: c.otherUserOwnerLabels,
            ),
          );
        } else if (c.hasDepartmentLocationConflict) {
          conflicts.add(
            LampOwnerConflict(
              conflictId: 'phone:${_norm(c.phone)}',
              kind: LampOwnerConflictKind.phone,
              value: c.phone,
              currentOwners: [
                'Κοινόχρηστο: ${c.existingDepartmentName ?? c.existingDepartmentId}',
              ],
            ),
          );
        }
      }
    }

    if (equipmentCodes.isNotEmpty) {
      final rows = await db.rawQuery(
        '''
        SELECT
          e.code_equipment AS code_equipment,
          u.id AS user_id,
          u.first_name AS first_name,
          u.last_name AS last_name
        FROM equipment e
        JOIN user_equipment ue ON ue.equipment_id = e.id
        JOIN users u ON u.id = ue.user_id
        WHERE e.code_equipment IN (${List.filled(equipmentCodes.length, '?').join(',')})
          AND COALESCE(e.is_deleted, 0) = 0
          AND COALESCE(u.is_deleted, 0) = 0
          AND (${selectedCandidateId == null ? '1 = 1' : 'u.id != ?'})
        ORDER BY e.code_equipment COLLATE NOCASE ASC, u.last_name COLLATE NOCASE ASC, u.first_name COLLATE NOCASE ASC
        ''',
        <Object?>[
          ...equipmentCodes,
          ?selectedCandidateId,
        ],
      );
      final ownersByCode = <String, Set<String>>{};
      for (final row in rows) {
        final code = row['code_equipment']?.toString().trim() ?? '';
        final owner = _fullName(
          _text(row['first_name']),
          _text(row['last_name']),
        );
        if (code.isEmpty || owner.isEmpty) continue;
        ownersByCode.putIfAbsent(code, () => <String>{}).add(owner);
      }
      for (final entry in ownersByCode.entries) {
        conflicts.add(
          LampOwnerConflict(
            conflictId: 'equipment:${_norm(entry.key)}',
            kind: LampOwnerConflictKind.equipment,
            value: entry.key,
            currentOwners: entry.value.toList(growable: false),
          ),
        );
      }
    }

    return conflicts;
  }

  /// Συγκρούσεις κοινόχρηστων τηλεφώνων κατά μεταφορά τμήματος.
  Future<List<LampOwnerConflict>> detectDepartmentConflicts({
    required Map<String, String> formValues,
    required int? selectedCandidateId,
  }) async {
    final phones = PhoneListParser.splitPhones(formValues['phones']);
    if (phones.isEmpty) return const <LampOwnerConflict>[];

    final policyConflicts =
        PhoneDepartmentPolicy.findConflictsForUserAssignment(
      phones: phones,
      targetDepartmentId: selectedCandidateId,
      editingUserId: null,
    );
    final conflicts = <LampOwnerConflict>[];
    for (final c in policyConflicts) {
      if (c.hasOtherUserOwners) {
        conflicts.add(
          LampOwnerConflict(
            conflictId: 'phone:${_norm(c.phone)}',
            kind: LampOwnerConflictKind.phone,
            value: c.phone,
            currentOwners: c.otherUserOwnerLabels,
          ),
        );
      } else if (c.hasDepartmentLocationConflict) {
        conflicts.add(
          LampOwnerConflict(
            conflictId: 'phone:${_norm(c.phone)}',
            kind: LampOwnerConflictKind.phone,
            value: c.phone,
            currentOwners: [
              'Κοινόχρηστο: ${c.existingDepartmentName ?? c.existingDepartmentId}',
            ],
          ),
        );
      }
    }
    return conflicts;
  }

  Future<List<LampOwnerConflict>> detectEquipmentConflicts({
    required Map<String, String> formValues,
    required int? selectedCandidateId,
  }) async {
    if (selectedCandidateId == null) return const <LampOwnerConflict>[];

    final code = (formValues['code_equipment'] ?? '').trim();
    if (code.isEmpty) return const <LampOwnerConflict>[];

    final db = await DatabaseHelper.instance.database;
    final users = UserRepository(db);
    final currentOwners = await users.getEquipmentOwnerSnapshots(
      selectedCandidateId,
    );
    if (currentOwners.isEmpty) return const <LampOwnerConflict>[];

    final newOwnerId = await _lookupOwnerIdByName(formValues['owner_name']);
    final currentOwnerIds = currentOwners
        .map((row) => row['id'] as int?)
        .whereType<int>()
        .toSet();
    final targetOwnerIds = newOwnerId == null ? <int>{} : <int>{newOwnerId};
    if (currentOwnerIds == targetOwnerIds) {
      return const <LampOwnerConflict>[];
    }

    final currentOwnerNames = currentOwners
        .map(
          (row) => _fullName(
            _text(row['first_name']),
            _text(row['last_name']),
          ),
        )
        .where((name) => name.isNotEmpty)
        .toList(growable: false);

    return <LampOwnerConflict>[
      LampOwnerConflict(
        conflictId: 'equipment:${_norm(code)}',
        kind: LampOwnerConflictKind.equipment,
        value: code,
        currentOwners: currentOwnerNames,
      ),
    ];
  }

  Future<LampMigrationDraft> _buildDepartmentDraft(
    Map<String, Object?> sourceRow,
  ) async {
    final oldName = _firstText(
      sourceRow['office_name'],
      sourceRow['department_name'],
      sourceRow['office_original_text'],
    );
    final oldBuilding = _text(sourceRow['building']);
    final oldLevel = _text(sourceRow['level']);
    final oldPhones = _text(sourceRow['office_phones']);
    final oldEmail = _text(sourceRow['office_email']);

    final db = await DatabaseHelper.instance.database;
    final departmentsRepo = DepartmentRepository(db);
    final buildingMap = BuildingMapRepository(db, DirectorySupport(db));
    final phonesRepo = PhoneRepository(db);
    final departments = await departmentsRepo.getDepartments();
    final buildingMapFloors = await buildingMap.listBuildingMapFloors();
    final departmentPhonesMap = await phonesRepo.getDepartmentDirectPhonesMap();
    final active = departments
        .where((row) => (row['is_deleted'] as int?) != 1)
        .toList(growable: false);

    final candidates = _topCandidates(
      source: oldName,
      rows: active,
      idKey: 'id',
      labelBuilder: (row) => _text(row['name']),
    );
    final exact = candidates.where((c) => c.isExact).toList(growable: false);
    final selected = exact.length == 1 ? exact.first.id : null;

    final candidateFormValues = <int, Map<String, String>>{};
    for (final row in active) {
      final id = row['id'] as int?;
      if (id == null) continue;
      candidateFormValues[id] = <String, String>{
        'name': _text(row['name']),
        'building': _text(row['building']),
        'level': _departmentLevelText(row),
        'phones': _joinFormListField(
          'phones',
          departmentPhonesMap[id] ?? const <String>[],
        ),
        'notes': _text(row['notes']),
      };
    }
    final newRecordFormValues = <String, String>{
      'name': oldName,
      'building': oldBuilding,
      'level': oldLevel,
      'phones': oldPhones,
      'notes': '',
    };
    final formValues = selected == null
        ? Map<String, String>.from(newRecordFormValues)
        : _mergeExistingWithLamp(
            destination: candidateFormValues[selected] ?? newRecordFormValues,
            lamp: newRecordFormValues,
            listKeys: const <String>{'phones'},
            singleValueKeys: const <String>{
              'building',
              'level',
              'notes',
            },
          );

    return LampMigrationDraft(
      target: LampTransferTarget.department,
      oldValues: <String, String>{
        'Παλιό τμήμα': oldName,
        'Παλιό email': oldEmail,
        'Παλιό τηλέφωνο': oldPhones,
        'Παλιό κτίριο': oldBuilding,
        'Παλιός όροφος': oldLevel,
      },
      formValues: formValues,
      newRecordFormValues: newRecordFormValues,
      candidateFormValues: candidateFormValues,
      candidates: candidates,
      selectedCandidateId: selected,
      updatesExistingRecord: selected != null,
      hint: selected == null && oldName.isNotEmpty
          ? 'Παλιό τμήμα: $oldName'
          : null,
      buildingMapFloors: buildingMapFloors,
    );
  }

  Future<LampMigrationDraft> _buildOwnerDraft(
    Map<String, Object?> sourceRow,
  ) async {
    var oldLastName = _text(sourceRow['last_name']);
    var oldFirstName = _text(sourceRow['first_name']);
    final oldOwnerOriginalText = _text(sourceRow['owner_original_text']);
    if (oldFirstName.isEmpty &&
        oldLastName.isEmpty &&
        oldOwnerOriginalText.isNotEmpty) {
      final parsed = NameParserUtility.parse(oldOwnerOriginalText);
      oldFirstName = parsed.firstName.trim();
      oldLastName = parsed.lastName.trim();
    }
    final oldOwnerName = _firstText(
      _fullName(oldFirstName, oldLastName),
      oldOwnerOriginalText,
    );
    final oldPhones = _text(sourceRow['owner_phones']);
    final oldEmail = _text(sourceRow['owner_email']);
    final oldDepartment = _firstText(
      sourceRow['office_name'],
      sourceRow['department_name'],
      sourceRow['office_original_text'],
    );
    final oldEquipmentCodes = _firstText(
      sourceRow['code_equipment'],
      sourceRow['code'],
    );
    final db = await DatabaseHelper.instance.database;
    final usersRepo = UserRepository(db);
    final departmentsRepo = DepartmentRepository(db);
    final users = await usersRepo.getAllUsers();
    final active = users
        .where((row) => (row['is_deleted'] as int?) != 1)
        .toList(growable: false);

    final sourceIdentityKeys = <String>{
      ...UserIdentityNormalizer.matchingIdentityKeysFromFreeText(oldOwnerName),
      if (oldOwnerOriginalText.trim().isNotEmpty)
        ...UserIdentityNormalizer.matchingIdentityKeysFromFreeText(
          oldOwnerOriginalText,
        ),
    };
    final exactByIdentity = active
        .where(
          (row) => UserIdentityNormalizer.personMatchesIdentityKeys(
            personFirstName: _text(row['first_name']),
            personLastName: _text(row['last_name']),
            sourceKeys: sourceIdentityKeys,
          ),
        )
        .toList(growable: false);
    final selected = exactByIdentity.length == 1
        ? (exactByIdentity.first['id'] as int?)
        : null;
    final newRecordFormValues = <String, String>{
      'first_name': oldFirstName,
      'last_name': oldLastName,
      'phones': oldPhones,
      'equipment_codes': oldEquipmentCodes,
      'department_name': oldDepartment,
      'location': '',
      'notes': '',
    };
    final candidateFormValues = <int, Map<String, String>>{};
    String? selectedHint;
    if (selected != null) {
      final selectedUser = active.firstWhere(
        (row) => row['id'] == selected,
        orElse: () => const <String, Object?>{},
      );
      final selectedPhonesRaw = selectedUser['phones'];
      final selectedPhones = selectedPhonesRaw is List
          ? selectedPhonesRaw
                .map((v) => v.toString().trim())
                .where((v) => v.isNotEmpty)
                .toList(growable: false)
          : const <String>[];
      final linkedEquipmentRows = await db.rawQuery(
        '''
        SELECT e.code_equipment AS code
        FROM user_equipment ue
        JOIN equipment e ON e.id = ue.equipment_id
        WHERE ue.user_id = ? AND COALESCE(e.is_deleted, 0) = 0
        ORDER BY e.code_equipment COLLATE NOCASE ASC
        ''',
        <Object?>[selected],
      );
      final linkedEquipmentCodes = <String>[
        for (final row in linkedEquipmentRows)
          if ((row['code']?.toString().trim() ?? '').isNotEmpty)
            row['code'].toString().trim(),
      ];
      selectedHint =
          'Υπάρχων χρήστης: '
          '${selectedPhones.length} τηλέφωνα · '
          '${linkedEquipmentCodes.length} εξοπλισμοί στη νέα βάση.';
    }
    final userEquipmentRows = await db.rawQuery(
      '''
      SELECT
        ue.user_id AS user_id,
        e.code_equipment AS code
      FROM user_equipment ue
      JOIN equipment e ON e.id = ue.equipment_id
      WHERE COALESCE(e.is_deleted, 0) = 0
      ORDER BY ue.user_id ASC, e.code_equipment COLLATE NOCASE ASC
      ''',
    );
    final equipmentCodesByUserId = <int, List<String>>{};
    for (final row in userEquipmentRows) {
      final userId = row['user_id'] as int?;
      final code = row['code']?.toString().trim() ?? '';
      if (userId == null || code.isEmpty) continue;
      equipmentCodesByUserId.putIfAbsent(userId, () => <String>[]).add(code);
    }
    final departmentNameCache = <int, String>{};
    for (final row in active) {
      final id = row['id'] as int?;
      if (id == null) continue;
      final phonesRaw = row['phones'];
      final phonesCsv = phonesRaw is List
          ? phonesRaw
                .map((v) => v.toString().trim())
                .where((v) => v.isNotEmpty)
                .join(', ')
          : '';
      final linkedEquipmentCodesCsv = (equipmentCodesByUserId[id] ?? const <String>[])
          .join(', ');
      final departmentId = row['department_id'] as int?;
      var departmentName = '';
      if (departmentId != null) {
        departmentName = departmentNameCache.putIfAbsent(
          departmentId,
          () => '',
        );
        if (departmentName.isEmpty) {
          final fetched = await departmentsRepo.getDepartmentNameById(departmentId);
          departmentName = fetched?.trim() ?? '';
          departmentNameCache[departmentId] = departmentName;
        }
      }
      candidateFormValues[id] = <String, String>{
        'first_name': _text(row['first_name']),
        'last_name': _text(row['last_name']),
        'phones': phonesCsv,
        'equipment_codes': linkedEquipmentCodesCsv,
        'department_name': departmentName,
        'location': _text(row['location']),
        'notes': _text(row['notes']),
      };
    }
    final candidates = _topCandidates(
      source: oldOwnerName,
      rows: active,
      idKey: 'id',
      labelBuilder: (row) =>
          _fullName(_text(row['first_name']), _text(row['last_name'])),
      sourceDepartment: oldDepartment.isEmpty ? null : oldDepartment,
      candidateDepartmentBuilder: (row) {
        final departmentId = row['department_id'] as int?;
        if (departmentId == null) return null;
        final cached = departmentNameCache[departmentId];
        return cached == null || cached.isEmpty ? null : cached;
      },
      identityMatchKeys: sourceIdentityKeys,
    );
    final formValues = selected == null
        ? Map<String, String>.from(newRecordFormValues)
        : _mergeExistingWithLamp(
            destination: candidateFormValues[selected] ?? newRecordFormValues,
            lamp: newRecordFormValues,
            listKeys: const <String>{'phones', 'equipment_codes'},
            singleValueKeys: const <String>{
              'department_name',
              'location',
              'notes',
            },
          );
    return LampMigrationDraft(
      target: LampTransferTarget.owner,
      oldValues: <String, String>{
        'Παλιός κάτοχος': oldOwnerName,
        'Παλιό email': oldEmail,
        'Παλιά τηλέφωνα': oldPhones,
        'Παλιός εξοπλισμός': oldEquipmentCodes,
        'Παλιό τμήμα': oldDepartment,
      },
      formValues: formValues,
      newRecordFormValues: newRecordFormValues,
      candidateFormValues: candidateFormValues,
      candidates: candidates,
      selectedCandidateId: selected,
      updatesExistingRecord: selected != null,
      hint: selected != null
          ? selectedHint
          : oldDepartment.isNotEmpty
          ? 'Παλιό τμήμα: $oldDepartment'
          : null,
    );
  }

  Future<LampMigrationDraft> _buildEquipmentDraft(
    Map<String, Object?> sourceRow,
  ) async {
    final oldCode = _text(sourceRow['code']);
    final oldDescription = _text(sourceRow['description']);
    final oldDepartment = _firstText(
      sourceRow['office_name'],
      sourceRow['department_name'],
      sourceRow['office_original_text'],
    );
    final oldOwnerName = _fullName(
      _text(sourceRow['first_name']),
      _text(sourceRow['last_name']),
    );
    final oldNotes = _firstText(
      sourceRow['equipment_comments'],
      sourceRow['description'],
    );

    final db = await DatabaseHelper.instance.database;
    final equipment = EquipmentRepository(db);
    final departmentsRepo = DepartmentRepository(db);
    final equipmentRows = await equipment.getAllEquipment();
    final active = equipmentRows
        .where((row) => (row['is_deleted'] as int?) != 1)
        .toList(growable: false);
    final candidates = _topCandidates(
      source: oldCode,
      rows: active,
      idKey: 'id',
      labelBuilder: (row) => _text(row['code_equipment']),
    );
    final selected = active
        .where((row) => _norm(_text(row['code_equipment'])) == _norm(oldCode))
        .map((row) => row['id'] as int?)
        .whereType<int>()
        .toList(growable: false);
    final selectedId = selected.length == 1 ? selected.first : null;

    final candidateFormValues = <int, Map<String, String>>{};
    final departmentNameCache = <int, String>{};
    final ownerRows = await db.rawQuery(
      '''
      SELECT
        ue.equipment_id AS equipment_id,
        u.first_name AS first_name,
        u.last_name AS last_name
      FROM user_equipment ue
      JOIN users u ON u.id = ue.user_id
      WHERE COALESCE(u.is_deleted, 0) = 0
      ORDER BY ue.equipment_id ASC, u.last_name COLLATE NOCASE ASC, u.first_name COLLATE NOCASE ASC
      ''',
    );
    final ownersByEquipmentId = <int, List<String>>{};
    for (final row in ownerRows) {
      final equipmentId = row['equipment_id'] as int?;
      final ownerName = _fullName(
        _text(row['first_name']),
        _text(row['last_name']),
      );
      if (equipmentId == null || ownerName.isEmpty) continue;
      ownersByEquipmentId.putIfAbsent(equipmentId, () => <String>[]).add(
        ownerName,
      );
    }
    for (final row in active) {
      final id = row['id'] as int?;
      if (id == null) continue;
      final departmentId = row['department_id'] as int?;
      var departmentName = '';
      if (departmentId != null) {
        departmentName = departmentNameCache.putIfAbsent(
          departmentId,
          () => '',
        );
        if (departmentName.isEmpty) {
          final fetched = await departmentsRepo.getDepartmentNameById(departmentId);
          departmentName = fetched?.trim() ?? '';
          departmentNameCache[departmentId] = departmentName;
        }
      }
      final linkedOwners = ownersByEquipmentId[id] ?? const <String>[];
      final ownerName = linkedOwners.length == 1
          ? linkedOwners.first
          : linkedOwners.join(', ');
      candidateFormValues[id] = <String, String>{
        'code_equipment': _text(row['code_equipment']),
        'type': _text(row['type']),
        'department_name': departmentName,
        'owner_name': ownerName,
        'location': _text(row['location']),
        'notes': _text(row['notes']),
      };
    }
    final newRecordFormValues = <String, String>{
      'code_equipment': oldCode,
      'type': oldDescription,
      'department_name': oldDepartment,
      'owner_name': oldOwnerName,
      'location': '',
      'notes': oldNotes,
    };
    final formValues = selectedId == null
        ? Map<String, String>.from(newRecordFormValues)
        : _mergeExistingWithLamp(
            destination:
                candidateFormValues[selectedId] ?? newRecordFormValues,
            lamp: newRecordFormValues,
            listKeys: const <String>{},
            singleValueKeys: const <String>{
              'department_name',
              'type',
              'location',
              'notes',
            },
          );

    return LampMigrationDraft(
      target: LampTransferTarget.equipment,
      oldValues: <String, String>{
        'Παλιός κωδικός': oldCode,
        'Παλιά περιγραφή': oldDescription,
        'Παλιός κάτοχος': oldOwnerName,
        'Παλιό τμήμα': oldDepartment,
      },
      formValues: formValues,
      newRecordFormValues: newRecordFormValues,
      candidateFormValues: candidateFormValues,
      candidates: candidates,
      selectedCandidateId: selectedId,
      updatesExistingRecord: selectedId != null,
      hint: selectedId == null && oldDepartment.isNotEmpty
          ? 'Παλιό τμήμα: $oldDepartment'
          : null,
    );
  }

  Future<LampMigrationSaveResult> _saveDepartment({
    required Map<String, String> formValues,
    required int? selectedCandidateId,
    List<LampOwnerConflictDecision>? ownerConflictDecisions,
    LampSoftDeletedDecision? softDeletedDecision,
  }) async {
    final name = formValues['name']?.trim() ?? '';
    if (name.isEmpty) throw StateError('Το πεδίο τμήμα είναι υποχρεωτικό.');

    final db = await DatabaseHelper.instance.database;
    final departments = DepartmentRepository(db);
    final buildingMap = BuildingMapRepository(db, DirectorySupport(db));
    final phones = PhoneRepository(db);
    final levelText = (formValues['level'] ?? '').trim();
    final buildingMapFloors = await buildingMap.listBuildingMapFloors();
    final matchedFloorId = LampFloorResolver.resolveFloorId(
      levelText: levelText,
      floors: buildingMapFloors,
    );
    final map = DepartmentFloorSync.mergeFloorContext(
      <String, dynamic>{
        'name': name,
        'name_key': _norm(name),
        'building': _nullable(formValues['building']),
        'notes': _nullable(formValues['notes']),
        'map_hidden': 1,
        'is_deleted': 0,
      },
      manualFloorId: matchedFloorId,
    );
    final reactivateId =
        softDeletedDecision?.action == LampSoftDeletedDecisionAction.reactivate
        ? softDeletedDecision!.recordId
        : null;
    final updateId = selectedCandidateId ?? reactivateId;

    if (updateId == null) {
      await _requireSoftDeletedDecisionBeforeInsert(
        target: LampTransferTarget.department,
        formValues: formValues,
        softDeletedDecision: softDeletedDecision,
      );
    }

    final phoneApplyPlan = await _buildDepartmentPhoneApplyPlan(
      formValues: formValues,
      selectedCandidateId: selectedCandidateId,
      ownerConflictDecisions: ownerConflictDecisions,
    );

    return db.transaction((txn) async {
      final int departmentId;
      final bool updated;
      final String message;
      if (updateId != null) {
        await departments.updateDepartment(updateId, map, executor: txn);
        departmentId = updateId;
        updated = true;
        message = reactivateId != null && selectedCandidateId == null
            ? 'Επαναφέρθηκε διαγραμμένο τμήμα.'
            : 'Ενημερώθηκε υπάρχον τμήμα.';
      } else {
        if (softDeletedDecision?.action ==
            LampSoftDeletedDecisionAction.createNew) {
          await _tombstoneSoftDeletedDepartmentNameKey(
            softDeletedDecision!.recordId,
            executor: txn,
          );
        }
        departmentId = await departments.insertDepartment(map, executor: txn);
        updated = false;
        message = 'Δημιουργήθηκε νέο τμήμα.';
      }

      await _applyDepartmentDirectPhones(
        phones: phones,
        departmentId: departmentId,
        plan: phoneApplyPlan,
        executor: txn,
      );

      return LampMigrationSaveResult(
        id: departmentId,
        updated: updated,
        message: message,
      );
    });
  }

  Future<_DepartmentPhoneApplyPlan> _buildDepartmentPhoneApplyPlan({
    required Map<String, String> formValues,
    required int? selectedCandidateId,
    List<LampOwnerConflictDecision>? ownerConflictDecisions,
  }) async {
    final phones = PhoneListParser.splitPhones(formValues['phones']);
    if (phones.isEmpty) {
      return const _DepartmentPhoneApplyPlan(
        phones: <String>[],
        transferPhones: <String>{},
        skipPhones: <String>{},
      );
    }

    final conflicts = await detectDepartmentConflicts(
      formValues: formValues,
      selectedCandidateId: selectedCandidateId,
    );
    final decisionsById = <String, LampOwnerConflictAction>{
      for (final decision in ownerConflictDecisions ?? const <LampOwnerConflictDecision>[])
        decision.conflictId: decision.action,
    };
    final unresolvedConflicts = conflicts
        .where((conflict) => !decisionsById.containsKey(conflict.conflictId))
        .toList(growable: false);
    if (unresolvedConflicts.isNotEmpty) {
      throw StateError('Απαιτείται επίλυση διενέξεων για κοινόχρηστα τηλέφωνα.');
    }

    final transferPhones = <String>{
      for (final conflict in conflicts)
        if (conflict.kind == LampOwnerConflictKind.phone &&
            decisionsById[conflict.conflictId] ==
                LampOwnerConflictAction.transferToSelectedOwner)
          conflict.value,
    };
    final skipPhones = <String>{
      for (final conflict in conflicts)
        if (conflict.kind == LampOwnerConflictKind.phone &&
            decisionsById[conflict.conflictId] ==
                LampOwnerConflictAction.keepWithoutAssignment)
          conflict.value,
    };

    return _DepartmentPhoneApplyPlan(
      phones: phones,
      transferPhones: transferPhones,
      skipPhones: skipPhones,
    );
  }

  Future<void> _applyDepartmentDirectPhones({
    required PhoneRepository phones,
    required int departmentId,
    required _DepartmentPhoneApplyPlan plan,
    DatabaseExecutor? executor,
  }) async {
    if (plan.phones.isEmpty) return;

    for (final phone in plan.transferPhones) {
      await phones.removePhoneFromAllUsers(phone, executor: executor);
      final usage = LookupService.instance.checkPhoneUsage(phone);
      final sourceDeptId = usage.departmentId;
      if (sourceDeptId != null && sourceDeptId != departmentId) {
        await phones.removeDepartmentDirectPhone(
          sourceDeptId,
          phone,
          executor: executor,
        );
      }
    }

    for (final phone in plan.phones) {
      if (plan.skipPhones.contains(phone)) continue;
      await phones.addDepartmentDirectPhone(
        departmentId,
        phone,
        executor: executor,
      );
    }
  }

  Future<LampMigrationSaveResult> _saveOwner({
    required Map<String, String> formValues,
    required int? selectedCandidateId,
    List<LampOwnerConflictDecision>? ownerConflictDecisions,
    required bool confirmEntityCreations,
    LampSoftDeletedDecision? softDeletedDecision,
  }) async {
    final firstName = (formValues['first_name'] ?? '').trim();
    final lastName = (formValues['last_name'] ?? '').trim();
    if (firstName.isEmpty && lastName.isEmpty) {
      throw StateError('Απαιτείται όνομα ή επώνυμο.');
    }
    final db = await DatabaseHelper.instance.database;
    final users = UserRepository(db);
    final departments = DepartmentRepository(db);
    final equipment = EquipmentRepository(db);
    final phoneRepo = PhoneRepository(db);
    final departmentName = (formValues['department_name'] ?? '').trim();
    final phones = PhoneListParser.splitPhones(formValues['phones']);
    final equipmentCodes = LampMigrationService.parseEquipmentCodes(
      formValues['equipment_codes'],
    );
    final conflicts = await detectOwnerConflicts(
      formValues: formValues,
      selectedCandidateId: selectedCandidateId,
    );
    final decisionsById = <String, LampOwnerConflictAction>{
      for (final decision in ownerConflictDecisions ?? const <LampOwnerConflictDecision>[])
        decision.conflictId: decision.action,
    };
    final unresolvedConflicts = conflicts
        .where((conflict) => !decisionsById.containsKey(conflict.conflictId))
        .toList(growable: false);
    if (unresolvedConflicts.isNotEmpty) {
      throw StateError('Απαιτείται επίλυση διενέξεων για τηλέφωνα/εξοπλισμό.');
    }

    final skipPhones = <String>{
      for (final conflict in conflicts)
        if (conflict.kind == LampOwnerConflictKind.phone &&
            decisionsById[conflict.conflictId] ==
                LampOwnerConflictAction.keepWithoutAssignment)
          conflict.value,
    };
    final transferEquipmentCodes = <String>{
      for (final conflict in conflicts)
        if (conflict.kind == LampOwnerConflictKind.equipment &&
            decisionsById[conflict.conflictId] ==
                LampOwnerConflictAction.transferToSelectedOwner)
          conflict.value,
    };
    final skipEquipmentCodes = <String>{
      for (final conflict in conflicts)
        if (conflict.kind == LampOwnerConflictKind.equipment &&
            decisionsById[conflict.conflictId] ==
                LampOwnerConflictAction.keepWithoutAssignment)
          conflict.value,
    };

    final phonePolicyBatch = _buildUserPhoneConflictBatch(
      conflicts: conflicts,
      decisionsById: decisionsById,
    );
    final resolvedPhones = <String>[
      for (final phone in phones)
        if (!skipPhones.contains(phone)) phone,
    ];
    final resolvedEquipmentCodes = <String>[
      for (final code in equipmentCodes)
        if (!skipEquipmentCodes.contains(code)) code,
    ];

    final reactivateId =
        softDeletedDecision?.action == LampSoftDeletedDecisionAction.reactivate
        ? softDeletedDecision!.recordId
        : null;
    final updateUserId = selectedCandidateId ?? reactivateId;

    if (updateUserId == null) {
      await _requireSoftDeletedDecisionBeforeInsert(
        target: LampTransferTarget.owner,
        formValues: formValues,
        softDeletedDecision: softDeletedDecision,
      );
    }

    return db.transaction((txn) async {
      final departmentId = departmentName.isEmpty
          ? null
          : await departments.getOrCreateDepartmentIdByName(
              departmentName,
              executor: txn,
            );

      if (!phonePolicyBatch.isEmpty) {
        await PhoneDepartmentPolicy.applyUserPhoneConflictResolutions(
          phones: phoneRepo,
          resolutions: phonePolicyBatch,
          targetDepartmentId: departmentId,
          executor: txn,
        );
      }

      for (final code in transferEquipmentCodes) {
        await equipment.removeEquipmentFromAllUsers(code, executor: txn);
      }

      final int savedUserId;
      final bool updated;
      final String message;
      if (updateUserId != null) {
        await users.updateUser(
          updateUserId,
          <String, dynamic>{
            'first_name': firstName,
            'last_name': lastName,
            'phones': resolvedPhones,
            'department_id': departmentId,
            'location': _nullable(formValues['location']),
            'notes': _nullable(formValues['notes']),
            'is_deleted': 0,
          },
          executor: txn,
          skipPhonePolicyValidation: !phonePolicyBatch.isEmpty,
        );
        savedUserId = updateUserId;
        updated = true;
        message = selectedCandidateId != null
            ? 'Ενημερώθηκε υπάρχων χρήστης.'
            : 'Επαναφέρθηκε διαγραμμένος χρήστης.';
      } else {
        savedUserId = await users.insertUser(
          firstName: firstName,
          lastName: lastName,
          phones: resolvedPhones,
          departmentId: departmentId,
          location: _nullable(formValues['location']),
          notes: _nullable(formValues['notes']),
          executor: txn,
          skipPhonePolicyValidation: !phonePolicyBatch.isEmpty,
        );
        updated = false;
        message = 'Δημιουργήθηκε νέος χρήστης.';
      }

      await _assignUserPhonesToDepartment(
        phoneRepo: phoneRepo,
        departmentId: departmentId,
        phones: resolvedPhones,
        executor: txn,
      );
      await _syncOwnerEquipmentLinks(
        userId: savedUserId,
        equipmentCodes: resolvedEquipmentCodes,
        confirmEntityCreations: confirmEntityCreations,
        executor: txn,
      );
      return LampMigrationSaveResult(
        id: savedUserId,
        updated: updated,
        message: message,
      );
    }).then((result) async {
      if (!phonePolicyBatch.isEmpty) {
        LookupService.instance.resetForReload();
        await LookupService.instance.loadFromDatabase();
      }
      return result;
    });
  }

  /// Μετατροπή αποφάσεων οδηγού Λάμπας σε batch πολιτικής (ίδιο με user_form_dialog).
  UserPhoneConflictBatchResult _buildUserPhoneConflictBatch({
    required List<LampOwnerConflict> conflicts,
    required Map<String, LampOwnerConflictAction> decisionsById,
  }) {
    final transfers = <String, int>{};
    final removeFromOthers = <String>{};
    for (final conflict in conflicts) {
      if (conflict.kind != LampOwnerConflictKind.phone) continue;
      if (decisionsById[conflict.conflictId] !=
          LampOwnerConflictAction.transferToSelectedOwner) {
        continue;
      }
      final usage = LookupService.instance.checkPhoneUsage(conflict.value);
      final sourceDeptId = usage.departmentId;
      if (sourceDeptId != null) {
        transfers[conflict.value] = sourceDeptId;
      }
      final hasOtherUserOwners = conflict.currentOwners.any(
        (label) => !label.startsWith('Κοινόχρηστο:'),
      );
      if (hasOtherUserOwners) {
        removeFromOthers.add(conflict.value);
      }
    }
    return UserPhoneConflictBatchResult(
      phonesToTransferShared: transfers,
      phonesToRemoveFromOtherUsers: removeFromOthers,
    );
  }

  /// Συγχρονισμός phones.department_id με το τμήμα του χρήστη (όπως Κατάλογος).
  Future<void> _assignUserPhonesToDepartment({
    required PhoneRepository phoneRepo,
    required int? departmentId,
    required List<String> phones,
    DatabaseExecutor? executor,
  }) async {
    if (departmentId == null) return;
    for (final phone in phones) {
      final trimmed = phone.trim();
      if (trimmed.isEmpty) continue;
      await phoneRepo.addDepartmentDirectPhone(
        departmentId,
        trimmed,
        executor: executor,
      );
    }
  }

  Future<List<TransferOperationResult>> _syncOwnerEquipmentLinks({
    required int userId,
    required List<String> equipmentCodes,
    required bool confirmEntityCreations,
    DatabaseExecutor? executor,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final equipment = EquipmentRepository(db);
    final e = executor ?? db;
    final allEquipment = await e.query(
      'equipment',
      where: 'COALESCE(is_deleted, 0) = ?',
      whereArgs: [0],
    );
    final operations = <TransferOperationResult>[];
    final desiredEquipmentIds = <int>{};
    final equipmentLabelById = <int, String>{
      for (final row in allEquipment)
        if (row['id'] is int)
          row['id'] as int: _text(row['code_equipment']),
    };
    for (final code in equipmentCodes) {
      final matched = allEquipment.firstWhere(
        (row) =>
            (row['is_deleted'] as int?) != 1 &&
            _norm(_text(row['code_equipment'])) == _norm(code),
        orElse: () => const <String, Object?>{},
      );
      final matchedId = matched['id'] as int?;
      if (matchedId != null) {
        desiredEquipmentIds.add(matchedId);
        continue;
      }
      final trimmedCode = code.trim();
      if (!confirmEntityCreations) {
        throw StateError(_kPendingEntityCreationError);
      }
      final createdId = await equipment.insertEquipmentFromMap(
        <String, dynamic>{
          'code_equipment': trimmedCode,
          'is_deleted': 0,
        },
        executor: executor,
      );
      desiredEquipmentIds.add(createdId);
      equipmentLabelById[createdId] = trimmedCode;
      operations.add(
        TransferOperationResult(
          kind: TransferOperationKind.created,
          entityKind: TransferEntityKind.equipment,
          label: trimmedCode,
          entityId: createdId,
        ),
      );
    }
    final existingLinks = await e.query(
      'user_equipment',
      columns: <String>['equipment_id'],
      where: 'user_id = ?',
      whereArgs: <Object?>[userId],
    );
    final existingEquipmentIds = <int>{
      for (final row in existingLinks)
        if (row['equipment_id'] is int) row['equipment_id'] as int,
    };
    for (final equipmentId
        in existingEquipmentIds.difference(desiredEquipmentIds)) {
      await equipment.unlinkUserFromEquipment(
        userId,
        equipmentId,
        executor: executor,
      );
      operations.add(
        TransferOperationResult(
          kind: TransferOperationKind.unlinked,
          entityKind: TransferEntityKind.equipment,
          label: equipmentLabelById[equipmentId] ?? '#$equipmentId',
          entityId: equipmentId,
        ),
      );
    }
    for (final equipmentId
        in desiredEquipmentIds.difference(existingEquipmentIds)) {
      await equipment.linkUserToEquipment(
        userId,
        equipmentId,
        executor: executor,
      );
      operations.add(
        TransferOperationResult(
          kind: TransferOperationKind.linked,
          entityKind: TransferEntityKind.equipment,
          label: equipmentLabelById[equipmentId] ?? '#$equipmentId',
          entityId: equipmentId,
        ),
      );
    }
    return operations;
  }

  Future<LampMigrationSaveResult> _saveEquipment({
    required Map<String, String> formValues,
    required int? selectedCandidateId,
    List<LampOwnerConflictDecision>? ownerConflictDecisions,
    required bool confirmEntityCreations,
    LampSoftDeletedDecision? softDeletedDecision,
  }) async {
    final code = (formValues['code_equipment'] ?? '').trim();
    if (code.isEmpty) {
      throw StateError('Ο κωδικός εξοπλισμού είναι υποχρεωτικός.');
    }

    final db = await DatabaseHelper.instance.database;
    final departments = DepartmentRepository(db);
    final equipment = EquipmentRepository(db);
    final departmentName = (formValues['department_name'] ?? '').trim();

    final reactivateId =
        softDeletedDecision?.action == LampSoftDeletedDecisionAction.reactivate
        ? softDeletedDecision!.recordId
        : null;
    final updateEquipmentId = selectedCandidateId ?? reactivateId;

    bool? keepCurrentOwners;
    if (updateEquipmentId != null) {
      final conflicts = await detectEquipmentConflicts(
        formValues: formValues,
        selectedCandidateId: updateEquipmentId,
      );
      final decisionsById = <String, LampOwnerConflictAction>{
        for (final decision
            in ownerConflictDecisions ?? const <LampOwnerConflictDecision>[])
          decision.conflictId: decision.action,
      };
      final unresolvedConflicts = conflicts
          .where((conflict) => !decisionsById.containsKey(conflict.conflictId))
          .toList(growable: false);
      if (unresolvedConflicts.isNotEmpty) {
        throw StateError(
          'Απαιτείται επίλυση διενέξεων για τηλέφωνα/εξοπλισμό.',
        );
      }

      keepCurrentOwners = conflicts.isNotEmpty &&
          decisionsById[conflicts.first.conflictId] ==
              LampOwnerConflictAction.keepWithoutAssignment;
    } else {
      await _requireSoftDeletedDecisionBeforeInsert(
        target: LampTransferTarget.equipment,
        formValues: formValues,
        softDeletedDecision: softDeletedDecision,
      );
    }

    return db.transaction((txn) async {
      final departmentId = departmentName.isEmpty
          ? null
          : await departments.getOrCreateDepartmentIdByName(
              departmentName,
              executor: txn,
            );
      final ownerOutcome = await _resolveOwnerId(
        formValues['owner_name'],
        confirmEntityCreations: confirmEntityCreations,
        executor: txn,
      );
      final ownerId = ownerOutcome?.ownerId;
      final ownerUserIds = ownerId == null ? const <int>[] : <int>[ownerId];
      final values = <String, dynamic>{
        'code_equipment': code,
        'type': _nullable(formValues['type']),
        'notes': _nullable(formValues['notes']),
        'department_id': departmentId,
        'location': _nullable(formValues['location']),
        'is_deleted': 0,
      };

      if (updateEquipmentId != null) {
        await equipment.updateEquipment(
          updateEquipmentId,
          values,
          executor: txn,
        );
        if (keepCurrentOwners != true) {
          await equipment.replaceEquipmentUsers(
            updateEquipmentId,
            ownerUserIds,
            executor: txn,
          );
        }
        return LampMigrationSaveResult(
          id: updateEquipmentId,
          updated: true,
          message: selectedCandidateId != null
              ? 'Ενημερώθηκε υπάρχων εξοπλισμός.'
              : 'Επαναφέρθηκε διαγραμμένος εξοπλισμός.',
        );
      }

      final id = await equipment.insertEquipmentFromMap(values, executor: txn);
      await equipment.replaceEquipmentUsers(
        id,
        ownerUserIds,
        executor: txn,
      );
      return LampMigrationSaveResult(
        id: id,
        updated: false,
        message: 'Δημιουργήθηκε νέος εξοπλισμός.',
      );
    });
  }

  Future<OwnerResolveOutcome?> _resolveOwnerId(
    String? ownerName, {
    required bool confirmEntityCreations,
    DatabaseExecutor? executor,
  }) async {
    final text = ownerName?.trim() ?? '';
    if (text.isEmpty) return null;
    final parsed = NameParserUtility.parse(text);
    final label = _fullName(parsed.firstName, parsed.lastName);
    final existingId = await _lookupOwnerIdByName(
      ownerName,
      executor: executor,
    );
    if (existingId != null) {
      return (
        ownerId: existingId,
        kind: TransferOperationKind.linked,
        label: label.isEmpty ? text : label,
      );
    }
    if (!confirmEntityCreations) {
      throw StateError(_kPendingEntityCreationError);
    }
    final db = await DatabaseHelper.instance.database;
    final users = UserRepository(db);
    final createdId = await users.insertUser(
      firstName: parsed.firstName,
      lastName: parsed.lastName,
      executor: executor,
    );
    return (
      ownerId: createdId,
      kind: TransferOperationKind.created,
      label: label.isEmpty ? text : label,
    );
  }

  Future<int?> _lookupOwnerIdByName(
    String? ownerName, {
    DatabaseExecutor? executor,
  }) async {
    final text = ownerName?.trim() ?? '';
    if (text.isEmpty) return null;
    final parsed = NameParserUtility.parse(text);
    final target = UserIdentityNormalizer.identityKeyForPerson(
      parsed.firstName,
      parsed.lastName,
    );
    if (target.isEmpty) return null;
    final db = await DatabaseHelper.instance.database;
    final e = executor ?? db;
    final users = await e.query(
      'users',
      where: 'COALESCE(is_deleted, 0) = 0',
    );
    for (final row in users) {
      if ((row['is_deleted'] as int?) == 1) continue;
      final key = UserIdentityNormalizer.identityKeyForPerson(
        _text(row['first_name']),
        _text(row['last_name']),
      );
      if (key == target) {
        return row['id'] as int?;
      }
    }
    return null;
  }

  List<LampMigrationCandidate> _topCandidates({
    required String source,
    required List<Map<String, dynamic>> rows,
    required String idKey,
    required String Function(Map<String, dynamic> row) labelBuilder,
    String? sourceDepartment,
    String? Function(Map<String, dynamic> row)? candidateDepartmentBuilder,
    Set<String>? identityMatchKeys,
  }) {
    final normalizedSource = _norm(source);
    if (normalizedSource.isEmpty) return const <LampMigrationCandidate>[];
    final scored = <LampMigrationCandidate>[];
    for (final row in rows) {
      final id = row[idKey] as int?;
      final label = labelBuilder(row);
      if (id == null || label.isEmpty) continue;
      final confidence = _resolutionService.similarityConfidenceScore(
        source,
        label,
        sourceDepartment: sourceDepartment,
        candidateDepartment: candidateDepartmentBuilder?.call(row),
      );
      final isExact = identityMatchKeys != null
          ? UserIdentityNormalizer.personMatchesIdentityKeys(
              personFirstName: _text(row['first_name']),
              personLastName: _text(row['last_name']),
              sourceKeys: identityMatchKeys,
            )
          : _norm(label) == normalizedSource;
      scored.add(
        LampMigrationCandidate(
          id: id,
          label: label,
          confidence: confidence,
          isExact: isExact,
        ),
      );
    }
    scored.sort((a, b) {
      final byConfidence = b.confidence.compareTo(a.confidence);
      if (byConfidence != 0) return byConfidence;
      return a.label.compareTo(b.label);
    });
    final filtered = scored
        .where(
          (candidate) =>
              candidate.isExact ||
              candidate.confidence >= kSuggestionConfidenceThreshold,
        )
        .take(3)
        .toList(growable: false);
    return filtered;
  }

  String? _nullable(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  String _fullName(String firstName, String lastName) {
    return '$firstName $lastName'.trim();
  }

  String _firstText(Object? first, [Object? second, Object? third]) {
    final a = _text(first);
    if (a.isNotEmpty) return a;
    final b = _text(second);
    if (b.isNotEmpty) return b;
    return _text(third);
  }

  String _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? '' : text;
  }

  String _norm(String value) => SearchTextNormalizer.normalizeForSearch(value);

  Future<void> _requireSoftDeletedDecisionBeforeInsert({
    required LampTransferTarget target,
    required Map<String, String> formValues,
    LampSoftDeletedDecision? softDeletedDecision,
  }) async {
    final match = await detectSoftDeletedMatch(
      target: target,
      formValues: formValues,
      selectedCandidateId: null,
    );
    if (match == null) return;
    if (softDeletedDecision == null ||
        softDeletedDecision.recordId != match.id) {
      throw StateError(_kSoftDeletedDecisionError);
    }
  }

  Future<LampSoftDeletedMatch?> _detectSoftDeletedOwnerMatch(
    Map<String, String> formValues,
  ) async {
    final firstName = (formValues['first_name'] ?? '').trim();
    final lastName = (formValues['last_name'] ?? '').trim();
    if (firstName.isEmpty && lastName.isEmpty) return null;
    final sourceKeys = UserIdentityNormalizer.matchingIdentityKeysFromFreeText(
      _fullName(firstName, lastName),
    );
    if (sourceKeys.isEmpty) return null;

    final db = await DatabaseHelper.instance.database;
    final activeRows = await db.query(
      'users',
      where: 'COALESCE(is_deleted, 0) = 0',
    );
    for (final row in activeRows) {
      if (UserIdentityNormalizer.personMatchesIdentityKeys(
        personFirstName: _text(row['first_name']),
        personLastName: _text(row['last_name']),
        sourceKeys: sourceKeys,
      )) {
        return null;
      }
    }

    final deletedRows = await db.query(
      'users',
      where: 'is_deleted = ?',
      whereArgs: [1],
    );
    for (final row in deletedRows) {
      if (UserIdentityNormalizer.personMatchesIdentityKeys(
        personFirstName: _text(row['first_name']),
        personLastName: _text(row['last_name']),
        sourceKeys: sourceKeys,
      )) {
        final id = row['id'] as int?;
        if (id == null) continue;
        return LampSoftDeletedMatch(
          id: id,
          label: _fullName(
            _text(row['first_name']),
            _text(row['last_name']),
          ),
        );
      }
    }
    return null;
  }

  Future<LampSoftDeletedMatch?> _detectSoftDeletedDepartmentMatch(
    Map<String, String> formValues,
  ) async {
    final name = (formValues['name'] ?? '').trim();
    if (name.isEmpty) return null;
    final nameKey = _norm(name);
    if (nameKey.isEmpty) return null;

    final db = await DatabaseHelper.instance.database;
    final activeRows = await db.query(
      'departments',
      where: 'COALESCE(is_deleted, 0) = 0 AND name_key = ?',
      whereArgs: [nameKey],
      limit: 1,
    );
    if (activeRows.isNotEmpty) return null;

    final deletedRows = await db.query(
      'departments',
      where: 'is_deleted = ? AND name_key = ?',
      whereArgs: [1, nameKey],
      limit: 1,
    );
    if (deletedRows.isEmpty) return null;
    final row = deletedRows.first;
    final id = row['id'] as int?;
    if (id == null) return null;
    return LampSoftDeletedMatch(
      id: id,
      label: _text(row['name']),
    );
  }

  Future<LampSoftDeletedMatch?> _detectSoftDeletedEquipmentMatch(
    Map<String, String> formValues,
  ) async {
    final code = (formValues['code_equipment'] ?? '').trim();
    if (code.isEmpty) return null;
    final codeKey = _norm(code);
    if (codeKey.isEmpty) return null;

    final db = await DatabaseHelper.instance.database;
    final activeRows = await db.query(
      'equipment',
      where: 'COALESCE(is_deleted, 0) = 0',
    );
    for (final row in activeRows) {
      if (_norm(_text(row['code_equipment'])) == codeKey) {
        return null;
      }
    }

    final deletedRows = await db.query(
      'equipment',
      where: 'is_deleted = ?',
      whereArgs: [1],
    );
    for (final row in deletedRows) {
      if (_norm(_text(row['code_equipment'])) == codeKey) {
        final id = row['id'] as int?;
        if (id == null) continue;
        return LampSoftDeletedMatch(
          id: id,
          label: _text(row['code_equipment']),
        );
      }
    }
    return null;
  }

  Future<void> _tombstoneSoftDeletedDepartmentNameKey(
    int departmentId, {
    DatabaseExecutor? executor,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final e = executor ?? db;
    final rows = await e.query(
      'departments',
      columns: <String>['name_key'],
      where: 'id = ?',
      whereArgs: [departmentId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final key = _text(rows.first['name_key']);
    if (key.isEmpty) return;
    await e.update(
      'departments',
      <String, Object?>{'name_key': '${key}__deleted__$departmentId'},
      where: 'id = ?',
      whereArgs: [departmentId],
    );
  }

  String _departmentLevelText(Map<String, dynamic> row) {
    final floorId = row['floor_id'];
    if (floorId != null) return floorId.toString();
    return _text(row['map_floor']);
  }

  static List<String> parseEquipmentCodes(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return const <String>[];
    final tokens = text
        .split(RegExp(r'[,\n;]+'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList(growable: false);
    final seen = <String>{};
    final normalizedUnique = <String>[];
    for (final token in tokens) {
      final key = SearchTextNormalizer.normalizeForSearch(token);
      if (key.isEmpty || seen.contains(key)) continue;
      seen.add(key);
      normalizedUnique.add(token);
    }
    return normalizedUnique;
  }

}
