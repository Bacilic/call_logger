// Το βήμα του A− / A+ στο πλαίσιο κειμένου του χάρτη.
//
//   flutter test test/features/directory/building_map/plan/widgets/floor_plan_text_editor_test.dart

import 'package:call_logger/features/directory/building_map/plan/widgets/floor_plan_text_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('A+ και A− αλλάζουν το μέγεθος, και το ένα αναιρεί το άλλο', () {
    final up = stepFloorPlanTextSize(40, increase: true);
    expect(up, greaterThan(40));
    expect(stepFloorPlanTextSize(up, increase: false), closeTo(40, 1e-9));
  });

  test('το μέγεθος μένει μέσα στα όρια', () {
    expect(
      stepFloorPlanTextSize(kFloorPlanTextSizeMaxCm, increase: true),
      kFloorPlanTextSizeMaxCm,
    );
    expect(
      stepFloorPlanTextSize(kFloorPlanTextSizeMinCm, increase: false),
      kFloorPlanTextSizeMinCm,
    );
  });
}
