import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../../../../core/models/floor_plan_element.dart';

/// Καθαρή γεωμετρία του σχεδιασμένου χάρτη — χωρίς Flutter widgets, χωρίς
/// βάση. Όλα σε **εκατοστά πραγματικού χώρου**, εκτός αν λέει αλλιώς.

/// Το πάχος ενός τοίχου που δεν έχει οριστεί δικό του.
const double kFloorPlanWallThicknessCm = kFloorPlanDefaultWallThicknessCm;

/// Ο μαγνήτης γωνίας: οι τοίχοι κουμπώνουν ανά τόσες μοίρες.
const double kFloorPlanAngleStepDegrees = 15;

/// Ο μαγνήτης μήκους: τα μήκη στρογγυλεύουν σε τόσα εκατοστά.
const double kFloorPlanLengthStepCm = 5;

/// Το μικρότερο άνοιγμα που δημιουργείται — κάτω από αυτό ήταν λάθος κλικ.
const double kFloorPlanMinOpeningCm = 20;

/// Πού βρέθηκε η άκρη ενός σημείου που κουμπώνει.
enum FloorPlanSnapKind {
  /// Κανένας μαγνήτης (ή Shift πατημένο).
  none,

  /// Κόλλησε στην άκρη υπάρχοντος τοίχου.
  endpoint,

  /// Κόλλησε στο σώμα υπάρχοντος τοίχου.
  wallBody,

  /// Γωνία ανά 15° και στρογγυλό μήκος από το προηγούμενο σημείο.
  angle,

  /// Κόλλησε ακριβώς στη μέση υπάρχοντος τοίχου.
  midpoint,

  /// Κόλλησε πάνω σε γραμμή-οδηγό: την προέκταση ενός τοίχου ή την κάθετη
  /// στην άκρη του.
  guide,
}

/// Ο μαγνήτης των οδηγών είναι πιο «σφιχτός» από των τοίχων: οι οδηγοί είναι
/// πολλοί και αόρατοι, και με ίδια έλξη ο δείκτης δεν θα έμενε ποτέ ελεύθερος.
const double kFloorPlanGuideToleranceFactor = 0.6;

/// Μια γραμμή-οδηγός: νοητή ευθεία που περνά από την άκρη ενός τοίχου, στην
/// κατεύθυνσή του (προέκταση) ή κάθετα σε αυτόν.
class FloorPlanGuide {
  const FloorPlanGuide(this.origin, this.direction);

  /// Η άκρη του τοίχου από την οποία φεύγει ο οδηγός.
  final Offset origin;

  /// Η κατεύθυνσή του, με μήκος 1.
  final Offset direction;

  /// Πόσο απέχει το [p] από την ευθεία.
  double distanceTo(Offset p) {
    final rel = p - origin;
    return (rel.dx * direction.dy - rel.dy * direction.dx).abs();
  }

  /// Το πλησιέστερο σημείο της ευθείας στο [p].
  Offset project(Offset p) {
    final rel = p - origin;
    return origin + direction * (rel.dx * direction.dx + rel.dy * direction.dy);
  }
}

class FloorPlanSnap {
  const FloorPlanSnap(this.point, this.kind, {this.guides = const []});

  final Offset point;
  final FloorPlanSnapKind kind;

  /// Οι οδηγοί πάνω στους οποίους κούμπωσε το σημείο — για να ζωγραφιστούν
  /// από την άκρη τους ως το σημείο.
  final List<FloorPlanGuide> guides;
}

/// Οι οδηγοί που φεύγουν από τις άκρες των [walls]: για κάθε άκρη, η
/// προέκταση του τοίχου και η κάθετή της. Με [visible] μετρούν μόνο οι άκρες
/// που φαίνονται στην οθόνη· ο τοίχος [exceptWallId] δεν δίνει οδηγούς.
List<FloorPlanGuide> wallEndGuides(
  Iterable<FloorPlanSegment> walls, {
  bool Function(Offset end)? visible,
  int? exceptWallId,
}) {
  final guides = <FloorPlanGuide>[];
  for (final w in walls) {
    if (exceptWallId != null && w.id == exceptWallId) continue;
    final length = w.length;
    if (length == 0) continue;
    final dir = (w.b - w.a) / length;
    final normal = Offset(-dir.dy, dir.dx);
    for (final end in [w.a, w.b]) {
      if (visible != null && !visible(end)) continue;
      guides
        ..add(FloorPlanGuide(end, dir))
        ..add(FloorPlanGuide(end, normal));
    }
  }
  return guides;
}

