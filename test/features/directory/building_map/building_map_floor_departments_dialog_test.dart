// «Τμήματα ορόφου»: σε όροφο του νέου χάρτη η λίστα δείχνει όσα τμήματα έχουν
// χώρο εκεί — όχι τα παλιά κουτάκια — και κρύβει ό,τι αφορά μόνο τον παλιό
// χάρτη (απόκρυψη, αφαίρεση).
//
//   flutter test test/features/directory/building_map/building_map_floor_departments_dialog_test.dart

import 'package:call_logger/core/models/floor_plan_element.dart';
import 'package:call_logger/features/directory/building_map/plan/providers/floor_plan_providers.dart';
import 'package:call_logger/features/directory/building_map/providers/building_map_providers.dart';
import 'package:call_logger/features/directory/building_map/widgets/building_map_floor_departments_dialog.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:call_logger/features/directory/providers/department_directory_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const int _kFloor = 1;

final _drawn = DepartmentModel(id: 10, name: 'Ακτινολογικό', floorId: _kFloor);

/// Έχει ακόμη κουτάκι στον παλιό χάρτη του ορόφου, αλλά όχι χώρο στον νέο.
final _oldBoxOnly = DepartmentModel(
  id: 11,
  name: 'Ορθοπαιδική',
  floorId: _kFloor,
  mapFloor: '$_kFloor',
  mapX: 0.1,
  mapY: 0.1,
  mapWidth: 0.2,
  mapHeight: 0.2,
);

Future<void> _pump(WidgetTester tester, {required bool newMap}) async {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activeFloorPlanIdsProvider.overrideWith(
          (ref) async => newMap ? {_kFloor} : <int>{},
        ),
        floorPlanElementsProvider.overrideWith(
          (ref, floorId) async => const [
            FloorPlanElement(
              id: 1,
              floorId: _kFloor,
              kind: FloorPlanElementKind.room,
              points: [Offset(0, 0), Offset(400, 0), Offset(400, 300)],
              departmentId: 10,
            ),
          ],
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: BuildingMapFloorDepartmentsButton(
            mode: BuildingMapFloorDepartmentsDialogMode.edit,
            floorTitle: 'Ισόγειο',
          ),
        ),
      ),
    ),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(MaterialApp)),
  );
  container.read(departmentDirectoryProvider.notifier).state =
      DepartmentDirectoryState(allDepartments: [_drawn, _oldBoxOnly]);
  container.read(buildingMapSelectedSheetIdProvider.notifier).setSheet(_kFloor);
  await tester.pumpAndSettle();
  await tester.tap(find.byType(IconButton));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('νέος χάρτης: μόνο τα τμήματα με χώρο, χωρίς απόκρυψη και '
      'αφαίρεση', (tester) async {
    await _pump(tester, newMap: true);

    expect(find.text('Ακτινολογικό'), findsOneWidget);
    expect(find.text('Ορθοπαιδική'), findsNothing);
    expect(find.text('1 τμήματα με χώρο στον νέο χάρτη'), findsOneWidget);
    expect(find.byTooltip('Απόκρυψη από τον χάρτη'), findsNothing);
    expect(find.textContaining('Αφαίρεση'), findsNothing);
  });

  testWidgets('παλιός χάρτης: όπως πάντα, τα κουτάκια του ορόφου', (
    tester,
  ) async {
    await _pump(tester, newMap: false);
    // Η παλιά γραμμή εργαλείων (επιλογή όλων, απόκρυψη, «Αφαίρεση από χάρτη»)
    // δεν χωρά με τη φαρδιά γραμματοσειρά των τεστ — μόνο εδώ, όχι στην
    // εφαρμογή. Ανεχόμαστε **μόνο** αυτή την υπερχείλιση.
    final overflow = tester.takeException();
    expect(overflow?.toString() ?? 'overflowed', contains('overflowed'));

    expect(find.text('Ορθοπαιδική'), findsOneWidget);
    expect(find.text('Ακτινολογικό'), findsNothing);
    expect(find.byTooltip('Απόκρυψη από τον χάρτη'), findsOneWidget);
  });
}
