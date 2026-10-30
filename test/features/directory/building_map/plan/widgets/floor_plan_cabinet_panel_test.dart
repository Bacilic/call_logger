// Το πάνελ της καμπίνας: σύρσιμο σε άλλο U ζητά μετακίνηση εκεί, και η
// προβολή (χωρίς ενέργειες) δεν αφήνει να αλλάξει τίποτα.
//
//   flutter test test/features/directory/building_map/plan/widgets/floor_plan_cabinet_panel_test.dart

import 'package:call_logger/core/models/floor_plan_object.dart';
import 'package:call_logger/core/models/floor_plan_object_kind.dart';
import 'package:call_logger/core/models/floor_plan_port.dart';
import 'package:call_logger/features/directory/building_map/plan/widgets/floor_plan_cabinet_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const kinds = {
    1: FloorPlanObjectKind(
      id: 1,
      name: 'Switch',
      symbol: FloorPlanSymbol.networkSwitch,
    ),
  };
  const sw = FloorPlanObject(
    id: 7,
    floorId: 1,
    kindId: 1,
    center: Offset.zero,
    name: 'SW-2',
    cabinetId: 9,
    rackU: 1,
  );

  Future<void> pump(WidgetTester tester, FloorPlanCabinetActions? actions) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: FloorPlanCabinetPanel(
                title: 'RC6',
                units: 12,
                contents: const [sw],
                kinds: kinds,
                onClose: () {},
                actions: actions,
              ),
            ),
          ),
        ),
      );

  testWidgets('σύρσιμο στο U5 ζητά μετακίνηση στο U5', (tester) async {
    final moves = <(int, int)>[];
    await pump(
      tester,
      FloorPlanCabinetActions(
        addableKinds: [kinds[1]!],
        onAdd: (_) {},
        onMove: (id, u) => moves.add((id, u)),
        onEdit: (_) {},
        onSetHeight: (_, _) {},
        onTakeOut: (_) {},
        onDelete: (_) {},
        onSetUnits: (_) {},
      ),
    );
    expect(find.text('κενό U2–U12'), findsOne);

    // Κάθε U έχει ύψος 24 pixel: τέσσερα πιο κάτω = U5.
    await tester.drag(find.text('Switch SW-2'), const Offset(0, 4 * 24));
    await tester.pumpAndSettle();

    expect(moves, [(7, 5)]);
  });

  testWidgets('στην προβολή δεν υπάρχει «Προσθήκη» ούτε μενού', (tester) async {
    await pump(tester, null);

    expect(find.text('Switch SW-2'), findsOne);
    expect(find.text('Προσθήκη'), findsNothing);
    expect(find.byTooltip('Ενέργειες'), findsNothing);
  });

  testWidgets('επιλεγμένο switch γράφει ελεύθερες θύρες και δείχνει την '
      'πρόσοψή του', (tester) async {
    const ports = [
      FloorPlanPort(id: 1, objectId: 7, number: 1),
      FloorPlanPort(id: 2, objectId: 7, number: 2),
      FloorPlanPort(id: 3, objectId: 7, number: 3),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: FloorPlanCabinetPanel(
              title: 'RC6',
              units: 12,
              contents: const [sw],
              kinds: kinds,
              onClose: () {},
              ports: ports,
              occupiedPortIds: const {2},
              initialSelection: const {7},
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('3 θύρες · 2 ελεύθερες'), findsNWidgets(2));
    // Η πρόσοψη: μία θύρα ανά αριθμό.
    for (final n in ['1', '2', '3']) {
      expect(find.text(n), findsOne);
    }
  });

  group('Επιλογή συσκευών', () {
    const ports = [FloorPlanPort(id: 1, objectId: 7, number: 1)];
    const switchKinds = {
      1: FloorPlanObjectKind(
        id: 1,
        name: 'Switch',
        symbol: FloorPlanSymbol.networkSwitch,
      ),
    };

    Future<List<int>> pumpEditable(WidgetTester tester) async {
      final edits = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FloorPlanCabinetPanel(
              title: 'RC6',
              units: 12,
              contents: const [sw],
              kinds: switchKinds,
              onClose: () {},
              ports: ports,
              actions: FloorPlanCabinetActions(
                addableKinds: const [],
                onAdd: (_) {},
                onMove: (_, _) {},
                onEdit: edits.add,
                onSetHeight: (_, _) {},
                onTakeOut: (_) {},
                onDelete: (_) {},
                onSetUnits: (_) {},
              ),
            ),
          ),
        ),
      );
      return edits;
    }

    testWidgets('από προεπιλογή καμία πρόσοψη· κλικ τη δείχνει, δεύτερο κλικ '
        'αργότερα την κρύβει', (tester) async {
      await pumpEditable(tester);
      expect(
        find.textContaining('ελεύθερες'),
        findsOne,
        reason: 'μόνο η γραμμή',
      );

      await tester.tap(find.textContaining('Switch SW-2'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('ελεύθερες'), findsNWidgets(2));

      await tester.tap(find.textContaining('Switch SW-2').first);
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('ελεύθερες'), findsOne);
    });

    testWidgets('διπλό κλικ ανοίγει τα στοιχεία χωρίς να αλλάξει η επιλογή', (
      tester,
    ) async {
      final edits = await pumpEditable(tester);

      await tester.tap(find.textContaining('Switch SW-2'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.textContaining('Switch SW-2').first);
      await tester.pump();

      expect(edits, [7]);
      expect(find.textContaining('ελεύθερες'), findsOne);
    });
  });
}