/// Κάτω από αυτή τη γωνία (ημίτονο ~15°) μια γραμμή θεωρείται σχεδόν
/// παράλληλη με τον οδηγό: η τομή τους θα έπεφτε πολύ μακριά από τον δείκτη.
const double _kGuideMinSine = 0.25;

/// Πού συναντά η ευθεία ([origin], [dir]) τον οδηγό [guide], ως απόσταση από
/// το [origin]· `null` όταν είναι σχεδόν παράλληλες.
double? lineMeetsGuide(Offset origin, Offset dir, FloorPlanGuide guide) {
  final e = guide.direction;
  final cross = dir.dx * e.dy - dir.dy * e.dx;
  if (cross.abs() < _kGuideMinSine) return null;
  final rel = guide.origin - origin;
  return (rel.dx * e.dy - rel.dy * e.dx) / cross;
}

/// Το [raw] κουμπωμένο πάνω στους [guides], ή `null` όταν κανένας δεν είναι
/// αρκετά κοντά.
///
/// - Με [from] (δεύτερο σημείο τοίχου) η γωνία μένει κουμπωμένη: το σημείο
///   πέφτει εκεί όπου η ίσια γραμμή από το [from] συναντά τον οδηγό.
/// - Χωρίς [from] το σημείο πέφτει πάνω στον πλησιέστερο οδηγό· αν είναι κοντά
///   και δεύτερος, στη διασταύρωσή τους — μια «νοητή γωνία».
FloorPlanSnap? snapToGuides({
  required Offset raw,
  required List<FloorPlanGuide> guides,
  required double toleranceCm,
  Offset? from,
}) {
  if (guides.isEmpty) return null;
  if (from != null) {
    final d = raw - from;
    if (d.distance == 0) return null;
    const step = kFloorPlanAngleStepDegrees * math.pi / 180;
    final angle = (math.atan2(d.dy, d.dx) / step).roundToDouble() * step;
    final dir = Offset(math.cos(angle), math.sin(angle));
    final rawAlong = d.dx * dir.dx + d.dy * dir.dy;
    FloorPlanGuide? best;
    double? bestAlong;
    var bestGap = toleranceCm;
    for (final g in guides) {
      final along = lineMeetsGuide(from, dir, g);
      if (along == null || along <= 0) continue;
      final gap = (along - rawAlong).abs();
      if (gap <= bestGap) {
        bestGap = gap;
        best = g;
        bestAlong = along;
      }
    }
    if (best == null || bestAlong == null) return null;
    return FloorPlanSnap(
      from + dir * bestAlong,
      FloorPlanSnapKind.guide,
      guides: [best],
    );
  }

  FloorPlanGuide? first;
  var firstDistance = toleranceCm;
  for (final g in guides) {
    final distance = g.distanceTo(raw);
    if (distance <= firstDistance) {
      firstDistance = distance;
      first = g;
    }
  }
  if (first == null) return null;
  final onFirst = first.project(raw);
  // Δεύτερος οδηγός που διασταυρώνεται με τον πρώτο κοντά στον δείκτη.
  FloorPlanGuide? second;
  Offset? corner;
  var cornerDistance = toleranceCm * 1.5;
  for (final g in guides) {
    if (identical(g, first) || g.distanceTo(raw) > toleranceCm) continue;
    final along = lineMeetsGuide(first.origin, first.direction, g);
    if (along == null) continue;
    final point = first.origin + first.direction * along;
    final distance = (point - raw).distance;
    if (distance <= cornerDistance) {
      cornerDistance = distance;
      second = g;
      corner = point;
    }
  }
  if (second != null && corner != null) {
    return FloorPlanSnap(
      corner,
      FloorPlanSnapKind.guide,
      guides: [first, second],
    );
  }
  return FloorPlanSnap(onFirst, FloorPlanSnapKind.guide, guides: [first]);
}

/// Ένα ευθύγραμμο τμήμα τοίχου, όπως το χρειάζεται η γεωμετρία.
class FloorPlanSegment {
  const FloorPlanSegment(
    this.a,
    this.b, {
    this.id,
    this.thickness = kFloorPlanWallThicknessCm,
  });

