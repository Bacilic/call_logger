// Το παράθυρο της καμπίνας: σύρσιμο από τη μπάρα τίτλου το μετακινεί,
// σύρσιμο από την άκρη αλλάζει μέγεθος, και δεν βγαίνει ποτέ έξω από τον χάρτη.
//
//   flutter test test/features/directory/building_map/plan/widgets/floor_plan_cabinet_window_test.dart

import 'package:call_logger/features/directory/building_map/plan/services/floor_plan_cabinet_preferences.dart';
import 'package:call_logger/features/directory/building_map/plan/widgets/floor_plan_cabinet_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const bounds = Size(1200, 800);
  final panelKey = GlobalKey();

  setUp(() {
    FloorPlanCabinetPreferences.resetForTest();
    // Γνωστή αφετηρία, χωρίς βάση: η μνήμη του πάνελ ξεκινά από εδώ.
    FloorPlanCabinetPreferences.setLayoutForTest(
      const FloorPlanCabinetLayout(
        rect: Rect.fromLTWH(400, 100, 500, 600),
        facadeHeight: 200,
      ),
    );
  });

  tearDown(FloorPlanCabinetPreferences.resetForTest);

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = bounds;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.fromSize(
            size: bounds,
            child: Stack(
              children: [
                FloorPlanCabinetWindow(
                  bounds: bounds,
                  builder: (context, hooks) => Material(
                    key: panelKey,
                    child: Column(
                      children: [
                        GestureDetector(
                          onPanUpdate: (d) => hooks.onTitleDrag(d.delta),
                          onPanEnd: (_) => hooks.onLayoutDone(),
                          child: const SizedBox(
                            height: 40,
                            width: double.infinity,
                            child: Text('Καμπίνα RC6'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Rect panel(WidgetTester tester) => tester.getRect(find.byKey(panelKey));

  testWidgets('σύρσιμο από τη μπάρα τίτλου μετακινεί το πάνελ', (tester) async {
    await pump(tester);
    expect(panel(tester), const Rect.fromLTWH(400, 100, 500, 600));

    await tester.drag(find.text('Καμπίνα RC6'), const Offset(-150, 50));
    await tester.pump();

    expect(panel(tester).topLeft, const Offset(250, 150));
    expect(panel(tester).size, const Size(500, 600));
  });

  testWidgets('σύρσιμο από τη δεξιά άκρη αλλάζει το πλάτος', (tester) async {
    await pump(tester);

    await tester.dragFrom(const Offset(898, 400), const Offset(100, 0));
    await tester.pump();

    expect(panel(tester).left, 400);
    expect(panel(tester).width, closeTo(600, 1));
  });

  testWidgets('δεν βγαίνει έξω από τον χάρτη', (tester) async {
    await pump(tester);

    await tester.drag(find.text('Καμπίνα RC6'), const Offset(2000, 2000));
    await tester.pump();

    expect(panel(tester).right, lessThanOrEqualTo(bounds.width));
    expect(panel(tester).bottom, lessThanOrEqualTo(bounds.height));
  });
}
