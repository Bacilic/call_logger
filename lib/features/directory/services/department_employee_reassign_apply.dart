import '../../../core/database/sqlite_types.dart';
import '../../../core/database/department_repository.dart';
import '../../../core/database/user_repository.dart';
import '../../../core/services/lookup_service.dart';
import '../screens/widgets/department_employee_reassign_dialog.dart';

/// Εφαρμόζει μεταφορές υπαλλήλων σε υπάρχοντα ή νέα τμήματα.
///
/// Περνάει μόνο `department_id` στο [UserRepository.updateUser] ώστε να μην
/// ενεργοποιηθεί επικύρωση τηλεφώνων.
///
/// Αν δοθεί [executor] (π.χ. μέσα σε εξωτερικό transaction), οι αλλαγές
/// γράφονται εκεί χωρίς νέο nested transaction και **χωρίς** reload του
/// LookupService — ευθύνη του caller μετά το commit.
Future<void> applyDepartmentEmployeeReassignBatch(
  Database db,
  DepartmentEmployeeReassignBatch batch, {
  DatabaseExecutor? executor,
}) async {
  if (batch.transfers.isEmpty) return;

  final departments = DepartmentRepository(db);
  final users = UserRepository(db);
  final resolved = <int, int>{};
  var createdNewDepartments = false;

  for (final entry in batch.transfers.entries) {
    final target = entry.value;
    if (target.departmentId != null) {
      resolved[entry.key] = target.departmentId!;
      continue;
    }
    final newName = target.newDepartmentName?.trim();
    if (newName == null || newName.isEmpty) continue;
    final deptId = await departments.getOrCreateDepartmentIdByName(
      newName,
      executor: executor,
    );
    if (deptId != null) {
      resolved[entry.key] = deptId;
      createdNewDepartments = true;
    }
  }

  for (final entry in resolved.entries) {
    await users.updateUser(
      entry.key,
      <String, dynamic>{
        'department_id': entry.value,
      },
      executor: executor,
    );
  }

  if (executor == null && createdNewDepartments) {
    LookupService.instance.resetForReload();
    await LookupService.instance.loadFromDatabase();
  }
}