  /// Ο τοίχος [wall] ως τμήμα, με το πάχος του.
  FloorPlanSegment.ofWall(FloorPlanElement wall)
    : a = wall.points[0],
      b = wall.points[1],
      id = wall.id,
      thickness = wall.wallThicknessCm;

  final Offset a;
  final Offset b;
  final int? id;

  /// Το πάχος του τοίχου, σε εκατοστά.
  final double thickness;

  /// Πόσο πιο κοντά «πιάνεται» ένας παχύς τοίχος: ό,τι περισσεύει από το
  /// συνηθισμένο πάχος, από κάθε πλευρά.
  double get extraReach => thickness > kFloorPlanWallThicknessCm
      ? (thickness - kFloorPlanWallThicknessCm) / 2
      : 0;

  double get length => (b - a).distance;
}

/// Η προβολή ενός σημείου πάνω σε τμήμα.
class SegmentProjection {
  const SegmentProjection({
    required this.along,
    required this.point,
    required this.distance,
  });

  /// Απόσταση από την αρχή του τμήματος, περιορισμένη στο μήκος του.
  final double along;
  final Offset point;

  /// Απόσταση του αρχικού σημείου από το τμήμα.
  final double distance;
}

SegmentProjection projectOntoSegment(Offset p, Offset a, Offset b) {
  final d = b - a;
  final len2 = d.dx * d.dx + d.dy * d.dy;
  if (len2 == 0) {
    return SegmentProjection(along: 0, point: a, distance: (p - a).distance);
  }
  final t = (((p.dx - a.dx) * d.dx + (p.dy - a.dy) * d.dy) / len2).clamp(
    0.0,
    1.0,
  );
  final point = Offset(a.dx + d.dx * t, a.dy + d.dy * t);
  return SegmentProjection(
    along: t * math.sqrt(len2),
    point: point,
    distance: (p - point).distance,
  );
}

/// Το [to] με τη γωνία από το [from] κουμπωμένη ανά [stepDegrees] και το
/// μήκος στρογγυλεμένο ανά [lengthStepCm]. Οι γωνίες μετρώνται ως προς το
/// σχέδιο, όχι ως προς την οθόνη: σε περιστραμμένο όροφο ο μαγνήτης
/// ευθυγραμμίζει με τους τοίχους, όχι με το παράθυρο.
Offset snapAngleAndLength(
  Offset from,
  Offset to, {
  double stepDegrees = kFloorPlanAngleStepDegrees,
  double lengthStepCm = kFloorPlanLengthStepCm,
}) {
  final d = to - from;
  final length = d.distance;
  if (length == 0) return from;
  final step = stepDegrees * math.pi / 180;
  final angle = (math.atan2(d.dy, d.dx) / step).roundToDouble() * step;
  final rounded = lengthStepCm > 0
      ? math.max(
          lengthStepCm,
          (length / lengthStepCm).roundToDouble() * lengthStepCm,
        )
      : length;
  return from + Offset(math.cos(angle), math.sin(angle)) * rounded;
}

