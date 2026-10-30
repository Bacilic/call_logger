// Η αντιστοίχιση σχεδίου ↔ οθόνης: ένα κλικ πρέπει να πέφτει στο σημείο του
// σχεδίου που φαίνεται κάτω από τον δείκτη, και σε περιστραμμένο όροφο.
//
//   flutter test test/features/directory/building_map/plan/floor_plan_view_transform_test.dart

import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:call_logger/features/directory/building_map/plan/floor_plan_view_transform.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  bool near(Offset a, Offset b) => (a - b).distance < 1e-6;

  const rotated = FloorPlanViewTransform(
    pixelsPerCm: 0.4,
    rotationRadians: math.pi / 6,
    origin: Offset(120, 80),
  );

  test('οθόνη → σχέδιο → οθόνη επιστρέφει στο ίδιο σημείο', () {
    const screen = Offset(431, 257);
    expect(near(rotated.toScreen(rotated.toWorld(screen)), screen), isTrue);
  });

  test('στη μεγέθυνση το σημείο κάτω από τον δείκτη δεν μετακινείται', () {
    const pointer = Offset(300, 200);
    final before = rotated.toWorld(pointer);
    final zoomed = rotated.zoomAt(pointer, 1.7);
    expect(near(zoomed.toWorld(pointer), before), isTrue);
    expect(zoomed.pixelsPerCm, closeTo(0.68, 1e-9));
  });

  test('η προβολή όλου χωράει το σχέδιο στην οθόνη', () {
    const viewport = Size(800, 600);
    final view = FloorPlanViewTransform.fit(
      worldRect: const Rect.fromLTWH(-500, 200, 4000, 2000),
      viewport: viewport,
      rotationRadians: math.pi / 2,
    );
    for (final corner in const [
      Offset(-500, 200),
      Offset(3500, 200),
      Offset(-500, 2200),
      Offset(3500, 2200),
    ]) {
      final s = view.toScreen(corner);
      expect(s.dx >= -1e-6 && s.dx <= viewport.width + 1e-6, isTrue);
      expect(s.dy >= -1e-6 && s.dy <= viewport.height + 1e-6, isTrue);
    }
  });

  test('η αλλαγή περιστροφής κρατά το κέντρο της οθόνης', () {
    const viewport = Size(800, 600);
    const center = Offset(400, 300);
    final before = rotated.toWorld(center);
    final turned = rotated.withRotation(math.pi, viewport);
    expect(near(turned.toWorld(center), before), isTrue);
  });
}
