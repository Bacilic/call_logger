import '../../../core/database/department_repository.dart';
import '../../../core/database/equipment_repository.dart';
import '../../../core/database/phone_repository.dart';
import '../../../core/database/sqlite_types.dart';
import '../../../core/database/user_repository.dart';
import '../screens/widgets/shared_asset_disconnect_dialog.dart';
import 'department_deletion_orchestrator.dart';
import 'user_deletion_undo_record.dart';

/// Διαγράφει τους υπαλλήλους [deletions] ΜΕΣΑ στο δοσμένο [txn] (μαζί με την
/// τύχη του προσωπικού τηλεφώνου/εξοπλισμού τους) και επιστρέφει τον φάκελο
/// αναίρεσης για πλήρη επαναφορά τους.
///
/// Για διαγραφόμενο υπάλληλο δεν υπάρχει «παραμονή στο τμήμα» (το τμήμα
/// διαγράφεται) — μόνο μεταφορά ή διαγραφή στοιχείων.
Future<UserDeletionUndoRecord> applyDepartmentEmployeeDeletionsInTxn(
  DatabaseExecutor txn,
  Database db,
  List<DepartmentEmployeeDeletion> deletions,
) async {
  if (deletions.isEmpty) {
    return const UserDeletionUndoRecord(
      deletedUserIds: [],
      originalUserPhones: {},
      originalUserEquipmentIds: {},
      phoneDeptAdds: [],
      equipmentDeptSets: [],
      softDeletedPhoneNumbers: [],
      softDeletedEquipmentCodes: [],
    );
  }

  final users = UserRepository(db);
  final phones = PhoneRepository(db);
  final equipment = EquipmentRepository(db);
  final departments = DepartmentRepository(db);

  final ids = [for (final d in deletions) d.userId];
  final captured = await users.deleteUsersInTxn(txn, ids);

  final originalUserPhones = <int, List<String>>{};
  final originalUserEquipmentIds = <int, List<int>>{};
  final phoneDeptAdds = <PhoneDeptAdd>[];
  final equipmentDeptSets = <EquipmentDeptSet>[];
  final softDeletedPhoneNumbers = <String>[];
  final softDeletedEquipmentCodes = <String>[];

  Future<int?> resolveTarget(SharedAssetTransferTarget target) async {
    if (target.departmentId != null) return target.departmentId;
    final name = target.newDepartmentName?.trim();
    if (name == null || name.isEmpty) return null;
    return departments.getOrCreateDepartmentIdByName(name, executor: txn);
  }

  for (final del in deletions) {
    final cap = captured[del.userId];
    if (cap != null) {
      originalUserPhones[del.userId] = cap.phoneNumbers;
      originalUserEquipmentIds[del.userId] = cap.equipmentIds;
    }

    for (final entry in del.phoneBatch.phoneTransfers.entries) {
      final toId = await resolveTarget(entry.value);
      if (toId == null) continue;
      await phones.addDepartmentDirectPhone(toId, entry.key, executor: txn);
      phoneDeptAdds.add(
        PhoneDeptAdd(departmentId: toId, phoneNumber: entry.key),
      );
    }
    for (final number in del.phoneBatch.phonesToDelete) {
      final id = await phones.getPhoneIdByNumber(number, executor: txn);
      if (id == null) continue;
      await phones.softDeletePhones([id], executor: txn);
      softDeletedPhoneNumbers.add(number);
    }

    for (final entry in del.equipmentBatch.equipmentTransfers.entries) {
      final toId = await resolveTarget(entry.value);
      if (toId == null) continue;
      final eqId =
          await equipment.getEquipmentIdByCode(entry.key, executor: txn);
      await equipment.updateEquipmentDepartment(entry.key, toId, executor: txn);
      if (eqId != null) {
        equipmentDeptSets.add(
          EquipmentDeptSet(equipmentId: eqId, departmentId: toId),
        );
      }
    }
    for (final code in del.equipmentBatch.equipmentToDelete) {
      final id = await equipment.getEquipmentIdByCode(code, executor: txn);
      if (id == null) continue;
      await equipment.deleteEquipments([id], executor: txn);
      softDeletedEquipmentCodes.add(code);
    }
  }

  return UserDeletionUndoRecord(
    deletedUserIds: ids,
    originalUserPhones: originalUserPhones,
    originalUserEquipmentIds: originalUserEquipmentIds,
    phoneDeptAdds: phoneDeptAdds,
    equipmentDeptSets: equipmentDeptSets,
    softDeletedPhoneNumbers: softDeletedPhoneNumbers,
    softDeletedEquipmentCodes: softDeletedEquipmentCodes,
  );
}
