// Ποιοι κάτοχοι εξοπλισμού ανήκουν σε άλλο τμήμα.
//
//   flutter test test/core/directory/equipment_department_policy_test.dart

import 'package:call_logger/core/directory/equipment_department_policy.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final plakogianni = UserModel(id: 7, firstName: 'Ελένη', departmentId: 3);
  final colleague = UserModel(id: 9, firstName: 'Ιωάννα', departmentId: 64);
  final noDepartment = UserModel(id: 11, firstName: 'Άγνωστη');

  test('κάτοχος άλλου τμήματος είναι ξένος', () {
    expect(
      equipmentOwnersInOtherDepartments(
        owners: [plakogianni],
        newOwnerId: 83,
        targetDepartmentId: 64,
      ),
      [plakogianni],
    );
  });

  test('συνάδελφος ίδιου τμήματος δεν είναι ξένος — βάρδια', () {
    expect(
      equipmentOwnersInOtherDepartments(
        owners: [colleague],
        newOwnerId: 83,
        targetDepartmentId: 64,
      ),
      isEmpty,
    );
  });

  test('ο ίδιος ο νέος κάτοχος και ο κάτοχος χωρίς τμήμα δεν κρίνονται', () {
    expect(
      equipmentOwnersInOtherDepartments(
        owners: [UserModel(id: 83, departmentId: 3), noDepartment],
        newOwnerId: 83,
        targetDepartmentId: 64,
      ),
      isEmpty,
    );
  });

  test('νέο τμήμα χωρίς id κάνει ξένο κάθε κάτοχο με τμήμα', () {
    expect(
      equipmentOwnersInOtherDepartments(
        owners: [colleague],
        newOwnerId: 83,
        targetDepartmentId: null,
      ),
      [colleague],
    );
  });
}
