import '../../../../core/models/floor_plan_object_kind.dart';
import '../../../../core/models/floor_plan_port.dart';

/// Καθαρή λογική των θυρών: πώς λέγονται, πώς στοιχίζονται στην πρόσοψη, και
/// τι αλλάζει όταν αλλάζει το πλήθος τους.

/// Το μεγαλύτερο πλήθος θυρών που δέχεται ένα αντικείμενο — περιθώριο για
/// μεγάλα patch panel, χωρίς να επιτρέπει τυπογραφικό λάθος χιλιάδων θυρών.
const int kFloorPlanMaxPorts = 96;

/// Το **αυτόματο όνομα** μιας θύρας. Δεν αποθηκεύεται· συντίθεται κάθε φορά.
///
/// - Patch panel σε καμπίνα: καμπίνα + patch panel + αριθμός, «RC6.F17»
///   (ενότητα 7 του σχεδίου).
/// - Οτιδήποτε άλλο: όνομα + αριθμός θύρας, «SW-2 / 14».
///
/// Ό,τι δεν έχει ακόμη όνομα απλώς παραλείπεται, ώστε η θύρα να έχει πάντα
/// κάτι να δείξει.
String floorPlanPortAutoName({
  required FloorPlanSymbol? symbol,
  required String? objectName,
  required String? cabinetName,
  required int number,
}) {
  final name = objectName?.trim() ?? '';
  final cabinet = cabinetName?.trim() ?? '';
  if (symbol == FloorPlanSymbol.patchPanel) {
    final panel = '$name$number';
    return cabinet.isEmpty ? panel : '$cabinet.$panel';
  }
  return name.isEmpty ? 'Θύρα $number' : '$name / $number';
}

/// Πόσες θύρες χωρούν το πολύ σε μία σειρά της πρόσοψης — όσες έχει ένα
/// τυπικό patch panel, ώστε να φαίνεται ολόκληρο σε μία γραμμή.
const int kFloorPlanFacadeMaxColumns = 24;

/// Οι γραμμές της πρόσοψης, κάθε μία με τους αριθμούς της, για [columns]
/// θύρες ανά σειρά.
///
/// Patch panel: στη σειρά, 1…24 και ξανά από κάτω — όπως είναι τυπωμένα. Τα
/// υπόλοιπα (switch, router, POE): σε ζεύγη, μονές από πάνω και ζυγές από
/// κάτω, όπως στο εγκεκριμένο σκαρίφημα του switch.
List<List<int>> floorPlanFacadeRows(
  FloorPlanSymbol? symbol,
  int count, {
  int columns = kFloorPlanFacadeMaxColumns,
}) {
  if (count <= 0 || columns <= 0) return const [];
  if (symbol == FloorPlanSymbol.patchPanel) {
    return [
      for (var start = 1; start <= count; start += columns)
        [for (var n = start; n <= count && n < start + columns; n++) n],
    ];
  }
  final rows = <List<int>>[];
  for (var start = 1; start <= count; start += 2 * columns) {
    final end = start + 2 * columns - 1 > count
        ? count
        : start + 2 * columns - 1;
    rows.add([for (var n = start; n <= end; n += 2) n]);
    final evens = [for (var n = start + 1; n <= end; n += 2) n];
    if (evens.isNotEmpty) rows.add(evens);
  }
  return rows;
}

/// Πόσες θύρες ανά σειρά χωρούν σε πλάτος [width], με θύρα τουλάχιστον
/// [minBox] pixel — ποτέ πάνω από [kFloorPlanFacadeMaxColumns], ποτέ κάτω
/// από 1. Ό,τι δεν χωρά πάει σε επόμενη σειρά αντί να κρυφτεί.
int floorPlanFacadeColumns(double width, {double minBox = 16, double gap = 2}) {
  final fit = ((width + gap) / (minBox + gap)).floor();
  return fit.clamp(1, kFloorPlanFacadeMaxColumns);
}

/// Τι γίνεται όταν το πλήθος θυρών αλλάζει σε [count]: ποιοι αριθμοί
/// προστίθενται, και ποιες θύρες φεύγουν (οι μεγαλύτεροι αριθμοί). Οι
/// υπόλοιπες μένουν ανέγγιχτες, με το γραμμένο τους όνομα.
({List<int> add, List<FloorPlanPort> remove}) floorPlanPortCountChange(
  List<FloorPlanPort> existing,
  int count,
) {
  final have = {for (final p in existing) p.number};
  return (
    add: [
      for (var n = 1; n <= count; n++)
        if (!have.contains(n)) n,
    ],
    remove: [
      for (final p in existing)
        if (p.number > count) p,
    ],
  );
}
