// Ο όροφος του Καταλόγου και ο χάρτης συμφωνούν πάντα: τι γίνεται όταν ένας
// χώρος παίρνει τμήμα.
//
//   flutter test test/features/directory/building_map/plan/floor_plan_room_department_rule_test.dart

import 'package:call_logger/features/directory/building_map/plan/floor_plan_room_department_rule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RoomDepartmentOutcome resolve({
    int? catalogFloor,
    Set<int> rooms = const {},
  }) => resolveRoomDepartment(
    targetFloorId: 1,
    catalogFloorId: catalogFloor,
    floorsWithRoom: rooms,
  );

  test('τμήμα του ίδιου ορόφου, πρώτος χώρος: δημιουργείται', () {
    expect(resolve(catalogFloor: 1), RoomDepartmentOutcome.create);
  });

  test('ίδιος όροφος με χώρο ήδη εδώ: δεύτερος, με ενημέρωση', () {
    expect(
      resolve(catalogFloor: 1, rooms: {1}),
      RoomDepartmentOutcome.createAlsoElsewhereOnFloor,
    );
  });

  test('τμήμα χωρίς όροφο: παίρνει αυτόν τον όροφο', () {
    expect(resolve(), RoomDepartmentOutcome.createAndAssignFloor);
  });

  test('άλλος όροφος χωρίς χώρο εκεί: ερώτηση μεταφορά ή παραμονή', () {
    expect(resolve(catalogFloor: 3), RoomDepartmentOutcome.askMoveOrStay);
  });

  test('άλλος όροφος με χώρο εκεί: μόνο παραμονή', () {
    expect(
      resolve(catalogFloor: 3, rooms: {3}),
      RoomDepartmentOutcome.stayOnly,
    );
  });
}
