// Οι κανόνες των πεδίων στα στοιχεία μιας συσκευής του χάρτη: IP, πλήθος
// θυρών, ύψος σε U και η προεπισκόπηση του ονόματος θύρας.
//
//   flutter test test/features/directory/building_map/plan/floor_plan_object_fields_test.dart

import 'package:call_logger/features/directory/building_map/plan/floor_plan_object_fields.dart';
import 'package:call_logger/features/directory/building_map/plan/floor_plan_ports.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IP', () {
    test('κενή ή έγκυρη: κανένα μήνυμα — και το κόμμα του ελληνικού '
        'πληκτρολογίου μετρά ως τελεία', () {
      expect(floorPlanIpError(''), isNull);
      expect(floorPlanIpError('10.10.1.25'), isNull);
      expect(floorPlanIpError('10,10,1,25'), isNull);
      expect(floorPlanNormalizedIp(' 10,10,1,25 '), '10.10.1.25');
    });

    test('λάθος IP: η ίδια διάγνωση με τους υπολογιστές του Καταλόγου', () {
      expect(floorPlanIpError('10.10.300.1'), contains('255'));
      expect(floorPlanIpError('10.10.1'), contains('4 αριθμούς'));
      expect(floorPlanIpError('1Ο.10.1.1'), contains('"Ο"'));
      expect(floorPlanIpError('switch-2'), isNotNull);
    });
  });

  test('θύρες: από 0 ως το ανώτατο, κενό = καμία', () {
    expect(floorPlanPortCountError(''), isNull);
    expect(floorPlanPortCountError('0'), isNull);
    expect(floorPlanPortCountError('$kFloorPlanMaxPorts'), isNull);
    expect(floorPlanPortCountError('${kFloorPlanMaxPorts + 1}'), isNotNull);
  });

  group('Ομάδες θυρών της φόρμας', () {
    test('οι επόμενες ομάδες χωρίς θύρες παραλείπονται, η πρώτη μένει', () {
      final specs = floorPlanPortGroupSpecs([
        (source: 0, count: '', prefix: 'Gi', speed: '', continues: true),
        (source: null, count: '0', prefix: 'Te', speed: '', continues: false),
        (source: 1, count: '4', prefix: ' Te ', speed: '10G', continues: true),
      ]);
      expect(specs, hasLength(2));
      expect(specs.first.count, 0);
      // Το «συνεχίζει» δεν έχει νόημα στην πρώτη ομάδα.
      expect(specs.first.group.continues, isFalse);
      expect(specs.last.source, 1);
      expect(
        specs.last.group,
        const FloorPlanPortGroup(prefix: 'Te', speed: '10G', continues: true),
      );
    });

    test('το switch χωρίς πρόθεμα δείχνει Gi', () {
      final drafts = floorPlanPortGroupDrafts([
        (source: 0, count: 24, group: const FloorPlanPortGroup()),
      ], isSwitch: true);
      expect(drafts.single.prefix, 'Gi');
      expect(drafts.single.count, '24');
    });
  });

  test('ύψος σε U: από 1 ως τα U της καμπίνας', () {
    expect(floorPlanHeightUError('2', 42), isNull);
    expect(floorPlanHeightUError('42', 42), isNull);
    expect(floorPlanHeightUError('0', 42), isNotNull);
    expect(floorPlanHeightUError('43', 42), isNotNull);
    expect(floorPlanHeightUError('', 42), isNotNull);
  });

  test('προεπισκόπηση: η πρώτη θύρα όπως θα γραφτεί', () {
    expect(
      floorPlanPortSeparatorPreview(
        panelName: 'Molex 1',
        cabinetName: 'MC.2.S',
        separator: '.',
      ),
      'MC.2.S.Molex 1.1',
    );
  });
}
