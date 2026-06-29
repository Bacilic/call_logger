import 'package:call_logger/core/models/building_map_floor.dart';
import 'package:call_logger/core/utils/lamp_floor_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LampFloorResolver', () {
    final floors = [
      BuildingMapFloor(
        id: 7,
        sortOrder: 0,
        label: '4ος όροφος',
        imagePath: 'x.png',
        rotationDegrees: 0,
      ),
      BuildingMapFloor(
        id: 3,
        sortOrder: 1,
        label: 'Ισόγειο',
        imagePath: 'y.png',
        rotationDegrees: 0,
      ),
    ];

    test('ταιριάζει ακριβές κείμενο ετικέτας', () {
      expect(
        LampFloorResolver.resolveFloorId(levelText: '4ος όροφος', floors: floors),
        7,
      );
    });

    test('ταιριάζει σύντομο ιστορικό κείμενο ως prefix ετικέτας', () {
      expect(
        LampFloorResolver.resolveFloorId(levelText: '4', floors: floors),
        7,
      );
    });

    test('επιστρέφει null όταν δεν υπάρχει φύλλο', () {
      expect(
        LampFloorResolver.resolveFloorId(levelText: '9', floors: floors),
        isNull,
      );
    });

    test('κενό κείμενο → null', () {
      expect(
        LampFloorResolver.resolveFloorId(levelText: '  ', floors: floors),
        isNull,
      );
    });
  });
}
