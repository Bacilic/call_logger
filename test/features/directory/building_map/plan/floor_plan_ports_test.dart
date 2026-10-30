// Οι θύρες: πώς λέγονται, πώς στοιχίζονται στην πρόσοψη, τι αλλάζει όταν
// αλλάζει το πλήθος τους.
//
//   flutter test test/features/directory/building_map/plan/floor_plan_ports_test.dart

import 'package:call_logger/core/models/floor_plan_object_kind.dart';
import 'package:call_logger/core/models/floor_plan_port.dart';
import 'package:call_logger/features/directory/building_map/plan/floor_plan_ports.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Αυτόματο όνομα', () {
    test('θύρα patch panel σε καμπίνα: καμπίνα.patch panel + αριθμός', () {
      expect(
        floorPlanPortAutoName(
          symbol: FloorPlanSymbol.patchPanel,
          objectName: 'F',
          cabinetName: 'RC6',
          number: 17,
        ),
        'RC6.F17',
      );
    });

    test('θύρα switch: όνομα / αριθμός', () {
      expect(
        floorPlanPortAutoName(
          symbol: FloorPlanSymbol.networkSwitch,
          objectName: 'SW-2',
          cabinetName: 'RC6',
          number: 14,
        ),
        'SW-2 / 14',
      );
    });

    test('χωρίς ονόματα η θύρα έχει πάντα κάτι να δείξει', () {
      expect(
        floorPlanPortAutoName(
          symbol: FloorPlanSymbol.networkSwitch,
          objectName: null,
          cabinetName: null,
          number: 3,
        ),
        'Θύρα 3',
      );
    });
  });

  group('Πρόσοψη', () {
    test('switch: μονές από πάνω, ζυγές από κάτω', () {
      expect(floorPlanFacadeRows(FloorPlanSymbol.networkSwitch, 6), [
        [1, 3, 5],
        [2, 4, 6],
      ]);
    });

    test('patch panel: στη σειρά, ανά 24', () {
      final rows = floorPlanFacadeRows(FloorPlanSymbol.patchPanel, 30);
      expect(rows.first.first, 1);
      expect(rows.first.last, 24);
      expect(rows.last, [25, 26, 27, 28, 29, 30]);
    });

    test('switch 96 θυρών: δύο ζεύγη σειρών', () {
      final rows = floorPlanFacadeRows(FloorPlanSymbol.networkSwitch, 96);
      expect(rows, hasLength(4));
      expect(rows[2].first, 49);
    });

    test('24άρι patch panel: όλες οι θέσεις σε μία σειρά', () {
      final rows = floorPlanFacadeRows(FloorPlanSymbol.patchPanel, 24);
      expect(rows, [
        [for (var n = 1; n <= 24; n++) n],
      ]);
    });

    test(
      'σε στενό πάνελ οι θύρες πάνε σε επόμενη σειρά, καμία δεν χάνεται',
      () {
        final columns = floorPlanFacadeColumns(200);
        expect(columns, lessThan(24));
        final rows = floorPlanFacadeRows(
          FloorPlanSymbol.patchPanel,
          24,
          columns: columns,
        );
        expect(rows.expand((r) => r), [for (var n = 1; n <= 24; n++) n]);
      },
    );

    test('σε φαρδύ πάνελ ποτέ πάνω από 24 ανά σειρά', () {
      expect(floorPlanFacadeColumns(5000), kFloorPlanFacadeMaxColumns);
    });

    test('χωρίς θύρες: καμία σειρά', () {
      expect(floorPlanFacadeRows(FloorPlanSymbol.networkSwitch, 0), isEmpty);
    });
  });

  group('Αλλαγή πλήθους', () {
    FloorPlanPort port(int n) =>
        FloorPlanPort(id: 100 + n, objectId: 1, number: n);

    test('μεγαλώνοντας προστίθενται οι επόμενοι αριθμοί', () {
      final change = floorPlanPortCountChange([port(1), port(2)], 4);
      expect(change.add, [3, 4]);
      expect(change.remove, isEmpty);
    });

    test('μικραίνοντας φεύγουν οι μεγαλύτεροι αριθμοί, οι άλλοι μένουν', () {
      final change = floorPlanPortCountChange([port(1), port(2), port(3)], 1);
      expect(change.add, isEmpty);
      expect([for (final p in change.remove) p.number], [2, 3]);
    });
  });
}
