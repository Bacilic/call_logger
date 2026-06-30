part of 'directory_repository.dart';

mixin DirectoryRepositoryUsers on DirectoryRepositoryBase {
  Future<void> replaceUserPhones(int userId, List<String> numbers) =>
      _users.replaceUserPhones(userId, numbers);

  Future<List<Map<String, dynamic>>> getAllUsers() => _users.getAllUsers();

  Future<int> insertUserFromMap(
    Map<String, dynamic> row, {
    DatabaseExecutor? executor,
    bool skipPhonePolicyValidation = false,
  }) =>
      _users.insertUserFromMap(
        row,
        executor: executor,
        skipPhonePolicyValidation: skipPhonePolicyValidation,
      );

  Future<List<Map<String, dynamic>>> getEquipmentOwnerSnapshots(
    int equipmentId,
  ) =>
      _users.getEquipmentOwnerSnapshots(equipmentId);

  Future<int> updateUser(
    int id,
    Map<String, dynamic> values, {
    bool recordAudit = true,
    DatabaseExecutor? executor,
    bool skipPhonePolicyValidation = false,
  }) =>
      _users.updateUser(
        id,
        values,
        recordAudit: recordAudit,
        executor: executor,
        skipPhonePolicyValidation: skipPhonePolicyValidation,
      );

  Future<void> bulkUpdateUsers(
    List<int> ids,
    Map<String, dynamic> changes,
  ) =>
      _users.bulkUpdateUsers(ids, changes);

  Future<List<ExclusivePhoneForUserDelete>> findExclusivePhonesForUserDelete(
    List<int> userIds,
  ) =>
      _users.findExclusivePhonesForUserDelete(userIds);

  Future<void> deleteUsers(List<int> ids) => _users.deleteUsers(ids);

  Future<void> restoreUsers(List<int> ids) => _users.restoreUsers(ids);

  Future<int> insertUser({
    required String firstName,
    required String lastName,
    List<String>? phones,
    String? department,
    String? location,
    String? notes,
    int? departmentId,
    DatabaseExecutor? executor,
    bool skipPhonePolicyValidation = false,
  }) =>
      _users.insertUser(
        firstName: firstName,
        lastName: lastName,
        phones: phones,
        department: department,
        location: location,
        notes: notes,
        departmentId: departmentId,
        executor: executor,
        skipPhonePolicyValidation: skipPhonePolicyValidation,
      );

  Future<void> updateAssociationsIfNeeded(
    int? userId,
    String? phone,
    String? equipmentCode,
  ) =>
      _users.updateAssociationsIfNeeded(userId, phone, equipmentCode);
}
