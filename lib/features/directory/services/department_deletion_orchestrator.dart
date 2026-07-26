import '../../../core/database/sqlite_types.dart';
import '../../../core/database/department_repository.dart';
import '../../../core/services/lookup_service.dart';
import '../screens/widgets/department_employee_reassign_dialog.dart';
import '../screens/widgets/shared_asset_disconnect_dialog.dart';
import 'department_employee_deletion_apply.dart';
import 'department_employee_reassign_apply.dart';
import 'shared_asset_disconnect_apply.dart';
import 'user_deletion_undo_record.dart';

/// Υπάλληλος του διαγραφόμενου τμήματος που επιλέχθηκε προς **διαγραφή** (όχι
/// μεταφορά), μαζί με τις αποφάσεις τύχης του προσωπικού τηλεφώνου/εξοπλισμού του.
class DepartmentEmployeeDeletion {
  const DepartmentEmployeeDeletion({
    required this.userId,
    this.phoneBatch = const SharedAssetDisconnectBatchResult(),
    this.equipmentBatch = const SharedAssetDisconnectBatchResult(),
  });

  final int userId;
  final SharedAssetDisconnectBatchResult phoneBatch;
  final SharedAssetDisconnectBatchResult equipmentBatch;
}

/// Συγκεντρωμένο σχέδιο διαγραφής ενός τμήματος (αποφάσεις διαλόγων).
class DepartmentDeletionPlan {
  const DepartmentDeletionPlan({
    required this.departmentId,
    required this.employeeBatch,
    required this.sharedBatch,
    this.deletedEmployees = const [],
  });

  final int departmentId;
  final DepartmentEmployeeReassignBatch employeeBatch;
  final SharedAssetDisconnectBatchResult sharedBatch;
  final List<DepartmentEmployeeDeletion> deletedEmployees;
}

/// Εφαρμόζει όλα τα [plans] σε **ένα** transaction: μεταφορές υπαλλήλων,
/// διαγραφές υπαλλήλων (με την τύχη τηλεφώνων/εξοπλισμού τους), κοινόχρηστα,
/// και soft-delete των τμημάτων. Μετά το commit (και μόνο τότε) κάνει μία φορά
/// reload του [LookupService].
///
/// Επιστρέφει τον φάκελο αναίρεσης για τους διαγραμμένους υπαλλήλους (κενός αν
/// δεν διαγράφηκε κανένας), ώστε ο caller να τον φωλιάσει στην αναίρεση τμήματος.
Future<UserDeletionUndoRecord> applyDepartmentDeletionPlansAtomic(
  Database db,
  List<DepartmentDeletionPlan> plans,
) async {
  if (plans.isEmpty) {
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

  final allDeletions = <DepartmentEmployeeDeletion>[
    for (final plan in plans) ...plan.deletedEmployees,
  ];

  late UserDeletionUndoRecord employeesUndo;
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
    employeesUndo = await applyDepartmentEmployeeDeletionsInTxn(
      txn,
      db,
      allDeletions,
    );
    await DepartmentRepository(db).softDeleteDepartments([
      for (final p in plans) p.departmentId,
    ], executor: txn);
  });

  LookupService.instance.resetForReload();
  await LookupService.instance.loadFromDatabase();
  return employeesUndo;
}
