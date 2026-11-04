// Η πρόσοψη στη σχεδίαση: κλικ σε θύρα για το καλώδιο, δεξί κλικ για το
// γραμμένο όνομα. Στην προβολή οι θύρες δεν πατιούνται.
//
//   flutter test test/features/directory/building_map/plan/widgets/floor_plan_port_facade_test.dart

import 'package:call_logger/core/models/floor_plan_object_kind.dart';
import 'package:call_logger/core/models/floor_plan_port.dart';
import 'package:call_logger/features/directory/building_map/plan/widgets/floor_plan_port_facade.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ports = [
    FloorPlanPort(id: 1, objectId: 1, number: 1),
    FloorPlanPort(id: 2, objectId: 1, number: 2),
  ];

  Future<void> pump(
    WidgetTester tester, {
    void Function(FloorPlanPort, Offset)? onPortTap,
    void Function(FloorPlanPort)? onEditWrittenName,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          child: FloorPlanPortFacade(
            title: 'Switch',
            symbol: FloorPlanSymbol.networkSwitch,
            ports: ports,
            occupied: const {},
            autoName: (p) => 'SW / ${p.number}',
            onPortTap: onPortTap,
            onEditWrittenName: onEditWrittenName,
          ),
        ),
      ),
    ),
  );

  testWidgets('κλικ δίνει τη θύρα για το καλώδιο, όχι το γραμμένο όνομα', (
    tester,
  ) async {
    final tapped = <int>[];
    final written = <int>[];
    await pump(
      tester,
      onPortTap: (p, _) => tapped.add(p.number),
      onEditWrittenName: (p) => written.add(p.number),
    );

    await tester.tap(find.text('2'));

    expect(tapped, [2]);
    expect(written, isEmpty);
  });

  testWidgets('δεξί κλικ ανοίγει το γραμμένο όνομα', (tester) async {
    final tapped = <int>[];
    final written = <int>[];
    await pump(
      tester,
      onPortTap: (p, _) => tapped.add(p.number),
      onEditWrittenName: (p) => written.add(p.number),
    );

    await tester.tap(find.text('1'), buttons: kSecondaryButton);

    expect(written, [1]);
    expect(tapped, isEmpty);
  });

  testWidgets('χωρίς ενέργειες (προβολή) το κλικ δεν κάνει τίποτα', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('1'));

    expect(tester.takeException(), isNull);
    expect(find.text('1'), findsOneWidget);
  });
}