/// Το σημείο όπου πέφτει ένα κλικ σχεδίασης τοίχου.
///
/// Σειρά προτεραιότητας: άκρη υπάρχοντος τοίχου → σώμα υπάρχοντος τοίχου
/// (ή ακριβώς η μέση του) → γραμμή-οδηγός από άκρη τοίχου → γωνία/μήκος από
/// το [from]. Με [magnetOff] (Shift) το σημείο μένει όπως είναι. Η
/// [toleranceCm] είναι η απόσταση «έλξης» — ο καλών τη δίνει από pixel
/// οθόνης, ώστε να μένει ίδια στο μάτι σε κάθε ζουμ.
///
/// Οι οδηγοί σβήνουν με [guides] `false`· με [guideEndVisible] μετρούν μόνο οι
/// άκρες τοίχων που φαίνονται στην οθόνη.
FloorPlanSnap snapWallPoint({
  required Offset raw,
  required Iterable<FloorPlanSegment> walls,
  required double toleranceCm,
  Offset? from,
  bool magnetOff = false,
  bool guides = true,
  bool Function(Offset end)? guideEndVisible,
}) {
  if (magnetOff) return FloorPlanSnap(raw, FloorPlanSnapKind.none);

  Offset? bestEnd;
  var bestEndDist = toleranceCm;
  for (final w in walls) {
    for (final end in [w.a, w.b]) {
      final dist = (end - raw).distance;
      if (dist <= bestEndDist) {
        bestEndDist = dist;
        bestEnd = end;
      }
    }
  }
  if (bestEnd != null) {
    return FloorPlanSnap(bestEnd, FloorPlanSnapKind.endpoint);
  }

  SegmentProjection? bestBody;
  FloorPlanSegment? bestWall;
  for (final w in walls) {
    final proj = projectOntoSegment(raw, w.a, w.b);
    if (proj.distance <= toleranceCm &&
        (bestBody == null || proj.distance < bestBody.distance)) {
      bestBody = proj;
      bestWall = w;
    }
  }
  if (bestBody != null && bestWall != null) {
    // Ο τοίχος που καταλήγει πάνω σε άλλον κρατά τη γωνία του: η άκρη πέφτει
    // εκεί όπου η ίσια γραμμή από το [from] συναντά τον τοίχο. Το σημείο κάτω
    // από τον δείκτη θα τον έβγαζε ελαφρά λοξό.
    final straight = from == null
        ? null
        : _angleRayMeetsSegment(from, raw, bestWall);
    final middle = Offset.lerp(bestWall.a, bestWall.b, 0.5)!;
    if (straight == null) {
      // Κοντά στη μέση του τοίχου, ακριβώς η μέση.
      if ((bestBody.point - middle).distance <= toleranceCm) {
        return FloorPlanSnap(middle, FloorPlanSnapKind.midpoint);
      }
      return FloorPlanSnap(bestBody.point, FloorPlanSnapKind.wallBody);
    }
    // Ο ίσιος τοίχος δεν λοξεύει για να βρει τη μέση: τη δείχνει μόνο όταν
    // πέφτει ήδη πάνω της.
    return FloorPlanSnap(
      straight,
      (straight - middle).distance <= 0.5
          ? FloorPlanSnapKind.midpoint
          : FloorPlanSnapKind.wallBody,
    );
  }

  if (guides) {
    final onGuide = snapToGuides(
      raw: raw,
      guides: wallEndGuides(walls, visible: guideEndVisible),
      toleranceCm: toleranceCm * kFloorPlanGuideToleranceFactor,
      from: from,
    );
    if (onGuide != null) return onGuide;
  }

  if (from != null) {
    return FloorPlanSnap(
      snapAngleAndLength(from, raw),
      FloorPlanSnapKind.angle,
    );
  }
  return FloorPlanSnap(raw, FloorPlanSnapKind.none);
}

/// Η γωνία που σχηματίζει ένας τοίχος με κάτι που συναντά στην άκρη του:
/// άλλον τοίχο ή μια γραμμή-οδηγό.
class FloorPlanAngleMark {
  const FloorPlanAngleMark({
    required this.vertex,
    required this.armA,
    required this.armB,
    required this.degrees,
    this.toGuide = false,
    this.bodyHalfWidthCm = 0,
  });

  /// Το σημείο όπου συναντιούνται.
  final Offset vertex;

  /// Η κατεύθυνση του τοίχου που εξετάζεται, από το [vertex] προς την άλλη
  /// άκρη του, με μήκος 1.
  final Offset armA;

  /// Η κατεύθυνση του άλλου τοίχου (ή του οδηγού) από το [vertex], με μήκος 1.
  final Offset armB;

  /// Η γωνία ανάμεσά τους, από 0 ως 180.
  final double degrees;

  /// Η γωνία είναι προς γραμμή-οδηγό, όχι προς πραγματικό τοίχο.
  final bool toGuide;

  /// Πόσο απλώνεται γύρω από τον [vertex] το σώμα των τοίχων που
  /// συναντιούνται (το μισό του παχύτερου), σε εκατοστά: τόξο και αριθμός
  /// μπαίνουν έξω από αυτό, αλλιώς τα σκεπάζει ο τοίχος.
  final double bodyHalfWidthCm;

  /// Ορθή γωνία — σημειώνεται με τετραγωνάκι αντί για τόξο.
  bool get isRight => (degrees - 90).abs() < _kWholeDegreeSlack;

