part of 'directory_repository.dart';

mixin DirectoryRepositoryDepartments on DirectoryRepositoryBase {
  Future<bool> departmentNameExists(String? name) =>
      _departments.departmentNameExists(name);

  Future<int?> getOrCreateDepartmentIdByName(
    String? name, {
    bool recordAudit = true,
    DatabaseExecutor? executor,
  }) =>
      _departments.getOrCreateDepartmentIdByName(
        name,
        recordAudit: recordAudit,
        executor: executor,
      );

  Future<List<Map<String, dynamic>>> getDepartments() =>
      _departments.getDepartments();

  Future<List<Map<String, dynamic>>> getActiveDepartments() =>
      _departments.getActiveDepartments();

  Future<Map<String, dynamic>?> getDepartmentRowById(int id) =>
      _departments.getDepartmentRowById(id);

  Future<int> insertDepartment(
    Map<String, dynamic> row, {
    DatabaseExecutor? executor,
  }) =>
      _departments.insertDepartment(row, executor: executor);

  Future<void> restoreDepartmentByName(
    String name, {
    String? building,
    String? color,
    String? notes,
  }) =>
      _departments.restoreDepartmentByName(
        name,
        building: building,
        color: color,
        notes: notes,
      );

  Future<int> saveDepartmentWithFloorContext(
    int departmentId,
    Map<String, dynamic> updates, {
    int? drawingFloorId,
    int? manualFloorId,
  }) =>
      _departments.saveDepartmentWithFloorContext(
        departmentId,
        updates,
        drawingFloorId: drawingFloorId,
        manualFloorId: manualFloorId,
      );

  Future<int> backfillDepartmentFloorIdsFromMapFloor() =>
      _departments.backfillDepartmentFloorIdsFromMapFloor();

  Future<DepartmentNameKeyBackfillResult> backfillAllDepartmentNameKeys() =>
      _departments.backfillAllDepartmentNameKeys();

  Future<int> updateDepartment(
    int id,
    Map<String, dynamic> values, {
    DatabaseExecutor? executor,
  }) =>
      _departments.updateDepartment(id, values, executor: executor);

  Future<void> bulkUpdateDepartments(
    List<int> ids,
    Map<String, dynamic> changes,
  ) =>
      _departments.bulkUpdateDepartments(ids, changes);

  Future<void> softDeleteDepartment(int id) =>
      _departments.softDeleteDepartment(id);

  Future<void> softDeleteDepartments(List<int> ids) =>
      _departments.softDeleteDepartments(ids);

  Future<void> restoreDepartments(List<int> ids) =>
      _departments.restoreDepartments(ids);

  Future<bool> departmentNameExistsExcluding(
    String? name,
    int excludeId,
  ) =>
      _departments.departmentNameExistsExcluding(name, excludeId);

  Future<String?> getDepartmentNameById(int departmentId) =>
      _departments.getDepartmentNameById(departmentId);
}
