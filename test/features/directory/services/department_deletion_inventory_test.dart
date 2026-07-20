import 'package:call_logger/features/directory/services/department_deletion_inventory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DepartmentDeletionInventory (primary constructor)', () {
    test('κενό inventory → isEmpty και κενή περίληψη', () {
      const inventory = DepartmentDeletionInventory(
        departmentName: 'Τμήμα Α',
        employeeNames: [],
        employeeOwnedPhoneCount: 0,
        employeeOwnedEquipmentCount: 0,
        sharedPhones: [],
        sharedEquipmentCodes: [],
      );

      expect(inventory.isEmpty, isTrue);
      expect(inventory.hasEmployees, isFalse);
      expect(inventory.hasSharedAssets, isFalse);
      expect(inventory.buildSummaryLines(), isEmpty);
    });

    test('μόνο υπάλληλοι → hasEmployees και ενικός/πληθυντικός', () {
      const one = DepartmentDeletionInventory(
        departmentName: 'Τμήμα Α',
        employeeNames: ['Άλφα'],
        employeeOwnedPhoneCount: 0,
        employeeOwnedEquipmentCount: 0,
        sharedPhones: [],
        sharedEquipmentCodes: [],
      );
      expect(one.hasEmployees, isTrue);
      expect(one.isEmpty, isFalse);
      expect(one.buildSummaryLines(), ['1 υπάλληλος']);

      const many = DepartmentDeletionInventory(
        departmentName: 'Τμήμα Α',
        employeeNames: ['Άλφα', 'Βήτα', 'Γάμμα', 'Δέλτα'],
        employeeOwnedPhoneCount: 0,
        employeeOwnedEquipmentCount: 0,
        sharedPhones: [],
        sharedEquipmentCodes: [],
      );
      expect(many.buildSummaryLines(), ['4 υπάλληλοι']);
    });

    test('φράση «θα τους ακολουθήσουν» μόνο με employee-owned στοιχεία', () {
      const withoutOwned = DepartmentDeletionInventory(
        departmentName: 'Τμήμα Α',
        employeeNames: ['Άλφα', 'Βήτα'],
        employeeOwnedPhoneCount: 0,
        employeeOwnedEquipmentCount: 0,
        sharedPhones: [],
        sharedEquipmentCodes: [],
      );
      final withoutLines = withoutOwned.buildSummaryLines();
      expect(withoutLines, hasLength(1));
      expect(withoutLines.single, isNot(contains('θα τους ακολουθήσουν')));

      const withPhones = DepartmentDeletionInventory(
        departmentName: 'Τμήμα Α',
        employeeNames: ['Άλφα'],
        employeeOwnedPhoneCount: 2,
        employeeOwnedEquipmentCount: 0,
        sharedPhones: [],
        sharedEquipmentCodes: [],
      );
      expect(
        withPhones.buildSummaryLines().single,
        contains('θα τους ακολουθήσουν'),
      );

      const withEquipment = DepartmentDeletionInventory(
        departmentName: 'Τμήμα Α',
        employeeNames: ['Άλφα'],
        employeeOwnedPhoneCount: 0,
        employeeOwnedEquipmentCount: 1,
        sharedPhones: [],
        sharedEquipmentCodes: [],
      );
      expect(
        withEquipment.buildSummaryLines().single,
        contains('θα τους ακολουθήσουν'),
      );
    });

    test('κοινόχρηστα → hasSharedAssets και σωστός πληθυντικός', () {
      const inventory = DepartmentDeletionInventory(
        departmentName: 'Τμήμα Α',
        employeeNames: [],
        employeeOwnedPhoneCount: 0,
        employeeOwnedEquipmentCount: 0,
        sharedPhones: ['2917'],
        sharedEquipmentCodes: ['PC-1', 'PC-2'],
      );

      expect(inventory.hasSharedAssets, isTrue);
      expect(inventory.isEmpty, isFalse);
      expect(
        inventory.buildSummaryLines(),
        [
          '1 κοινόχρηστο τηλέφωνο',
          '2 κοινόχρηστοι εξοπλισμοί',
        ],
      );

      const manyPhones = DepartmentDeletionInventory(
        departmentName: 'Τμήμα Α',
        employeeNames: [],
        employeeOwnedPhoneCount: 0,
        employeeOwnedEquipmentCount: 0,
        sharedPhones: ['1', '2', '3'],
        sharedEquipmentCodes: ['EQ'],
      );
      expect(
        manyPhones.buildSummaryLines(),
        [
          '3 κοινόχρηστα τηλέφωνα',
          '1 κοινόχρηστος εξοπλισμός',
        ],
      );
    });
  });
}
