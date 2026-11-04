import 'package:intl/intl.dart';

import '../../../../core/models/floor_plan_object_kind.dart';
import '../../../../core/models/floor_plan_placement.dart';
import 'floor_plan_layers.dart';

/// Τι βγαίνει σε εικόνα ή σε χαρτί.
enum FloorPlanOutputScope {
  /// Ολόκληρος ο όροφος, χωρίς επισημάνσεις.
  wholeFloor,

  /// Ό,τι φαίνεται εκείνη την ώρα στην οθόνη.
  snapshot,
}

/// Η γραμμή πάνω από τον χάρτη, ώστε ένα χαρτί ή ένα email να λέει τι δείχνει
/// και πότε: «0 - Ισόγειο · 04/11/2026».
String floorPlanOutputCaption(String floorLabel, DateTime date) =>
    '$floorLabel · ${DateFormat('dd/MM/yyyy').format(date)}';

/// Τα ονόματα των κρυμμένων στρώσεων, με τη σειρά του μενού «Στρώσεις»:
/// πρώτα του Καταλόγου, μετά τα είδη αλφαβητικά. Είδος που δεν υπάρχει πια
/// δεν κρύβει τίποτα, οπότε δεν αναφέρεται.
List<String> floorPlanHiddenLayerNames(
  Set<String> hidden,
  Iterable<FloorPlanObjectKind> kinds,
) {
  const catalogNames = {
    FloorPlanPlacementType.user: 'Υπάλληλοι',
    FloorPlanPlacementType.phone: 'Τηλέφωνα',
    FloorPlanPlacementType.equipment: 'Εξοπλισμός Καταλόγου',
  };
  final sortedKinds = [...kinds]..sort((a, b) => a.name.compareTo(b.name));
  return [
    for (final entry in catalogNames.entries)
      if (hidden.contains(floorPlanPlacementLayer(entry.key))) entry.value,
    for (final kind in sortedKinds)
      if (hidden.contains(floorPlanKindLayer(kind.id))) kind.name,
  ];
}
