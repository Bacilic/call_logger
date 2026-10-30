import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import '../../../../core/models/floor_plan_element.dart';
import 'floor_plan_geometry.dart';
import 'floor_plan_rooms.dart';

/// Καθαρή γεωμετρία της επιλογής: ποιο στοιχείο είναι κάτω από τον δείκτη,
/// ποια πέφτουν μέσα σε ορθογώνιο, και πώς μετακινούνται, γυρίζουν και
/// αντιγράφονται. Όλα σε εκατοστά σχεδίου.

/// Πλάτος κειμένου ανά εκατοστό μεγέθους, κατά προσέγγιση — αρκεί για να
/// «πιάνεται» το κείμενο με το ποντίκι χωρίς να μετρηθεί κάθε γράμμα.
const double _kTextWidthPerChar = 0.6;

/// Οι γωνίες του πλαισίου ενός κειμένου, με την κλίση του.
List<Offset> textBoxCorners(FloorPlanElement text) {
  final center = text.points.isEmpty ? Offset.zero : text.points.first;
  final size = text.fontSize ?? kFloorPlanDefaultTextSizeCm;
  final content = text.name ?? '';
  final halfW = math.max(1, content.length) * size * _kTextWidthPerChar / 2;
  final halfH = size * 0.7;
  final angle = text.rotationDegrees * math.pi / 180;
  final c = math.cos(angle);
  final s = math.sin(angle);
  Offset rotate(double x, double y) =>
      center + Offset(x * c - y * s, x * s + y * c);
  return [
    rotate(-halfW, -halfH),
    rotate(halfW, -halfH),
    rotate(halfW, halfH),
    rotate(-halfW, halfH),
  ];
}

/// Η γραμμή διάστασης όπως σχεδιάζεται: τα δύο άκρα της, μετατοπισμένα προς
/// το τρίτο σημείο κάθετα στη μέτρηση.
({Offset a, Offset b})? dimensionLine(FloorPlanElement dimension) {
  final p = dimension.points;
  if (p.length < 2) return null;
  final a = p[0];
  final b = p[1];
  if (p.length < 3) return (a: a, b: b);
  final d = b - a;
  final len = d.distance;
  if (len == 0) return (a: a, b: b);
  final normal = Offset(-d.dy / len, d.dx / len);
  final offset = (p[2] - a).dx * normal.dx + (p[2] - a).dy * normal.dy;
  return (a: a + normal * offset, b: b + normal * offset);
}

/// Τα σημεία ενός στοιχείου στο σχέδιο — για το άνοιγμα, τα άκρα του πάνω
/// στον τοίχο του ([walls]: τοίχοι κατά id).
List<Offset> elementWorldPoints(
  FloorPlanElement e,
  Map<int, FloorPlanElement> walls,
) {
  switch (e.kind) {
    case FloorPlanElementKind.opening:
      final wall = walls[e.parentId];
      if (wall == null || wall.points.length < 2 || e.points.length < 2) {
        return const [];
      }
      final a = wall.points[0];
      final b = wall.points[1];
      final len = (b - a).distance;
      if (len == 0) return [a];
      final dir = (b - a) / len;
      return [a + dir * e.points[0].dx, a + dir * e.points[1].dx];
    case FloorPlanElementKind.text:
      return textBoxCorners(e);
    case FloorPlanElementKind.wall:
    case FloorPlanElementKind.room:
    case FloorPlanElementKind.dimension:
      return e.points;
  }
}

/// Το στοιχείο κάτω από το [p], με απόσταση «έλξης» [toleranceCm].
///
/// Σειρά: κείμενο και διάσταση (μικρά, πάνω από όλα) → άνοιγμα → τοίχος →
/// ο μικρότερος χώρος που περιέχει το σημείο.
FloorPlanElement? hitTestElement(
  Offset p,
  List<FloorPlanElement> elements,
  double toleranceCm,
) {
  final walls = {
    for (final e in elements)
      if (e.kind == FloorPlanElementKind.wall) e.id: e,
  };

  for (final e in elements) {
    if (e.kind == FloorPlanElementKind.text &&
        polygonContains(textBoxCorners(e), p)) {
      return e;
    }
    if (e.kind == FloorPlanElementKind.dimension) {
      final line = dimensionLine(e);
      if (line != null &&
          projectOntoSegment(p, line.a, line.b).distance <= toleranceCm) {
        return e;
      }
    }
  }
  for (final e in elements) {
    if (e.kind != FloorPlanElementKind.opening) continue;
    final ends = elementWorldPoints(e, walls);
    if (ends.length == 2 &&
        projectOntoSegment(p, ends[0], ends[1]).distance <= toleranceCm) {
      return e;
    }
  }
  FloorPlanElement? wall;
  var wallDist = toleranceCm;
  for (final e in walls.values) {
    if (e.points.length < 2) continue;
    final d = projectOntoSegment(p, e.points[0], e.points[1]).distance;
    if (d <= wallDist) {
      wallDist = d;
      wall = e;
    }
  }
  if (wall != null) return wall;

  FloorPlanElement? room;
  var roomArea = double.infinity;
  for (final e in elements) {
    if (e.kind != FloorPlanElementKind.room || e.points.length < 3) continue;
    if (!polygonContains(e.points, p)) continue;
    final area = signedPolygonArea(e.points).abs();
    if (area < roomArea) {
      roomArea = area;
      room = e;
    }
  }
  return room;
}

