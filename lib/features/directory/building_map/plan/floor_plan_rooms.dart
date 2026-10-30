import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'floor_plan_geometry.dart';

/// Καθαρή γεωμετρία των **χώρων**: εμβαδόν, «είναι μέσα;», και ο χώρος που
/// περικλείουν οι τοίχοι γύρω από ένα σημείο (το διπλό κλικ του Sweet Home).

/// Εμβαδόν πολυγώνου με πρόσημο (θετικό ή αρνητικό ανάλογα με τη φορά).
double signedPolygonArea(List<Offset> polygon) {
  var sum = 0.0;
  for (var i = 0; i < polygon.length; i++) {
    final a = polygon[i];
    final b = polygon[(i + 1) % polygon.length];
    sum += a.dx * b.dy - b.dx * a.dy;
  }
  return sum / 2;
}

bool polygonContains(List<Offset> polygon, Offset p) {
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final a = polygon[i];
    final b = polygon[j];
    if ((a.dy > p.dy) != (b.dy > p.dy) &&
        p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}

/// Σημείο για την ετικέτα του χώρου: το κέντρο βάρους όταν πέφτει μέσα στον
/// χώρο· αλλιώς (χώρος σε σχήμα Γ) το μέσο της πιο πλατιάς οριζόντιας τομής
/// που περνά από το ύψος του κέντρου.
Offset polygonLabelPoint(List<Offset> polygon) {
  if (polygon.isEmpty) return Offset.zero;
  final area = signedPolygonArea(polygon);
  Offset centroid;
  if (area.abs() < 1e-9) {
    var sx = 0.0, sy = 0.0;
    for (final p in polygon) {
      sx += p.dx;
      sy += p.dy;
    }
    centroid = Offset(sx / polygon.length, sy / polygon.length);
  } else {
    var cx = 0.0, cy = 0.0;
    for (var i = 0; i < polygon.length; i++) {
      final a = polygon[i];
      final b = polygon[(i + 1) % polygon.length];
      final cross = a.dx * b.dy - b.dx * a.dy;
      cx += (a.dx + b.dx) * cross;
      cy += (a.dy + b.dy) * cross;
    }
    centroid = Offset(cx / (6 * area), cy / (6 * area));
  }
  if (polygonContains(polygon, centroid)) return centroid;

  // Τομές της οριζόντιας γραμμής από το κέντρο με τις πλευρές.
  final y = centroid.dy;
  final xs = <double>[];
  for (var i = 0; i < polygon.length; i++) {
    final a = polygon[i];
    final b = polygon[(i + 1) % polygon.length];
    if ((a.dy > y) != (b.dy > y)) {
      xs.add(a.dx + (y - a.dy) * (b.dx - a.dx) / (b.dy - a.dy));
    }
  }
  xs.sort();
  var best = centroid;
  var bestWidth = -1.0;
  for (var i = 0; i + 1 < xs.length; i += 2) {
    final width = xs[i + 1] - xs[i];
    if (width > bestWidth) {
      bestWidth = width;
      best = Offset((xs[i] + xs[i + 1]) / 2, y);
    }
  }
  return best;
}

/// Ο μικρότερος κλειστός χώρος που σχηματίζουν οι [walls] γύρω από το [p]·
/// `null` όταν το σημείο δεν είναι κλεισμένο από τοίχους.
///
/// Τα ανοίγματα (πόρτες) **δεν** μετρούν: η πόρτα δεν κάνει το δωμάτιο
/// ανοιχτό. Τοίχοι που διασταυρώνονται ή ακουμπούν τον έναν στο σώμα του άλλου
/// (σχήμα Τ) σπάνε στο σημείο επαφής, ώστε να σχηματίζουν γωνίες.
List<Offset>? enclosingRoom(
  Offset p,
  List<FloorPlanSegment> walls, {
  double toleranceCm = 1,
  double minAreaCm2 = 100,
}) {
  final graph = _PlanarGraph.build(walls, toleranceCm);
  List<Offset>? best;
  var bestArea = double.infinity;
  for (final face in graph.faces()) {
    final cleaned = _removeSpikes(face, toleranceCm);
    if (cleaned.length < 3) continue;
    final area = signedPolygonArea(cleaned).abs();
    if (area < minAreaCm2 || area >= bestArea) continue;
    if (!polygonContains(cleaned, p)) continue;
    best = cleaned;
    bestArea = area;
  }
  return best;
}

/// Αφαιρεί «αγκάθια» — τοίχους που μπαίνουν στον χώρο και τελειώνουν
/// (Α→Β→Α) — και σημεία πάνω σε ευθεία, ώστε το πολύγωνο να έχει μόνο
/// πραγματικές γωνίες.
List<Offset> _removeSpikes(List<Offset> polygon, double tolerance) {
  final points = List<Offset>.from(polygon);
  var changed = true;
  while (changed && points.length >= 3) {
    changed = false;
    for (var i = 0; i < points.length; i++) {
      final prev = points[(i - 1 + points.length) % points.length];
      final cur = points[i];
      final next = points[(i + 1) % points.length];
      final backtrack = (prev - next).distance <= tolerance;
      final d1 = cur - prev;
      final d2 = next - cur;
      final cross = d1.dx * d2.dy - d1.dy * d2.dx;
      final collinear =
          cross.abs() <= tolerance * math.max(d1.distance, d2.distance) &&
          (d1.dx * d2.dx + d1.dy * d2.dy) > 0;
      if (backtrack) {
        // Το Β και το επαναλαμβανόμενο Α φεύγουν μαζί.
        final nextIndex = (i + 1) % points.length;
        if (nextIndex > i) {
          points
            ..removeAt(nextIndex)
            ..removeAt(i);
        } else {
          points
            ..removeAt(i)
            ..removeAt(nextIndex);
        }
        changed = true;
        break;
      }
      if (collinear || d1.distance <= tolerance) {
        points.removeAt(i);
        changed = true;
        break;
      }
    }
  }
  return points;
}

/// Επίπεδος γράφος από τοίχους: κόμβοι στις άκρες και στις τομές, ακμές τα
/// κομμάτια ανάμεσά τους.
class _PlanarGraph {
  _PlanarGraph(this.vertices, this.adjacency);

  final List<Offset> vertices;

  /// Για κάθε κόμβο, οι γείτονές του.
  final List<List<int>> adjacency;

  static _PlanarGraph build(List<FloorPlanSegment> walls, double tolerance) {
    final vertices = <Offset>[];
    int vertexFor(Offset p) {
      for (var i = 0; i < vertices.length; i++) {
        if ((vertices[i] - p).distance <= tolerance) return i;
      }
      vertices.add(p);
      return vertices.length - 1;
    }

    // Για κάθε τοίχο, οι θέσεις (κατά μήκος) όπου πρέπει να σπάσει.
    final cuts = [
      for (final w in walls) <double>[0, w.length],
    ];
    for (var i = 0; i < walls.length; i++) {
      final a = walls[i];
      for (var j = i + 1; j < walls.length; j++) {
        final b = walls[j];
        final hit = _intersection(a, b, tolerance);
        if (hit == null) continue;
        cuts[i].add(projectOntoSegment(hit, a.a, a.b).along);
        cuts[j].add(projectOntoSegment(hit, b.a, b.b).along);
      }
    }

    final edges = <(int, int)>{};
    for (var i = 0; i < walls.length; i++) {
      final w = walls[i];
      if (w.length <= tolerance) continue;
      final dir = (w.b - w.a) / w.length;
      final along = cuts[i]..sort();
      var prev = vertexFor(w.a);
      for (final t in along.skip(1)) {
        final v = vertexFor(w.a + dir * t);
        if (v != prev) {
          edges.add(prev < v ? (prev, v) : (v, prev));
        }
        prev = v;
      }
    }

    final adjacency = List.generate(vertices.length, (_) => <int>[]);
    for (final (u, v) in edges) {
      adjacency[u].add(v);
      adjacency[v].add(u);
    }
    return _PlanarGraph(vertices, adjacency);
  }

  /// Όλες οι «όψεις» του γράφου: κάθε κατευθυνόμενη ακμή ανήκει σε μία.
  /// Σε κάθε κόμβο η διαδρομή στρίβει όσο πιο πολύ γίνεται προς την ίδια
  /// πλευρά, οπότε κάθε κύκλος περικλείει ένα ελάχιστο κομμάτι του επιπέδου.
  Iterable<List<Offset>> faces() sync* {
    final visited = <(int, int)>{};
    for (var u = 0; u < vertices.length; u++) {
      for (final v in adjacency[u]) {
        if (visited.contains((u, v))) continue;
        final cycle = <Offset>[];
        var from = u;
        var to = v;
        var guard = 0;
        while (!visited.contains((from, to)) && guard++ < 10000) {
          visited.add((from, to));
          cycle.add(vertices[from]);
          final next = _nextAround(from, to);
          from = to;
          to = next;
        }
        yield cycle;
      }
    }
  }

  /// Από την ακμή from→to, η επόμενη στρέφοντας δεξιόστροφα γύρω από το to
  /// ξεκινώντας από την επιστροφή to→from.
  int _nextAround(int from, int to) {
    final center = vertices[to];
    final back = vertices[from] - center;
    final backAngle = math.atan2(back.dy, back.dx);
    var best = from;
    var bestTurn = double.infinity;
    for (final candidate in adjacency[to]) {
      if (candidate == from && adjacency[to].length > 1) continue;
      final d = vertices[candidate] - center;
      var turn = math.atan2(d.dy, d.dx) - backAngle;
      while (turn <= 0) {
        turn += 2 * math.pi;
      }
      if (turn < bestTurn) {
        bestTurn = turn;
        best = candidate;
      }
    }
    return best;
  }
}

/// Το σημείο επαφής δύο τμημάτων — διασταύρωση ή άκρη του ενός πάνω στο
/// άλλο — με ανοχή [tolerance]. Παράλληλα τμήματα δεν δίνουν σημείο.
Offset? _intersection(
  FloorPlanSegment s1,
  FloorPlanSegment s2,
  double tolerance,
) {
  final r = s1.b - s1.a;
  final s = s2.b - s2.a;
  final denom = r.dx * s.dy - r.dy * s.dx;
  if (denom.abs() > 1e-9) {
    final q = s2.a - s1.a;
    final t = (q.dx * s.dy - q.dy * s.dx) / denom;
    final u = (q.dx * r.dy - q.dy * r.dx) / denom;
    final tTol = tolerance / math.max(r.distance, 1e-9);
    final uTol = tolerance / math.max(s.distance, 1e-9);
    if (t >= -tTol && t <= 1 + tTol && u >= -uTol && u <= 1 + uTol) {
      return s1.a + r * t.clamp(0.0, 1.0);
    }
    return null;
  }
  // Παράλληλα: μόνο αν μια άκρη του ενός ακουμπά το άλλο.
  for (final end in [s2.a, s2.b]) {
    if (projectOntoSegment(end, s1.a, s1.b).distance <= tolerance) return end;
  }
  return null;
}
