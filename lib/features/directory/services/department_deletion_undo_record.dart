import '../../../core/database/department_repository.dart';
import '../../../core/database/equipment_repository.dart';
import '../../../core/database/phone_repository.dart';
import '../../../core/database/sqlite_types.dart';
import '../../../core/database/user_repository.dart';
import 'user_deletion_undo_record.dart';

/// Υπάλληλος που μεταφέρθηκε αλλού κατά τη διαγραφή τμήματος.
class DepartmentDeletionReassignedEmployee {
  const DepartmentDeletionReassignedEmployee({
    required this.userId,
    required this.originalDeletedDeptId,
  });

  final int userId;
  final int originalDeletedDeptId;
}

/// Τηλέφωνο που μεταφέρθηκε από το διαγραμμένο τμήμα σε άλλο.
class DepartmentDeletionPhoneTransfer {
  const DepartmentDeletionPhoneTransfer({
    required this.phoneNumber,
    required this.fromDeletedDeptId,
    required this.toTargetDeptId,
  });

  final String phoneNumber;
  final int fromDeletedDeptId;
  final int toTargetDeptId;
}

/// Τηλέφωνο που soft-διαγράφηκε μαζί με το τμήμα.
class DepartmentDeletionSoftDeletedPhone {
  const DepartmentDeletionSoftDeletedPhone({
    required this.phoneNumber,
    required this.deletedDeptId,
  });

  final String phoneNumber;
  final int deletedDeptId;
}

/// Εξοπλισμός που μεταφέρθηκε από το διαγραμμένο τμήμα σε άλλο.
class DepartmentDeletionEquipmentTransfer {
  const DepartmentDeletionEquipmentTransfer({
    required this.code,
    required this.deletedDeptId,
    required this.toTargetDeptId,
  });

  final String code;
  final int deletedDeptId;
  final int toTargetDeptId;
}

/// Εξοπλισμός που soft-διαγράφηκε μαζί με το τμήμα.
class DepartmentDeletionSoftDeletedEquipment {
  const DepartmentDeletionSoftDeletedEquipment({
    required this.code,
    required this.deletedDeptId,
  });

  final String code;
  final int deletedDeptId;
}

/// Φάκελος αναίρεσης διαγραφής τμήματος (τμήμα + υπάλληλοι + κοινόχρηστα).
///
/// Τα [createdDepartmentIds] είναι τμήματα που δημιουργήθηκαν ως προορισμοί
/// «μεταφορά σε νέο τμήμα» κατά τη διαγραφή· στην αναίρεση soft-διαγράφονται
/// αφού επιστραφούν όλα τα στοιχεία.
class DepartmentDeletionUndoRecord {
  const DepartmentDeletionUndoRecord({
    required this.deletedDepartmentIds,
    required this.reassignedEmployees,
    required this.phoneTransfers,
    required this.softDeletedPhones,
    required this.equipmentTransfers,
    required this.softDeletedEquipment,
    this.deletedEmployeesUndo,
    this.createdDepartmentIds = const [],
  });

  final List<int> deletedDepartmentIds;
  final List<DepartmentDeletionReassignedEmployee> reassignedEmployees;
  final List<DepartmentDeletionPhoneTransfer> phoneTransfers;
  final List<DepartmentDeletionSoftDeletedPhone> softDeletedPhones;
  final List<DepartmentDeletionEquipmentTransfer> equipmentTransfers;
  final List<DepartmentDeletionSoftDeletedEquipment> softDeletedEquipment;

  /// Πλήρης αναίρεση για υπαλλήλους που **διαγράφηκαν** (όχι μεταφέρθηκαν) κατά
  /// τη διαγραφή του τμήματος· null αν δεν διαγράφηκε κανένας.
  final UserDeletionUndoRecord? deletedEmployeesUndo;

  /// Τμήματα που δημιουργήθηκαν ως προορισμοί μεταφοράς σε αυτή τη διαγραφή.
  final List<int> createdDepartmentIds;
}

