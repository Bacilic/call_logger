// Μετάβαση από αναζήτηση σε τμήμα του χάρτη: πού πηγαίνει και τι μήνυμα δείχνει
// όταν το τμήμα δεν έχει σχεδιαστεί. Τιμές από εκτέλεση του σημερινού κώδικα.
//
//   flutter test test/features/directory/building_map/building_map_jump_fallback_test.dart

import 'package:call_logger/core/models/building_map_floor.dart';
import 'package:call_logger/features/directory/building_map/services/building_map_jump_fallback.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:flutter_test/flutter_test.dart';

DepartmentModel _dept({String? mapFloor, int? floorId, bool placed = true}) =>
    DepartmentModel(
      id: 9,
      name: 'Ακτινολογικό',
      mapFloor: mapFloor,
      floorId: floorId,
      mapX: placed ? 0.1 : null,
      mapY: placed ? 0.2 : null,
      mapWidth: placed ? 0.3 : null,
      mapHeight: placed ? 0.3 : null,
    );

void main() {
  final floors = [
    BuildingMapFloor(
      id: 1,
      sortOrder: 1,
      label: 'Ισόγειο',
      imagePath: '',
      rotationDegrees: 0,
    ),
    BuildingMapFloor(
      id: 2,
      sortOrder: 2,
      label: 'Α',
      floorGroup: 'Α όροφος',
      imagePath: '',
      rotationDegrees: 0,
    ),
  ];

  test('σχεδιασμένο σε υπαρκτό φύλλο: απευθείας μετάβαση, χωρίς μήνυμα', () {
    final o = resolveBuildingMapJumpFallback(
      department: _dept(mapFloor: '2'),
      floors: floors,
    );

    expect(o.isMapped, isTrue);
    expect(o.message, isNull);
  });

  test('μη σχεδιασμένο με όροφο στη φόρμα: ανοίγει εκείνος και το λέει', () {
    final o = resolveBuildingMapJumpFallback(
      department: _dept(placed: false, floorId: 2),
      floors: floors,
    );

    expect(o.isMapped, isFalse);
    expect(o.fallbackFloorId, 2);
    expect(
      o.message,
      'Το τμήμα «Ακτινολογικό» βρίσκεται στον όροφο «Α όροφος · Α», αλλά '
      'δεν έχει σχεδιαστεί ακόμα στον χάρτη.',
    );
  });

  test('ορφανή θέση χωρίς όροφο φόρμας: ανοίγει το φύλλο της θέσης', () {
    final o = resolveBuildingMapJumpFallback(
      department: _dept(mapFloor: '2', placed: false),
      floors: floors,
    );

    expect(o.fallbackFloorId, 2);
    expect(
      o.message,
      'Το τμήμα «Ακτινολογικό» δεν έχει καταχωρημένη θέση στον χάρτη.',
    );
  });

  test('φύλλο και όροφος που δεν υπάρχουν πια: ανοίγει το πρώτο φύλλο', () {
    final o = resolveBuildingMapJumpFallback(
      department: _dept(mapFloor: '7', floorId: 5),
      floors: floors,
    );

    expect(o.isMapped, isFalse);
    expect(o.fallbackFloorId, 1);
  });

  test('χωρίς κανένα φύλλο: καμία μετάβαση', () {
    final o = resolveBuildingMapJumpFallback(
      department: _dept(placed: false),
      floors: const [],
    );

    expect(o.isMapped, isFalse);
    expect(o.fallbackFloorId, isNull);
    expect(o.message, isNull);
  });
}
