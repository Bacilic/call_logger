// Οι θύρες: πώς λέγονται, πώς στοιχίζονται στην πρόσοψη, τι αλλάζει όταν
// αλλάζει το πλήθος τους.
//
//   flutter test test/features/directory/building_map/plan/floor_plan_ports_test.dart

import 'package:call_logger/core/models/floor_plan_object_kind.dart';
import 'package:call_logger/core/models/floor_plan_port.dart';
import 'package:call_logger/features/directory/building_map/plan/floor_plan_ports.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ίδιο όνομα θύρας: χωρίς κεφαλαία και τόνους, όχι με τον εαυτό της', () {
    const names = [
      FloorPlanWrittenPortName(
        portId: 1,
        number: 5,
        name: 'Κάμερα Είσοδος',
        objectLabel: 'Patch A',
        cabinetName: 'MC.2.S',
        floorLabel: 'Ισόγειο',
      ),
    ];
    final clash = floorPlanWrittenNameClash(' ΚΑΜΕΡΑ ΕΙΣΟΔΟΣ', names);
    expect(clash?.where, 'θύρα 5 · Patch A · καμπίνα MC.2.S · Ισόγειο');
    expect(
      floorPlanWrittenNameClash('Κάμερα Είσοδος', names, exceptPortIds: {1}),
      isNull,
    );
    expect(floorPlanWrittenNameClash('Κάμερα Έξοδος', names), isNull);
    expect(floorPlanWrittenNameClash('  ', names), isNull);
  });

  test('το μοτίβο συνεχίζει τον αριθμό με το ίδιο πλάτος', () {
    expect(floorPlanPatternName('MC.2.N01', 1), 'MC.2.N02');
    expect(floorPlanPatternName('MC.2.N09', 1), 'MC.2.N10');
    expect(floorPlanPatternName('A-9', 1), 'A-10');
    expect(floorPlanPatternName('001', 23), '024');
    expect(floorPlanPatternName('Κάμερα', 1), isNull);
  });

  test('η συμπλήρωση μοτίβου γεμίζει μόνο τις επόμενες κενές θύρες', () {
    const ports = [
      FloorPlanPort(id: 1, objectId: 9, number: 1),
      FloorPlanPort(id: 2, objectId: 9, number: 2),
      FloorPlanPort(id: 3, objectId: 9, number: 3, writtenName: 'ΧΕΙΡΟΓΡΑΦΟ'),
      FloorPlanPort(id: 4, objectId: 9, number: 4),
      FloorPlanPort(id: 5, objectId: 8, number: 2),
    ];
    final plan = floorPlanPatternFill(
      seed: 'MC.2.N01',
      from: ports.first,
      ports: ports,
    );
    expect(
      [for (final f in plan.fill) (f.port.id, f.name)],
      [(2, 'MC.2.N02'), (4, 'MC.2.N04')],
    );
    expect(plan.kept, 1);
  });

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

    test('patch panel με όνομα που τελειώνει σε ψηφίο: τελεία από μόνη της, '
        'όχι «Molex 11»', () {
      expect(
        floorPlanPortAutoName(
          symbol: FloorPlanSymbol.patchPanel,
          objectName: 'Molex 1',
          cabinetName: 'MC.2.S',
          number: 1,
        ),
        'MC.2.S.Molex 1.1',
      );
    });

    test('το διαχωριστικό της συσκευής νικά την πρόταση — και το κενό '
        'σημαίνει «χωρίς διαχωριστικό»', () {
      String name(String? separator, {String panel = 'Molex 1'}) =>
          floorPlanPortAutoName(
            symbol: FloorPlanSymbol.patchPanel,
            objectName: panel,
            cabinetName: null,
            number: 12,
            portSeparator: separator,
          );

      expect(name('-'), 'Molex 1-12');
      expect(name(''), 'Molex 112');
      expect(name('Θ', panel: 'Α'), 'ΑΘ12');
    });

    test('το διαχωριστικό αφορά μόνο το patch panel', () {
      expect(
        floorPlanPortAutoName(
          symbol: FloorPlanSymbol.poe,
          objectName: 'POE-1',
          cabinetName: null,
          number: 3,
          portSeparator: '.',
        ),
        'POE-1 / 3',
      );
    });

    test('θύρα switch: πρότυπο Cisco, μέλος 1 και Gi όταν δεν δηλώθηκαν', () {
      expect(
        floorPlanPortAutoName(
          symbol: FloorPlanSymbol.networkSwitch,
          objectName: 'SW-2',
          cabinetName: 'RC6',
          number: 14,
        ),
        'SW-2 Gi1/0/14',
      );
    });

    test('θύρα switch σε stack, με άλλο πρόθεμα', () {
      expect(
        floorPlanPortAutoName(
          symbol: FloorPlanSymbol.networkSwitch,
          objectName: 'SW-2',
          cabinetName: null,
          number: 14,
          stackUnit: 2,
          groups: const [FloorPlanPortGroup(prefix: 'Te')],
        ),
        'SW-2 Te2/0/14',
      );
    });

    test('POE και router μένουν όνομα / αριθμός', () {
      expect(
        floorPlanPortAutoName(
          symbol: FloorPlanSymbol.poe,
          objectName: 'POE-1',
          cabinetName: null,
          number: 3,
        ),
        'POE-1 / 3',
      );
    });

    test('χωρίς ονόματα η θύρα έχει πάντα κάτι να δείξει', () {
      expect(
        floorPlanPortAutoName(
          symbol: FloorPlanSymbol.poe,
          objectName: null,
          cabinetName: null,
          number: 3,
        ),
        'Θύρα 3',
      );
    });

    test('το σήμα άλλου ορόφου: το βέλος δείχνει πού είναι ο όροφος', () {
      String badge(int? here, int? there) => floorPlanOtherFloorBadge(
        target: 'RC6',
        floorLabel: '1ος',
        hereLevel: here,
        thereLevel: there,
      );
      expect(badge(-1, 1), '↑ RC6 · 1ος');
      expect(badge(2, 1), '↓ RC6 · 1ος');
      expect(badge(null, 1), '→ RC6 · 1ος');
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

  group('Ομάδες θυρών · ονόματα', () {
    String name(
      FloorPlanSymbol symbol,
      List<FloorPlanPortGroup> groups,
      int group,
      int number, {
      String objectName = 'SW-2',
    }) => floorPlanPortAutoName(
      symbol: symbol,
      objectName: objectName,
      cabinetName: null,
      number: number,
      groups: groups,
      group: group,
    );

    test('9300L: 24 × 1G και uplink 4 × 10G που ξαναμετρούν', () {
      const groups = [
        FloorPlanPortGroup(),
        FloorPlanPortGroup(prefix: 'Te', speed: '10G SFP+'),
      ];
      expect(
        name(FloorPlanSymbol.networkSwitch, groups, 0, 24),
        'SW-2 Gi1/0/24',
      );
      expect(name(FloorPlanSymbol.networkSwitch, groups, 1, 3), 'SW-2 Te1/1/3');
    });

    test('9300 mGig: η δεύτερη ομάδα συνεχίζει, η τρίτη ξαναμετρά', () {
      const groups = [
        FloorPlanPortGroup(prefix: 'Te'),
        FloorPlanPortGroup(prefix: 'Gi', continues: true),
        FloorPlanPortGroup(prefix: 'Te'),
      ];
      expect(name(FloorPlanSymbol.networkSwitch, groups, 0, 8), 'SW-2 Te1/0/8');
      expect(name(FloorPlanSymbol.networkSwitch, groups, 1, 9), 'SW-2 Gi1/0/9');
      expect(name(FloorPlanSymbol.networkSwitch, groups, 2, 1), 'SW-2 Te1/1/1');
    });

    test('POE 8 + 2: η πρώτη ομάδα όπως πριν, η δεύτερη με πρόθεμα', () {
      const groups = [FloorPlanPortGroup(), FloorPlanPortGroup(prefix: 'SFP')];
      expect(
        name(FloorPlanSymbol.poe, groups, 0, 2, objectName: 'POE-1'),
        'POE-1 / 2',
      );
      expect(
        name(FloorPlanSymbol.poe, groups, 1, 2, objectName: 'POE-1'),
        'POE-1 / SFP2',
      );
    });
  });

  group('Ομάδες θυρών · αποθήκευση', () {
    test('μία ομάδα χωρίς ταχύτητα δεν γράφει τίποτα, όπως πριν', () {
      expect(floorPlanPortGroupsData(const [FloorPlanPortGroup()]), isNull);
      expect(floorPlanPortGroupsFrom('Te', null), const [
        FloorPlanPortGroup(prefix: 'Te'),
      ]);
    });

    test('ό,τι γράφεται διαβάζεται ίδιο, με το πρόθεμα της πρώτης χωριστά', () {
      const groups = [
        FloorPlanPortGroup(prefix: 'Te', speed: 'mGig'),
        FloorPlanPortGroup(prefix: 'Gi', continues: true),
        FloorPlanPortGroup(prefix: 'Te', speed: '10G SFP+'),
      ];
      final data = floorPlanPortGroupsData(groups);
      expect(floorPlanPortGroupsFrom('Te', data), groups);
    });

    test('χαλασμένη εγγραφή διαβάζεται ως μία ομάδα', () {
      expect(floorPlanPortGroupsFrom('Gi', '{oops'), const [
        FloorPlanPortGroup(prefix: 'Gi'),
      ]);
    });
  });

  group('Ομάδες θυρών · αλλαγές', () {
    FloorPlanPort port(int id, int group, int number) =>
        FloorPlanPort(id: id, objectId: 1, groupIndex: group, number: number);
    FloorPlanPortGroupSpec spec(
      int? source,
      int count, {
      bool continues = false,
    }) => (
      source: source,
      count: count,
      group: FloorPlanPortGroup(continues: continues),
    );

    test('μεγαλώνοντας προστίθενται οι επόμενοι αριθμοί', () {
      final change = floorPlanPortGroupsChange(
        objectId: 1,
        existing: [port(1, 0, 1), port(2, 0, 2)],
        oldGroups: const [FloorPlanPortGroup()],
        specs: [spec(0, 4)],
      );
      expect([for (final p in change.add) p.number], [3, 4]);
      expect(change.remove, isEmpty);
      expect(change.update, isEmpty);
    });

    test('μικραίνοντας φεύγουν οι μεγαλύτεροι αριθμοί, οι άλλοι μένουν', () {
      final change = floorPlanPortGroupsChange(
        objectId: 1,
        existing: [port(1, 0, 1), port(2, 0, 2), port(3, 0, 3)],
        oldGroups: const [FloorPlanPortGroup()],
        specs: [spec(0, 1)],
      );
      expect(change.add, isEmpty);
      expect([for (final p in change.remove) p.number], [2, 3]);
    });

    test('νέα ομάδα: ξεκινά από το 1, στη δική της ομάδα', () {
      final change = floorPlanPortGroupsChange(
        objectId: 1,
        existing: [port(1, 0, 1), port(2, 0, 2)],
        oldGroups: const [FloorPlanPortGroup()],
        specs: [spec(0, 2), spec(null, 2)],
      );
      expect(
        [for (final p in change.add) (p.groupIndex, p.number)],
        [(1, 1), (1, 2)],
      );
    });

    test('η προηγούμενη μεγαλώνει: η ομάδα που συνεχίζει μετακινείται '
        'κρατώντας τις θύρες της', () {
      final change = floorPlanPortGroupsChange(
        objectId: 1,
        existing: [port(1, 0, 1), port(2, 0, 2), port(3, 1, 3), port(4, 1, 4)],
        oldGroups: const [
          FloorPlanPortGroup(),
          FloorPlanPortGroup(continues: true),
        ],
        specs: [spec(0, 3), spec(1, 2, continues: true)],
      );
      expect([for (final p in change.add) (p.groupIndex, p.number)], [(0, 3)]);
      expect(change.remove, isEmpty);
      expect(
        [for (final p in change.update) (p.id, p.number)],
        [(3, 4), (4, 5)],
      );
    });

    test('αφαίρεση ενδιάμεσης ομάδας: η επόμενη ανεβαίνει μία θέση', () {
      final change = floorPlanPortGroupsChange(
        objectId: 1,
        existing: [port(1, 0, 1), port(2, 1, 1), port(3, 2, 1)],
        oldGroups: const [
          FloorPlanPortGroup(),
          FloorPlanPortGroup(),
          FloorPlanPortGroup(),
        ],
        specs: [spec(0, 1), spec(2, 1)],
      );
      expect([for (final p in change.remove) p.id], [2]);
      expect([for (final p in change.update) (p.id, p.groupIndex)], [(3, 1)]);
      expect(change.add, isEmpty);
    });
  });

  group('Θύρες πρίζας', () {
    FloorPlanPort port(int n, {String? written, String? text}) => FloorPlanPort(
      id: 100 + n,
      objectId: 1,
      number: n,
      writtenName: written,
      connectedText: text,
    );

    FloorPlanOutletChange change(
      List<FloorPlanPort> existing,
      List<FloorPlanOutletPortDraft> drafts, {
      Map<int, int> links = const {},
      Map<int, String?> types = const {},
    }) => floorPlanOutletChange(
      objectId: 1,
      existing: existing,
      patchPortOfOutletPort: links,
      drafts: drafts,
      cableTypeOfOutletPort: types,
    );

    test('ίδιο patch panel με άλλο τύπο: αλλάζει μόνο ο τύπος', () {
      final result = change(
        [port(1)],
        [
          const FloorPlanOutletPortDraft(
            number: 1,
            patchPortId: 60,
            cableType: 'Cat 6',
          ),
        ],
        links: {101: 60},
      );
      expect(result.disconnect, isEmpty);
      expect(result.connect, isEmpty);
      expect(result.retype.single, (outletPortId: 101, type: 'Cat 6'));
    });

    test('Cat 5e γραμμένο ή κενό είναι το ίδιο: καμία αλλαγή', () {
      final result = change(
        [port(1)],
        [
          const FloorPlanOutletPortDraft(
            number: 1,
            patchPortId: 60,
            cableType: 'Cat 5e',
          ),
        ],
        links: {101: 60},
        types: {101: null},
      );
      expect(result.isEmpty, isTrue);
    });

    test('νέα σύνδεση: γίνεται με τον τύπο που διαλέχτηκε', () {
      final result = change(
        [port(1)],
        [
          const FloorPlanOutletPortDraft(
            number: 1,
            patchPortId: 60,
            cableType: 'Cat 7',
          ),
        ],
      );
      expect(result.connect.single.type, 'Cat 7');
    });

    test('ό,τι έμεινε ίδιο δεν αγγίζεται', () {
      final result = change(
        [port(1, written: 'Κάμερα 7')],
        [
          const FloorPlanOutletPortDraft(
            number: 1,
            writtenName: ' Κάμερα 7 ',
            patchPortId: 50,
          ),
        ],
        links: {101: 50},
      );
      expect(result.isEmpty, isTrue);
    });

    test('η δεύτερη θύρα γεννιέται με ό,τι γράφτηκε και δένεται', () {
      final result = change(
        [port(1)],
        [
          const FloorPlanOutletPortDraft(number: 1),
          FloorPlanOutletPortDraft(
            number: 2,
            writtenName: 'Κάμερα 7',
            patchPortId: 60,
            connection: FloorPlanPortConnection.freeText('αναλυτής'),
          ),
        ],
      );
      final added = result.insert.single;
      expect(added.number, 2);
      expect(added.writtenName, 'Κάμερα 7');
      expect(added.connectedText, 'αναλυτής');
      expect(result.connect.single.number, 2);
      expect(result.connect.single.patchPortId, 60);
    });

    test('από 2 σε 1: φεύγει μόνο η δεύτερη', () {
      final result = change(
        [port(1), port(2)],
        [const FloorPlanOutletPortDraft(number: 1)],
      );
      expect([for (final p in result.remove) p.number], [2]);
      expect(result.update, isEmpty);
    });

    test('αλλαγή θύρας patch panel: το παλιό καλώδιο φεύγει, μπαίνει νέο', () {
      final result = change(
        [port(1)],
        [const FloorPlanOutletPortDraft(number: 1, patchPortId: 70)],
        links: {101: 50},
      );
      expect(result.disconnect, [101]);
      expect(result.connect.single.patchPortId, 70);
    });

    test('«Χωρίς σύνδεση»: το καλώδιο φεύγει, η θύρα μένει', () {
      final result = change(
        [port(1)],
        [const FloorPlanOutletPortDraft(number: 1)],
        links: {101: 50},
      );
      expect(result.disconnect, [101]);
      expect(result.connect, isEmpty);
      expect(result.remove, isEmpty);
    });

    test('το κείμενο με μόνο κενά δεν είναι σύνδεση', () {
      expect(FloorPlanPortConnection.freeText('   ').isEmpty, isTrue);
    });

    test('η γραμμή της θύρας: χωρίς δέσιμο και με όλα μαζί', () {
      expect(
        floorPlanOutletPortLine(link: null, writtenName: null, connected: null),
        kFloorPlanOutletUnlinked,
      );
      expect(
        floorPlanOutletPortLine(
          link: const FloorPlanPortLink(
            outletPortId: 1,
            outletFloorId: 1,
            patchPortId: 2,
            patchNumber: 17,
            panelId: 3,
            panelFloorId: 1,
            panelName: 'F',
            cabinetName: 'RC6',
          ),
          writtenName: 'Κάμερα 7',
          connected: 'PC-0412',
        ),
        'PC-0412 → πρίζα → RC6.F17 («Κάμερα 7») → χωρίς switch',
      );
      expect(
        floorPlanOutletPortLine(
          link: const FloorPlanPortLink(
            outletPortId: 1,
            outletFloorId: 1,
            patchPortId: 2,
            patchNumber: 17,
            panelId: 3,
            panelFloorId: 1,
            panelName: 'F',
            cabinetName: 'RC6',
          ),
          writtenName: null,
          connected: 'PC-0412',
          switchEnd: const FloorPlanCableEnd(
            portId: 9,
            side: kFloorPlanCableFront,
            number: 14,
            objectId: 8,
            floorId: 1,
            objectName: 'SW-2',
            symbol: FloorPlanSymbol.networkSwitch,
          ),
        ),
        'PC-0412 → πρίζα → RC6.F17 → SW-2 Gi1/0/14',
      );
    });

    test('συσκευή στην πρίζα χωρίς δέσιμο: φαίνεται ότι δεν πάει πουθενά', () {
      expect(
        floorPlanOutletPortLine(
          link: null,
          writtenName: null,
          connected: 'αναλυτής',
        ),
        'αναλυτής → πρίζα → $kFloorPlanOutletUnlinked',
      );
    });

    test('η πίσω πλευρά δείχνει τη συσκευή όταν υπάρχει', () {
      expect(floorPlanPatchPortBehind(null), 'Πίσω: πρίζα');
      expect(floorPlanPatchPortBehind('PR3918'), 'Πίσω: πρίζα → PR3918');
    });
  });

  group('Καλώδια', () {
    FloorPlanCableEnd end(int port, int object, {String side = 'front'}) =>
        FloorPlanCableEnd(
          portId: port,
          side: side,
          number: port,
          objectId: object,
          floorId: 1,
        );

    test('η θύρα patch panel ξεχωρίζει πίσω και μπροστά', () {
      final cables = FloorPlanPortCables([
        FloorPlanCableLine(
          cableId: 1,
          a: end(10, 1),
          b: end(20, 2, side: kFloorPlanCableBack),
        ),
        FloorPlanCableLine(cableId: 2, a: end(20, 2), b: end(30, 3)),
      ]);

      expect(cables.back, {20});
      expect(cables.front, {10, 20, 30});
      expect(cables.otherEnd(20, kFloorPlanCableBack)!.portId, 10);
      expect(cables.otherEnd(20, kFloorPlanCableFront)!.portId, 30);
      expect(cables.cableIdAt(20, kFloorPlanCableFront), 2);
    });

    test(
      'καλώδιο ανάμεσα σε δύο συσκευές της ίδιας καμπίνας μετρά μία φορά',
      () {
        final cables = FloorPlanPortCables([
          FloorPlanCableLine(cableId: 1, a: end(10, 1), b: end(20, 2)),
        ]);
        expect(cables.countTouching({1, 2}), 1);
        expect(cables.countTouching({3}), 0);
      },
    );

    FloorPlanPort port(int id, int object) =>
        FloorPlanPort(id: id, objectId: object, number: 1);

    String? problem(
      FloorPlanPort from,
      FloorPlanPort to, {
      FloorPlanSymbol? toSymbol,
      Set<int> taken = const {},
    }) => floorPlanCableProblem(
      from: from,
      to: to,
      toSymbol: toSymbol,
      toName: 'SW-2 / 1',
      frontTaken: taken.contains,
    );

    test(
      'επιτρέπεται ανάμεσα σε δύο ελεύθερες θύρες διαφορετικών συσκευών',
      () {
        expect(problem(port(1, 1), port(2, 2)), isNull);
      },
    );

    test('όχι στην ίδια συσκευή, όχι σε πρίζα, όχι σε πιασμένη θύρα', () {
      expect(problem(port(1, 1), port(2, 1)), contains('ίδια'));
      expect(
        problem(port(1, 1), port(2, 2), toSymbol: FloorPlanSymbol.outlet),
        contains('πλαίσιό της'),
      );
      expect(problem(port(1, 1), port(2, 2), taken: {2}), contains('SW-2 / 1'));
    });

    test('συσκευή με μία θύρα: φαίνεται σκέτο το όνομά της', () {
      expect(
        floorPlanCableEndName(
          const FloorPlanCableEnd(
            portId: 1,
            side: kFloorPlanCableFront,
            number: 1,
            objectId: 1,
            floorId: 1,
            objectName: 'AP-3',
            symbol: FloorPlanSymbol.printer,
          ),
        ),
        'AP-3',
      );
    });

    test('με πόσες θύρες γεννιέται κάθε είδος', () {
      int count(FloorPlanSymbol symbol, {bool hasPorts = false}) =>
          floorPlanDefaultPortCount(
            FloorPlanObjectKind(
              id: 1,
              name: 'x',
              symbol: symbol,
              hasPorts: hasPorts,
            ),
          );
      expect(count(FloorPlanSymbol.outlet), 2);
      expect(count(FloorPlanSymbol.printer, hasPorts: true), 1);
      expect(count(FloorPlanSymbol.printer), 0);
      expect(count(FloorPlanSymbol.networkSwitch, hasPorts: true), 0);
      expect(count(FloorPlanSymbol.cabinet, hasPorts: true), 0);
    });
  });

  group('Επιλογή θύρας patch panel', () {
    FloorPlanPatchPortOption option(
      int id, {
      int panel = 1,
      int floor = 1,
      bool taken = false,
    }) => FloorPlanPatchPortOption(
      portId: id,
      number: id,
      panelId: panel,
      floorId: floor,
      taken: taken,
    );

    test('μόνο οι ελεύθερες, συν όσες κρατά ήδη το πλαίσιο', () {
      final groups = floorPlanPatchPanelGroups(
        [option(1, taken: true), option(2, taken: true), option(3)],
        currentFloorId: 1,
        keep: {2},
      );
      expect([for (final p in groups.single.ports) p.portId], [2, 3]);
    });

    test('η άλλη θύρα της ίδιας πλάκας δεν προσφέρεται', () {
      final groups = floorPlanPatchPanelGroups(
        [option(1), option(2)],
        currentFloorId: 1,
        exclude: {1},
      );
      expect([for (final p in groups.single.ports) p.portId], [2]);
    });

    test('patch panel χωρίς διαθέσιμη θύρα παραλείπεται', () {
      expect(
        floorPlanPatchPanelGroups([option(1, taken: true)], currentFloorId: 1),
        isEmpty,
      );
    });

    test('πρώτα ο όροφος της πρίζας, μετά οι άλλοι', () {
      final groups = floorPlanPatchPanelGroups([
        option(1, panel: 1, floor: 1),
        option(2, panel: 2, floor: 5),
      ], currentFloorId: 5);
      expect([for (final g in groups) g.floorId], [5, 1]);
    });
  });
}
