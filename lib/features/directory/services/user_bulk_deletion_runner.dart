// Ενορχήστρωση μαζικής διαγραφής υπαλλήλων: προετοιμασία, ατομική εκτέλεση,
// εγγραφή αναίρεσης και σύνοψη ενεργειών — χωρίς widgets και χωρίς διαλόγους.
//
// Το widget κρατά ό,τι είναι όντως δικό του: πότε ρωτά τον χρήστη και τι του
// δείχνει. Ό,τι αφορά δεδομένα ζει εδώ και τεστάρεται χωρίς UI.

import '../../../core/database/department_repository.dart';
import '../../../core/database/equipment_repository.dart';
import '../../../core/database/sqlite_types.dart';
import '../../../core/database/user_delete_equipment_policy.dart';
import '../../../core/database/user_delete_phone_policy.dart';
import '../../../core/database/user_repository.dart';
import '../../calls/models/user_model.dart';
import 'asset_disconnect_models.dart';
import 'asset_disconnect_session.dart';
import 'shared_asset_disconnect_apply.dart';
import 'user_deletion_messages.dart';
import 'user_deletion_undo_record.dart';

/// Οι απαντήσεις του χρήστη για τα στοιχεία ενός υπαλλήλου.
typedef UserDisconnectBatch = ({
  SharedAssetDisconnectBatchResult batch,
  int? sourceDepartmentId,
});

/// Ό,τι πρέπει να ξέρουμε ΠΡΙΝ ρωτήσουμε τον χρήστη.
///
/// Τα αρχικά τηλέφωνα/εξοπλισμοί διαβάζονται εδώ, όσο οι συνδέσεις υπάρχουν
/// ακόμα: μετά τη διαγραφή δεν υπάρχει τρόπος να ανακτηθούν για την αναίρεση.
class UserBulkDeletionPlan {
  const UserBulkDeletionPlan({
    required this.users,
    required this.exclusivePhones,
    required this.exclusiveEquipment,
    required this.originalUserPhones,
    required this.originalUserEquipmentIds,
  });

  final List<UserModel> users;
  final List<ExclusivePhoneForUserDelete> exclusivePhones;
  final List<ExclusiveEquipmentForUserDelete> exclusiveEquipment;
  final Map<int, List<String>> originalUserPhones;
  final Map<int, List<int>> originalUserEquipmentIds;

  List<int> get userIds => [
    for (final u in users)
      if (u.id != null) u.id!,
  ];

  bool get hasAssetsToResolve =>
      exclusivePhones.isNotEmpty || exclusiveEquipment.isNotEmpty;

  Map<int, String> get _nameByUserId => {
    for (final u in users)
      if (u.id != null) u.id!: '${u.firstName} ${u.lastName}'.trim(),
  };

  /// Τα στοιχεία που θα ρωτηθούν, με τη σειρά που θα ρωτηθούν και με πλήρη
  /// ταυτότητα (κάτοχος + τμήμα) ώστε ο χρήστης να μη βλέπει ξερούς αριθμούς.
  List<AssetDisconnectItem> disconnectItems() {
    final names = _nameByUserId;
    return <AssetDisconnectItem>[
      for (final phone in exclusivePhones)
        AssetDisconnectItem.phone(
          phone.number,
          ownerName: names[phone.userId],
          departmentId: phone.departmentId,
          departmentName: phone.departmentName,
        ),
      for (final item in exclusiveEquipment)
        AssetDisconnectItem.equipment(
          item.codeEquipment,
          ownerName: names[item.userId],
          departmentId: item.departmentId,
          departmentName: item.departmentName,
        ),
    ];
  }

