// Η επιλογή «όροφος ή στιγμιότυπο», η γραμμή πάνω από τον χάρτη και οι
// κρυμμένες στρώσεις που δηλώνονται στον χρήστη.
//
//   flutter test test/features/directory/building_map/plan/floor_plan_output_test.dart

import 'package:call_logger/core/models/floor_plan_object_kind.dart';
import 'package:call_logger/core/models/floor_plan_placement.dart';
import 'package:call_logger/features/directory/building_map/plan/floor_plan_layers.dart';
import 'package:call_logger/features/directory/building_map/plan/floor_plan_output.dart';
import 'package:call_logger/features/directory/building_map/plan/widgets/floor_plan_output_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('η γραμμή λέει τον όροφο και την ημερομηνία', () {
    expect(
      floorPlanOutputCaption('0 - Ισόγειο', DateTime(2026, 11, 4)),
      '0 - Ισόγειο · 04/11/2026',
    );
  });

  group('Κρυμμένες στρώσεις', () {
    const kinds = [
      FloorPlanObjectKind(
        id: 1,
        name: 'Εκτυπωτής',
        symbol: FloorPlanSymbol.printer,
      ),
      FloorPlanObjectKind(
        id: 2,
        name: 'Έπιπλο',
        symbol: FloorPlanSymbol.furniture,
      ),
    ];

    test('πρώτα του Καταλόγου, μετά τα είδη', () {
      expect(
        floorPlanHiddenLayerNames({
          floorPlanKindLayer(1),
          floorPlanPlacementLayer(FloorPlanPlacementType.user),
        }, kinds),
        ['Υπάλληλοι', 'Εκτυπωτής'],
      );
    });

    test('είδος που δεν υπάρχει πια δεν αναφέρεται', () {
      expect(
        floorPlanHiddenLayerNames({floorPlanKindLayer(99)}, kinds),
        isEmpty,
      );
    });
  });

  group('Παράθυρο επιλογής', () {
    FloorPlanOutputScope? result;

    Future<void> openDialog(WidgetTester tester) async {
      result = null;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showFloorPlanOutputDialog(
                  context: context,
                  title: 'Εξαγωγή χάρτη',
                  confirmLabel: 'Εξαγωγή…',
                  hiddenLayerNames: const ['Υπάλληλοι', 'Τηλέφωνα'],
                );
              },
              child: const Text('άνοιγμα'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('άνοιγμα'));
      await tester.pumpAndSettle();
    }

    Future<void> press(WidgetTester tester, String label) async {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    testWidgets('χωρίς αλλαγή βγαίνει ολόκληρος ο όροφος', (tester) async {
      await openDialog(tester);
      await press(tester, 'Εξαγωγή…');
      expect(result, FloorPlanOutputScope.wholeFloor);
    });

    testWidgets('διαλέγοντας στιγμιότυπο, βγαίνει στιγμιότυπο', (tester) async {
      await openDialog(tester);
      await press(tester, 'Στιγμιότυπο: ό,τι φαίνεται τώρα');
      await press(tester, 'Εξαγωγή…');
      expect(result, FloorPlanOutputScope.snapshot);
    });

    testWidgets('το «Άκυρο» δεν βγάζει τίποτα', (tester) async {
      await openDialog(tester);
      await press(tester, 'Άκυρο');
      expect(result, isNull);
    });

    testWidgets('δηλώνει ποιες στρώσεις λείπουν', (tester) async {
      await openDialog(tester);
      expect(
        find.text('Κρυμμένες στρώσεις: Υπάλληλοι, Τηλέφωνα'),
        findsOneWidget,
      );
    });
  });
}
