import 'package:flutter/material.dart';

import '../floor_plan_geometry.dart';
import '../floor_plan_measure.dart';
import '../floor_plan_view_transform.dart';

const Color _kMeasureColor = Color(0xFFE65100);

/// Ζωγραφίζει τη [measure] πάνω από τον χάρτη, σε pixel οθόνης ώστε να
/// διαβάζεται σε κάθε ζουμ: η διαδρομή, το μήκος κάθε κομματιού, και το
/// σύνολο στο τέλος. Όσο η διαδρομή είναι ανοιχτή, ένα διακεκομμένο κομμάτι
/// ακολουθεί τον δείκτη ([hover]) και το σύνολο τον περιλαμβάνει.
///
/// Κοινό για τη σχεδίαση και την προβολή του χάρτη.
class FloorPlanMeasurePainter extends CustomPainter {
  const FloorPlanMeasurePainter({
    required this.view,
    required this.measure,
    this.hover,
  });

  final FloorPlanViewTransform view;
  final FloorPlanMeasure measure;
  final Offset? hover;

  @override
  void paint(Canvas canvas, Size size) {
    final points = measure.points;
    if (points.isEmpty) return;
    final screen = [for (final p in points) view.toScreen(p)];
    final line = Paint()
      ..color = _kMeasureColor
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    for (var i = 1; i < screen.length; i++) {
      canvas.drawLine(screen[i - 1], screen[i], line);
    }
    final hover = this.hover;
    final live = !measure.finished && hover != null;
    if (live) _dashed(canvas, screen.last, view.toScreen(hover), line);

    final dot = Paint()..color = _kMeasureColor;
    final ring = Paint()..color = Colors.white;
    for (final s in screen) {
      canvas
        ..drawCircle(s, 5, ring)
        ..drawCircle(s, 3.5, dot);
    }

    final lengths = measure.segmentLengths;
    for (var i = 0; i < lengths.length; i++) {
      final mid = (screen[i] + screen[i + 1]) / 2;
      if ((screen[i + 1] - screen[i]).distance < 60) continue;
      _label(canvas, formatCmAsMeters(lengths[i]), mid, small: true);
    }

    var total = measure.totalLength;
    var end = screen.last;
    if (live) {
      total += (hover - points.last).distance;
      end = view.toScreen(hover);
    }
    if (total > 0) {
      _label(
        canvas,
        'Σύνολο: ${formatCmAsMeters(total)}',
        end + const Offset(14, -18),
        small: false,
      );
    }
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    final length = (b - a).distance;
    if (length == 0) return;
    final step = (b - a) / length;
    for (var d = 0.0; d < length; d += 12) {
      final to = d + 7 < length ? d + 7 : length;
      canvas.drawLine(a + step * d, a + step * to, paint);
    }
  }

  void _label(Canvas canvas, String text, Offset at, {required bool small}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: small ? 11 : 13,
          fontWeight: small ? FontWeight.w500 : FontWeight.w600,
          color: small ? _kMeasureColor : Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final box = Rect.fromCenter(
      center: at,
      width: painter.width + 10,
      height: painter.height + 4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(4)),
      Paint()
        ..color = small ? Colors.white.withValues(alpha: 0.9) : _kMeasureColor,
    );
    painter
      ..paint(canvas, box.topLeft + const Offset(5, 2))
      ..dispose();
  }

  @override
  bool shouldRepaint(FloorPlanMeasurePainter old) =>
      old.view != view || old.measure != measure || old.hover != hover;
}

/// Οι οδηγίες της μέτρησης, όπως εμφανίζονται στη γραμμή κατάστασης και
/// στην προβολή.
String floorPlanMeasureHint(FloorPlanMeasure measure) {
  if (measure.isEmpty) {
    return 'Μέτρηση: κλικ στην αρχή. Shift = χωρίς μαγνήτη.';
  }
  if (measure.finished) {
    return 'Σύνολο ${formatCmAsMeters(measure.totalLength)} · κλικ για νέα '
        'μέτρηση · Esc σβήνει';
  }
  return 'Κλικ σε κάθε στροφή · Enter ή διπλό κλικ για τέλος · Backspace '
      'σβήνει το τελευταίο σημείο · Esc ακύρωση';
}
