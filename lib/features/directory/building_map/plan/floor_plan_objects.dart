import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import '../../../../core/models/floor_plan_object.dart';
import '../../../../core/models/floor_plan_object_kind.dart';
import '../../../../core/models/floor_plan_placement.dart';
import 'floor_plan_rooms.dart';

/// Καθαρή γεωμετρία των αντικειμένων του χάρτη: πόσο πιάνουν, ποιο είναι
/// κάτω από τον δείκτη, και πώς μετακινούνται, γυρίζουν και αλλάζουν μέγεθος.
/// Όλα σε εκατοστά σχεδίου.

/// Η πλευρά ενός συμβόλου (εκτυπωτής…) στον χάρτη: μεγέθος σχεδίου, όπως
/// τα ονόματα χώρων, ώστε να μεγαλώνει με το ζουμ.
const double kFloorPlanSymbolSizeCm = 60;

/// Το μέγεθος των γραμμάτων της ετικέτας κάτω από ένα αντικείμενο.
const double kFloorPlanObjectLabelSizeCm = 20;

/// Κάτω από αυτό το μέγεθος (σε pixel) τα σύμβολα κρύβονται και μένουν οι
/// χώροι — από μακριά θα ήταν κουκκίδες που μπουκώνουν τον χάρτη.
const double kFloorPlanMinSymbolPx = 12;

/// Φαίνονται τα σύμβολα σε αυτό το ζουμ;
bool floorPlanSymbolsVisible(double pixelsPerCm) =>
    kFloorPlanSymbolSizeCm * pixelsPerCm >= kFloorPlanMinSymbolPx;

/// Όσα φαίνονται σε αυτό το ζουμ: από μακριά μόνο τα έπιπλα. Το ζουμ είναι
/// φίλτρο — ό,τι δεν φαίνεται δεν δίνει υπόδειξη και δεν πιάνεται.
List<FloorPlanObjectView> floorPlanObjectsAtZoom(
  List<FloorPlanObjectView> views,
  double pixelsPerCm,
) {
  if (floorPlanSymbolsVisible(pixelsPerCm)) return views;
  return [
    for (final v in views)
      if (v.isVolume) v,
  ];
}

/// Το μικρότερο έπιπλο που δέχεται η αλλαγή μεγέθους.
const double kFloorPlanMinVolumeCm = 10;

/// Από πού έρχεται ένα σύμβολο του χάρτη: αντικείμενο του χάρτη ή θέση
/// εγγραφής του Καταλόγου. Τα id τους είναι από διαφορετικούς πίνακες.
enum FloorPlanItemSource { object, placement }

/// Ένα αντικείμενο έτοιμο για σχεδίαση: πού, πόσο, με ποιο σύμβολο και
/// ποια ετικέτα.
class FloorPlanObjectView {
  const FloorPlanObjectView({
    required this.id,
    required this.center,
    required this.size,
    required this.rotationDegrees,
    required this.symbol,
    required this.label,
    this.source = FloorPlanItemSource.object,
    this.kindId,
    this.placementType,
  });

  final int id;
  final FloorPlanItemSource source;

  /// Αντικείμενο του χάρτη: το είδος του (για τις στρώσεις).
  final int? kindId;

  /// Θέση του Καταλόγου: υπάλληλος, τηλέφωνο ή εξοπλισμός.
  final FloorPlanPlacementType? placementType;
  final Offset center;
  final Size size;
  final double rotationDegrees;

  /// `null` όταν το είδος γράφτηκε από νεότερη έκδοση ή δεν βρέθηκε.
  final FloorPlanSymbol? symbol;
  final String label;

  /// Σχεδιάζεται ως παραλληλόγραμμο με το πραγματικό του μέγεθος.
  bool get isVolume => symbol?.isVolume ?? false;

  /// Καμπίνα: με κλικ ανοίγει το περιεχόμενό της.
  bool get isCabinet =>
      source == FloorPlanItemSource.object && (symbol?.isCabinet ?? false);

  /// Οι γωνίες του, με την κλίση του: πάνω αριστερά, πάνω δεξιά, κάτω δεξιά,
  /// κάτω αριστερά (ως προς το ίδιο το αντικείμενο).
  List<Offset> get corners => rotatedRectCorners(center, size, rotationDegrees);
}

