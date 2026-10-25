import 'dart:math' as math;
import 'dart:ui';

/// Μετασχηματισμός από τοπικό σημείο σε normalized [0,1]² ανάστροφα από περιστροφή κέντρου.
Offset inverseRotateAroundCenter(
  Offset localInImageStack,
  Size box,
  double rotationRad,
) {
  final cx = box.width / 2;
  final cy = box.height / 2;
  final dx = localInImageStack.dx - cx;
  final dy = localInImageStack.dy - cy;
  final c = math.cos(-rotationRad);
  final s = math.sin(-rotationRad);
  return Offset(c * dx - s * dy + cx, s * dx + c * dy + cy);
}

/// Ορθογώνιο σε normalized συντεταγμένες από δύο γωνίες (πολύ μικρά εμβαδά κόβονται στο caller).
Rect normalizedRectFromCorners(Offset a, Offset b) {
  final left = math.min(a.dx, b.dx);
  final top = math.min(a.dy, b.dy);
  final right = math.max(a.dx, b.dx);
  final bottom = math.max(a.dy, b.dy);
  return Rect.fromLTRB(left, top, right, bottom);
}

/// Περιστροφή σημείου γύρω από κέντρο, κατά τη φορά του καμβά.
Offset rotateAroundCenter(Offset point, Offset center, double radians) {
  final dx = point.dx - center.dx;
  final dy = point.dy - center.dy;
  final c = math.cos(radians);
  final s = math.sin(radians);
  return Offset(
    center.dx + (dx * c) - (dy * s),
    center.dy + (dx * s) + (dy * c),
  );
}

/// Σημείο στο περίγραμμα περιστραμμένου ορθογωνίου, στην κατεύθυνση του στόχου.
Offset pointOnRotatedRectBoundaryToward({
  required Rect rect,
  required double rotation,
  required Offset targetPoint,
}) {
  final center = rect.center;
  final targetLocal = rotateAroundCenter(targetPoint, center, -rotation);
  final vx = targetLocal.dx - center.dx;
  final vy = targetLocal.dy - center.dy;
  if (vx == 0 && vy == 0) {
    return rotateAroundCenter(Offset(center.dx, rect.top), center, rotation);
  }
  final halfW = rect.width / 2;
  final halfH = rect.height / 2;
  final sx = vx == 0 ? double.infinity : (halfW / vx.abs());
  final sy = vy == 0 ? double.infinity : (halfH / vy.abs());
  final s = math.min(sx, sy);
  final edgeLocal = Offset(center.dx + (vx * s), center.dy + (vy * s));
  return rotateAroundCenter(edgeLocal, center, rotation);
}
