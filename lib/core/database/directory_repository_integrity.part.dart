part of 'directory_repository.dart';

mixin DirectoryRepositoryIntegrity on DirectoryRepositoryBase {
  Future<void> softDeleteTask(int id) => _integrity.softDeleteTask(id);

  Future<void> softDeletePhoneForIntegrity({
    required int phoneId,
    required String details,
    Map<String, dynamic>? oldValues,
    Map<String, dynamic>? newValues,
  }) =>
      _integrity.softDeletePhoneForIntegrity(
        phoneId: phoneId,
        details: details,
        oldValues: oldValues,
        newValues: newValues,
      );

  Future<void> deleteCallExternalLinkForIntegrity({
    required int linkId,
    required String details,
    Map<String, dynamic>? oldValues,
    Map<String, dynamic>? newValues,
  }) =>
      _integrity.deleteCallExternalLinkForIntegrity(
        linkId: linkId,
        details: details,
        oldValues: oldValues,
        newValues: newValues,
      );

  Future<void> deleteOrphanUserPhonesJunction({
    required int userId,
    required int phoneId,
    required String details,
    Map<String, dynamic>? oldValues,
    Map<String, dynamic>? newValues,
  }) =>
      _integrity.deleteOrphanUserPhonesJunction(
        userId: userId,
        phoneId: phoneId,
        details: details,
        oldValues: oldValues,
        newValues: newValues,
      );

  Future<void> deleteOrphanDepartmentPhonesJunction({
    required int departmentId,
    required int phoneId,
    required String details,
    Map<String, dynamic>? oldValues,
    Map<String, dynamic>? newValues,
  }) =>
      _integrity.deleteOrphanDepartmentPhonesJunction(
        departmentId: departmentId,
        phoneId: phoneId,
        details: details,
        oldValues: oldValues,
        newValues: newValues,
      );

  Future<void> deleteOrphanUserEquipmentJunction({
    required int userId,
    required int equipmentId,
    required String details,
    Map<String, dynamic>? oldValues,
    Map<String, dynamic>? newValues,
  }) =>
      _integrity.deleteOrphanUserEquipmentJunction(
        userId: userId,
        equipmentId: equipmentId,
        details: details,
        oldValues: oldValues,
        newValues: newValues,
      );

  Future<void> linkOrphanPhoneToDepartmentForIntegrity({
    required int phoneId,
    required int departmentId,
    required String details,
    Map<String, dynamic>? oldValues,
    Map<String, dynamic>? newValues,
  }) =>
      _integrity.linkOrphanPhoneToDepartmentForIntegrity(
        phoneId: phoneId,
        departmentId: departmentId,
        details: details,
        oldValues: oldValues,
        newValues: newValues,
      );

  Future<void> linkOrphanPhoneToUserForIntegrity({
    required int phoneId,
    required int userId,
    required String details,
    Map<String, dynamic>? oldValues,
    Map<String, dynamic>? newValues,
  }) =>
      _integrity.linkOrphanPhoneToUserForIntegrity(
        phoneId: phoneId,
        userId: userId,
        details: details,
        oldValues: oldValues,
        newValues: newValues,
      );

  Future<void> fixDepartmentNameKeyForIntegrity({
    required int departmentId,
    required String nameKey,
    required String details,
    Map<String, dynamic>? oldValues,
    Map<String, dynamic>? newValues,
  }) =>
      _integrity.fixDepartmentNameKeyForIntegrity(
        departmentId: departmentId,
        nameKey: nameKey,
        details: details,
        oldValues: oldValues,
        newValues: newValues,
      );

  Future<void> softDeleteUserForIntegrity({
    required int userId,
    required String details,
    Map<String, dynamic>? oldValues,
    Map<String, dynamic>? newValues,
  }) =>
      _integrity.softDeleteUserForIntegrity(
        userId: userId,
        details: details,
        oldValues: oldValues,
        newValues: newValues,
      );

  Future<void> updateUserDepartmentForIntegrity({
    required int userId,
    required int? departmentId,
    required String details,
    Map<String, dynamic>? oldValues,
    Map<String, dynamic>? newValues,
  }) =>
      _integrity.updateUserDepartmentForIntegrity(
        userId: userId,
        departmentId: departmentId,
        details: details,
        oldValues: oldValues,
        newValues: newValues,
      );

  Future<Map<String, dynamic>?> integrityUpdateTaskFk(
    DatabaseExecutor e,
    int taskId,
    String field,
    int? newValue,
  ) =>
      _integrity.integrityUpdateTaskFk(e, taskId, field, newValue);

  Future<Map<String, dynamic>?> integritySyncTaskTimestamps(
    DatabaseExecutor e,
    int taskId,
  ) =>
      _integrity.integritySyncTaskTimestamps(e, taskId);

  Future<String> integrityDepartmentLabel(
    DatabaseExecutor e,
    int? departmentId,
  ) =>
      _integrity.integrityDepartmentLabel(e, departmentId);

  Future<String> integrityUserLabel(DatabaseExecutor e, int? userId) =>
      _integrity.integrityUserLabel(e, userId);
}