  /// Πόσο μακριά από τον [vertex], πάνω στη διχοτόμο, βγαίνει κανείς από το
  /// σώμα των τοίχων — στις ίδιες μονάδες με το [bodyHalfWidth] (εκατοστά ή
  /// pixel). Όσο κλειστότερη η γωνία, τόσο πιο μακριά· σε πολύ κλειστή
  /// γωνία σταματά στο τετραπλάσιο, να μη φύγει ο αριθμός από την οθόνη.
  double clearanceAlongBisector(double bodyHalfWidth) {
    final sine = math.sin(degrees * math.pi / 360);
    return sine < 0.25 ? bodyHalfWidth * 4 : bodyHalfWidth / sine;
  }
}

/// Πόσο κοντά σε ακέραια μοίρα μετρά ως «ακριβώς»: τα σημεία αποθηκεύονται
/// στρογγυλεμένα στο χιλιοστό, και σε κοντό τοίχο αυτό αρκεί για ένα δέκατο
/// της μοίρας — που δεν είναι λάθος του χρήστη.
const double _kWholeDegreeSlack = 0.15;

double _degreesBetween(Offset a, Offset b) {
  final dot = (a.dx * b.dx + a.dy * b.dy).clamp(-1.0, 1.0);
  return math.acos(dot) * 180 / math.pi;
}

/// Οι γωνίες που σχηματίζει στο [vertex] ένας τοίχος που φτάνει ως το
/// [otherEnd], με όσους τοίχους συναντά εκεί — το πολύ δύο.
///
/// - Σε **άκρη** άλλου τοίχου: η γωνία ανάμεσα στους δύο τοίχους.
/// - Στο **σώμα** άλλου τοίχου (σχήμα Τ): η μικρότερη από τις δύο γωνίες.
/// - Όταν εκεί δεν υπάρχει τοίχος αλλά το σημείο κάθεται πάνω σε
///   [guides]: η μικρότερη γωνία με τον οδηγό.
///
/// Δύο τοίχοι «συναντιούνται» όταν ακουμπούν όπως φαίνονται: η άκρη του
/// τοίχου (με πάχος [thicknessCm]) απέχει από τη μεσαία γραμμή του άλλου
/// το πολύ όσο τα δύο μισά πάχη μαζί — το σώμα του ενός φτάνει στο σώμα του
/// άλλου. Τοίχοι που σχεδιάστηκαν «στο μάτι» ως την όψη ενός παχιού τοίχου
/// δίνουν έτσι κι αυτοί μοίρες.
///
/// Ο τοίχος [exceptWallId] (ο ίδιος, όταν υπάρχει ήδη) δεν μετρά. Τοίχος
/// ακριβώς πάνω στον άλλον (0°) δεν δίνει γωνία.
List<FloorPlanAngleMark> wallJunctionAngles({
  required Offset vertex,
  required Offset otherEnd,
  required Iterable<FloorPlanSegment> walls,
  int? exceptWallId,
  List<FloorPlanGuide> guides = const [],
  double thicknessCm = kFloorPlanWallThicknessCm,
  double toleranceCm = 0.5,
}) {
  final span = otherEnd - vertex;
  final length = span.distance;
  if (length == 0) return const [];
  final own = span / length;
  final marks = <FloorPlanAngleMark>[];

  void add(Offset arm, {bool toGuide = false, double otherThickness = 0}) {
    final degrees = _degreesBetween(own, arm);
    // Κάτω από μία μοίρα οι τοίχοι τρέχουν πλάι-πλάι (π.χ. διπλός τοίχος
    // σχεδιασμένος με το χέρι), δεν σχηματίζουν γωνία.
    if (degrees < 1) return;
    // Δύο τοίχοι προς την ίδια κατεύθυνση δίνουν την ίδια γωνία: μία φορά
    // αρκεί.
    if (marks.any((m) => m.armB.dx * arm.dx + m.armB.dy * arm.dy > 0.9999)) {
      return;
    }
    marks.add(
      FloorPlanAngleMark(
        vertex: vertex,
        armA: own,
        armB: arm,
        degrees: degrees,
        toGuide: toGuide,
        bodyHalfWidthCm: math.max(thicknessCm, otherThickness) / 2,
      ),
    );
  }

  for (final w in walls) {
    if (exceptWallId != null && w.id == exceptWallId) continue;
    final wallLength = w.length;
    if (wallLength == 0) continue;
    final dir = (w.b - w.a) / wallLength;
    final touch = math.max(toleranceCm, (thicknessCm + w.thickness) / 2);
    if ((w.a - vertex).distance <= touch) {
      add(dir, otherThickness: w.thickness);
    } else if ((w.b - vertex).distance <= touch) {
      add(-dir, otherThickness: w.thickness);
    } else if (projectOntoSegment(vertex, w.a, w.b).distance <= touch) {
      // Στο σώμα: από τις δύο γωνίες, η μικρότερη.
      add(
        own.dx * dir.dx + own.dy * dir.dy >= 0 ? dir : -dir,
        otherThickness: w.thickness,
      );
    }
    if (marks.length == 2) return marks;
  }
  if (marks.isNotEmpty) return marks;

  for (final g in guides) {
    if (g.distanceTo(vertex) > toleranceCm) continue;
    final dir = g.direction;
    add(own.dx * dir.dx + own.dy * dir.dy >= 0 ? dir : -dir, toGuide: true);
    if (marks.length == 2) break;
  }
  return marks;
}

