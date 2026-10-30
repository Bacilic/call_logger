// Η εξαγωγή ενεργοποιημένου ορόφου: ολόκληρος ο όροφος σε εικόνα, με το
// σχήμα που έχει όπως φαίνεται (και περιστραμμένος).
//
//   flutter test test/features/directory/building_map/plan/services/floor_plan_export_test.dart

import 'package:call_logger/core/models/floor_plan_element.dart';
import 'package:call_logger/features/directory/building_map/plan/services/floor_plan_export.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const elements = [
    FloorPlanElement(
      id: 1,
      floorId: 1,
      kind: FloorPlanElementKind.wall,
      points: [Offset(0, 0), Offset(4000, 0)],
    ),
    FloorPlanElement(
      id: 2,
      floorId: 1,
      kind: FloorPlanElementKind.wall,
      points: [Offset(4000, 0), Offset(4000, 1000)],
    ),
  ];

  testWidgets('ο όροφος βγαίνει ολόκληρος, πλατύς όσο είναι', (tester) async {
    final image = await tester.runAsync(
      () => renderFloorPlanImage(
        elements: elements,
        departments: const {},
        rotationDegrees: 0,
        colors: const ColorScheme.light(),
      ),
    );
    expect(image!.width, greaterThan(image.height * 2));
    expect(image.width, greaterThanOrEqualTo(3000));
    image.dispose();
  });

  testWidgets('περιστραμμένος κατά 90°: η εικόνα γίνεται ψηλή', (tester) async {
    final image = await tester.runAsync(
      () => renderFloorPlanImage(
        elements: elements,
        departments: const {},
        rotationDegrees: 90,
        colors: const ColorScheme.light(),
      ),
    );
    expect(image!.height, greaterThan(image.width * 2));
    image.dispose();
  });
}