  /// Μία συνεδρία για ΟΛΗ τη διαγραφή: ο μετρητής μετρά τηλέφωνα και
  /// εξοπλισμούς όλων των υπαλλήλων μαζί, και μια γρήγορη επιλογή ισχύει από
  /// εκεί και πέρα για όλους τους υπόλοιπους.
  AssetDisconnectSession createDisconnectSession({
    AssetDisconnectCompletedWork? Function()? completedWork,
  }) {
    return AssetDisconnectSession(
      items: disconnectItems(),
      cancelScopeDescription: userDeletionCancelScopeDescription(users.length),
      completedWork: completedWork,
    );
  }
}

/// Διαβάζει από τη βάση ό,τι χρειάζεται η ροή πριν από τους διαλόγους.
Future<UserBulkDeletionPlan> prepareUserBulkDeletion({
  required Database db,
  required List<UserModel> users,
}) async {
  final repo = UserRepository(db);
  final ids = [
    for (final u in users)
      if (u.id != null) u.id!,
  ];

  final exclusivePhones = await repo.findExclusivePhonesForUserDelete(ids);
  final exclusiveEquipment = await repo.findExclusiveEquipmentForUserDelete(
    ids,
  );

  final originalUserPhones = <int, List<String>>{};
  final originalUserEquipmentIds = <int, List<int>>{};
  for (final uid in ids) {
    originalUserPhones[uid] = await repo.userPhoneNumbersOrdered(db, uid);
    originalUserEquipmentIds[uid] = (await repo.equipmentIdsForUser(
      uid,
    )).toList();
  }

  return UserBulkDeletionPlan(
    users: users,
    exclusivePhones: exclusivePhones,
    exclusiveEquipment: exclusiveEquipment,
    originalUserPhones: originalUserPhones,
    originalUserEquipmentIds: originalUserEquipmentIds,
  );
}

/// Διαγράφει τους υπαλλήλους και εφαρμόζει τις αποφάσεις σε ΜΙΑ συναλλαγή.
///
/// Διακοπή στη μέση δεν αφήνει διαγραμμένους υπαλλήλους με τα τηλέφωνά τους σε
/// ενδιάμεση κατάσταση. Επιστρέφει την εγγραφή αναίρεσης, ήδη συμπληρωμένη.
Future<UserDeletionUndoRecord> applyUserBulkDeletion({
  required Database db,
  required UserBulkDeletionPlan plan,
  required List<UserDisconnectBatch> phoneBatches,
  required List<UserDisconnectBatch> equipmentBatches,
}) async {
  final repo = UserRepository(db);
  final ids = plan.userIds;

  await db.transaction((txn) async {
    await repo.deleteUsers(ids, executor: txn);
    for (final pending in phoneBatches) {
      await applyPersonalPhoneDisconnectBatch(
        db,
        pending.batch,
        sourceDepartmentId: pending.sourceDepartmentId,
        executor: txn,
      );
    }
    for (final pending in equipmentBatches) {
      await applyPersonalEquipmentDisconnectBatch(
        db,
        pending.batch,
        sourceDepartmentId: pending.sourceDepartmentId,
        executor: txn,
      );
    }
  });

  return _buildUndoRecord(
    db: db,
    ids: ids,
    plan: plan,
    phoneBatches: phoneBatches,
    equipmentBatches: equipmentBatches,
  );
}

