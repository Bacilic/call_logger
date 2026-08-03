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

  const sharedWithOwners = PhoneDepartmentConflict(
    phone: phone,
    existingDepartmentId: deptB,
    existingDepartmentName: 'Χειρουργείο',
    otherUserOwnerLabels: ['Σοφία Σπυροπούλου (Χειρουργείο)'],
    hasDepartmentLocationConflict: true,
    hasOtherUserOwners: true,
  );
  const ownersOnly = PhoneDepartmentConflict(
    phone: phone,
    otherUserOwnerLabels: ['Βασίλης Πρόβος (Φαρμακείο)'],
    hasDepartmentLocationConflict: false,
    hasOtherUserOwners: true,
  );
  const sharedOnly = PhoneDepartmentConflict(
    phone: phone,
    existingDepartmentId: deptB,
    existingDepartmentName: 'Χειρουργείο',
    hasDepartmentLocationConflict: true,
    hasOtherUserOwners: false,
  );

  group('availableResolutions — ποιες διέξοδοι προσφέρονται', () {
    test(
      'κοινόχρηστο με τμήμα-στόχο → μόνο μεταφορά, ακόμη και με κατόχους',
      () {
        expect(
          PhoneDepartmentPolicy.availableResolutions(
            sharedWithOwners,
            targetDepartmentId: deptA,
          ),
          [UserPhoneConflictResolution.transferSharedToUserDepartment],
        );
      },
    );

    test('κοινόχρηστο με κατόχους χωρίς τμήμα-στόχο → μόνο αφαίρεση', () {
      expect(
        PhoneDepartmentPolicy.availableResolutions(
          sharedWithOwners,
          targetDepartmentId: null,
        ),
        [UserPhoneConflictResolution.removeFromOtherUsersAndAssign],
      );
    });

    test('μόνο κάτοχοι → μόνο αφαίρεση', () {
      expect(
        PhoneDepartmentPolicy.availableResolutions(
          ownersOnly,
          targetDepartmentId: deptA,
        ),
        [UserPhoneConflictResolution.removeFromOtherUsersAndAssign],
      );
    });

    test('κοινόχρηστο χωρίς κατόχους και χωρίς τμήμα-στόχο → αδιέξοδο', () {
      expect(
        PhoneDepartmentPolicy.availableResolutions(
          sharedOnly,
          targetDepartmentId: null,
        ),
        isEmpty,
      );
    });
  });

  group('resolutionEffects — τι αφαιρεί κάθε διέξοδος', () {
    test('μεταφορά κοινόχρηστου με κατόχους αφαιρεί ΚΑΙ τους κατόχους', () {
      final effects = PhoneDepartmentPolicy.resolutionEffects(
        sharedWithOwners,
        UserPhoneConflictResolution.transferSharedToUserDepartment,
      );
      expect(effects.removesSharedDepartment, isTrue);
      expect(effects.removesOtherUsers, isTrue);
    });

    test('μεταφορά κοινόχρηστου χωρίς κατόχους αφαιρεί μόνο το τμήμα', () {
      final effects = PhoneDepartmentPolicy.resolutionEffects(
        sharedOnly,
        UserPhoneConflictResolution.transferSharedToUserDepartment,
      );
      expect(effects.removesSharedDepartment, isTrue);
      expect(effects.removesOtherUsers, isFalse);
    });

    test('αφαίρεση από κατόχους δεν αγγίζει κοινόχρηστο τμήματος', () {
      final effects = PhoneDepartmentPolicy.resolutionEffects(
        ownersOnly,
        UserPhoneConflictResolution.removeFromOtherUsersAndAssign,
      );
      expect(effects.removesSharedDepartment, isFalse);
      expect(effects.removesOtherUsers, isTrue);
    });
  });

  group('buildBatchResult — αποφάσεις σε batch', () {
    test('μεταφορά γεμίζει και τα δύο σκέλη, άκριτη απόφαση παραλείπεται', () {
      const other = PhoneDepartmentConflict(
        phone: '2900',
        otherUserOwnerLabels: ['Άννα Πατσαρίκα (Ακτινολογικό)'],
        hasDepartmentLocationConflict: false,
        hasOtherUserOwners: true,
      );
      const undecided = PhoneDepartmentConflict(
        phone: '2999',
        hasDepartmentLocationConflict: true,
        hasOtherUserOwners: false,
        existingDepartmentId: deptA,
      );

      final result = PhoneDepartmentPolicy.buildBatchResult(
        conflicts: const [sharedWithOwners, other, undecided],
        decisions: {
          phone: UserPhoneConflictResolution.transferSharedToUserDepartment,
          '2900': UserPhoneConflictResolution.removeFromOtherUsersAndAssign,
          '2999': null,
        },
      );

      expect(result.phonesToTransferShared, {phone: deptB});
      expect(result.phonesToRemoveFromOtherUsers, {phone, '2900'});
    });
  });
}
