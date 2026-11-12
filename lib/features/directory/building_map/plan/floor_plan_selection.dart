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
    // Ο παχύς τοίχος πιάνεται και από την επιφάνειά του.
    final d = math.max(
      0.0,
      projectOntoSegment(p, e.points[0], e.points[1]).distance -
          FloorPlanSegment.ofWall(e).extraReach,
    );
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

/// Ο τοίχος μετά το σύρσιμο μιας άκρης του, μαζί με τα ανοίγματά του.
class WallEndResize {
  const WallEndResize({
    required this.wall,
    required this.openings,
    required this.movedEnd,
    required this.snapKind,
    this.guides = const [],
  });

  final FloorPlanElement wall;

  /// Τα ανοίγματα του τοίχου, στη **ίδια θέση του σχεδίου** όπου ήταν.
  final List<FloorPlanElement> openings;

  /// Πού κατέληξε η άκρη που σύρθηκε.
  final Offset movedEnd;

  /// Αν η άκρη κούμπωσε σε άλλον τοίχο.
  final FloorPlanSnapKind snapKind;

  /// Οι γραμμές-οδηγοί πάνω στις οποίες κούμπωσε η άκρη.
  final List<FloorPlanGuide> guides;
}

/// Αλλάζει το **μήκος** του [wall] σέρνοντας την άκρη [end] (0 = αρχή,
/// 1 = τέλος) προς το [to]. Η άλλη άκρη μένει ακίνητη και η κλίση δεν αλλάζει:
/// η άκρη κινείται μόνο πάνω στην ευθεία του τοίχου.
///
/// Με [free] (Ctrl) η άκρη πηγαίνει **όπου δείχνει ο δείκτης** και ο τοίχος
/// αλλάζει και κλίση, με τους μαγνήτες της σχεδίασης: άκρη ή σώμα άλλου
/// τοίχου, γραμμές-οδηγοί, γωνία ανά 15° από τη σταθερή άκρη.
///
/// - Η άκρη κουμπώνει και εκεί όπου η ευθεία του τοίχου συναντά γραμμή-οδηγό
///   από άκρη άλλου τοίχου· με [guideEndVisible] μετρούν μόνο οι άκρες που
///   φαίνονται στην οθόνη.
/// - Με μαγνήτη, η άκρη κουμπώνει εκεί όπου η ευθεία συναντά άλλον τοίχο από
///   τους [others] (εντός [toleranceCm])· αλλιώς το μήκος στρογγυλεύει ανά
///   [kFloorPlanLengthStepCm]. Με [magnetOff] μένει όπου δείχνει ο δείκτης.
/// - Ο τοίχος **δεν κονταίνει μέσα σε άνοιγμά του**: σταματά στην άκρη της
///   πόρτας.
/// - Τα ανοίγματα μετρώνται από την αρχή του τοίχου· όταν σύρεται η αρχή,
///   οι αποστάσεις τους διορθώνονται ώστε κάθε πόρτα να μείνει όπου ήταν.
///
/// `null` όταν το [wall] δεν είναι τοίχος με μήκος.
WallEndResize? resizeWallEnd({
  required FloorPlanElement wall,
  required int end,
  required Offset to,
  required Iterable<FloorPlanElement> openings,
  required Iterable<FloorPlanSegment> others,
  required double toleranceCm,
  bool magnetOff = false,
  bool free = false,
  bool Function(Offset end)? guideEndVisible,
}) {
  if (wall.kind != FloorPlanElementKind.wall || wall.points.length < 2) {
    return null;
  }
  final a = wall.points[0];
  final b = wall.points[1];
  final oldLength = (b - a).distance;
  if (oldLength == 0) return null;
  final movesStart = end == 0;
  final fixed = movesStart ? b : a;
  final dir = (movesStart ? a - b : b - a) / oldLength;

  // Ως πού φτάνει το πιο μακρινό άνοιγμα, μετρημένο από τη σταθερή άκρη.
  var minLength = kFloorPlanLengthStepCm;
  final own = [
    for (final o in openings)
      if (o.kind == FloorPlanElementKind.opening &&
          o.parentId == wall.id &&
          o.points.length >= 2)
        o,
  ];
  for (final o in own) {
    final start = math.min(o.points[0].dx, o.points[1].dx).clamp(0, oldLength);
    final finish = math.max(o.points[0].dx, o.points[1].dx).clamp(0, oldLength);
    final reach = movesStart ? oldLength - start : finish;
    if (reach > minLength) minLength = reach.toDouble();
  }

  final otherWalls = [
    for (final other in others)
      if (other.id == null || other.id != wall.id) other,
  ];

  WallEndResize result(
    Offset moved,
    FloorPlanSnapKind kind,
    List<FloorPlanGuide> guides,
  ) {
    // Οι πόρτες κρατούν την απόστασή τους από τη σταθερή άκρη.
    final shift = movesStart ? oldLength - (moved - fixed).distance : 0.0;
    return WallEndResize(
      wall: wall.copyWith(points: movesStart ? [moved, b] : [a, moved]),
      openings: [
        for (final o in own)
          shift == 0
              ? o
              : o.copyWith(
                  points: [
                    for (final p in o.points) Offset(p.dx - shift, p.dy),
                  ],
                ),
      ],
      movedEnd: moved,
      snapKind: kind,
      guides: guides,
    );
  }

  if (free) {
    final snap = snapWallPoint(
      raw: to,
      walls: otherWalls,
      toleranceCm: toleranceCm,
      from: fixed,
      magnetOff: magnetOff,
      guideEndVisible: guideEndVisible,
    );
    final span = snap.point - fixed;
    if (span.distance >= minLength) {
      return result(snap.point, snap.kind, snap.guides);
    }
    // Πολύ κοντός για τις πόρτες του: κρατά την κατεύθυνση του δείκτη και
    // το μικρότερο μήκος που τις χωρά.
    final toward = span.distance == 0 ? dir : span / span.distance;
    return result(fixed + toward * minLength, FloorPlanSnapKind.none, const []);
  }

  final raw = (to.dx - fixed.dx) * dir.dx + (to.dy - fixed.dy) * dir.dy;
  var length = raw;
  var kind = FloorPlanSnapKind.none;
  var usedGuides = const <FloorPlanGuide>[];
  if (!magnetOff) {
    double? best;
    var bestDistance = toleranceCm;
    void consider(double along) {
      if (along < minLength) return;
      final distance = (along - raw).abs();
      if (distance <= bestDistance) {
        bestDistance = distance;
        best = along;
      }
    }

    for (final other in otherWalls) {
      final hit = _lineMeetsSegment(fixed, dir, other);
      if (hit != null) consider(hit);
    }
    // Γραμμές-οδηγοί από τις άκρες των άλλων τοίχων, όταν δεν υπάρχει
    // τοίχος να σταματήσει την άκρη.
    FloorPlanGuide? guide;
    double? onGuide;
    if (best == null) {
      var gap = toleranceCm * kFloorPlanGuideToleranceFactor;
      for (final g in wallEndGuides(otherWalls, visible: guideEndVisible)) {
        final along = lineMeetsGuide(fixed, dir, g);
        if (along == null || along < minLength) continue;
        if ((along - raw).abs() <= gap) {
          gap = (along - raw).abs();
          guide = g;
          onGuide = along;
        }
      }
    }
    if (best != null) {
      length = best!;
      kind = FloorPlanSnapKind.wallBody;
    } else if (guide != null && onGuide != null) {
      length = onGuide;
      kind = FloorPlanSnapKind.guide;
      usedGuides = [guide];
    } else {
      length =
          (raw / kFloorPlanLengthStepCm).roundToDouble() *
          kFloorPlanLengthStepCm;
      kind = FloorPlanSnapKind.angle;
    }
  }
  if (length < minLength) {
    length = minLength;
    kind = FloorPlanSnapKind.none;
    usedGuides = const [];
  }

  return result(fixed + dir * length, kind, usedGuides);
}

