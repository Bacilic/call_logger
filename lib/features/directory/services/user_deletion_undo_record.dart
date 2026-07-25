import '../../../core/database/equipment_repository.dart';
import '../../../core/database/phone_repository.dart';
import '../../../core/database/sqlite_types.dart';
import '../../../core/database/user_repository.dart';

/// Ζεύγος τμήματος + αριθμού που προστέθηκε ως direct-phone κατά τη διαγραφή.
class PhoneDeptAdd {
  const PhoneDeptAdd({
    required this.departmentId,
    required this.phoneNumber,
  });

  final int departmentId;
  final String phoneNumber;
}

/// Ζεύγος εξοπλισμού + τμήματος που τέθηκε από `null` → dept κατά τη διαγραφή.
class EquipmentDeptSet {
  const EquipmentDeptSet({
    required this.equipmentId,
    required this.departmentId,
  });

  final int equipmentId;
  final int departmentId;
}

/// Φάκελος αναίρεσης διαγραφής υπαλλήλου (υπάλληλος + τηλέφωνα + εξοπλισμός).
///
/// Αποδεκτό κατάλοιπο: νέα κενά τμήματα που δημιουργήθηκαν από «μεταφορά σε νέο
/// τμήμα» **δεν** διαγράφονται στην αναίρεση (ασφάλεια δεδομένων).
class UserDeletionUndoRecord {
  const UserDeletionUndoRecord({
    required this.deletedUserIds,
    required this.originalUserPhones,
    required this.originalUserEquipmentIds,
    required this.phoneDeptAdds,
    required this.equipmentDeptSets,
    required this.softDeletedPhoneNumbers,
    required this.softDeletedEquipmentCodes,
  });

  final List<int> deletedUserIds;
  final Map<int, List<String>> originalUserPhones;
  final Map<int, List<int>> originalUserEquipmentIds;
  final List<PhoneDeptAdd> phoneDeptAdds;
  final List<EquipmentDeptSet> equipmentDeptSets;
  final List<String> softDeletedPhoneNumbers;
  final List<String> softDeletedEquipmentCodes;
}

Future<List<int>> _idsByNumberIncludingDeleted(
  DatabaseExecutor txn,
  List<String> numbers,
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

Future<List<int>> _idsByEquipmentCodeIncludingDeleted(
  DatabaseExecutor txn,
  List<String> codes,
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

Future<String?> _equipmentCodeById(
  DatabaseExecutor txn,
  int equipmentId,
) async {
  final rows = await txn.query(
    'equipment',
    columns: ['code_equipment'],
    where: 'id = ?',
    whereArgs: [equipmentId],
    limit: 1,
  );
  if (rows.isEmpty) return null;
  final code = (rows.first['code_equipment'] as String?)?.trim();
  if (code == null || code.isEmpty) return null;
  return code;
}

/// Αντιστροφή διαγραφής υπαλλήλου σε ένα μόνο transaction.
Future<void> applyUserDeletionUndo(
  Database db,
  UserDeletionUndoRecord record,
) async {
  if (record.deletedUserIds.isEmpty) return;

  final phones = PhoneRepository(db);
  final equipment = EquipmentRepository(db);
  final users = UserRepository(db);

  await db.transaction((txn) async {
    await applyUserDeletionUndoInTxn(
      txn,
      record,
      phones: phones,
      equipment: equipment,
      users: users,
    );
  });
}

/// Αντιστροφή διαγραφής υπαλλήλου ΜΕΣΑ σε δοσμένο [txn] (για φώλιασμα σε
/// μεγαλύτερη συναλλαγή, π.χ. αναίρεση διαγραφής τμήματος).
Future<void> applyUserDeletionUndoInTxn(
  DatabaseExecutor txn,
  UserDeletionUndoRecord record, {
  required PhoneRepository phones,
  required EquipmentRepository equipment,
  required UserRepository users,
}) async {
  if (record.deletedUserIds.isEmpty) return;
  {
    final softPhoneIds = await _idsByNumberIncludingDeleted(
      txn,
      record.softDeletedPhoneNumbers,
    );
    if (softPhoneIds.isNotEmpty) {
      await phones.restorePhones(softPhoneIds, executor: txn);
    }

    final softEquipmentIds = await _idsByEquipmentCodeIncludingDeleted(
      txn,
      record.softDeletedEquipmentCodes,
    );
    if (softEquipmentIds.isNotEmpty) {
      await equipment.restoreEquipments(softEquipmentIds, executor: txn);
    }

    for (final set in record.equipmentDeptSets) {
      final code = await _equipmentCodeById(txn, set.equipmentId);
      if (code == null) continue;
      await equipment.clearEquipmentSharedDepartment(
        code,
        set.departmentId,
        executor: txn,
      );
    }

    for (final add in record.phoneDeptAdds) {
      await phones.removeDepartmentDirectPhone(
        add.departmentId,
        add.phoneNumber,
        executor: txn,
      );
    }

    for (final entry in record.originalUserPhones.entries) {
      await users.replaceUserPhones(
        entry.key,
        entry.value,
        executor: txn,
      );
    }

    for (final entry in record.originalUserEquipmentIds.entries) {
      for (final equipmentId in entry.value) {
        await equipment.linkUserEquipment(
          entry.key,
          equipmentId,
          executor: txn,
        );
      }
    }

    await users.restoreUsers(record.deletedUserIds, executor: txn);
  }
}
