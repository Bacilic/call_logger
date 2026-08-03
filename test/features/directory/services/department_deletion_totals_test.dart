// Σύνοψη πολλαπλής διαγραφής τμημάτων: πόσα και τι ακριβώς.
//
// Ολόκληρο αρχείο (από ρίζα έργου):
//   flutter test test/features/directory/services/department_deletion_totals_test.dart

import 'package:call_logger/features/directory/services/department_deletion_inventory.dart';
import 'package:flutter_test/flutter_test.dart';

var _nextId = 0;

DepartmentDeletionInventory _inv(
  String name, {
  List<String> employees = const [],
  int ownedPhones = 0,
  int ownedEquipment = 0,
  List<String> sharedPhones = const [],
  List<String> sharedEquipment = const [],
}) {
  return DepartmentDeletionInventory(
    departmentId: ++_nextId,
    departmentName: name,
    employeeNames: employees,
    employeeOwnedPhoneCount: ownedPhones,
    employeeOwnedEquipmentCount: ownedEquipment,
    sharedPhones: sharedPhones,
    sharedEquipmentCodes: sharedEquipment,
  );
}

void main() {
  group('Άθροισμα απογραφών', () {
    test('μαζεύει πλήθη από όλα τα τμήματα', () {
      final totals = DepartmentDeletionTotals.from([
        _inv(
          'Αιμοδοσία',
          employees: ['Σοφία', 'Χριστίνα'],
          ownedPhones: 1,
          sharedPhones: ['2101'],
        ),
        _inv('Ακτινολογικό', sharedPhones: ['2102']),
        _inv(
          'Αξονικός',
          employees: ['Σούλα'],
          ownedEquipment: 2,
          sharedPhones: ['2103'],
          sharedEquipment: ['PC-1'],
        ),
      ]);

      expect(totals.departmentCount, 3);
      expect(totals.employeeCount, 3);
      expect(totals.sharedPhoneCount, 3);
      expect(totals.sharedEquipmentCount, 1);
      expect(totals.employeeOwnedPhoneCount, 1);
      expect(totals.employeeOwnedEquipmentCount, 2);
    });

    test('κενή λίστα: όλα μηδέν', () {
      final totals = DepartmentDeletionTotals.from(const []);

      expect(totals.departmentCount, 0);
      expect(totals.employeeCount, 0);
    });
  });

  group('Κύρια γραμμή σύνοψης', () {
    test('πληθυντικοί με όλα τα είδη παρόντα', () {
      final totals = DepartmentDeletionTotals.from([
        _inv(
          'Α',
          employees: ['α', 'β'],
          sharedPhones: ['1', '2'],
          sharedEquipment: ['x', 'y'],
        ),
        _inv('Β', employees: ['γ']),
      ]);

      expect(
        totals.headline(),
        '2 τμήματα · 3 υπάλληλοι · 2 κοινόχρηστα τηλέφωνα · '
        '2 κοινόχρηστοι εξοπλισμοί',
      );
    });

    test('ενικοί παντού', () {
      final totals = DepartmentDeletionTotals.from([
        _inv(
          'Α',
          employees: ['α'],
          sharedPhones: ['1'],
          sharedEquipment: ['x'],
        ),
      ]);

      expect(
        totals.headline(),
        '1 τμήμα · 1 υπάλληλος · 1 κοινόχρηστο τηλέφωνο · '
        '1 κοινόχρηστος εξοπλισμός',
      );
    });

    test('τα μηδενικά είδη παραλείπονται τελείως', () {
      final totals = DepartmentDeletionTotals.from([
        _inv('Α'),
        _inv('Β', sharedPhones: ['1']),
      ]);

      expect(totals.headline(), '2 τμήματα · 1 κοινόχρηστο τηλέφωνο');
    });

    test('τμήματα χωρίς τίποτα: μόνο το πλήθος τμημάτων', () {
      final totals = DepartmentDeletionTotals.from([_inv('Α'), _inv('Β')]);

      expect(totals.headline(), '2 τμήματα');
    });
  });

  group('Όταν ο χρήστης αφαίρεσε τμήματα από τη λίστα', () {
    test('η σύνοψη λέει «Ν από τα Μ επιλεγμένα»', () {
      final totals = DepartmentDeletionTotals.from([
        _inv('Α', sharedPhones: ['1']),
        _inv('Β', sharedPhones: ['2']),
        _inv('Γ'),
      ]);

      expect(
        totals.headline(initiallySelected: 6),
        '3 από τα 6 επιλεγμένα · 2 κοινόχρηστα τηλέφωνα',
      );
    });

    test('χωρίς αφαίρεση μένει η κανονική μορφή', () {
      final totals = DepartmentDeletionTotals.from([_inv('Α'), _inv('Β')]);

      expect(totals.headline(initiallySelected: 2), '2 τμήματα');
    });

    test('ένα τμήμα από πολλά: πάλι «1 από τα Μ»', () {
      final totals = DepartmentDeletionTotals.from([_inv('Α')]);

      expect(totals.headline(initiallySelected: 6), '1 από τα 6 επιλεγμένα');
    });
  });

  group('Γραμμή για όσα ακολουθούν τους υπαλλήλους', () {
    test('χωρίς προσωπικά εξαρτήματα: καμία γραμμή', () {
      final totals = DepartmentDeletionTotals.from([
        _inv('Α', employees: ['α'], sharedPhones: ['1']),
      ]);

      expect(totals.followingAssetsLine, isNull);
    });

    test('μόνο τηλέφωνα', () {
      final totals = DepartmentDeletionTotals.from([
        _inv('Α', employees: ['α'], ownedPhones: 3),
      ]);

      expect(
        totals.followingAssetsLine,
        'Επιπλέον 3 τηλέφωνα ανήκουν σε υπαλλήλους και θα τους ακολουθήσουν '
        'αν μεταφερθούν.',
      );
    });

    test('τηλέφωνα και εξοπλισμός, με ενικούς', () {
      final totals = DepartmentDeletionTotals.from([
        _inv('Α', employees: ['α'], ownedPhones: 1, ownedEquipment: 1),
      ]);

      expect(
        totals.followingAssetsLine,
        'Επιπλέον 1 τηλέφωνο και 1 εξοπλισμός ανήκουν σε υπαλλήλους και θα '
        'τους ακολουθήσουν αν μεταφερθούν.',
      );
    });
  });
}