/// Σε ποια απόσταση από το [origin], προς το [dir], η ευθεία συναντά το
/// [segment]· `null` όταν δεν το συναντά μπροστά της. Παράλληλο τμήμα πάνω
/// στην ίδια ευθεία δίνει την πλησιέστερη άκρη του.
double? _lineMeetsSegment(Offset origin, Offset dir, FloorPlanSegment segment) {
  const slackCm = 0.5;
  final s = segment.b - segment.a;
  final cross = dir.dx * s.dy - dir.dy * s.dx;
  final rel = segment.a - origin;
  if (cross.abs() < 1e-9) {
    // Παράλληλα: μετρά μόνο όταν είναι πάνω στην ίδια ευθεία.
    final off = (rel.dx * dir.dy - rel.dy * dir.dx).abs();
    if (off > slackCm) return null;
    double? nearest;
    for (final p in [segment.a, segment.b]) {
      final along = (p.dx - origin.dx) * dir.dx + (p.dy - origin.dy) * dir.dy;
      if (along > 0 && (nearest == null || along < nearest)) nearest = along;
    }
    return nearest;
  }
  final along = (rel.dx * s.dy - rel.dy * s.dx) / cross;
  final onSegment = (rel.dx * dir.dy - rel.dy * dir.dx) / cross;
  final length = segment.length;
  if (length == 0 || along <= 0) return null;
  final slack = slackCm / length;
  if (onSegment < -slack || onSegment > 1 + slack) return null;
  return along;
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

/// Πού καταλήγει μια μετακίνηση τοίχων: η μετατόπιση μετά το κούμπωμα, και
/// σε ποιο σημείο (και πάνω σε ποιους οδηγούς) κούμπωσε — `null` όταν έμεινε
/// ελεύθερη.
class WallMoveSnap {
  const WallMoveSnap(this.delta, [this.snap]);

  final Offset delta;
  final FloorPlanSnap? snap;
}

/// Κουμπώνει τη μετατόπιση [delta] τοίχων των οποίων οι άκρες είναι τώρα στα
/// [movingEnds], με τους ίδιους μαγνήτες και οδηγούς της σχεδίασης: άκρη ή
/// σώμα άλλου τοίχου πρώτα, μετά οι γραμμές-οδηγοί από τις άκρες των
/// [others]. Από όλες τις άκρες που κουμπώνουν κερδίζει το ισχυρότερο
/// κούμπωμα (άκρη, σώμα, οδηγός) και, σε ισοπαλία, η μικρότερη διόρθωση· η
/// υπόλοιπη επιλογή ακολουθεί. Οι [others] είναι μόνο
/// οι τοίχοι που **δεν** μετακινούνται — αλλιώς ο τοίχος θα κούμπωνε στον
/// εαυτό του.
WallMoveSnap snapWallMove({
  required Iterable<Offset> movingEnds,
  required Offset delta,
  required List<FloorPlanSegment> others,
  required double toleranceCm,
  bool Function(Offset end)? guideEndVisible,
}) {
  // Άκρη σε άκρη κερδίζει το σώμα, και το σώμα τον οδηγό: μια άκρη που
  // γλιστρά πάνω σε κάθετο τοίχο «κουμπώνει» συνέχεια με μηδενική διόρθωση,
  // και δεν πρέπει να εμποδίζει την άλλη άκρη να βρει γωνία.
  int rank(FloorPlanSnapKind kind) => switch (kind) {
    FloorPlanSnapKind.endpoint => 0,
    FloorPlanSnapKind.guide => 2,
    _ => 1,
  };
  FloorPlanSnap? best;
  Offset? bestFix;
  for (final end in movingEnds) {
    final raw = end + delta;
    final snap = snapWallPoint(
      raw: raw,
      walls: others,
      toleranceCm: toleranceCm,
      guides: guideEndVisible != null,
      guideEndVisible: guideEndVisible,
    );
    if (snap.kind == FloorPlanSnapKind.none) continue;
    final fix = snap.point - raw;
    if (best == null ||
        rank(snap.kind) < rank(best.kind) ||
        (rank(snap.kind) == rank(best.kind) &&
            fix.distance < bestFix!.distance)) {
      best = snap;
      bestFix = fix;
    }
  }
  if (best == null) return WallMoveSnap(delta);
  return WallMoveSnap(delta + bestFix!, best);
}
