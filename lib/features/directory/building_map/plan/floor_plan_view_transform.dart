import 'dart:math' as math;
import 'dart:ui' show Canvas, Offset, Rect, Size;

import 'package:flutter/foundation.dart';

/// Η αντιστοίχιση ανάμεσα στο σχέδιο (εκατοστά) και την οθόνη (pixel).
///
/// οθόνη = [origin] + περιστροφή([rotationRadians]) · (σχέδιο × [pixelsPerCm])
///
/// Η περιστροφή είναι η **περιστροφή του ορόφου** — ο όροφος γυρίζει ολόκληρος
/// για να φαίνεται με τον βολικό προσανατολισμό. Τα εργαλεία δουλεύουν πάντα
/// σε συντεταγμένες σχεδίου, άρα ο μαγνήτης ευθυγραμμίζει ως προς το σχέδιο.
@immutable
class FloorPlanViewTransform {
  const FloorPlanViewTransform({
    required this.pixelsPerCm,
    required this.rotationRadians,
    required this.origin,
  });

  static const double minPixelsPerCm = 0.005;
  static const double maxPixelsPerCm = 20;

  final double pixelsPerCm;
  final double rotationRadians;

  /// Πού πέφτει στην οθόνη το σημείο (0, 0) του σχεδίου.
  final Offset origin;

  Offset toScreen(Offset world) {
    final c = math.cos(rotationRadians);
    final s = math.sin(rotationRadians);
    final x = world.dx * pixelsPerCm;
    final y = world.dy * pixelsPerCm;
    return origin + Offset(x * c - y * s, x * s + y * c);
  }

  Offset toWorld(Offset screen) {
    final c = math.cos(rotationRadians);
    final s = math.sin(rotationRadians);
    final d = screen - origin;
    final x = d.dx * c + d.dy * s;
    final y = -d.dx * s + d.dy * c;
    return Offset(x / pixelsPerCm, y / pixelsPerCm);
  }

  /// Απόσταση οθόνης σε εκατοστά σχεδίου — για «έλξη» μαγνήτη και κλικ που
  /// μένουν ίδια στο μάτι σε κάθε ζουμ.
  double screenToCm(double pixels) => pixels / pixelsPerCm;

  /// Μετασχηματίζει τον [canvas] ώστε από εκεί και πέρα να σχεδιάζει σε
  /// εκατοστά σχεδίου.
  void applyTo(Canvas canvas) {
    canvas
      ..translate(origin.dx, origin.dy)
      ..rotate(rotationRadians)
      ..scale(pixelsPerCm);
  }

  FloorPlanViewTransform panBy(Offset screenDelta) => FloorPlanViewTransform(
    pixelsPerCm: pixelsPerCm,
    rotationRadians: rotationRadians,
    origin: origin + screenDelta,
  );

  /// Μεγέθυνση κατά [factor] με το σημείο του σχεδίου κάτω από το
  /// [screenFocus] να μένει ακίνητο (εκεί που είναι ο δείκτης).
  FloorPlanViewTransform zoomAt(Offset screenFocus, double factor) {
    final world = toWorld(screenFocus);
    final next = (pixelsPerCm * factor).clamp(minPixelsPerCm, maxPixelsPerCm);
    final scaled = FloorPlanViewTransform(
      pixelsPerCm: next,
      rotationRadians: rotationRadians,
      origin: Offset.zero,
    );
    return FloorPlanViewTransform(
      pixelsPerCm: next,
      rotationRadians: rotationRadians,
      origin: screenFocus - scaled.toScreen(world),
    );
  }

  /// Χωράει το [worldRect] στο [viewport] με περιθώριο [margin] pixel.
  static FloorPlanViewTransform fit({
    required Rect worldRect,
    required Size viewport,
    required double rotationRadians,
    double margin = 40,
  }) {
    final c = math.cos(rotationRadians).abs();
    final s = math.sin(rotationRadians).abs();
    // Το πλαίσιο του περιστραμμένου ορθογωνίου.
    final w = worldRect.width * c + worldRect.height * s;
    final h = worldRect.width * s + worldRect.height * c;
    final availW = math.max(1.0, viewport.width - 2 * margin);
    final availH = math.max(1.0, viewport.height - 2 * margin);
    final scale = (w <= 0 || h <= 0)
        ? 1.0
        : math
              .min(availW / w, availH / h)
              .clamp(minPixelsPerCm, maxPixelsPerCm)
              .toDouble();
    final base = FloorPlanViewTransform(
      pixelsPerCm: scale,
      rotationRadians: rotationRadians,
      origin: Offset.zero,
    );
    final center = base.toScreen(worldRect.center);
    return FloorPlanViewTransform(
      pixelsPerCm: scale,
      rotationRadians: rotationRadians,
      origin: Offset(viewport.width / 2, viewport.height / 2) - center,
    );
  }

  /// Ίδια θέαση με άλλη περιστροφή ορόφου, γύρω από το κέντρο της οθόνης.
  FloorPlanViewTransform withRotation(double radians, Size viewport) {
    final focus = Offset(viewport.width / 2, viewport.height / 2);
    final world = toWorld(focus);
    final rotated = FloorPlanViewTransform(
      pixelsPerCm: pixelsPerCm,
      rotationRadians: radians,
      origin: Offset.zero,
    );
    return FloorPlanViewTransform(
      pixelsPerCm: pixelsPerCm,
      rotationRadians: radians,
      origin: focus - rotated.toScreen(world),
    );
  }
}