/// Τα αντικείμενα με το σύμβολο και το μέγεθός τους — **πρώτα τα έπιπλα**,
/// ώστε να ζωγραφίζονται από κάτω και ό,τι κάθεται πάνω τους να πιάνεται
/// πρώτο.
///
/// Ό,τι είναι μέσα σε καμπίνα λείπει: δεν ζωγραφίζεται στον χάρτη, μόνο στη
/// λίστα της καμπίνας. Αυτό είναι το **ένα** σημείο που το κρίνει — σχεδίαση,
/// προβολή, μικρός χάρτης και εξαγωγή περνούν όλα από εδώ.
List<FloorPlanObjectView> buildFloorPlanObjectViews(
  List<FloorPlanObject> objects,
  Map<int, FloorPlanObjectKind> kinds,
) {
  final views = [
    for (final o in objects)
      if (!o.inCabinet)
        FloorPlanObjectView(
          id: o.id,
          center: o.center,
          size: floorPlanObjectSize(o, kinds[o.kindId]?.symbol),
          rotationDegrees: o.rotationDegrees,
          symbol: kinds[o.kindId]?.symbol,
          label: o.name ?? '',
          kindId: o.kindId,
        ),
  ];
  return [
    for (final v in views)
      if (v.isVolume) v,
    for (final v in views)
      if (!v.isVolume) v,
  ];
}

/// Το σύμβολο κάθε εγγραφής του Καταλόγου.
FloorPlanSymbol floorPlanPlacementSymbol(FloorPlanPlacementType type) =>
    switch (type) {
      FloorPlanPlacementType.user => FloorPlanSymbol.person,
      FloorPlanPlacementType.phone => FloorPlanSymbol.phone,
      FloorPlanPlacementType.equipment => FloorPlanSymbol.computer,
    };

/// Οι θέσεις του Καταλόγου έτοιμες για σχεδίαση, με την κλίση τους (π.χ. ο
/// υπολογιστής ακολουθεί το γυρισμένο γραφείο). Θέση χωρίς εγγραφή στο
/// [catalog] (π.χ. μόλις διαγράφηκε) παραλείπεται.
List<FloorPlanObjectView> buildFloorPlanPlacementViews(
  List<FloorPlanPlacement> placements,
  Map<(FloorPlanPlacementType, int), FloorPlanCatalogEntry> catalog,
) => [
  for (final p in placements)
    if (catalog[(p.type, p.entityId)] case final entry?)
      FloorPlanObjectView(
        id: p.id,
        center: p.center,
        size: const Size.square(kFloorPlanSymbolSizeCm),
        rotationDegrees: p.rotationDegrees,
        symbol: floorPlanPlacementSymbol(p.type),
        label: entry.label,
        source: FloorPlanItemSource.placement,
        placementType: p.type,
      ),
];

/// Η θέση γυρισμένη κατά [radians] γύρω από το [pivot]: μετακινείται το
/// σημείο της και γυρίζει και το σύμβολο, όπως τα αντικείμενα.
FloorPlanPlacement rotateFloorPlanPlacement(
  FloorPlanPlacement p,
  Offset pivot,
  double radians,
) {
  final c = math.cos(radians);
  final s = math.sin(radians);
  final d = p.center - pivot;
  var degrees = (p.rotationDegrees + radians * 180 / math.pi) % 360;
  if (degrees > 180) degrees -= 360;
  return p.copyWith(
    center: pivot + Offset(d.dx * c - d.dy * s, d.dx * s + d.dy * c),
    rotationDegrees: degrees,
  );
}

/// Πόσο πιάνει το αντικείμενο: το έπιπλο το δικό του μέγεθος, τα σύμβολα
/// ένα σταθερό τετράγωνο.
Size floorPlanObjectSize(FloorPlanObject object, FloorPlanSymbol? symbol) {
  final size = object.size;
  if (symbol != null && symbol.isVolume && size != null) return size;
  return const Size.square(kFloorPlanSymbolSizeCm);
}

/// Οι γωνίες ενός ορθογωνίου [size] με κέντρο [center] και κλίση
/// [rotationDegrees].
List<Offset> rotatedRectCorners(
  Offset center,
  Size size,
  double rotationDegrees,
) {
  final angle = rotationDegrees * math.pi / 180;
  final c = math.cos(angle);
  final s = math.sin(angle);
  final hw = size.width / 2;
  final hh = size.height / 2;
  Offset at(double x, double y) =>
      center + Offset(x * c - y * s, x * s + y * c);
  return [at(-hw, -hh), at(hw, -hh), at(hw, hh), at(-hw, hh)];
}

/// Το αντικείμενο κάτω από το [p]. Τα σύμβολα πρώτα (το πιο πρόσφατο, που
/// ζωγραφίζεται από πάνω)· μετά το μικρότερο έπιπλο που περιέχει το σημείο —
/// ώστε κλικ στον υπολογιστή πάνω σε γραφείο να πιάνει τον υπολογιστή.
FloorPlanObjectView? hitTestFloorPlanObject(
  Offset p,
  List<FloorPlanObjectView> objects,
) {
  for (final o in objects.reversed) {
    if (!o.isVolume && polygonContains(o.corners, p)) return o;
  }
  FloorPlanObjectView? volume;
  var area = double.infinity;
  for (final o in objects) {
    if (!o.isVolume || !polygonContains(o.corners, p)) continue;
    final a = o.size.width * o.size.height;
    if (a < area) {
      area = a;
      volume = o;
    }
  }
  return volume;
}

