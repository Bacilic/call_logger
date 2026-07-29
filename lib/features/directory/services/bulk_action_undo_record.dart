import '../../../core/database/department_repository.dart';
import '../../../core/database/equipment_repository.dart';
import '../../../core/database/phone_repository.dart';
import '../../../core/database/sqlite_types.dart';
import '../../../core/database/user_repository.dart';
import 'user_deletion_undo_record.dart' show PhoneDeptAdd;

/// Δεσμός χρήστη-εξοπλισμού που λύθηκε (για επανασύνδεση στην αναίρεση).
class BulkUserEquipmentUnlink {
  const BulkUserEquipmentUnlink({
    required this.userId,
    required this.equipmentId,
  });

  final int userId;
  final int equipmentId;
}

/// Πακέτο πλήρους αναίρεσης μίας μαζικής ενέργειας του καταλόγου.
///
/// Ένα κοινό σχήμα για ΟΛΕΣ τις μαζικές ενέργειες — υπαλλήλων και εξοπλισμού.
/// Τα πεδία που δεν αφορούν την εκάστοτε ενέργεια μένουν κενά.
class BulkActionUndoRecord {
  const BulkActionUndoRecord({
    this.userDepartmentBefore = const {},
    this.userPhonesBefore = const {},
    this.phoneDeptAdds = const [],
    this.equipmentDepartmentBefore = const {},
    this.equipmentDepartmentAfter = const {},
    this.unlinkedUserEquipment = const [],
    this.softDeletedPhoneNumbers = const [],
    this.softDeletedEquipmentCodes = const [],
    this.userNotesBefore = const {},
    this.equipmentFieldsBefore = const {},
    this.equipmentOwnersBefore = const {},
    this.departmentFieldsBefore = const {},
    this.createdDepartmentId,
  });

  final Map<int, int?> userDepartmentBefore;
  final Map<int, List<String>> userPhonesBefore;
  final List<PhoneDeptAdd> phoneDeptAdds;

  /// code_equipment → τμήμα ΠΡΙΝ την αλλαγή (null = ήταν χωρίς τμήμα).
  final Map<String, int?> equipmentDepartmentBefore;

  /// code_equipment → τμήμα ΜΕΤΑ την αλλαγή (για αντιστροφή του null-πριν).
  final Map<String, int> equipmentDepartmentAfter;

  final List<BulkUserEquipmentUnlink> unlinkedUserEquipment;
  final List<String> softDeletedPhoneNumbers;
  final List<String> softDeletedEquipmentCodes;
  final Map<int, String?> userNotesBefore;

  /// equipment.id → στήλες του πίνακα `equipment` ΠΡΙΝ την αλλαγή
  /// (type, notes, location, remote_params, default_remote_tool, department_id).
  final Map<int, Map<String, Object?>> equipmentFieldsBefore;

  /// equipment.id → κάτοχοι (`user_equipment`) ΠΡΙΝ την αλλαγή.
  final Map<int, List<int>> equipmentOwnersBefore;

  /// departments.id → στήλες του πίνακα `departments` ΠΡΙΝ την αλλαγή
  /// (building, color, notes, group_name, map_hidden).
  final Map<int, Map<String, Object?>> departmentFieldsBefore;

  /// Τμήμα που δημιουργήθηκε ως προορισμός — η αναίρεση το σβήνει κι αυτό.
  final int? createdDepartmentId;

  bool get isEmpty =>
      userDepartmentBefore.isEmpty &&
      userPhonesBefore.isEmpty &&
      phoneDeptAdds.isEmpty &&
      equipmentDepartmentBefore.isEmpty &&
      unlinkedUserEquipment.isEmpty &&
      softDeletedPhoneNumbers.isEmpty &&
      softDeletedEquipmentCodes.isEmpty &&
      userNotesBefore.isEmpty &&
      equipmentFieldsBefore.isEmpty &&
      equipmentOwnersBefore.isEmpty &&
      departmentFieldsBefore.isEmpty &&
      createdDepartmentId == null;
}

Future<List<int>> _phoneIdsByNumberIncludingDeleted(
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

Future<List<int>> _equipmentIdsByCodeIncludingDeleted(
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

/// Πλήρης αναίρεση μαζικής ενέργειας (υπαλλήλων ή εξοπλισμού) σε ΜΙΑ συναλλαγή.
Future<void> applyBulkActionUndo(
  Database db,
  BulkActionUndoRecord record,
) async {
  if (record.isEmpty) return;

  final users = UserRepository(db);
  final phones = PhoneRepository(db);
  final equipment = EquipmentRepository(db);
  final departments = DepartmentRepository(db);

  await db.transaction((txn) async {
    final softPhoneIds = await _phoneIdsByNumberIncludingDeleted(
      txn,
      record.softDeletedPhoneNumbers,
    );
    if (softPhoneIds.isNotEmpty) {
      await phones.restorePhones(softPhoneIds, executor: txn);
    }

    final softEquipmentIds = await _equipmentIdsByCodeIncludingDeleted(
      txn,
      record.softDeletedEquipmentCodes,
    );
    if (softEquipmentIds.isNotEmpty) {
      await equipment.restoreEquipments(softEquipmentIds, executor: txn);
    }

    for (final link in record.unlinkedUserEquipment) {
      await equipment.linkUserEquipment(
        link.userId,
        link.equipmentId,
        executor: txn,
      );
    }

    // Οι στήλες του εξοπλισμού γράφονται απευθείας: το πακέτο κρατά ΟΛΟΚΛΗΡΗ
    // την προηγούμενη τιμή κάθε στήλης, οπότε η επαναφορά είναι αντιγραφή.
    for (final entry in record.equipmentFieldsBefore.entries) {
      if (entry.value.isEmpty) continue;
      await txn.update(
        'equipment',
        entry.value,
        where: 'id = ?',
        whereArgs: [entry.key],
      );
    }

    for (final entry in record.equipmentOwnersBefore.entries) {
      await equipment.replaceEquipmentUsers(
        entry.key,
        entry.value,
        executor: txn,
      );
    }

    for (final entry in record.departmentFieldsBefore.entries) {
      if (entry.value.isEmpty) continue;
      await txn.update(
        'departments',
        entry.value,
        where: 'id = ?',
        whereArgs: [entry.key],
      );
    }

    for (final entry in record.equipmentDepartmentBefore.entries) {
      final code = entry.key;
      final before = entry.value;
      if (before == null) {
        final after = record.equipmentDepartmentAfter[code];
        if (after != null) {
          await equipment.clearEquipmentSharedDepartment(
            code,
            after,
            executor: txn,
          );
        }
      } else {
        await equipment.updateEquipmentDepartment(code, before, executor: txn);
      }
    }

    for (final add in record.phoneDeptAdds) {
      await phones.removeDepartmentDirectPhone(
        add.departmentId,
        add.phoneNumber,
        executor: txn,
      );
    }

    for (final entry in record.userPhonesBefore.entries) {
      await users.replaceUserPhones(entry.key, entry.value, executor: txn);
    }

    for (final entry in record.userDepartmentBefore.entries) {
      await users.updateUser(
        entry.key,
        {'department_id': entry.value},
        executor: txn,
        recordAudit: false,
        skipPhonePolicyValidation: true,
      );
    }

    for (final entry in record.userNotesBefore.entries) {
      await users.updateUser(
        entry.key,
        {'notes': entry.value},
        executor: txn,
        recordAudit: false,
        skipPhonePolicyValidation: true,
      );
    }

    final created = record.createdDepartmentId;
    if (created != null) {
      await departments.softDeleteDepartments([created], executor: txn);
    }
  });
}
