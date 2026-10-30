// Η γεωμετρία της επιλογής: τι πιάνει το κλικ, τι χωρά στο ορθογώνιο, πώς
// μετακινούνται και γυρίζουν τα στοιχεία.
//
//   flutter test test/features/directory/building_map/plan/floor_plan_selection_test.dart

import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:call_logger/core/models/floor_plan_element.dart';
import 'package:call_logger/features/directory/building_map/plan/floor_plan_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const wall = FloorPlanElement(
    id: 1,
    floorId: 1,
    kind: FloorPlanElementKind.wall,
    points: [Offset(0, 0), Offset(500, 0)],
  );
  const door = FloorPlanElement(
    id: 2,
    floorId: 1,
    kind: FloorPlanElementKind.opening,
    points: [Offset(100, 0), Offset(190, 0)],
    parentId: 1,
  );
  const room = FloorPlanElement(
    id: 3,
    floorId: 1,
    kind: FloorPlanElementKind.room,
    points: [Offset(0, 0), Offset(500, 0), Offset(500, 400), Offset(0, 400)],
  );
  const label = FloorPlanElement(
    id: 4,
    floorId: 1,
    kind: FloorPlanElementKind.text,
    points: [Offset(250, 200)],
    name: 'Αποθήκη',
    fontSize: 40,
  );
  const all = [wall, door, room, label];

  bool near(Offset a, Offset b) => (a - b).distance < 1e-6;

  group('Τι πιάνει το κλικ', () {
    test('το κείμενο πάνω από τον χώρο που το περιέχει', () {
      expect(hitTestElement(const Offset(250, 200), all, 10)?.id, 4);
    });

    test('η πόρτα πριν από τον τοίχο της', () {
      expect(hitTestElement(const Offset(150, 3), all, 10)?.id, 2);
    });

    test('ο τοίχος έξω από την πόρτα', () {
      expect(hitTestElement(const Offset(400, 3), all, 10)?.id, 1);
    });

    test('ο χώρος όπου δεν υπάρχει τίποτα άλλο', () {
      expect(hitTestElement(const Offset(450, 350), all, 10)?.id, 3);
    });

    test('έξω από όλα: τίποτα', () {
      expect(hitTestElement(const Offset(900, 900), all, 10), isNull);
    });
  });

  test('το ορθογώνιο επιλέγει μόνο ό,τι χωρά ολόκληρο — όχι πόρτες μόνες', () {
    final inside = elementsInRect(Rect.fromLTWH(-10, -10, 520, 20), all);
    expect(inside, {1});
  });

  test('η μετακίνηση αφήνει την πόρτα πάνω στον τοίχο της', () {
    expect(translateElement(door, const Offset(50, 50)).points, door.points);
    expect(translateElement(wall, const Offset(50, 50)).points, const [
      Offset(50, 50),
      Offset(550, 50),
    ]);
  });

  test('η περιστροφή γυρίζει και τα γράμματα του κειμένου', () {
    final turned = rotateElement(label, const Offset(0, 0), math.pi / 2);
    expect(near(turned.points.single, const Offset(-200, 250)), isTrue);
    expect(turned.rotationDegrees, closeTo(90, 1e-9));
  });

  test('η περιστροφή χώρου γυρίζει και το μετακινημένο όνομά του', () {
    const room = FloorPlanElement(
      id: 9,
      floorId: 1,
      kind: FloorPlanElementKind.room,
      points: [Offset(0, 0), Offset(400, 0), Offset(400, 300)],
      labelOffset: Offset(100, 0),
    );
    final turned = rotateElement(room, Offset.zero, math.pi / 2);
    expect(near(turned.labelOffset!, const Offset(0, 100)), isTrue);
  });

  test('ο μαγνήτης περιστροφής κουμπώνει ανά 15°', () {
    expect(snapRadians(0.30) * 180 / math.pi, closeTo(15, 1e-9));
  });

  test('η αντιγραφή τοίχου παίρνει μαζί τις πόρτες του', () {
    expect(withOwnedOpenings({1}, all).map((e) => e.id), [1, 2]);
  });

  test('η γραμμή διάστασης απέχει όσο ορίζει το τρίτο σημείο', () {
    const dim = FloorPlanElement(
      id: 5,
      floorId: 1,
      kind: FloorPlanElementKind.dimension,
      points: [Offset(0, 0), Offset(400, 0), Offset(123, 60)],
    );
    final line = dimensionLine(dim)!;
    expect(near(line.a, const Offset(0, 60)), isTrue);
    expect(near(line.b, const Offset(400, 60)), isTrue);
  });
}
