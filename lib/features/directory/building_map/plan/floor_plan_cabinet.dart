import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import '../../../../core/models/floor_plan_object.dart';

/// Καθαρή λογική της καμπίνας: πόσα U έχει, τι χωρά πού, και πώς φαίνεται
/// με τα κενά της. Οι θέσεις U μετρούν **από πάνω** (U1 η πρώτη), όπως στο
/// εγκεκριμένο σκαρίφημα.

/// Πόσα U έχει μια νέα καμπίνα ώσπου να αλλάξει (απόφαση 30/10/2026).
const int kFloorPlanDefaultCabinetUnits = 42;

/// Το μεγαλύτερο πλήθος U που δέχεται η καμπίνα. Οι μεγαλύτερες του
/// νοσοκομείου έχουν 120· το όριο αφήνει περιθώριο χωρίς να επιτρέπει
/// τυπογραφικό λάθος χιλιάδων γραμμών.
const int kFloorPlanMaxCabinetUnits = 200;

/// Πόσα U έχει η [cabinet].
int floorPlanCabinetUnits(FloorPlanObject cabinet) =>
    cabinet.rackUnits ?? kFloorPlanDefaultCabinetUnits;

/// Ό,τι είναι μέσα στην καμπίνα [cabinetId], από πάνω προς τα κάτω.
List<FloorPlanObject> floorPlanCabinetContents(
  int cabinetId,
  Iterable<FloorPlanObject> objects,
) {
  final contents = [
    for (final o in objects)
      if (o.cabinetId == cabinetId) o,
  ];
  contents.sort((a, b) {
    final byU = (a.rackU ?? 0).compareTo(b.rackU ?? 0);
    return byU != 0 ? byU : a.id.compareTo(b.id);
  });
  return contents;
}

/// Χωρά αντικείμενο ύψους [height] στη θέση [u] μιας καμπίνας [units] U,
/// χωρίς να πατά κάτι από τα [contents]; Το [exceptId] (αυτό που
/// μετακινείται) δεν μετρά ως εμπόδιο.
bool floorPlanRackFits({
  required int units,
  required List<FloorPlanObject> contents,
  required int u,
  required int height,
  int? exceptId,
}) {
  if (height < 1 || u < 1 || u + height - 1 > units) return false;
  final end = u + height - 1;
  for (final o in contents) {
    final start = o.rackU;
    if (o.id == exceptId || start == null) continue;
    final oEnd = start + o.heightU - 1;
    if (start <= end && u <= oEnd) return false;
  }
  return true;
}

/// Η πρώτη θέση από πάνω όπου χωρά αντικείμενο ύψους [height]· `null` όταν
/// δεν χωρά πουθενά.
int? floorPlanFirstFreeRackU({
  required int units,
  required List<FloorPlanObject> contents,
  int height = 1,
  int? exceptId,
}) {
  for (var u = 1; u + height - 1 <= units; u++) {
    if (floorPlanRackFits(
      units: units,
      contents: contents,
      u: u,
      height: height,
      exceptId: exceptId,
    )) {
      return u;
    }
  }
  return null;
}

/// Όσα από τα [contents] δεν θα χωρούσαν σε καμπίνα [units] U — αυτά
/// εμποδίζουν το μίκρεμά της.
List<FloorPlanObject> floorPlanContentsBeyond(
  int units,
  List<FloorPlanObject> contents,
) => [
  for (final o in contents)
    if ((o.rackU ?? 1) + o.heightU - 1 > units) o,
];

/// Μία γραμμή της πιστής όψης της καμπίνας: ένα αντικείμενο που πιάνει
/// [heightU] θέσεις από το [fromU], ή μια σειρά κενών θέσεων.
class FloorPlanRackRow {
  FloorPlanRackRow.item(FloorPlanObject this.object, this.fromU)
    : heightU = object.heightU;

  const FloorPlanRackRow.empty(this.fromU, this.heightU) : object = null;

  /// `null` για κενές θέσεις.
  final FloorPlanObject? object;
  final int fromU;
  final int heightU;

  int get toU => fromU + heightU - 1;
  bool get isEmpty => object == null;
}

/// Η καμπίνα από πάνω προς τα κάτω, **μαζί με τα κενά U**: κάθε αντικείμενο
/// στη θέση του και κάθε σειρά διαδοχικών κενών ως μία γραμμή.
///
/// Ό,τι πατά πάνω σε άλλο (π.χ. δύο σταθμοί έβαλαν ταυτόχρονα στο ίδιο U) ή
/// βγαίνει έξω από τα [units] δεν χάνεται: μπαίνει αμέσως μετά.
List<FloorPlanRackRow> floorPlanRackRows(
  int units,
  List<FloorPlanObject> contents,
) {
  final placed = [...contents]
    ..sort((a, b) {
      final byU = (a.rackU ?? 1).compareTo(b.rackU ?? 1);
      return byU != 0 ? byU : a.id.compareTo(b.id);
    });
  final rows = <FloorPlanRackRow>[];
  var next = 1;
  for (final o in placed) {
    final start = math.max(o.rackU ?? 1, next);
    if (start > next) rows.add(FloorPlanRackRow.empty(next, start - next));
    rows.add(FloorPlanRackRow.item(o, start));
    next = start + o.heightU;
  }
  if (next <= units) rows.add(FloorPlanRackRow.empty(next, units - next + 1));
  return rows;
}

/// Η θέση U κάτω από το σημείο [dy] (pixel από την κορυφή της όψης), όταν
/// κάθε U έχει ύψος [slotHeight]. Ποτέ έξω από 1…[units].
int floorPlanRackUAt(double dy, double slotHeight, int units) =>
    math.min(math.max((dy / slotHeight).floor(), 0), math.max(0, units - 1)) +
    1;

/// Πού πέφτει στον χάρτη ό,τι βγαίνει από την καμπίνα: δίπλα της, στα δεξιά
/// όπως είναι γυρισμένη, ώστε να φαίνεται και να πιάνεται αμέσως.
Offset floorPlanBesideCabinet(
  Offset center,
  Size size,
  double rotationDegrees, {
  double gapCm = 50,
}) {
  final angle = rotationDegrees * math.pi / 180;
  final d = size.width / 2 + gapCm;
  return center + Offset(d * math.cos(angle), d * math.sin(angle));
}