/// Τα στοιχεία που χωρούν **ολόκληρα** μέσα στο [rect] — όπως το ορθογώνιο
/// επιλογής του Sweet Home. Τα ανοίγματα ακολουθούν τον τοίχο τους.
Set<int> elementsInRect(Rect rect, List<FloorPlanElement> elements) =>
    elementsInside(rect.contains, elements);

/// Όπως το [elementsInRect], με οποιονδήποτε έλεγχο «είναι μέσα;» — π.χ. το
/// ορθογώνιο της οθόνης σε περιστραμμένο όροφο.
Set<int> elementsInside(
  bool Function(Offset worldPoint) contains,
  List<FloorPlanElement> elements,
) {
  final walls = {
    for (final e in elements)
      if (e.kind == FloorPlanElementKind.wall) e.id: e,
  };
  final inside = <int>{};
  for (final e in elements) {
    if (e.kind == FloorPlanElementKind.opening) continue;
    final points = elementWorldPoints(e, walls);
    if (points.isNotEmpty && points.every(contains)) inside.add(e.id);
  }
  return inside;
}

/// Το πλαίσιο που περικλείει τα στοιχεία [ids].
Rect? selectionBounds(Set<int> ids, List<FloorPlanElement> elements) {
  final walls = {
    for (final e in elements)
      if (e.kind == FloorPlanElementKind.wall) e.id: e,
  };
  Rect? bounds;
  for (final e in elements) {
    if (!ids.contains(e.id)) continue;
    for (final p in elementWorldPoints(e, walls)) {
      final r = Rect.fromLTWH(p.dx, p.dy, 0, 0);
      bounds = bounds == null ? r : bounds.expandToInclude(r);
    }
  }
  return bounds;
}

/// Το στοιχείο μετακινημένο κατά [delta]. Το άνοιγμα δεν αλλάζει: ζει πάνω
/// στον τοίχο του και ακολουθεί εκείνον.
FloorPlanElement translateElement(FloorPlanElement e, Offset delta) {
  if (e.kind == FloorPlanElementKind.opening) return e;
  return e.copyWith(points: [for (final p in e.points) p + delta]);
}

/// Το στοιχείο γυρισμένο κατά [radians] γύρω από το [center]. Το κείμενο
/// παίρνει και την ίδια κλίση στα γράμματά του.
FloorPlanElement rotateElement(
  FloorPlanElement e,
  Offset center,
  double radians,
) {
  if (e.kind == FloorPlanElementKind.opening) return e;
  final c = math.cos(radians);
  final s = math.sin(radians);
  Offset rotate(Offset p) {
    final d = p - center;
    return center + Offset(d.dx * c - d.dy * s, d.dx * s + d.dy * c);
  }

  // Το όνομα ενός χώρου που έχει μετακινηθεί γυρίζει μαζί του.
  final label = e.labelOffset;
  return e.copyWith(
    points: [for (final p in e.points) rotate(p)],
    rotationDegrees: e.kind == FloorPlanElementKind.text
        ? _normalizeDegrees(e.rotationDegrees + radians * 180 / math.pi)
        : null,
    labelOffset: label == null
        ? null
        : Offset(label.dx * c - label.dy * s, label.dx * s + label.dy * c),
  );
}

/// Η γωνία κουμπωμένη ανά [stepDegrees].
double snapRadians(double radians, {double stepDegrees = 15}) {
  final step = stepDegrees * math.pi / 180;
  return (radians / step).roundToDouble() * step;
}

double _normalizeDegrees(double degrees) {
  var d = degrees % 360;
  if (d > 180) d -= 360;
  return d;
}

/// Τα στοιχεία [ids] μαζί με όσα ανοίγματα ανήκουν σε τοίχους τους — αυτό
/// αντιγράφεται, αποκόπτεται και σβήνεται ως ένα.
List<FloorPlanElement> withOwnedOpenings(
  Set<int> ids,
  List<FloorPlanElement> elements,
) {
  return [
    for (final e in elements)
      if (ids.contains(e.id) ||
          (e.kind == FloorPlanElementKind.opening && ids.contains(e.parentId)))
        e,
  ];
}