/// Οι τέσσερις γωνίες του τοίχου [a]–[b] όπως ζωγραφίζεται: με πάχος
/// [thicknessCm] και με τετράγωνες απολήξεις, που απλώνουν μισό πάχος πέρα
/// από κάθε άκρη.
List<Offset> wallOutlineCorners(Offset a, Offset b, double thicknessCm) {
  final span = b - a;
  final dir = span.distance == 0 ? const Offset(1, 0) : span / span.distance;
  final along = dir * (thicknessCm / 2);
  final across = Offset(-dir.dy, dir.dx) * (thicknessCm / 2);
  return [
    a - along + across,
    a - along - across,
    b + along - across,
    b + along + across,
  ];
}

/// Οι λαβές μήκους ενός τοίχου [a]–[b]: πάνω στην ευθεία του, [reachCm] πέρα
/// από κάθε άκρη — έξω από το σώμα του, όπου τις βρίσκει το μάτι. Έτσι και
/// μια κολόνα (κοντός, παχύς τοίχος) έχει δύο λαβές που δεν πέφτουν η μία
/// πάνω στην άλλη. Τοίχος χωρίς μήκος παίρνει οριζόντιες λαβές.
List<Offset> wallEndHandlePoints(Offset a, Offset b, double reachCm) {
  final span = b - a;
  final dir = span.distance == 0 ? const Offset(1, 0) : span / span.distance;
  return [a - dir * reachCm, b + dir * reachCm];
}

/// Πού πάει η άκρη του τοίχου όταν η λαβή της σύρεται στο [handle], με την
/// άλλη άκρη σταθερή στο [fixedEnd]: [reachCm] πιο μέσα από τη λαβή, ώστε η
/// άκρη να μην πετάγεται κάτω από τον δείκτη τη στιγμή που πιάνεται.
Offset wallEndFromHandle(Offset handle, Offset fixedEnd, double reachCm) {
  final span = handle - fixedEnd;
  final distance = span.distance;
  if (distance <= reachCm) return fixedEnd;
  return handle - span / distance * reachCm;
}

/// Μοίρες για προβολή: «90°» όταν η γωνία είναι ακέραια, «89,4°» όταν δεν
/// είναι — ώστε ένας σχεδόν ορθός τοίχος να μην περνά για ορθός.
String formatAngleDegrees(double degrees) {
  final rounded = degrees.roundToDouble();
  if ((degrees - rounded).abs() < _kWholeDegreeSlack) {
    return '${rounded.toInt()}°';
  }
  return '${degrees.toStringAsFixed(1).replaceAll('.', ',')}°';
}

/// Πού συναντά το [wall] η γραμμή που φεύγει από το [from] προς το [toward],
/// με τη γωνία της κουμπωμένη ανά [kFloorPlanAngleStepDegrees]· `null` όταν
/// δεν το συναντά (παράλληλη, ή περνά έξω από τις άκρες του).
Offset? _angleRayMeetsSegment(
  Offset from,
  Offset toward,
  FloorPlanSegment wall,
) {
  final d = toward - from;
  if (d.distance == 0) return null;
  const step = kFloorPlanAngleStepDegrees * math.pi / 180;
  final angle = (math.atan2(d.dy, d.dx) / step).roundToDouble() * step;
  final dir = Offset(math.cos(angle), math.sin(angle));
  final s = wall.b - wall.a;
  final cross = dir.dx * s.dy - dir.dy * s.dx;
  if (cross.abs() < 1e-9) return null;
  final rel = wall.a - from;
  final along = (rel.dx * s.dy - rel.dy * s.dx) / cross;
  final onWall = (rel.dx * dir.dy - rel.dy * dir.dx) / cross;
  if (along <= 0 || onWall < 0 || onWall > 1) return null;
  return from + dir * along;
}

