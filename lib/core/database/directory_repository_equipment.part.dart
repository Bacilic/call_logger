part of 'directory_repository.dart';

mixin DirectoryRepositoryEquipment on DirectoryRepositoryBase {
  Future<int?> getEquipmentIdByCode(String code) =>
      _equipment.getEquipmentIdByCode(code);

  Future<int> countEquipmentReferencesExcludingAudit(int equipmentId) =>
      _equipment.countEquipmentReferencesExcludingAudit(equipmentId);

  Future<bool> equipmentCodeExists(String equipmentCode) =>
      _equipment.equipmentCodeExists(equipmentCode);

  Future<Map<int, int>> getEquipmentDefaultRemoteToolUsageCounts() =>
      _equipment.getEquipmentDefaultRemoteToolUsageCounts();

  Future<void> updateEquipmentDepartment(
    String equipmentCode,
    int departmentId,
  ) =>
      _equipment.updateEquipmentDepartment(equipmentCode, departmentId);

  Future<void> clearEquipmentSharedDepartment(
    String equipmentCode,
    int departmentId,
  ) =>
      _equipment.clearEquipmentSharedDepartment(equipmentCode, departmentId);

  Future<void> removeEquipmentFromAllUsers(
    String equipmentCode, {
    DatabaseExecutor? executor,
  }) =>
      _equipment.removeEquipmentFromAllUsers(
        equipmentCode,
        executor: executor,
      );

  Future<List<Map<String, dynamic>>> getAllEquipment() =>
      _equipment.getAllEquipment();

  Future<List<Map<String, dynamic>>> getAllUserEquipmentLinks() =>
      _equipment.getAllUserEquipmentLinks();

  Future<int> countUsersLinkedToEquipment(int equipmentId) =>
      _equipment.countUsersLinkedToEquipment(equipmentId);

  Future<void> unlinkUserFromEquipment(
    int userId,
    int equipmentId, {
    DatabaseExecutor? executor,
  }) =>
      _equipment.unlinkUserFromEquipment(
        userId,
        equipmentId,
        executor: executor,
      );

  Future<void> linkUserToEquipment(
    int userId,
    int equipmentId, {
    DatabaseExecutor? executor,
  }) =>
      _equipment.linkUserToEquipment(
        userId,
        equipmentId,
        executor: executor,
      );

  Future<void> copyUserEquipmentLinks(int fromUserId, int toUserId) =>
      _equipment.copyUserEquipmentLinks(fromUserId, toUserId);

  Future<void> replaceEquipmentUsers(
    int equipmentId,
    List<int> userIds, {
    DatabaseExecutor? executor,
  }) =>
      _equipment.replaceEquipmentUsers(
        equipmentId,
        userIds,
        executor: executor,
      );

  Future<int> insertEquipmentFromMap(
    Map<String, dynamic> row, {
    DatabaseExecutor? executor,
  }) =>
      _equipment.insertEquipmentFromMap(row, executor: executor);

  Future<int> updateEquipment(
    int id,
    Map<String, dynamic> values, {
    DatabaseExecutor? executor,
  }) =>
      _equipment.updateEquipment(id, values, executor: executor);

  Future<void> bulkUpdateEquipments(
    List<int> ids,
    Map<String, dynamic> changes,
  ) =>
      _equipment.bulkUpdateEquipments(ids, changes);

  Future<void> deleteEquipments(List<int> ids) =>
      _equipment.deleteEquipments(ids);

  Future<void> restoreEquipment(List<int> ids) =>
      _equipment.restoreEquipment(ids);
}