Future<UserDeletionUndoRecord> _buildUndoRecord({
  required Database db,
  required List<int> ids,
  required UserBulkDeletionPlan plan,
  required List<UserDisconnectBatch> phoneBatches,
  required List<UserDisconnectBatch> equipmentBatches,
}) async {
  final phoneDeptAdds = <PhoneDeptAdd>[];
  final equipmentDeptSets = <EquipmentDeptSet>[];
  final softDeletedPhoneNumbers = <String>[];
  final softDeletedEquipmentCodes = <String>[];
  final equipmentRepo = EquipmentRepository(db);

  for (final pending in phoneBatches) {
    final sourceDeptId = pending.sourceDepartmentId;
    for (final phone in pending.batch.phonesToKeep) {
      if (sourceDeptId == null) continue;
      phoneDeptAdds.add(
        PhoneDeptAdd(departmentId: sourceDeptId, phoneNumber: phone),
      );
    }
    for (final entry in pending.batch.phoneTransfers.entries) {
      final deptId = await _resolveTransferDeptId(db, entry.value);
      if (deptId == null) continue;
      phoneDeptAdds.add(
        PhoneDeptAdd(departmentId: deptId, phoneNumber: entry.key),
      );
    }
    softDeletedPhoneNumbers.addAll(pending.batch.phonesToDelete);
  }

  for (final pending in equipmentBatches) {
    final sourceDeptId = pending.sourceDepartmentId;
    for (final code in pending.batch.equipmentToKeep) {
      if (sourceDeptId == null) continue;
      final eid = await equipmentRepo.getEquipmentIdByCode(code);
      if (eid == null) continue;
      equipmentDeptSets.add(
        EquipmentDeptSet(equipmentId: eid, departmentId: sourceDeptId),
      );
    }
    for (final entry in pending.batch.equipmentTransfers.entries) {
      final deptId = await _resolveTransferDeptId(db, entry.value);
      if (deptId == null) continue;
      final eid = await equipmentRepo.getEquipmentIdByCode(entry.key);
      if (eid == null) continue;
      equipmentDeptSets.add(
        EquipmentDeptSet(equipmentId: eid, departmentId: deptId),
      );
    }
    softDeletedEquipmentCodes.addAll(pending.batch.equipmentToDelete);
  }

  return UserDeletionUndoRecord(
    deletedUserIds: ids,
    originalUserPhones: plan.originalUserPhones,
    originalUserEquipmentIds: plan.originalUserEquipmentIds,
    phoneDeptAdds: phoneDeptAdds,
    equipmentDeptSets: equipmentDeptSets,
    softDeletedPhoneNumbers: softDeletedPhoneNumbers,
    softDeletedEquipmentCodes: softDeletedEquipmentCodes,
  );
}

/// Το τμήμα-στόχος μιας μεταφοράς — υπάρχον ή νεοδημιουργημένο.
Future<int?> _resolveTransferDeptId(
  Database db,
  SharedAssetTransferTarget target,
) async {
  if (target.departmentId != null) return target.departmentId;
  return DepartmentRepository(
    db,
  ).findActiveDepartmentIdByName(target.newDepartmentName);
}

/// Τι έγινε με κάθε τηλέφωνο/εξοπλισμό, για τη σύνοψη στο snackbar.
List<UserDeletionAssetAction> userDeletionAssetActions({
  required List<UserDisconnectBatch> phoneBatches,
  required List<UserDisconnectBatch> equipmentBatches,
}) {
  final actions = <UserDeletionAssetAction>[];

  void collect(SharedAssetDisconnectBatchResult batch, {required bool phones}) {
    final transfers = phones
        ? batch.phoneTransfers.keys
        : batch.equipmentTransfers.keys;
    final deleted = phones ? batch.phonesToDelete : batch.equipmentToDelete;
    final kept = phones ? batch.phonesToKeep : batch.equipmentToKeep;

    for (final id in transfers) {
      actions.add(
        UserDeletionAssetAction(
          kind: UserDeletionAssetActionKind.transfer,
          identifier: id,
          isPhone: phones,
        ),
      );
    }
    for (final id in deleted) {
      actions.add(
        UserDeletionAssetAction(
          kind: UserDeletionAssetActionKind.delete,
          identifier: id,
          isPhone: phones,
        ),
      );
    }
    for (final id in kept) {
      actions.add(
        UserDeletionAssetAction(
          kind: UserDeletionAssetActionKind.keep,
          identifier: id,
          isPhone: phones,
        ),
      );
    }
  }

  for (final pending in phoneBatches) {
    collect(pending.batch, phones: true);
  }
  for (final pending in equipmentBatches) {
    collect(pending.batch, phones: false);
  }
  return actions;
}
