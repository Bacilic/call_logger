part of 'directory_repository.dart';

mixin DirectoryRepositoryPhones on DirectoryRepositoryBase {
  Future<void> addDepartmentDirectPhone(
    int departmentId,
    String phoneNumber, {
    DatabaseExecutor? executor,
  }) =>
      _phones.addDepartmentDirectPhone(
        departmentId,
        phoneNumber,
        executor: executor,
      );

  Future<void> removeDepartmentDirectPhone(
    int departmentId,
    String phoneNumber, {
    DatabaseExecutor? executor,
  }) =>
      _phones.removeDepartmentDirectPhone(
        departmentId,
        phoneNumber,
        executor: executor,
      );

  Future<int?> getPhoneIdByNumber(String phoneNumber) =>
      _phones.getPhoneIdByNumber(phoneNumber);

  Future<int> countPhoneReferencesExcludingAudit(
    int phoneId,
    String phoneNumber,
  ) =>
      _phones.countPhoneReferencesExcludingAudit(phoneId, phoneNumber);

  Future<void> softDeletePhones(List<int> ids) =>
      _phones.softDeletePhones(ids);

  Future<Map<int, List<String>>> getDepartmentDirectPhonesMap() =>
      _phones.getDepartmentDirectPhonesMap();

  Future<bool> phoneNumberExists(String phoneNumber) =>
      _phones.phoneNumberExists(phoneNumber);

  Future<void> updatePhoneDepartment(
    String phoneNumber,
    int departmentId,
  ) =>
      _phones.updatePhoneDepartment(phoneNumber, departmentId);

  Future<void> removePhoneFromAllUsers(
    String phoneNumber, {
    DatabaseExecutor? executor,
  }) =>
      _phones.removePhoneFromAllUsers(phoneNumber, executor: executor);
}