/// Το σημείο σε απόσταση [lengthCm] από το [from], στην κατεύθυνση του
/// [toward] — η πληκτρολόγηση μήκους («4,20» και Enter).
Offset pointAtLength(Offset from, Offset toward, double lengthCm) {
  final d = toward - from;
  final dist = d.distance;
  final dir = dist == 0 ? const Offset(1, 0) : d / dist;
  return from + dir * lengthCm;
}

/// Διαβάζει μήκος σε **μέτρα** όπως το γράφει ο χρήστης («4,20», «4.2», «4»)
/// και το επιστρέφει σε εκατοστά· `null` για ό,τι δεν είναι θετικός αριθμός.
double? parseMetersToCm(String text) {
  final normalized = text.trim().replaceAll(',', '.');
  if (normalized.isEmpty) return null;
  final meters = double.tryParse(normalized);
  if (meters == null || meters <= 0 || meters.isNaN || meters.isInfinite) {
    return null;
  }
  return meters * 100;
}

/// Μήκος για προβολή: «4,20 μ.» — ελληνική υποδιαστολή, δύο δεκαδικά.
String formatCmAsMeters(double cm) =>
    '${(cm / 100).toStringAsFixed(2).replaceAll('.', ',')} μ.';

/// Το άνοιγμα που προκύπτει από σύρσιμο από [dragStart] σε [dragEnd] πάνω
/// στον τοίχο [wall]: αποστάσεις από την αρχή του τοίχου, μικρότερη πρώτη.
/// `null` όταν βγαίνει μικρότερο από [kFloorPlanMinOpeningCm].
({double start, double end})? openingFromDrag(
  FloorPlanSegment wall,
  Offset dragStart,
  Offset dragEnd,
) {
  final a = projectOntoSegment(dragStart, wall.a, wall.b).along;
  final b = projectOntoSegment(dragEnd, wall.a, wall.b).along;
  final start = math.min(a, b);
  final end = math.max(a, b);
  if (end - start < kFloorPlanMinOpeningCm) return null;
  return (start: start, end: end);
}

/// Τα κομμάτια του τοίχου που μένουν όταν αφαιρεθούν τα ανοίγματά του.
///
/// Τα ανοίγματα δίνονται ως αποστάσεις από την αρχή του τοίχου· μπορεί να
/// επικαλύπτονται ή να βγαίνουν έξω από τον τοίχο — περιορίζονται και
/// συγχωνεύονται.
List<FloorPlanSegment> wallPiecesWithOpenings(
  FloorPlanSegment wall,
  Iterable<({double start, double end})> openings,
) {
  final length = wall.length;
  if (length == 0) return const [];
  final gaps = [
    for (final o in openings)
      (start: o.start.clamp(0.0, length), end: o.end.clamp(0.0, length)),
  ]..sort((x, y) => x.start.compareTo(y.start));
  final dir = (wall.b - wall.a) / length;
  final pieces = <FloorPlanSegment>[];
  var cursor = 0.0;
  for (final g in gaps) {
    if (g.start > cursor) {
      pieces.add(
        FloorPlanSegment(
          wall.a + dir * cursor,
          wall.a + dir * g.start,
          id: wall.id,
          thickness: wall.thickness,
        ),
      );
    }
    cursor = math.max(cursor, g.end);
  }
  if (cursor < length) {
    pieces.add(
      FloorPlanSegment(
        wall.a + dir * cursor,
        wall.b,
        id: wall.id,
        thickness: wall.thickness,
      ),
    );
  }
  return pieces;
}

