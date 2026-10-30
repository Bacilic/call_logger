// Ο χώρος που βρίσκει το διπλό κλικ μέσα σε κλειστούς τοίχους.
//
//   flutter test test/features/directory/building_map/plan/floor_plan_rooms_test.dart

import 'package:call_logger/features/directory/building_map/plan/floor_plan_geometry.dart';
import 'package:call_logger/features/directory/building_map/plan/floor_plan_rooms.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Ορθογώνιο από τέσσερις τοίχους.
  List<FloorPlanSegment> box(double l, double t, double r, double b) => [
    FloorPlanSegment(Offset(l, t), Offset(r, t)),
    FloorPlanSegment(Offset(r, t), Offset(r, b)),
    FloorPlanSegment(Offset(r, b), Offset(l, b)),
    FloorPlanSegment(Offset(l, b), Offset(l, t)),
  ];

  double area(List<Offset> p) => signedPolygonArea(p).abs();

  test('κλειστό δωμάτιο: ο χώρος ακολουθεί τους τοίχους', () {
    final room = enclosingRoom(const Offset(200, 150), box(0, 0, 400, 300));
    expect(room, isNotNull);
    expect(room, hasLength(4));
    expect(area(room!), closeTo(400 * 300, 1));
  });

  test('ανοιχτοί τοίχοι: κανένας χώρος', () {
    final walls = box(0, 0, 400, 300)..removeLast();
    expect(enclosingRoom(const Offset(200, 150), walls), isNull);
  });

  test('σημείο έξω από το κτίριο: κανένας χώρος', () {
    expect(enclosingRoom(const Offset(900, 900), box(0, 0, 400, 300)), isNull);
  });

  test('ενδιάμεσος τοίχος σε σχήμα Τ χωρίζει δύο δωμάτια', () {
    final walls = [
      ...box(0, 0, 600, 300),
      // Από τον πάνω τοίχο ως τον κάτω, ακουμπώντας στο σώμα τους.
      const FloorPlanSegment(Offset(200, 0), Offset(200, 300)),
    ];
    final left = enclosingRoom(const Offset(100, 150), walls)!;
    final right = enclosingRoom(const Offset(400, 150), walls)!;
    expect(area(left), closeTo(200 * 300, 1));
    expect(area(right), closeTo(400 * 300, 1));
  });

  test('διασταυρούμενοι τοίχοι κόβονται στο σημείο τομής', () {
    final walls = [
      ...box(0, 0, 400, 400),
      const FloorPlanSegment(Offset(200, -50), Offset(200, 450)),
      const FloorPlanSegment(Offset(-50, 200), Offset(450, 200)),
    ];
    final quarter = enclosingRoom(const Offset(300, 300), walls)!;
    expect(area(quarter), closeTo(200 * 200, 1));
  });

  test('τοίχος που μπαίνει στο δωμάτιο και σταματά δεν το χαλάει', () {
    final walls = [
      ...box(0, 0, 400, 300),
      const FloorPlanSegment(Offset(0, 150), Offset(120, 150)),
    ];
    final room = enclosingRoom(const Offset(300, 150), walls)!;
    expect(area(room), closeTo(400 * 300, 1));
    expect(room, hasLength(4));
  });

  test('η ετικέτα χώρου σε σχήμα Γ πέφτει μέσα στον χώρο', () {
    const l = [
      Offset(0, 0),
      Offset(1000, 0),
      Offset(1000, 100),
      Offset(100, 100),
      Offset(100, 1000),
      Offset(0, 1000),
    ];
    expect(polygonContains(l, polygonLabelPoint(l)), isTrue);
  });
}
