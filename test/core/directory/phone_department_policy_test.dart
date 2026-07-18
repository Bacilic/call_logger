// Πολιτική τηλεφώνου ανά τμήμα: κοινόχρηστο σε συναδέλφους ίδιου τμήματος.
//
//   flutter test test/core/directory/phone_department_policy_test.dart

import 'package:call_logger/core/directory/phone_department_policy.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/utils/phone_list_parser.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:flutter_test/flutter_test.dart';

UserModel _user({
  required int id,
  required String first,
  required String last,
  required String phone,
  int? departmentId,
}) {
  return UserModel(
    id: id,
    firstName: first,
    lastName: last,
    phones: PhoneListParser.splitPhones(phone),
    departmentId: departmentId,
  );
}

void _inject({
  required List<UserModel> users,
  required List<DepartmentModel> departments,
}) {
  final svc = LookupService.instance;
  svc.resetForReload();
  svc.injectInMemoryCatalogForTests(
    users: users,
    equipment: const [],
    departmentRows: departments,
  );
}

void main() {
  const phone = '2531';
  const deptA = 1;
  const deptB = 2;

  final departments = [
    DepartmentModel(id: deptA, name: 'Φαρμακείο'),
    DepartmentModel(id: deptB, name: 'Χειρουργείο'),
  ];

  group('findConflictsForUserAssignment — βάρδια ίδιου τμήματος', () {
    test('κάτοχος ίδιου τμήματος → καμία σύγκρουση', () {
      _inject(
        users: [
          _user(
            id: 10,
            first: 'Πρωινή',
            last: 'Βάρδια',
            phone: phone,
            departmentId: deptA,
          ),
        ],
        departments: departments,
      );

      final conflicts = PhoneDepartmentPolicy.findConflictsForUserAssignment(
        phones: [phone],
        targetDepartmentId: deptA,
        editingUserId: 99,
      );

      expect(conflicts, isEmpty);
    });

    test('κάτοχος άλλου τμήματος → σύγκρουση', () {
      _inject(
        users: [
          _user(
            id: 10,
            first: 'Άλλο',
            last: 'Τμήμα',
            phone: phone,
            departmentId: deptB,
          ),
        ],
        departments: departments,
      );

      final conflicts = PhoneDepartmentPolicy.findConflictsForUserAssignment(
        phones: [phone],
        targetDepartmentId: deptA,
        editingUserId: 99,
      );

      expect(conflicts, hasLength(1));
      expect(conflicts.single.phone, phone);
      expect(conflicts.single.hasOtherUserOwners, isTrue);
    });

    test('targetDepartmentId null με οποιονδήποτε κάτοχο → σύγκρουση', () {
      _inject(
        users: [
          _user(
            id: 10,
            first: 'Κάτοχος',
            last: 'Υπάρχων',
            phone: phone,
            departmentId: deptA,
          ),
        ],
        departments: departments,
      );

      final conflicts = PhoneDepartmentPolicy.findConflictsForUserAssignment(
        phones: [phone],
        targetDepartmentId: null,
        editingUserId: 99,
      );

      expect(conflicts, hasLength(1));
      expect(conflicts.single.hasOtherUserOwners, isTrue);
    });
  });
}