Future<List<int>> _phoneIdsIncludingDeleted(
  DatabaseExecutor txn,
  Iterable<String> numbers,
) async {
  final ids = <int>[];
  for (final raw in numbers) {
    final t = raw.trim();
    if (t.isEmpty) continue;
    final rows = await txn.query(
      'phones',
      columns: ['id'],
      where: 'number = ?',
      whereArgs: [t],
      limit: 1,
    );
    if (rows.isEmpty) continue;
    final id = rows.first['id'] as int?;
    if (id != null) ids.add(id);
  }
  return ids;
}

Future<List<int>> _equipmentIdsIncludingDeleted(
  DatabaseExecutor txn,
  Iterable<String> codes,
) async {
  final ids = <int>[];
  for (final raw in codes) {
    final t = raw.trim();
    if (t.isEmpty) continue;
    final rows = await txn.query(
      'equipment',
      columns: ['id'],
      where: 'code_equipment = ?',
      whereArgs: [t],
      limit: 1,
    );
    if (rows.isEmpty) continue;
    final id = rows.first['id'] as int?;
    if (id != null) ids.add(id);
  }
  return ids;
}

/// Αντιστροφή διαγραφής τμήματος σε ένα μόνο transaction.
Future<void> applyDepartmentDeletionUndo(
  Database db,
  DepartmentDeletionUndoRecord record,
) async {
  if (record.deletedDepartmentIds.isEmpty) return;

  final phones = PhoneRepository(db);
  final equipment = EquipmentRepository(db);
  final users = UserRepository(db);
  final departments = DepartmentRepository(db);

  await db.transaction((txn) async {
    final deletedEmployeesUndo = record.deletedEmployeesUndo;
    if (deletedEmployeesUndo != null) {
      await applyUserDeletionUndoInTxn(
        txn,
        deletedEmployeesUndo,
        phones: phones,
        equipment: equipment,
        users: users,
      );
    }

    final softPhoneIds = await _phoneIdsIncludingDeleted(
      txn,
      record.softDeletedPhones.map((e) => e.phoneNumber),
    );
    if (softPhoneIds.isNotEmpty) {
      await phones.restorePhones(softPhoneIds, executor: txn);
    }

    final softEquipmentIds = await _equipmentIdsIncludingDeleted(
      txn,
      record.softDeletedEquipment.map((e) => e.code),
    );
    if (softEquipmentIds.isNotEmpty) {
      await equipment.restoreEquipments(softEquipmentIds, executor: txn);
    }

    for (final transfer in record.equipmentTransfers) {
      await equipment.updateEquipmentDepartment(
        transfer.code,
        transfer.deletedDeptId,
        executor: txn,
      );
    }
    for (final soft in record.softDeletedEquipment) {
      await equipment.updateEquipmentDepartment(
        soft.code,
        soft.deletedDeptId,
        executor: txn,
      );
    }

    for (final transfer in record.phoneTransfers) {
      await phones.removeDepartmentDirectPhone(
        transfer.toTargetDeptId,
        transfer.phoneNumber,
        executor: txn,
      );
      await phones.addDepartmentDirectPhone(
        transfer.fromDeletedDeptId,
        transfer.phoneNumber,
        executor: txn,
      );
    }
    for (final soft in record.softDeletedPhones) {
      await phones.addDepartmentDirectPhone(
        soft.deletedDeptId,
        soft.phoneNumber,
        executor: txn,
      );
    }

    for (final emp in record.reassignedEmployees) {
      await users.updateUser(emp.userId, <String, dynamic>{
        'department_id': emp.originalDeletedDeptId,
      }, executor: txn);
    }

    await departments.restoreDepartments(
      record.deletedDepartmentIds,
      executor: txn,
    );

    if (record.createdDepartmentIds.isNotEmpty) {
      await departments.softDeleteDepartments(
        record.createdDepartmentIds,
        executor: txn,
      );
    }
  });
}
