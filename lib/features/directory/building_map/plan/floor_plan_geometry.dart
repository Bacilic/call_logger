import 'dart:math' as math;
import 'dart:ui' show Offset;

/// Καθαρή γεωμετρία του σχεδιασμένου χάρτη — χωρίς Flutter widgets, χωρίς
/// βάση. Όλα σε **εκατοστά πραγματικού χώρου**, εκτός αν λέει αλλιώς.

/// Το πάχος με το οποίο σχεδιάζεται κάθε τοίχος (απόφαση: σταθερό πάχος).
const double kFloorPlanWallThicknessCm = 15;

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
}

class FloorPlanSnap {
  const FloorPlanSnap(this.point, this.kind);

  final Offset point;
  final FloorPlanSnapKind kind;
}

/// Ένα ευθύγραμμο τμήμα τοίχου, όπως το χρειάζεται η γεωμετρία.
class FloorPlanSegment {
  const FloorPlanSegment(this.a, this.b, {this.id});

  final Offset a;
  final Offset b;
  final int? id;

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
/// Σειρά προτεραιότητας: άκρη υπάρχοντος τοίχου → σώμα υπάρχοντος τοίχου →
/// γωνία/μήκος από το [from]. Με [magnetOff] (Shift) το σημείο μένει όπως
/// είναι. Η [toleranceCm] είναι η απόσταση «έλξης» — ο καλών τη δίνει από
/// pixel οθόνης, ώστε να μένει ίδια στο μάτι σε κάθε ζουμ.
FloorPlanSnap snapWallPoint({
  required Offset raw,
  required Iterable<FloorPlanSegment> walls,
  required double toleranceCm,
  Offset? from,
  bool magnetOff = false,
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
  for (final w in walls) {
    final proj = projectOntoSegment(raw, w.a, w.b);
    if (proj.distance <= toleranceCm &&
        (bestBody == null || proj.distance < bestBody.distance)) {
      bestBody = proj;
    }
  }
  if (bestBody != null) {
    return FloorPlanSnap(bestBody.point, FloorPlanSnapKind.wallBody);
  }

  if (from != null) {
    return FloorPlanSnap(
      snapAngleAndLength(from, raw),
      FloorPlanSnapKind.angle,
    );
  }
  return FloorPlanSnap(raw, FloorPlanSnapKind.none);
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
        ),
      );
    }
    cursor = math.max(cursor, g.end);
  }
  if (cursor < length) {
    pieces.add(FloorPlanSegment(wall.a + dir * cursor, wall.b, id: wall.id));
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
    final dist = projectOntoSegment(p, w.a, w.b).distance;
    if (dist <= bestDist) {
      bestDist = dist;
      best = w;
    }
  }
  return best;
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