/// Τα αντικείμενα που χωρούν **ολόκληρα** μέσα, όπως τα στοιχεία σχεδίου.
Set<int> floorPlanObjectsInside(
  bool Function(Offset worldPoint) contains,
  List<FloorPlanObjectView> objects,
) => {
  for (final o in objects)
    if (o.corners.every(contains)) o.id,
};

/// Το πλαίσιο που περικλείει τα αντικείμενα [ids].
Rect? floorPlanObjectsBounds(Set<int> ids, List<FloorPlanObjectView> objects) {
  Rect? bounds;
  for (final o in objects) {
    if (!ids.contains(o.id)) continue;
    for (final p in o.corners) {
      final r = Rect.fromLTWH(p.dx, p.dy, 0, 0);
      bounds = bounds == null ? r : bounds.expandToInclude(r);
    }
  }
  return bounds;
}

FloorPlanObject translateFloorPlanObject(FloorPlanObject o, Offset delta) =>
    o.copyWith(center: o.center + delta);

/// Το αντικείμενο γυρισμένο κατά [radians] γύρω από το [pivot]: μετακινείται
/// το κέντρο του και γυρίζει και το ίδιο.
FloorPlanObject rotateFloorPlanObject(
  FloorPlanObject o,
  Offset pivot,
  double radians,
) {
  final c = math.cos(radians);
  final s = math.sin(radians);
  final d = o.center - pivot;
  var degrees = (o.rotationDegrees + radians * 180 / math.pi) % 360;
  if (degrees > 180) degrees -= 360;
  return o.copyWith(
    center: pivot + Offset(d.dx * c - d.dy * s, d.dx * s + d.dy * c),
    rotationDegrees: degrees,
  );
}

/// Το έπιπλο με τη γωνία [corner] (όπως στο [FloorPlanObjectView.corners])
/// σερμένη στο [to]· η απέναντι γωνία μένει ακίνητη. Δεν μικραίνει κάτω από
/// [kFloorPlanMinVolumeCm].
FloorPlanObject resizeFloorPlanVolume(
  FloorPlanObject o,
  Size size,
  int corner,
  Offset to,
) {
  final corners = rotatedRectCorners(o.center, size, o.rotationDegrees);
  final fixed = corners[(corner + 2) % 4];
  final angle = o.rotationDegrees * math.pi / 180;
  final c = math.cos(angle);
  final s = math.sin(angle);
  // Η διαγώνιος στο σύστημα του ίδιου του επίπλου.
  final d = to - fixed;
  final local = Offset(d.dx * c + d.dy * s, -d.dx * s + d.dy * c);
  final width = math.max(kFloorPlanMinVolumeCm, local.dx.abs());
  final height = math.max(kFloorPlanMinVolumeCm, local.dy.abs());
  final half = Offset(
    (local.dx < 0 ? -width : width) / 2,
    (local.dy < 0 ? -height : height) / 2,
  );
  final center =
      fixed + Offset(half.dx * c - half.dy * s, half.dx * s + half.dy * c);
  return o.copyWith(center: center, size: Size(width, height));
}

/// Ένα έπιπλο από τη γωνία [a] ως την [b], ευθυγραμμισμένο με το σχέδιο.
({Offset center, Size size}) floorPlanVolumeFromCorners(Offset a, Offset b) {
  final rect = Rect.fromPoints(a, b);
  return (
    center: rect.center,
    size: Size(
      math.max(kFloorPlanMinVolumeCm, rect.width),
      math.max(kFloorPlanMinVolumeCm, rect.height),
    ),
  );
}

/// Το έπιπλο που σχεδιάζεται από τη γωνία [start] προς το [toward]. Με
/// πληκτρολογημένες διαστάσεις [typed] έχει ακριβώς αυτές, προς την πλευρά που
/// δείχνει ο δείκτης.
({Offset center, Size size}) floorPlanVolumeToward(
  Offset start,
  Offset toward,
  Size? typed,
) {
  if (typed == null) return floorPlanVolumeFromCorners(start, toward);
  final sx = toward.dx >= start.dx ? 1.0 : -1.0;
  final sy = toward.dy >= start.dy ? 1.0 : -1.0;
  return floorPlanVolumeFromCorners(
    start,
    start + Offset(sx * typed.width, sy * typed.height),
  );
}

/// Διαστάσεις επίπλου όπως πληκτρολογούνται: «1,60 x 0,80», «1.6*0.8» ή
/// «1,60 0,80» — σε μέτρα. `null` όταν δεν διαβάζονται δύο θετικοί αριθμοί.
Size? parseVolumeSizeMeters(String text) {
  final parts = text
      .trim()
      .split(RegExp(r'\s*[xX×*χΧ]\s*|\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.length != 2) return null;
  final w = double.tryParse(parts[0].replaceAll(',', '.'));
  final h = double.tryParse(parts[1].replaceAll(',', '.'));
  if (w == null || h == null || w <= 0 || h <= 0) return null;
  return Size(w * 100, h * 100);
}
