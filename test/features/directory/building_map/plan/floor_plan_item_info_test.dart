// Τι λέει η υπόδειξη του χάρτη για κάθε σύμβολο: υπάλληλος, τηλέφωνο,
// εξοπλισμός του Καταλόγου, αντικείμενο του χάρτη — και πότε προειδοποιεί.
//
//   flutter test test/features/directory/building_map/plan/floor_plan_item_info_test.dart

import 'dart:ui' show Offset, Size;

import 'package:call_logger/core/models/floor_plan_object.dart';
import 'package:call_logger/core/models/floor_plan_object_kind.dart';
import 'package:call_logger/core/models/floor_plan_placement.dart';
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
