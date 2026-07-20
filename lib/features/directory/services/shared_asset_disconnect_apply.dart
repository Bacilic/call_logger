import '../../../core/database/sqlite_types.dart';
import '../../../core/database/department_repository.dart';
import '../../../core/database/equipment_repository.dart';
import '../../../core/database/phone_repository.dart';
import '../../../core/services/lookup_service.dart';
import '../screens/widgets/shared_asset_disconnect_dialog.dart';

Future<void> reloadLookupAfterNewDepartments(
  SharedAssetDisconnectBatchResult batch,
) async {
  if (batch.newDepartmentNamesToCreate.isEmpty) return;
  LookupService.instance.resetForReload();
  await LookupService.instance.loadFromDatabase();
}

Future<Map<String, int>> _resolvePhoneTransferTargets(
  Database db,
  Map<String, SharedAssetTransferTarget> transfers, {
  DatabaseExecutor? executor,
}) async {
  final departments = DepartmentRepository(db);
  final out = <String, int>{};
  for (final entry in transfers.entries) {
    final target = entry.value;
    if (target.departmentId != null) {
      out[entry.key] = target.departmentId!;
      continue;
    }
    final newName = target.newDepartmentName?.trim();
    if (newName == null || newName.isEmpty) continue;
    final deptId = await departments.getOrCreateDepartmentIdByName(
      newName,
      executor: executor,
    );
    if (deptId != null) out[entry.key] = deptId;
  }
  return out;
}

/// Μετά από αποσύνδεση προσωπικού τηλεφώνου χρήστη (φόρμα ή διαγραφή χρήστη).
Future<void> applyPersonalPhoneDisconnectBatch(
  Database db,
  SharedAssetDisconnectBatchResult batch, {
  required int? sourceDepartmentId,
}) async {
  if (batch.phonesToKeep.isEmpty &&
      batch.phoneTransfers.isEmpty &&
      batch.phonesToDelete.isEmpty &&
      batch.newDepartmentNamesToCreate.isEmpty) {
    return;
  }

  await reloadLookupAfterNewDepartments(batch);

  final phones = PhoneRepository(db);
  final phoneTransfers = await _resolvePhoneTransferTargets(
    db,
    batch.phoneTransfers,
  );

  if (sourceDepartmentId != null) {
    for (final phone in batch.phonesToKeep) {
      await phones.addDepartmentDirectPhone(sourceDepartmentId, phone);
    }
  }

  for (final entry in phoneTransfers.entries) {
    await phones.addDepartmentDirectPhone(entry.value, entry.key);
  }

  if (batch.phonesToDelete.isNotEmpty) {
    final phoneIds = <int>[];
    for (final p in batch.phonesToDelete) {
      final id = await phones.getPhoneIdByNumber(p);
      if (id != null) phoneIds.add(id);
    }
    if (phoneIds.isNotEmpty) {
      await phones.softDeletePhones(phoneIds);
    }
  }
}

/// Μετά από αποδέσμευση κοινόχρηστων στοιχείων τμήματος (φόρμα ή διαγραφή τμήματος).
///
/// Αν δοθεί [executor] (π.χ. μέσα σε εξωτερικό transaction), οι αλλαγές
/// γράφονται εκεί χωρίς nested transactions και **χωρίς**
/// [reloadLookupAfterNewDepartments] — ευθύνη του caller μετά το commit.
Future<void> applyDepartmentSharedAssetDisconnectBatch(
  Database db,
  SharedAssetDisconnectBatchResult batch, {
  required int sourceDepartmentId,
  DatabaseExecutor? executor,
}) async {
  if (batch.phonesToKeep.isEmpty &&
      batch.equipmentToKeep.isEmpty &&
      batch.phoneTransfers.isEmpty &&
      batch.equipmentTransfers.isEmpty &&
      batch.phonesToDelete.isEmpty &&
      batch.equipmentToDelete.isEmpty &&
      batch.newDepartmentNamesToCreate.isEmpty) {
    return;
  }

  if (executor == null) {
    await reloadLookupAfterNewDepartments(batch);
  }

  final phones = PhoneRepository(db);
  final equipment = EquipmentRepository(db);
  final phoneTransfers = await _resolvePhoneTransferTargets(
    db,
    batch.phoneTransfers,
    executor: executor,
  );
  final equipmentTransfers = await _resolvePhoneTransferTargets(
    db,
    batch.equipmentTransfers,
    executor: executor,
  );

  for (final phone in batch.phonesToKeep) {
    await phones.addDepartmentDirectPhone(
      sourceDepartmentId,
      phone,
      executor: executor,
    );
  }
  for (final code in batch.equipmentToKeep) {
    await equipment.updateEquipmentDepartment(
      code,
      sourceDepartmentId,
      executor: executor,
    );
  }

  final phonesLeavingSource = <String>{
    ...batch.phonesToDelete,
    ...phoneTransfers.keys,
  };
  for (final phone in phonesLeavingSource) {
    await phones.removeDepartmentDirectPhone(
      sourceDepartmentId,
      phone,
      executor: executor,
    );
  }
  for (final entry in phoneTransfers.entries) {
    await phones.addDepartmentDirectPhone(
      entry.value,
      entry.key,
      executor: executor,
    );
  }

  final equipmentLeavingSource = <String>{
    ...batch.equipmentToDelete,
    ...equipmentTransfers.keys,
  };
  for (final code in equipmentLeavingSource) {
    await equipment.clearEquipmentSharedDepartment(
      code,
      sourceDepartmentId,
      executor: executor,
    );
  }
  for (final entry in equipmentTransfers.entries) {
    await equipment.updateEquipmentDepartment(
      entry.key,
      entry.value,
      executor: executor,
    );
  }

  if (batch.phonesToDelete.isNotEmpty) {
    final phoneIds = <int>[];
    for (final p in batch.phonesToDelete) {
      final id = await phones.getPhoneIdByNumber(p, executor: executor);
      if (id != null) phoneIds.add(id);
    }
    if (phoneIds.isNotEmpty) {
      await phones.softDeletePhones(phoneIds, executor: executor);
    }
  }

  if (batch.equipmentToDelete.isNotEmpty) {
    final equipmentIds = <int>[];
    for (final code in batch.equipmentToDelete) {
      final id = await equipment.getEquipmentIdByCode(
        code,
        executor: executor,
      );
      if (id != null) equipmentIds.add(id);
    }
    if (equipmentIds.isNotEmpty) {
      await equipment.deleteEquipments(equipmentIds, executor: executor);
    }
  }
}

