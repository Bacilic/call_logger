// Ζώνες μαζικής διαγραφής εξοπλισμού: ποιος αφήνει ίχνη και ποιος όχι.
//
// Ολόκληρο αρχείο (από ρίζα έργου):
//   flutter test test/features/directory/services/equipment_deletion_zones_test.dart

import 'package:call_logger/features/directory/services/equipment_deletion_summary.dart';
import 'package:call_logger/features/directory/services/equipment_deletion_zones.dart';
import 'package:flutter_test/flutter_test.dart';

var _nextId = 0;

EquipmentDeletionSummary _eq(String code, {int calls = 0, int tasks = 0}) {
  return EquipmentDeletionSummary(
    equipmentId: ++_nextId,
    code: code,
    callCount: calls,
    taskCount: tasks,
  );
}

List<String> _codesOf(List<EquipmentDeletionSummary> zone) =>
    zone.map((s) => s.code).toList();

void main() {
  group('Κατάταξη σε ζώνες', () {
    test('χωρίζει όσους αφήνουν ίχνη από τους υπόλοιπους', () {
      final zones = EquipmentDeletionZones.from([
        _eq('3601'),
        _eq('3602', calls: 1),
        _eq('3603'),
        _eq('3604', tasks: 2),
      ]);

      expect(_codesOf(zones.withTraces), ['3602', '3604']);
      expect(_codesOf(zones.withoutTraces), ['3601', '3603']);
    });

    test('η εκκρεμότητα αρκεί — δεν χρειάζεται κλήση', () {
      final zones = EquipmentDeletionZones.from([_eq('3605', tasks: 1)]);

      expect(_codesOf(zones.withTraces), ['3605']);
    });

    test('η σειρά μέσα σε κάθε ζώνη μένει όπως δόθηκε', () {
      final zones = EquipmentDeletionZones.from([
        _eq('9002', calls: 1),
        _eq('9001', calls: 1),
      ]);

      expect(_codesOf(zones.withTraces), ['9002', '9001']);
    });
  });

  group('Επικεφαλίδες', () {
    test('μία μόνο γεμάτη ζώνη: καμία επικεφαλίδα', () {
      final zones = EquipmentDeletionZones.from([
        _eq('1', calls: 1),
        _eq('2', calls: 1),
      ]);

      expect(zones.showsZoneHeaders, isFalse);
    });

    test('και οι δύο ζώνες γεμάτες: επικεφαλίδες με πλήθος', () {
      final zones = EquipmentDeletionZones.from([
        _eq('1', calls: 1),
        _eq('2', tasks: 1),
        _eq('3'),
      ]);

      expect(zones.showsZoneHeaders, isTrue);
      expect(zones.withTracesHeader, 'Με ιστορικό ή ανοιχτές εκκρεμότητες (2)');
    });

    test('η γραμμή των άιχνων μετρά σωστά', () {
      final zones = EquipmentDeletionZones.from([
        _eq('1', calls: 1),
        _eq('2'),
        _eq('3'),
      ]);

      expect(
        zones.withoutTracesHeader,
        '2 εξοπλισμοί χωρίς κανένα ίχνος χρήσης',
      );
    });

    test('ένας άιχνος: ενικός', () {
      final zones = EquipmentDeletionZones.from([_eq('1', calls: 1), _eq('2')]);

      expect(
        zones.withoutTracesHeader,
        '1 εξοπλισμός χωρίς κανένα ίχνος χρήσης',
      );
    });

    test('χωρίς άιχνους: καμία γραμμή', () {
      final zones = EquipmentDeletionZones.from([_eq('1', calls: 1)]);

      expect(zones.withoutTracesHeader, isNull);
    });
  });
}