/// Ενώνει τμήματα που μοιράζονται άκρη σε συνεχείς γραμμές, ώστε οι γωνίες
/// να σχεδιάζονται «γεμάτες» (miter) και όχι ως δύο ξεχωριστά παραλληλόγραμμα
/// με σκαλοπάτι.
///
/// Κάθε τμήμα χρησιμοποιείται μία φορά. Σε κόμβο με τρία ή περισσότερα τμήματα
/// (σχήμα Τ) η γραμμή συνεχίζει σε ένα από αυτά και τα άλλα ξεκινούν δική τους.
List<List<Offset>> chainSegments(
  List<FloorPlanSegment> segments, {
  double toleranceCm = 0.5,
}) {
  bool same(Offset x, Offset y) => (x - y).distance <= toleranceCm;
  final used = List<bool>.filled(segments.length, false);
  final chains = <List<Offset>>[];

  int? findNext(Offset end) {
    for (var i = 0; i < segments.length; i++) {
      if (used[i]) continue;
      if (same(segments[i].a, end) || same(segments[i].b, end)) return i;
    }
    return null;
  }

  for (var i = 0; i < segments.length; i++) {
    if (used[i]) continue;
    used[i] = true;
    final chain = <Offset>[segments[i].a, segments[i].b];
    // Επέκταση προς τα εμπρός.
    while (true) {
      final next = findNext(chain.last);
      if (next == null) break;
      used[next] = true;
      final s = segments[next];
      chain.add(same(s.a, chain.last) ? s.b : s.a);
    }
    // Και προς τα πίσω.
    while (true) {
      final prev = findNext(chain.first);
      if (prev == null) break;
      used[prev] = true;
      final s = segments[prev];
      chain.insert(0, same(s.a, chain.first) ? s.b : s.a);
    }
    chains.add(chain);
  }
  return chains;
}

/// Ο τοίχος που βρίσκεται πιο κοντά στο [p], εντός [toleranceCm]· `null` αν
/// κανένας.
FloorPlanSegment? nearestWall(
  Offset p,
  Iterable<FloorPlanSegment> walls,
  double toleranceCm,
) {
  FloorPlanSegment? best;
  var bestDist = toleranceCm;
  for (final w in walls) {
    // Ο παχύς τοίχος πιάνεται και από την επιφάνειά του, όχι μόνο από τη
    // μέση του.
    final dist = math.max(
      0.0,
      projectOntoSegment(p, w.a, w.b).distance - w.extraReach,
    );
    if (dist <= bestDist) {
      bestDist = dist;
      best = w;
    }
  }
  return best;
}

/// Το σημείο πάνω στον πλησιέστερο τοίχο, εντός [toleranceCm]· αν δεν υπάρχει
/// τοίχος τόσο κοντά, το ίδιο το [p].
Offset snapToNearestWall(
  Offset p,
  Iterable<FloorPlanSegment> walls,
  double toleranceCm,
) {
  final wall = nearestWall(p, walls, toleranceCm);
  return wall == null ? p : projectOntoSegment(p, wall.a, wall.b).point;
}

/// Η νέα κλίμακα του πατρόν μετά από βαθμονόμηση: μια γραμμή που με την
/// τρέχουσα κλίμακα μετρά [measuredCm] είναι στην πραγματικότητα [realCm].
double calibratedCmPerPixel({
  required double currentCmPerPixel,
  required double measuredCm,
  required double realCm,
}) {
  if (measuredCm <= 0 || realCm <= 0) return currentCmPerPixel;
  return currentCmPerPixel * realCm / measuredCm;
}

/// Το νέο κέντρο του πατρόν όταν η κλίμακά του πολλαπλασιάζεται επί
/// [factor] **γύρω από το [anchor]** — το σημείο της βαθμονόμησης μένει
/// ακίνητο κάτω από τον δείκτη, αντί να «φύγει» η εικόνα.
Offset scaleCenterAbout({
  required Offset center,
  required Offset anchor,
  required double factor,
}) => anchor + (center - anchor) * factor;

/// Το βήμα του πλέγματος για το τρέχον ζουμ: το μικρότερο από τα «στρογγυλά»
/// βήματα που απέχει τουλάχιστον [minPixels] στην οθόνη.
double gridStepCm(double pixelsPerCm, {double minPixels = 14}) {
  const steps = [10.0, 50.0, 100.0, 500.0, 1000.0, 5000.0];
  for (final step in steps) {
    if (step * pixelsPerCm >= minPixels) return step;
  }
  return steps.last;
}
