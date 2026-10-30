// Η καμπίνα με θέσεις U: τι χωρά πού, πού μπαίνει κάτι νέο, τι εμποδίζει
// το μίκρεμά της, και πώς φαίνεται μαζί με τα κενά της.
//
//   flutter test test/features/directory/building_map/plan/floor_plan_cabinet_test.dart

import 'dart:ui' show Offset, Size;

import 'package:call_logger/core/models/floor_plan_object.dart';
import 'package:call_logger/features/directory/building_map/plan/floor_plan_cabinet.dart';
import 'package:flutter_test/flutter_test.dart';

FloorPlanObject _at(int id, int u, [int? units]) => FloorPlanObject(
  id: id,
  floorId: 1,
  kindId: 1,
  center: Offset.zero,
  cabinetId: 9,
  rackU: u,
  rackUnits: units,
);

void main() {
  test('δύο αντικείμενα δεν πιάνουν το ίδιο U, ούτε μέρος του', () {
    final ups = _at(1, 40, 3);
    bool fits(int u, int height) =>
        floorPlanRackFits(units: 42, contents: [ups], u: u, height: height);
    expect(fits(39, 1), isTrue);
    expect(fits(42, 1), isFalse);
    expect(fits(39, 2), isFalse);
    expect(fits(43, 1), isFalse, reason: 'έξω από την καμπίνα');
  });

  test('αυτό που μετακινείται δεν εμποδίζει τον εαυτό του', () {
    final ups = _at(1, 40, 3);
    expect(
      floorPlanRackFits(
        units: 42,
        contents: [ups],
        u: 39,
        height: 3,
        exceptId: 1,
      ),
      isTrue,
    );
  });

  test('νέο αντικείμενο πηγαίνει στο πρώτο ελεύθερο U από πάνω', () {
    final contents = [_at(1, 1), _at(2, 3)];
    expect(floorPlanFirstFreeRackU(units: 42, contents: contents), 2);
    expect(
      floorPlanFirstFreeRackU(units: 42, contents: contents, height: 2),
      4,
    );
    expect(floorPlanFirstFreeRackU(units: 2, contents: [_at(1, 1, 2)]), isNull);
  });

  test('το μίκρεμα το εμποδίζει μόνο ό,τι θα έβγαινε έξω', () {
    final contents = [_at(1, 1), _at(2, 40, 3)];
    expect(floorPlanContentsBeyond(42, contents), isEmpty);
    expect(floorPlanContentsBeyond(41, contents).map((o) => o.id), [2]);
  });

  test('η όψη δείχνει κάθε αντικείμενο στη θέση του και τα κενά ως σειρές', () {
    final rows = floorPlanRackRows(42, [_at(1, 1), _at(2, 3), _at(3, 40, 3)]);
    expect(
      [for (final r in rows) (r.object?.id, r.fromU, r.toU)],
      [(1, 1, 1), (null, 2, 2), (2, 3, 3), (null, 4, 39), (3, 40, 42)],
    );
  });

  test('άδεια καμπίνα: μία σειρά κενών από το U1 ως το τέλος', () {
    final rows = floorPlanRackRows(12, const []);
    expect(
      [for (final r in rows) (r.isEmpty, r.fromU, r.toU)],
      [(true, 1, 12)],
    );
  });

  test('δύο στο ίδιο U (από δύο σταθμούς) δεν χάνονται από την όψη', () {
    final rows = floorPlanRackRows(42, [_at(1, 5), _at(2, 5)]);
    final items = [
      for (final r in rows)
        if (!r.isEmpty) (r.object!.id, r.fromU),
    ];
    expect(items, [(1, 5), (2, 6)]);
  });

  test('η θέση κάτω από τον δείκτη μένει μέσα στην καμπίνα', () {
    expect(floorPlanRackUAt(0, 24, 42), 1);
    expect(floorPlanRackUAt(50, 24, 42), 3);
    expect(floorPlanRackUAt(-10, 24, 42), 1);
    expect(floorPlanRackUAt(5000, 24, 42), 42);
  });

  test(
    'ό,τι βγαίνει από την καμπίνα πέφτει δίπλα της, όπως είναι γυρισμένη',
    () {
      const size = Size(60, 80);
      expect(floorPlanBesideCabinet(Offset.zero, size, 0), const Offset(80, 0));
      final turned = floorPlanBesideCabinet(Offset.zero, size, 90);
      expect(turned.dx, closeTo(0, 1e-9));
      expect(turned.dy, closeTo(80, 1e-9));
    },
  );
}
