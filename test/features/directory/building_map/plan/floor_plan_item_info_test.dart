// Τι λέει η υπόδειξη του χάρτη για κάθε σύμβολο: υπάλληλος, τηλέφωνο,
// εξοπλισμός του Καταλόγου, αντικείμενο του χάρτη — και πότε προειδοποιεί.
//
//   flutter test test/features/directory/building_map/plan/floor_plan_item_info_test.dart

import 'dart:ui' show Offset, Size;

import 'package:call_logger/core/models/floor_plan_object.dart';
import 'package:call_logger/core/models/floor_plan_object_kind.dart';
import 'package:call_logger/core/models/floor_plan_placement.dart';
import 'package:call_logger/core/models/floor_plan_port.dart';
import 'package:call_logger/features/directory/building_map/plan/floor_plan_item_info.dart';
import 'package:call_logger/features/directory/building_map/plan/floor_plan_objects.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const user = FloorPlanCatalogEntry(
    type: FloorPlanPlacementType.user,
    entityId: 10,
    label: 'Παπαδόπουλος Γιώργος',
    departmentIds: {1},
    phones: ['2345'],
    equipment: ['PC-0412'],
  );
  const phone = FloorPlanCatalogEntry(
    type: FloorPlanPlacementType.phone,
    entityId: 20,
    label: '2345',
    departmentIds: {1},
    holders: ['Παπαδόπουλος Γιώργος', 'Νικολάου Ελένη'],
  );
  const printerKind = FloorPlanObjectKind(
    id: 5,
    name: 'Εκτυπωτής',
    symbol: FloorPlanSymbol.printer,
  );

  FloorPlanInfoSources sources({int? roomDepartment, String? roomName}) =>
      FloorPlanInfoSources(
        objects: {
          7: const FloorPlanObject(
            id: 7,
            floorId: 1,
            kindId: 5,
            center: Offset.zero,
            name: 'ΕΚΤ-ΥΛ-01',
            ip: '10.1.2.33',
            notes: 'δίπλα στο παράθυρο',
          ),
        },
        kinds: {5: printerKind},
        catalog: {user.key: user, phone.key: phone},
        placements: {
          1: const FloorPlanPlacement(
            id: 1,
            type: FloorPlanPlacementType.user,
            entityId: 10,
            floorId: 1,
            center: Offset.zero,
          ),
          2: const FloorPlanPlacement(
            id: 2,
            type: FloorPlanPlacementType.phone,
            entityId: 20,
            floorId: 1,
            center: Offset.zero,
          ),
        },
        departmentName: (id) => {1: 'Υλικού', 2: 'Χειρουργική'}[id],
        roomAt: (_) => roomDepartment == null && roomName == null
            ? null
            : (departmentId: roomDepartment, name: roomName),
      );

  test('πρίζα: κάθε θύρα με το όνομα, το γραμμένο και το τι είναι συνδεδεμένο; '
      'το patch panel βλέπει τη συσκευή πίσω του', () {
    const port1 = FloorPlanPort(
      id: 1,
      objectId: 9,
      number: 1,
      writtenName: 'Κάμερα 7',
      connectedText: 'αναλυτής',
    );
    const port2 = FloorPlanPort(id: 2, objectId: 9, number: 2);
    final info = FloorPlanInfoSources(
      objects: {
        9: const FloorPlanObject(
          id: 9,
          floorId: 1,
          kindId: 6,
          center: Offset.zero,
        ),
      },
      kinds: {
        6: const FloorPlanObjectKind(
          id: 6,
          name: 'Πρίζα',
          symbol: FloorPlanSymbol.outlet,
        ),
      },
      catalog: const {},
      placements: const {},
      departmentName: (_) => null,
      roomAt: (_) => null,
      ports: const [port2, port1],
      portLinks: const [
        FloorPlanPortLink(
          outletPortId: 1,
          outletFloorId: 1,
          patchPortId: 50,
          patchNumber: 17,
          panelId: 3,
          panelFloorId: 1,
          panelName: 'F',
          cabinetName: 'RC6',
          connection: FloorPlanPortConnection(text: 'αναλυτής'),
        ),
      ],
    );

    final result = floorPlanItemInfo(
      const FloorPlanObjectView(
        id: 9,
        kindId: 6,
        center: Offset.zero,
        size: Size.square(60),
        rotationDegrees: 0,
        symbol: FloorPlanSymbol.outlet,
        label: '',
        source: FloorPlanItemSource.object,
      ),
      info,
    );

    expect(result!.rows, [
      ('Θύρα 1', 'αναλυτής → πρίζα → RC6.F17 («Κάμερα 7») → χωρίς switch'),
      ('Θύρα 2', 'χωρίς σύνδεση'),
    ]);
    expect(
      info.portDetails()(const FloorPlanPort(id: 50, objectId: 3, number: 17)),
      'Πίσω: πρίζα → αναλυτής',
    );
  });

  test(
    'καμπίνα: το περιεχόμενο σε μία γραμμή και οι ελεύθερες θύρες switch',
    () {
      final info = floorPlanItemInfo(
        const FloorPlanObjectView(
          id: 1,
          kindId: 1,
          center: Offset.zero,
          size: Size.square(60),
          rotationDegrees: 0,
          symbol: FloorPlanSymbol.cabinet,
          label: 'RC6',
          source: FloorPlanItemSource.object,
        ),
        FloorPlanInfoSources(
          objects: {
            1: const FloorPlanObject(
              id: 1,
              floorId: 1,
              kindId: 1,
              center: Offset.zero,
              name: 'RC6',
            ),
            2: const FloorPlanObject(
              id: 2,
              floorId: 1,
              kindId: 2,
              center: Offset.zero,
              name: 'SW-2',
              cabinetId: 1,
              rackU: 1,
            ),
            3: const FloorPlanObject(
              id: 3,
              floorId: 1,
              kindId: 3,
              center: Offset.zero,
              cabinetId: 1,
              rackU: 2,
            ),
          },
          kinds: {
            1: const FloorPlanObjectKind(
              id: 1,
              name: 'Καμπίνα',
              symbol: FloorPlanSymbol.cabinet,
            ),
            2: const FloorPlanObjectKind(
              id: 2,
              name: 'Switch',
              symbol: FloorPlanSymbol.networkSwitch,
            ),
            3: const FloorPlanObjectKind(
              id: 3,
              name: 'UPS',
              symbol: FloorPlanSymbol.ups,
            ),
          },
          catalog: const {},
          placements: const {},
          departmentName: (_) => null,
          roomAt: (_) => null,
          ports: const [
            FloorPlanPort(id: 1, objectId: 2, number: 1),
            FloorPlanPort(id: 2, objectId: 2, number: 2),
          ],
          occupiedPortIds: const {1},
        ),
      )!;

      expect(info.rows, [
        ('Περιέχει', 'SW-2, UPS'),
        ('Ελεύθερες θύρες switch', '1'),
      ]);
    },
  );

  group('Διαδρομή προς άλλον όροφο', () {
    FloorPlanInfoSources sourcesWith(List<FloorPlanObject> extra) =>
        FloorPlanInfoSources(
          objects: {
            9: const FloorPlanObject(
              id: 9,
              floorId: 1,
              kindId: 6,
              center: Offset.zero,
            ),
            for (final o in extra) o.id: o,
          },
          kinds: {
            6: const FloorPlanObjectKind(
              id: 6,
              name: 'Πρίζα',
              symbol: FloorPlanSymbol.outlet,
            ),
            7: const FloorPlanObjectKind(
              id: 7,
              name: 'Σκάλα',
              symbol: FloorPlanSymbol.riser,
            ),
          },
          catalog: const {},
          placements: const {},
          departmentName: (_) => null,
          roomAt: (_) => null,
          ports: const [FloorPlanPort(id: 1, objectId: 9, number: 1)],
          portLinks: const [
            FloorPlanPortLink(
              outletPortId: 1,
              outletFloorId: 1,
              patchPortId: 50,
              patchNumber: 17,
              panelId: 3,
              panelFloorId: 2,
              panelName: 'F',
              cabinetId: 8,
              cabinetName: 'RC6',
            ),
          ],
          floorLabel: (id) => {1: 'Υπόγειο', 2: '1ος'}[id],
          floorLevel: (id) => {1: -1, 2: 1}[id],
        );

    test('χωρίς σκάλα: σήμα δίπλα στην πρίζα, χωρίς γραμμή', () {
      final route = sourcesWith(const []).outletRoute(9);

      expect(route.targets, isEmpty);
      expect(route.riser, isNull);
      expect(route.badgeAnchor, Offset.zero);
      expect(route.otherFloors.single.badge, '↑ RC6 · 1ος');
      expect(route.otherFloors.single.objectId, 8);
      expect(route.otherFloors.single.floorId, 2);
    });

    test('με σκάλες: η γραμμή πάει στην πλησιέστερη', () {
      final route = sourcesWith(const [
        FloorPlanObject(id: 20, floorId: 1, kindId: 7, center: Offset(900, 0)),
        FloorPlanObject(id: 21, floorId: 1, kindId: 7, center: Offset(100, 0)),
      ]).outletRoute(9);

      expect(route.riser!.id, 21);
      expect(route.badgeAnchor, const Offset(100, 0));
    });
  });

  test('η θύρα 3 του switch δείχνει τη θύρα 12 του patch panel και, σε '
      'παρένθεση, τη συσκευή πίσω της', () {
    const panelPort = FloorPlanCableEnd(
      portId: 50,
      side: kFloorPlanCableFront,
      number: 12,
      objectId: 3,
      floorId: 1,
      objectName: 'F',
      cabinetName: 'RC6',
      symbol: FloorPlanSymbol.patchPanel,
    );
    const switchPort = FloorPlanCableEnd(
      portId: 60,
      side: kFloorPlanCableFront,
      number: 3,
      objectId: 4,
      floorId: 1,
      objectName: 'SW-2',
      symbol: FloorPlanSymbol.networkSwitch,
    );
    final info = FloorPlanInfoSources(
      objects: {
        3: const FloorPlanObject(
          id: 3,
          floorId: 1,
          kindId: 1,
          center: Offset.zero,
        ),
        4: const FloorPlanObject(
          id: 4,
          floorId: 1,
          kindId: 2,
          center: Offset.zero,
        ),
      },
      kinds: {
        1: const FloorPlanObjectKind(
          id: 1,
          name: 'Patch',
          symbol: FloorPlanSymbol.patchPanel,
        ),
        2: const FloorPlanObjectKind(
          id: 2,
          name: 'Switch',
          symbol: FloorPlanSymbol.networkSwitch,
        ),
      },
      catalog: const {},
      placements: const {},
      departmentName: (_) => null,
      roomAt: (_) => null,
      cableLines: const [
        FloorPlanCableLine(cableId: 1, a: panelPort, b: switchPort),
      ],
      portLinks: const [
        FloorPlanPortLink(
          outletPortId: 9,
          outletFloorId: 1,
          patchPortId: 50,
          patchNumber: 12,
          panelId: 3,
          panelFloorId: 1,
          connection: FloorPlanPortConnection(text: 'PR3918'),
        ),
      ],
    );

    final details = info.portDetails();
    expect(
      details(const FloorPlanPort(id: 60, objectId: 4, number: 3)),
      '→ RC6.F12 (PR3918)',
    );
    expect(
      details(const FloorPlanPort(id: 50, objectId: 3, number: 12)),
      'Πίσω: πρίζα → PR3918\nΜπροστά: SW-2 Gi1/0/3',
    );
    expect(
      details(const FloorPlanPort(id: 61, objectId: 4, number: 4)),
      isNull,
    );
  });

  FloorPlanObjectView placementView(int id) => FloorPlanObjectView(
    id: id,
    center: Offset.zero,
    size: const Size.square(60),
    rotationDegrees: 0,
    symbol: null,
    label: '',
    source: FloorPlanItemSource.placement,
  );

  test('υπάλληλος: τμήμα, τηλέφωνα, εξοπλισμός', () {
    final info = floorPlanItemInfo(
      placementView(1),
      sources(roomDepartment: 1),
    )!;
    expect(info.title, 'Παπαδόπουλος Γιώργος');
    expect(info.kindLabel, 'Υπάλληλος');
    expect(info.rows, [
      ('Τμήμα', 'Υλικού'),
      ('Τηλέφωνα', '2345'),
      ('Εξοπλισμός', 'PC-0412'),
    ]);
    expect(info.warning, isNull);
  });

  test('τηλέφωνο: ποιοι το έχουν', () {
    final info = floorPlanItemInfo(placementView(2), sources())!;
    expect(
      info.rows,
      contains(('Το έχουν', 'Παπαδόπουλος Γιώργος, Νικολάου Ελένη')),
    );
  });

  test('σε χώρο άλλου τμήματος: προειδοποίηση', () {
    final info = floorPlanItemInfo(
      placementView(1),
      sources(roomDepartment: 2),
    )!;
    expect(info.warning, 'Ο χώρος είναι του «Χειρουργική».');
  });

  test('σε διάδρομο (χώρος χωρίς τμήμα): καμία προειδοποίηση', () {
    final info = floorPlanItemInfo(
      placementView(1),
      sources(roomName: 'Διάδρομος'),
    )!;
    expect(info.warning, isNull);
  });

  test('αντικείμενο χάρτη: είδος, IP, και τμήμα του χώρου ως κάτοχος', () {
    const view = FloorPlanObjectView(
      id: 7,
      center: Offset.zero,
      size: Size.square(60),
      rotationDegrees: 0,
      symbol: FloorPlanSymbol.printer,
      label: 'ΕΚΤ-ΥΛ-01',
    );
    final info = floorPlanItemInfo(view, sources(roomDepartment: 1))!;
    expect(info.title, 'ΕΚΤ-ΥΛ-01');
    expect(info.kindLabel, 'Εκτυπωτής');
    expect(info.rows, [('IP', '10.1.2.33'), ('Τμήμα', 'Υλικού')]);
    expect(info.notes, 'δίπλα στο παράθυρο');
  });

  test('αντικείμενο σε χώρο χωρίς τμήμα: ο χώρος με το όνομά του', () {
    const view = FloorPlanObjectView(
      id: 7,
      center: Offset.zero,
      size: Size.square(60),
      rotationDegrees: 0,
      symbol: FloorPlanSymbol.printer,
      label: '',
    );
    final info = floorPlanItemInfo(view, sources(roomName: 'Αποθήκη'))!;
    expect(info.rows, contains(('Χώρος', 'Αποθήκη')));
  });

  test('εγγραφή που σβήστηκε στο μεταξύ: καμία περιγραφή', () {
    expect(floorPlanItemInfo(placementView(99), sources()), isNull);
  });

  test('είδος χωρίς πληροφορίες: καμία περιγραφή, και το ποντίκι το '
      'προσπερνά', () {
    const view = FloorPlanObjectView(
      id: 7,
      center: Offset.zero,
      size: Size.square(60),
      rotationDegrees: 0,
      symbol: FloorPlanSymbol.furniture,
      label: '',
      kindId: 5,
    );
    final base = sources(roomDepartment: 1);
    final quiet = FloorPlanInfoSources(
      objects: base.objects,
      kinds: {
        5: const FloorPlanObjectKind(
          id: 5,
          name: 'Γραφείο',
          symbol: FloorPlanSymbol.furniture,
          showInfo: false,
        ),
      },
      catalog: base.catalog,
      placements: base.placements,
      departmentName: base.departmentName,
      roomAt: base.roomAt,
    );

    expect(floorPlanItemInfo(view, quiet), isNull);
    expect(floorPlanItemHasInfo(view, quiet.kinds), isFalse);
    expect(floorPlanItemHasInfo(placementView(1), quiet.kinds), isTrue);
  });
}
