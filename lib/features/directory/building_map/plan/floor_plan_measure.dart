import 'dart:ui' show Offset;

/// Μια μέτρηση απόστασης πάνω στον χάρτη, όπως στο Google Maps: σημεία με
/// τη σειρά που μπήκαν, και τα μήκη ανάμεσά τους σε εκατοστά.
///
/// **Δεν αποθηκεύεται πουθενά.** Είναι μέτρηση της στιγμής· για μόνιμη
/// ένδειξη μήκους υπάρχει η «Διάσταση».
class FloorPlanMeasure {
  const FloorPlanMeasure({this.points = const [], this.finished = false});

  static const FloorPlanMeasure empty = FloorPlanMeasure();

  final List<Offset> points;

  /// Η διαδρομή έκλεισε (Enter ή διπλό κλικ): το σύνολο μένει ορατό, και το
  /// επόμενο κλικ ξεκινά νέα μέτρηση.
  final bool finished;

  bool get isEmpty => points.isEmpty;

  /// Ένα σημείο ακόμη. Μετά από κλεισμένη διαδρομή ξεκινά νέα.
  FloorPlanMeasure add(Offset point) => finished
      ? FloorPlanMeasure(points: [point])
      : FloorPlanMeasure(points: [...points, point]);

  /// Σβήνει το τελευταίο σημείο· η διαδρομή ξανανοίγει.
  FloorPlanMeasure removeLast() => points.isEmpty
      ? this
      : FloorPlanMeasure(points: points.sublist(0, points.length - 1));

  /// Κλείνει τη διαδρομή. Με λιγότερα από δύο σημεία δεν υπάρχει τι να
  /// μετρηθεί, και η μέτρηση σβήνει.
  FloorPlanMeasure finish() => points.length < 2
      ? empty
      : FloorPlanMeasure(points: points, finished: true);

  /// Το μήκος κάθε κομματιού, με τη σειρά.
  List<double> get segmentLengths => [
    for (var i = 1; i < points.length; i++)
      (points[i] - points[i - 1]).distance,
  ];

  /// Το συνολικό μήκος της διαδρομής.
  double get totalLength =>
      segmentLengths.fold(0, (sum, length) => sum + length);
}
