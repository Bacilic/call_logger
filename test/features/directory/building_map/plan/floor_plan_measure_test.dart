// Η μέτρηση απόστασης του χάρτη: σημεία, μήκη, κλείσιμο, νέα μέτρηση.
//
//   flutter test test/features/directory/building_map/plan/floor_plan_measure_test.dart

import 'package:call_logger/features/directory/building_map/plan/floor_plan_measure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final route = FloorPlanMeasure.empty
      .add(Offset.zero)
      .add(const Offset(300, 0))
      .add(const Offset(300, 400));

  test('κάθε κομμάτι μετριέται, και το σύνολο τα αθροίζει', () {
    expect(route.segmentLengths, [300, 400]);
    expect(route.totalLength, 700);
  });

  test('το Backspace σβήνει το τελευταίο σημείο', () {
    expect(route.removeLast().totalLength, 300);
  });

  test('κλείσιμο με ένα μόνο σημείο σβήνει τη μέτρηση', () {
    expect(FloorPlanMeasure.empty.add(Offset.zero).finish().isEmpty, isTrue);
  });

  test('μετά το κλείσιμο, το επόμενο κλικ ξεκινά νέα μέτρηση', () {
    final next = route.finish().add(const Offset(50, 50));
    expect(next.points, [const Offset(50, 50)]);
    expect(next.finished, isFalse);
  });
}
