import '../../../core/database/sqlite_types.dart';
import '../../../core/database/department_repository.dart';
import '../../../core/services/lookup_service.dart';
import '../screens/widgets/department_employee_reassign_dialog.dart';
import '../screens/widgets/shared_asset_disconnect_dialog.dart';
import 'department_employee_reassign_apply.dart';
import 'shared_asset_disconnect_apply.dart';

/// Συγκεντρωμένο σχέδιο διαγραφής ενός τμήματος (αποφάσεις διαλόγων).
class DepartmentDeletionPlan {
  const DepartmentDeletionPlan({
    required this.departmentId,
    required this.employeeBatch,
    required this.sharedBatch,
  });

  final int departmentId;
  final DepartmentEmployeeReassignBatch employeeBatch;
  final SharedAssetDisconnectBatchResult sharedBatch;
}

/// Εφαρμόζει όλα τα [plans] σε **ένα** transaction: μεταφορές υπαλλήλων,
/// κοινόχρηστα, και soft-delete των τμημάτων. Μετά το commit (και μόνο τότε)
/// κάνει μία φορά reload του [LookupService].
Future<void> applyDepartmentDeletionPlansAtomic(
  Database db,
  List<DepartmentDeletionPlan> plans,
) async {
  if (plans.isEmpty) return;

  await db.transaction((txn) async {
    for (final plan in plans) {
      await applyDepartmentEmployeeReassignBatch(
        db,
        plan.employeeBatch,
        executor: txn,
      );
      await applyDepartmentSharedAssetDisconnectBatch(
        db,
        plan.sharedBatch,
        sourceDepartmentId: plan.departmentId,
        executor: txn,
      );
    }
    await DepartmentRepository(db).softDeleteDepartments(
      [for (final p in plans) p.departmentId],
      executor: txn,
    );
  });

  LookupService.instance.resetForReload();
  await LookupService.instance.loadFromDatabase();
}
