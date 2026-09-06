// Ποια τμήματα δικαιούνται θέση στην κάτοψη του νοσοκομείου.
//
// Ολόκληρο αρχείο (από ρίζα έργου):
//   flutter test test/features/directory/building_map/building_map_department_eligibility_test.dart

import 'package:call_logger/features/directory/building_map/services/building_map_department_eligibility.dart';
import 'package:call_logger/features/directory/models/department_kind.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> _namesOf(List<DepartmentModel> departments) =>
    departments.map((d) => d.name).toList();

void main() {
  group('Τμήματα που δικαιούνται θέση στην κάτοψη', () {
    test('η εταιρεία μένει έξω από τον χάρτη', () {
      final result = departmentsEligibleForBuildingMap([
        DepartmentModel(id: 1, name: 'Ακτινολογικό'),
        DepartmentModel(id: 2, name: 'DataMed', kind: DepartmentKind.company),
      ]);

      expect(_namesOf(result), ['Ακτινολογικό']);
    });

    test('η εξωτερική μονάδα μένει κι αυτή έξω', () {
      final result = departmentsEligibleForBuildingMap([
        DepartmentModel(id: 1, name: 'Ακτινολογικό'),
        DepartmentModel(
          id: 2,
          name: 'Κέντρο Υγείας Κορίνθου',
          kind: DepartmentKind.externalUnit,
        ),
      ]);

      expect(_namesOf(result), ['Ακτινολογικό']);
    });

    test('η εταιρεία μένει έξω ακόμη κι αν κουβαλά θέση στον χάρτη', () {
      final result = departmentsEligibleForBuildingMap([
        DepartmentModel(
          id: 2,
          name: 'DataMed',
          kind: DepartmentKind.company,
          mapFloor: '3',
          mapX: 10,
          mapY: 20,
          mapWidth: 100,
          mapHeight: 50,
        ),
      ]);

      expect(result, isEmpty);
    });

    test('το διαγραμμένο τμήμα κόβεται στο ίδιο σημείο', () {
      final result = departmentsEligibleForBuildingMap([
        DepartmentModel(id: 1, name: 'Ακτινολογικό'),
        DepartmentModel(id: 3, name: 'Παλιό Μαγειρείο', isDeleted: true),
      ]);

      expect(_namesOf(result), ['Ακτινολογικό']);
    });

    test('τα τμήματα του νοσοκομείου περνούν όλα', () {
      final result = departmentsEligibleForBuildingMap([
        DepartmentModel(id: 1, name: 'Ακτινολογικό'),
        DepartmentModel(id: 2, name: 'Γραμματεία ΤΕΠ'),
      ]);

      expect(_namesOf(result), ['Ακτινολογικό', 'Γραμματεία ΤΕΠ']);
    });
  });
}
