// Κατάταξη τμημάτων σε ζώνες κατά το τι θα ζητηθεί από τον χρήστη.
//
// Ολόκληρο αρχείο (από ρίζα έργου):
//   flutter test test/features/directory/services/department_deletion_zones_test.dart

import 'package:call_logger/features/directory/services/department_deletion_inventory.dart';
import 'package:flutter_test/flutter_test.dart';

var _nextId = 0;

DepartmentDeletionInventory _inv(
  String name, {
  List<String> employees = const [],
  List<String> sharedPhones = const [],
  List<String> sharedEquipment = const [],
}) {
  return DepartmentDeletionInventory(
    departmentId: ++_nextId,
    departmentName: name,
    employeeNames: employees,
    employeeOwnedPhoneCount: 0,
    employeeOwnedEquipmentCount: 0,
    sharedPhones: sharedPhones,
    sharedEquipmentCodes: sharedEquipment,
  );
}

List<String> _namesOf(List<DepartmentDeletionInventory> zone) =>
    zone.map((i) => i.departmentName).toList();

void main() {
  group('Κατάταξη σε ζώνες', () {
    test('τρεις ζώνες κατά το βάρος της απόφασης', () {
      final zones = DepartmentDeletionZones.from([
        _inv('Άδειο Α'),
        _inv('Με υπαλλήλους', employees: ['Σοφία']),
        _inv('Με τηλέφωνο', sharedPhones: ['2101']),
        _inv('Άδειο Β'),
        _inv('Με εξοπλισμό', sharedEquipment: ['PC-1']),
      ]);

      expect(_namesOf(zones.withEmployees), ['Με υπαλλήλους']);
      expect(_namesOf(zones.sharedOnly), ['Με τηλέφωνο', 'Με εξοπλισμό']);
      expect(_namesOf(zones.empty), ['Άδειο Α', 'Άδειο Β']);
    });

    test('τμήμα με υπαλλήλους ΚΑΙ κοινόχρηστα μετράει στη βαρύτερη ζώνη', () {
      final zones = DepartmentDeletionZones.from([
        _inv('Μικτό', employees: ['Σοφία'], sharedPhones: ['2101']),
      ]);

      expect(_namesOf(zones.withEmployees), ['Μικτό']);
      expect(zones.sharedOnly, isEmpty);
    });

    test('η σειρά μέσα σε κάθε ζώνη μένει όπως δόθηκε', () {
      final zones = DepartmentDeletionZones.from([
        _inv('Ωμέγα', sharedPhones: ['1']),
        _inv('Άλφα', sharedPhones: ['2']),
      ]);

      expect(_namesOf(zones.sharedOnly), ['Ωμέγα', 'Άλφα']);
    });
  });

  group('Πότε δείχνουμε επικεφαλίδες ζωνών', () {
    test('μία μόνο γεμάτη ζώνη: καμία επικεφαλίδα — θα ήταν θόρυβος', () {
      final zones = DepartmentDeletionZones.from([
        _inv('Α', sharedPhones: ['1']),
        _inv('Β', sharedPhones: ['2']),
      ]);

      expect(zones.showsZoneHeaders, isFalse);
    });

    test('δύο γεμάτες ζώνες: επικεφαλίδες', () {
      final zones = DepartmentDeletionZones.from([
        _inv('Α', employees: ['α']),
        _inv('Β', sharedPhones: ['1']),
      ]);

      expect(zones.showsZoneHeaders, isTrue);
    });

    test('γεμάτη ζώνη μαζί με άδεια τμήματα: επικεφαλίδες', () {
      final zones = DepartmentDeletionZones.from([
        _inv('Α', employees: ['α']),
        _inv('Β'),
      ]);

      expect(zones.showsZoneHeaders, isTrue);
    });
  });

  group('Επικεφαλίδες', () {
    test('δείχνουν το πλήθος της ζώνης', () {
      final zones = DepartmentDeletionZones.from([
        _inv('Α', employees: ['α']),
        _inv('Β', employees: ['β']),
        _inv('Γ', sharedPhones: ['1']),
      ]);

      expect(zones.withEmployeesHeader, 'Με υπαλλήλους (2)');
      expect(zones.sharedOnlyHeader, 'Με κοινόχρηστα τηλέφωνα ή εξοπλισμό (1)');
    });

    test('η γραμμή των άδειων λέει ότι δεν θα ρωτηθεί τίποτα', () {
      final zones = DepartmentDeletionZones.from([
        _inv('Α', employees: ['α']),
        _inv('Β'),
        _inv('Γ'),
      ]);

      expect(
        zones.emptyHeader,
        '2 τμήματα χωρίς εξαρτήματα — διαγράφονται χωρίς ερώτηση',
      );
    });

    test('ένα άδειο τμήμα: ενικός', () {
      final zones = DepartmentDeletionZones.from([
        _inv('Α', employees: ['α']),
        _inv('Β'),
      ]);

      expect(
        zones.emptyHeader,
        '1 τμήμα χωρίς εξαρτήματα — διαγράφεται χωρίς ερώτηση',
      );
    });

    test('χωρίς άδεια τμήματα: καμία γραμμή', () {
      final zones = DepartmentDeletionZones.from([
        _inv('Α', employees: ['α']),
      ]);

      expect(zones.emptyHeader, isNull);
    });
  });
}
