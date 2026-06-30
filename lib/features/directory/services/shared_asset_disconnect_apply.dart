import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
  Map<String, SharedAssetTransferTarget> transfers,
) async {
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
    final deptId = await departments.getOrCreateDepartmentIdByName(newName);
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
Future<void> applyDepartmentSharedAssetDisconnectBatch(
  Database db,
  SharedAssetDisconnectBatchResult batch, {
  required int sourceDepartmentId,
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

  await reloadLookupAfterNewDepartments(batch);

  final phones = PhoneRepository(db);
  final equipment = EquipmentRepository(db);
  final phoneTransfers = await _resolvePhoneTransferTargets(
    db,
    batch.phoneTransfers,
  );
  final equipmentTransfers = await _resolvePhoneTransferTargets(
    db,
    batch.equipmentTransfers,
  );

  for (final phone in batch.phonesToKeep) {
    await phones.addDepartmentDirectPhone(sourceDepartmentId, phone);
  }
  for (final code in batch.equipmentToKeep) {
    await equipment.updateEquipmentDepartment(code, sourceDepartmentId);
  }

  final phonesLeavingSource = <String>{
    ...batch.phonesToDelete,
    ...phoneTransfers.keys,
  };
  for (final phone in phonesLeavingSource) {
    await phones.removeDepartmentDirectPhone(sourceDepartmentId, phone);
  }
  for (final entry in phoneTransfers.entries) {
    await phones.addDepartmentDirectPhone(entry.value, entry.key);
  }

  final equipmentLeavingSource = <String>{
    ...batch.equipmentToDelete,
    ...equipmentTransfers.keys,
  };
  for (final code in equipmentLeavingSource) {
    await equipment.clearEquipmentSharedDepartment(code, sourceDepartmentId);
  }
  for (final entry in equipmentTransfers.entries) {
    await equipment.updateEquipmentDepartment(entry.key, entry.value);
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

  if (batch.equipmentToDelete.isNotEmpty) {
    final equipmentIds = <int>[];
    for (final code in batch.equipmentToDelete) {
      final id = await equipment.getEquipmentIdByCode(code);
      if (id != null) equipmentIds.add(id);
    }
    if (equipmentIds.isNotEmpty) {
      await equipment.deleteEquipments(equipmentIds);
    }
  }
}
