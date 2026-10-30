// Σε ποιον όροφο ανοίγει ο χάρτης: ο τελευταίος που είδε ο χρήστης, ακόμη κι
// όταν η οθόνη έχει ήδη βάλει «προσωρινά» τον πρώτο όροφο της βάσης.
//
//   flutter test test/features/directory/building_map/controllers/building_map_controller_initial_floor_test.dart

import 'package:call_logger/core/models/building_map_floor.dart';
import 'package:call_logger/features/directory/building_map/controllers/building_map_controller.dart';
import 'package:call_logger/features/directory/building_map/providers/building_map_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

BuildingMapFloor _floor(int id, String label, int sort) => BuildingMapFloor(
  id: id,
  sortOrder: sort,
  label: label,
  imagePath: '',
  rotationDegrees: 0,
);

void main() {
  final floors = [
    _floor(1, '2ος - Καρδιολογική', 0),
    _floor(5, '-1 - Υπόγειο', 4),
  ];

  late ProviderContainer container;
  late BuildingMapController controller;

  setUp(() {
    container = ProviderContainer();
    controller = container.read(buildingMapControllerProvider);
    controller.initialFloorInputs = (_) async =>
        (rememberedId: 5, itFloorIds: <int>{}, newMapFloorIds: <int>{});
    controller.rememberFloor = (_) async {};
    controller.resetSession();
  });

  tearDown(() => container.dispose());

  int? selected() => container.read(buildingMapSelectedSheetIdProvider);

  test('μετά από επανεκκίνηση ανοίγει ο τελευταίος όροφος, όχι ο πρώτος της '
      'βάσης που μπήκε προσωρινά', () async {
    // Περιστατικό 30/10/2026: η οθόνη βάζει πρώτα τον πρώτο όροφο της βάσης,
    // και μετά ρωτά ποιος πρέπει να ανοίξει.
    container.read(buildingMapSelectedSheetIdProvider.notifier).setSheet(1);

    await controller.syncSheetSelection(floors, initial: true);

    expect(selected(), 5);
  });

  test('όροφος που διάλεξε ο χρήστης σε αυτό το άνοιγμα δεν αλλάζει', () async {
    await controller.selectFloorFromList(1, floors);

    await controller.syncSheetSelection(floors, initial: true);

    expect(selected(), 1);
  });
}
