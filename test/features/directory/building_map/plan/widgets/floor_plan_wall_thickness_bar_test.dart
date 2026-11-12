// Η μπάρα «Πάχος» των επιλεγμένων τοίχων: τα βήματα των − / +, τι δέχεται η
// πληκτρολόγηση, και ότι το Enter στέλνει το πάχος που γράφτηκε.
//
//   flutter test test/features/directory/building_map/plan/widgets/floor_plan_wall_thickness_bar_test.dart

import 'package:call_logger/features/directory/building_map/plan/widgets/floor_plan_wall_thickness_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'τα − / + πάνε στο επόμενο στρογγυλό πεντάρι και σταματούν στα όρια',
    () {
      expect(stepFloorPlanWallThickness(15, increase: true), 20);
      expect(stepFloorPlanWallThickness(15, increase: false), 10);
      expect(stepFloorPlanWallThickness(12, increase: true), 15);
      expect(stepFloorPlanWallThickness(12, increase: false), 10);
      expect(stepFloorPlanWallThickness(100, increase: true), 100);
      expect(stepFloorPlanWallThickness(5, increase: false), 5);
    },
  );

  test('η πληκτρολόγηση μένει μέσα στα όρια· ό,τι δεν είναι αριθμός '
      'αγνοείται', () {
    expect(parseFloorPlanWallThickness('40'), 40);
    expect(parseFloorPlanWallThickness('3'), 5);
    expect(parseFloorPlanWallThickness('250'), 100);
    expect(parseFloorPlanWallThickness(''), isNull);
    expect(parseFloorPlanWallThickness('0'), isNull);
  });

  testWidgets('γράφω 40 και Enter → στέλνεται πάχος 40 και η εστίαση '
      'επιστρέφει στον χάρτη', (tester) async {
    final sent = <double>[];
    var done = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: FloorPlanWallThicknessBar(
              thicknessCm: 15,
              onChanged: sent.add,
              onDone: () => done++,
            ),
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('wall-thickness-field')),
      '40',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(sent, [40]);
    expect(done, 1);
  });

  testWidgets('τοίχοι με διαφορετικά πάχη: το «+» ξεκινά από το συνηθισμένο', (
    tester,
  ) async {
    final sent = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: FloorPlanWallThicknessBar(
              thicknessCm: null,
              onChanged: sent.add,
              onDone: () {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Παχύτερος τοίχος'));
    await tester.pump();

    expect(sent, [20]);
  });
}
