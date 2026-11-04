import '../../../../core/models/floor_plan_object.dart';

/// Καθαρή λογική των ενοποιημένων switches (stack): πολλά μηχανήματα που
/// λειτουργούν σαν ένα, το καθένα με αριθμό μέλους.
///
/// Το stack δεν έχει δικό του πίνακα: τα μέλη του μοιράζονται το ίδιο `stackId`,
/// και το όνομά του είναι το όνομα του μικρότερου μέλους.

/// Το μεγαλύτερο μέλος που δέχεται ένα stack.
const int kFloorPlanMaxStackUnit = 9;

/// Τα μέλη του [stackId], από το μικρότερο στο μεγαλύτερο.
List<FloorPlanObject> floorPlanStackMembers(
  int stackId,
  Iterable<FloorPlanObject> objects,
) => [
  for (final o in objects)
    if (o.stackId == stackId) o,
]..sort((a, b) => (a.stackUnit ?? 1).compareTo(b.stackUnit ?? 1));

/// Το όνομα με το οποίο φαίνονται οι θύρες του [object]: το όνομα του stack
/// του, αν ανήκει σε κάποιο, αλλιώς το δικό του.
String? floorPlanStackName(
  FloorPlanObject object,
  Iterable<FloorPlanObject> objects,
) {
  final stackId = object.stackId;
  if (stackId == null) return object.name;
  final members = floorPlanStackMembers(stackId, objects);
  return members.isEmpty ? object.name : members.first.name;
}

/// Τι αλλάζει όταν το [switchA] ενώνεται με το [switchB]: το A, μαζί με ό,τι
/// τυχόν ήταν ήδη στο δικό του stack, παίρνει τα επόμενα ελεύθερα μέλη.
List<FloorPlanObject> floorPlanStackJoin(
  FloorPlanObject switchA,
  FloorPlanObject switchB,
  Iterable<FloorPlanObject> objects,
) {
  final bStack = switchB.stackId;
  final stackId = bStack ?? switchB.id;
  final existing = bStack == null
      ? [switchB.withStack(stackId: stackId, stackUnit: 1)]
      : floorPlanStackMembers(bStack, objects);
  final aStack = switchA.stackId;
  final moving = aStack == null
      ? [switchA]
      : floorPlanStackMembers(aStack, objects);
  var next = existing
      .map((o) => o.stackUnit ?? 1)
      .fold(0, (a, b) => a > b ? a : b);
  return [
    if (bStack == null) existing.single,
    for (final o in moving) o.withStack(stackId: stackId, stackUnit: ++next),
  ];
}

/// Τι αλλάζει όταν το [object] φεύγει από το stack του. Αν μένει ένα μόνο
/// μέλος, παύει κι αυτό να είναι stack.
List<FloorPlanObject> floorPlanStackLeave(
  FloorPlanObject object,
  Iterable<FloorPlanObject> objects,
) {
  final stackId = object.stackId;
  if (stackId == null) return const [];
  final members = floorPlanStackMembers(stackId, objects);
  return [
    object.withStack(stackId: null, stackUnit: null),
    if (members.length == 2)
      for (final o in members)
        if (o.id != object.id) o.withStack(stackId: null, stackUnit: null),
  ];
}

/// Τι αλλάζει όταν το [object] γίνεται μέλος [unit]. Αν το μέλος αυτό υπάρχει
/// ήδη, οι δύο ανταλλάσσουν αριθμούς.
List<FloorPlanObject> floorPlanStackSetUnit(
  FloorPlanObject object,
  int unit,
  Iterable<FloorPlanObject> objects,
) {
  final stackId = object.stackId;
  if (stackId == null || object.stackUnit == unit) return const [];
  return [
    object.withStack(stackId: stackId, stackUnit: unit),
    for (final o in floorPlanStackMembers(stackId, objects))
      if (o.stackUnit == unit && o.id != object.id)
        o.withStack(stackId: stackId, stackUnit: object.stackUnit),
  ];
}

/// Τα αντικείμενα σε ομάδες για τις προσόψεις: κάθε stack μαζί, με τα μέλη του
/// στη σειρά, στη θέση του πρώτου του. Τα υπόλοιπα μόνα τους.
List<List<FloorPlanObject>> floorPlanStackGroups(
  Iterable<FloorPlanObject> objects,
) {
  final seen = <int>{};
  final groups = <List<FloorPlanObject>>[];
  for (final o in objects) {
    final stackId = o.stackId;
    if (stackId == null) {
      groups.add([o]);
    } else if (seen.add(stackId)) {
      groups.add(floorPlanStackMembers(stackId, objects));
    }
  }
  return groups;
}
