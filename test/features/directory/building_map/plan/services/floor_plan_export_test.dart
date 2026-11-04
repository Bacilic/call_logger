// Η εξαγωγή ενεργοποιημένου ορόφου: ολόκληρος ο όροφος σε εικόνα, με το
// σχήμα που έχει όπως φαίνεται (και περιστραμμένος).
//
//   flutter test test/features/directory/building_map/plan/services/floor_plan_export_test.dart

import 'package:call_logger/core/models/floor_plan_element.dart';
import 'package:call_logger/features/directory/building_map/plan/services/floor_plan_export.dart';
import 'package:call_logger/features/directory/building_map/plan/widgets/floor_plan_map_view.dart';
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

  testWidgets(
    'η γραμμή ορόφου μπαίνει πάνω από τον χάρτη, χωρίς να τον κόψει',
    (tester) async {
      final image = await tester.runAsync(() async {
        final map = await renderFloorPlanImage(
          elements: elements,
          departments: const {},
          rotationDegrees: 0,
          colors: const ColorScheme.light(),
        );
        final width = map.width;
        final height = map.height;
        final captioned = await addFloorPlanCaption(
          map,
          '0 - Ισόγειο · 04/11/2026',
        );
        expect(captioned.width, width);
        expect(captioned.height, greaterThan(height));
        return captioned;
      });
      image!.dispose();
    },
  );

  testWidgets('το στιγμιότυπο βγάζει ό,τι δείχνει ο χάρτης, πιο πυκνά', (
    tester,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 300,
          child: FloorPlanMapView(
            elements: elements,
            departments: const {},
            rotationDegrees: 0,
            snapshotKey: key,
          ),
        ),
      ),
    );
    final capture = captureFloorPlanSnapshot(key);
    await tester.pump();
    final image = await tester.runAsync(() => capture);
    expect(image!.width, greaterThan(tester.getSize(find.byKey(key)).width));
    image.dispose();
  });

  testWidgets('για το χαρτί το στιγμιότυπο δεν ξεπερνά το όριο μεγέθους', (
    tester,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 300,
          child: FloorPlanMapView(
            elements: elements,
            departments: const {},
            rotationDegrees: 0,
            snapshotKey: key,
          ),
        ),
      ),
    );
    final capture = captureFloorPlanSnapshot(key, maxLongSide: 200);
    await tester.pump();
    final image = await tester.runAsync(() => capture);
    expect(image!.width, lessThanOrEqualTo(200));
    expect(image.height, lessThanOrEqualTo(200));
    image.dispose();
  });

  testWidgets('χωρίς χάρτη στην οθόνη το στιγμιότυπο αποτυγχάνει με σφάλμα', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final capture = captureFloorPlanSnapshot(GlobalKey());
    final expectation = expectLater(capture, throwsStateError);
    await tester.pump();
    await expectation;
  });
}
