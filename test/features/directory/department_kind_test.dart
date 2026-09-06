// Το «Είδος» του τμήματος: τι σημαίνει και τι ανοιγοκλείνει.
//
// Ολόκληρο αρχείο (από ρίζα έργου):
//   flutter test test/features/directory/department_kind_test.dart

import 'package:call_logger/features/directory/models/department_kind.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Ανάγνωση του είδους από τη βάση', () {
    test('τμήμα γραμμένο πριν υπάρξει το πεδίο διαβάζεται ως νοσοκομείο', () {
      final department = DepartmentModel.fromMap({'id': 1, 'name': 'ΤΕΠ'});

      expect(department.kind, DepartmentKind.hospital);
    });

    test('άγνωστη τιμή δεν εξαφανίζει το τμήμα από τον χάρτη', () {
      final department = DepartmentModel.fromMap({
        'id': 1,
        'name': 'ΤΕΠ',
        'kind': 'κάτι_από_νεότερη_έκδοση',
      });

      expect(department.kind, DepartmentKind.hospital);
      expect(department.kind.belongsOnBuildingMap, isTrue);
    });

    test('η αποθηκευμένη εταιρεία διαβάζεται ως εταιρεία', () {
      final department = DepartmentModel.fromMap({
        'id': 5,
        'name': 'DataMed',
        'kind': 'company',
      });

      expect(department.kind, DepartmentKind.company);
    });
  });

  group('Τι ανοίγει και τι κλείνει το είδος', () {
    test('μόνο το νοσοκομείο ζωγραφίζεται στην κάτοψη', () {
      expect(DepartmentKind.hospital.belongsOnBuildingMap, isTrue);
      expect(DepartmentKind.company.belongsOnBuildingMap, isFalse);
      expect(DepartmentKind.externalUnit.belongsOnBuildingMap, isFalse);
    });

    test('μόνο το νοσοκομείο είναι υποψήφιος αιτών σε Lansweeper', () {
      expect(DepartmentKind.hospital.participatesInLansweeper, isTrue);
      expect(DepartmentKind.company.participatesInLansweeper, isFalse);
      expect(DepartmentKind.externalUnit.participatesInLansweeper, isFalse);
    });

    test('η εταιρεία δεν κρατά δικό μας εξοπλισμό', () {
      expect(DepartmentKind.company.canOwnEquipment, isFalse);
    });

    test('η εξωτερική μονάδα κρατά εξοπλισμό, όπως και το νοσοκομείο', () {
      // Στα Κέντρα Υγείας τα μηχανήματα είναι δικά μας: δικοί μας κωδικοί,
      // δική μας απομακρυσμένη σύνδεση.
      expect(DepartmentKind.externalUnit.canOwnEquipment, isTrue);
      expect(DepartmentKind.hospital.canOwnEquipment, isTrue);
    });

    test('μόνο από το νοσοκομείο περιμένουμε κτίριο', () {
      expect(DepartmentKind.hospital.expectsHospitalBuilding, isTrue);
      expect(DepartmentKind.company.expectsHospitalBuilding, isFalse);
      expect(DepartmentKind.externalUnit.expectsHospitalBuilding, isFalse);
    });
  });

  group('Εγγραφή του είδους', () {
    test('το είδος φτάνει στη στήλη kind', () {
      final department = DepartmentModel(
        id: 5,
        name: 'DataMed',
        kind: DepartmentKind.company,
      );

      expect(department.toMap()['kind'], 'company');
    });

    test('τμήμα χωρίς δηλωμένο είδος γράφεται ως νοσοκομείο', () {
      final department = DepartmentModel(id: 1, name: 'ΤΕΠ');

      expect(department.toMap()['kind'], 'hospital');
    });

    test('η αλλαγή είδους δεν πειράζει τα υπόλοιπα πεδία', () {
      final department = DepartmentModel(
        id: 5,
        name: 'DataMed',
        notes: 'Medico',
      ).copyWith(kind: DepartmentKind.company);

      expect(department.kind, DepartmentKind.company);
      expect(department.name, 'DataMed');
      expect(department.notes, 'Medico');
    });
  });
}
