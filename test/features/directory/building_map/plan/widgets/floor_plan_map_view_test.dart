// Η προβολή του νέου χάρτη (και στον μικρό χάρτη των κλήσεων): ροδέλα =
// ζουμ, σύρσιμο = μετακίνηση, διπλό κλικ = πίσω στην αρχική θέαση· πέρασμα
// του ποντικιού πάνω από σύμβολο = υπόδειξη, κλικ = πλήρη στοιχεία.
//
//   flutter test test/features/directory/building_map/plan/widgets/floor_plan_map_view_test.dart

import 'package:call_logger/core/models/floor_plan_element.dart';
import 'package:call_logger/core/models/floor_plan_object_kind.dart';
import 'package:call_logger/core/models/floor_plan_placement.dart';
import 'package:call_logger/features/directory/building_map/plan/floor_plan_item_info.dart';
import 'package:call_logger/features/directory/building_map/plan/floor_plan_objects.dart';
import 'package:call_logger/features/directory/building_map/plan/floor_plan_measure.dart';
import 'package:call_logger/features/directory/building_map/plan/floor_plan_view_transform.dart';
import 'package:call_logger/features/directory/building_map/plan/widgets/floor_plan_measure_painter.dart';
import 'package:call_logger/features/directory/building_map/plan/widgets/floor_plan_map_view.dart';
import 'package:call_logger/features/directory/building_map/plan/widgets/floor_plan_painter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const elements = [
    FloorPlanElement(
      id: 1,
      floorId: 1,
      kind: FloorPlanElementKind.room,
      points: [Offset(0, 0), Offset(400, 0), Offset(400, 300), Offset(0, 300)],
      departmentId: 10,
    ),
  ];

  Future<void> pump(WidgetTester tester, {bool measuring = false}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 336,
                height: 170,
                child: FloorPlanMapView(
                  elements: elements,
                  departments: const {},
                  rotationDegrees: 0,
                  highlightDepartmentId: 10,
                  margin: 8,
                  measuring: measuring,
                ),
              ),
            ),
          ),
        ),
      );

  FloorPlanViewTransform view(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is FloorPlanPainter,
      ),
    );
    return (paint.painter! as FloorPlanPainter).view;
  }

  testWidgets('ροδέλα μεγεθύνει, σύρσιμο μετακινεί, διπλό κλικ επαναφέρει', (
    tester,
  ) async {
    await pump(tester);
    final initial = view(tester);
    final center = tester.getCenter(find.byType(FloorPlanMapView));

    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(center));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -200)));
    await tester.pump();
    expect(view(tester).pixelsPerCm, greaterThan(initial.pixelsPerCm));

    final zoomed = view(tester);
    await tester.dragFrom(
      center,
      const Offset(40, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(view(tester).origin.dx, greaterThan(zoomed.origin.dx));

    await tester.tapAt(center, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(center, kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(view(tester).pixelsPerCm, closeTo(initial.pixelsPerCm, 1e-9));
    expect(view(tester).origin, initial.origin);
  });

  FloorPlanMeasure? measureOf(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is FloorPlanPainter,
      ),
    );
    final painter = paint.foregroundPainter;
    return painter is FloorPlanMeasurePainter ? painter.measure : null;
  }

  testWidgets('μέτρηση: κλικ σε σημεία, Enter κλείνει με το σύνολο', (
    tester,
  ) async {
    await pump(tester, measuring: true);
    final center = tester.getCenter(find.byType(FloorPlanMapView));
    final ppc = view(tester).pixelsPerCm;

    await tester.tapAt(center, kind: PointerDeviceKind.mouse);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 600)),
    );
    await tester.tapAt(
      center + Offset(100 * ppc, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 600)),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    final measure = measureOf(tester)!;
    expect(measure.finished, isTrue);
    expect(measure.points, hasLength(2));
    expect(measure.totalLength, closeTo(100, 1));
  });

  testWidgets('χωρίς μέτρηση, τα κλικ δεν μετρούν τίποτα', (tester) async {
    await pump(tester);
    await tester.tapAt(
      tester.getCenter(find.byType(FloorPlanMapView)),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(measureOf(tester), isNull);
  });

  group('Σύμβολα', () {
    const entry = FloorPlanCatalogEntry(
      type: FloorPlanPlacementType.user,
      entityId: 7,
      label: 'Παπαδόπουλος Γιώργος',
      departmentIds: {10},
      phones: ['2345'],
    );
    const placement = FloorPlanPlacement(
      id: 3,
      type: FloorPlanPlacementType.user,
      entityId: 7,
      floorId: 1,
      center: Offset(200, 150),
    );
    final views = buildFloorPlanPlacementViews([placement], {entry.key: entry});
    final opened = <int>[];

    Future<void> pumpWithItems(
      WidgetTester tester, {
      Set<({FloorPlanItemSource source, int id})> focusItems = const {},
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: FloorPlanMapView(
              elements: elements,
              departments: const {},
              rotationDegrees: 0,
              objects: views,
              infoSources: FloorPlanInfoSources(
                objects: const {},
                kinds: const <int, FloorPlanObjectKind>{},
                catalog: {entry.key: entry},
                placements: {placement.id: placement},
                departmentName: (id) => id == 10 ? 'Υλικού' : null,
                roomAt: floorPlanRoomLookup(elements),
              ),
              onOpenCard: (view) =>
                  () => opened.add(view.id),
              focusItems: focusItems,
            ),
          ),
        ),
      ),
    );

    Offset at(WidgetTester tester, Offset world) {
      final finder = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is FloorPlanPainter,
      );
      return tester.getTopLeft(finder) + view(tester).toScreen(world);
    }

    testWidgets('πέρασμα του ποντικιού δείχνει την υπόδειξη', (tester) async {
      await pumpWithItems(tester);
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(at(tester, Offset.zero)));
      await tester.pump();
      expect(find.text('Παπαδόπουλος Γιώργος'), findsNothing);

      await tester.sendEventToBinding(
        mouse.hover(at(tester, const Offset(200, 150))),
      );
      await tester.pump();
      expect(find.text('Παπαδόπουλος Γιώργος'), findsOne);
      expect(find.textContaining('2345'), findsOne);
    });

    testWidgets('κλικ ανοίγει τα στοιχεία, και «Άνοιγμα καρτέλας» ανοίγει τον '
        'υπάλληλο', (tester) async {
      opened.clear();
      await pumpWithItems(tester);

      await tester.tapAt(
        at(tester, const Offset(200, 150)),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(find.text('Άνοιγμα καρτέλας'), findsOne);

      await tester.tap(find.text('Άνοιγμα καρτέλας'));
      expect(opened, [3]);
    });

    testWidgets('ό,τι βρήκε η αναζήτηση: ο χάρτης κεντράρει εκεί, από '
        'απόσταση που φαίνεται το σύμβολο', (tester) async {
      await pumpWithItems(
        tester,
        focusItems: {(source: FloorPlanItemSource.placement, id: placement.id)},
      );
      final finder = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is FloorPlanPainter,
      );
      expect(
        (at(tester, placement.center) - tester.getCenter(finder)).distance,
        lessThan(1),
      );
      expect(floorPlanSymbolsVisible(view(tester).pixelsPerCm), isTrue);
    });
  });
}
