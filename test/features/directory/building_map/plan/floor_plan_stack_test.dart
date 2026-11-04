// Τα ενοποιημένα switches: ένωση, αποχώρηση, αριθμός μέλους, και το κοινό
// όνομα με το οποίο φαίνονται οι θύρες.
//
//   flutter test test/features/directory/building_map/plan/floor_plan_stack_test.dart

import 'package:call_logger/core/models/floor_plan_object.dart';
import 'package:call_logger/features/directory/building_map/plan/floor_plan_stack.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FloorPlanObject sw(int id, {String? name, int? stack, int? unit}) =>
      FloorPlanObject(
        id: id,
        floorId: 1,
        kindId: 1,
        center: Offset.zero,
        name: name,
        stackId: stack,
        stackUnit: unit,
      );

  test('δύο ελεύθερα switches: το δεύτερο γίνεται μέλος 2 του πρώτου', () {
    final a = sw(1);
    final b = sw(2);

    final changes = floorPlanStackJoin(a, b, [a, b]);

    final byId = {for (final o in changes) o.id: o};
    expect(byId[2]!.stackId, 2);
    expect(byId[2]!.stackUnit, 1);
    expect(byId[1]!.stackId, 2);
    expect(byId[1]!.stackUnit, 2);
  });

  test('σε υπάρχον stack παίρνει το επόμενο μέλος', () {
    final m1 = sw(1, stack: 1, unit: 1);
    final m2 = sw(2, stack: 1, unit: 2);
    final c = sw(3);

    final changes = floorPlanStackJoin(c, m2, [m1, m2, c]);

    expect(changes.single.id, 3);
    expect(changes.single.stackUnit, 3);
  });

  test('stack με δύο μέλη: όποιο φύγει, παύει να είναι stack και το άλλο', () {
    final m1 = sw(1, stack: 1, unit: 1);
    final m2 = sw(2, stack: 1, unit: 2);

    final changes = floorPlanStackLeave(m2, [m1, m2]);

    expect(changes, hasLength(2));
    expect(changes.every((o) => o.stackId == null), isTrue);
  });

  test('stack με τρία μέλη: φεύγει μόνο αυτό, οι αριθμοί των άλλων μένουν', () {
    final m1 = sw(1, stack: 1, unit: 1);
    final m2 = sw(2, stack: 1, unit: 2);
    final m3 = sw(3, stack: 1, unit: 3);

    final changes = floorPlanStackLeave(m2, [m1, m2, m3]);

    expect(changes.single.id, 2);
  });

  test('αριθμός μέλους που υπάρχει: οι δύο ανταλλάσσουν', () {
    final m1 = sw(1, stack: 1, unit: 1);
    final m2 = sw(2, stack: 1, unit: 2);

    final changes = floorPlanStackSetUnit(m2, 1, [m1, m2]);

    final byId = {for (final o in changes) o.id: o};
    expect(byId[2]!.stackUnit, 1);
    expect(byId[1]!.stackUnit, 2);
  });

  test('το όνομα του stack είναι το όνομα του μικρότερου μέλους', () {
    final m1 = sw(1, name: 'SW-2', stack: 1, unit: 1);
    final m2 = sw(2, name: 'άλλο', stack: 1, unit: 2);

    expect(floorPlanStackName(m2, [m2, m1]), 'SW-2');
    expect(floorPlanStackName(sw(3, name: 'SW-3'), [m1, m2]), 'SW-3');
  });

  test('στις προσόψεις το stack μένει μαζί, στη θέση του πρώτου του', () {
    final m2 = sw(2, stack: 1, unit: 2);
    final solo = sw(3);
    final m1 = sw(1, stack: 1, unit: 1);

    final groups = floorPlanStackGroups([m2, solo, m1]);

    expect(groups, hasLength(2));
    expect([for (final o in groups.first) o.id], [1, 2]);
    expect(groups.last.single.id, 3);
  });
}
