import 'package:flutter/material.dart';

import '../../../../../core/models/floor_plan_object_kind.dart';

/// Ζωγραφίζει ένα από τα έτοιμα σύμβολα του χάρτη μέσα στο [rect].
///
/// Όλα φαίνονται **από μπροστά** (αποφάσεις 29/10 και 30/10/2026), εκτός από
/// το έπιπλο, που είναι παραλληλόγραμμο από πάνω. Τα σύμβολα του δικτύου
/// ακολουθούν τα εγκεκριμένα σκαριφήματα της Φάσης 3. Τα σχήματα είναι σχεδιασμένα σε ένα
/// τετράγωνο 100×100 και κλιμακώνονται στο [rect]· ένα [symbol] `null` (από
/// νεότερη έκδοση) γίνεται ουδέτερο τετράγωνο με ερωτηματικό αντί να χαθεί.
void paintFloorPlanSymbol(Canvas canvas, FloorPlanSymbol? symbol, Rect rect) {
  final side = rect.shortestSide;
  canvas.save();
  canvas.translate(rect.center.dx - side / 2, rect.center.dy - side / 2);
  canvas.scale(side / 100);
  switch (symbol) {
    case FloorPlanSymbol.person:
      _person(canvas);
    case FloorPlanSymbol.phone:
      _phone(canvas);
    case FloorPlanSymbol.computer:
      _computer(canvas);
    case FloorPlanSymbol.printer:
      _printer(canvas);
    case FloorPlanSymbol.furniture:
      _furniture(canvas);
    case FloorPlanSymbol.cabinet:
      _cabinet(canvas);
    case FloorPlanSymbol.patchPanel:
      _patchPanel(canvas);
    case FloorPlanSymbol.networkSwitch:
      _switch(canvas);
    case FloorPlanSymbol.outlet:
      _outlet(canvas);
    case FloorPlanSymbol.router:
      _router(canvas);
    case FloorPlanSymbol.poe:
      _poe(canvas);
    case FloorPlanSymbol.ups:
      _ups(canvas);
    case null:
      _unknown(canvas);
  }
  canvas.restore();
}

/// Τα χρώματα (γέμισμα, περίγραμμα) του συμβόλου — για ό,τι το δείχνει χωρίς
/// να το ζωγραφίζει, όπως οι γραμμές της όψης της καμπίνας.
({Color fill, Color line}) floorPlanSymbolColors(FloorPlanSymbol? symbol) =>
    switch (symbol) {
      FloorPlanSymbol.person ||
      FloorPlanSymbol.patchPanel ||
      FloorPlanSymbol.poe => (fill: _tealFill, line: _tealLine),
      FloorPlanSymbol.computer ||
      FloorPlanSymbol.networkSwitch => (fill: _purpleFill, line: _purpleLine),
      FloorPlanSymbol.furniture => (fill: _amberFill, line: _amberLine),
      FloorPlanSymbol.phone => (fill: _coralFill, line: _coralLine),
      _ => (fill: _grayFill, line: _grayLine),
    };

/// Ένα σύμβολο ως εικονίδιο σε λίστα ή κουμπί.
class FloorPlanSymbolIcon extends StatelessWidget {
  const FloorPlanSymbolIcon(this.symbol, {super.key, this.size = 32});

  final FloorPlanSymbol? symbol;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _SymbolPainter(symbol)),
    );
  }
}

class _SymbolPainter extends CustomPainter {
  const _SymbolPainter(this.symbol);

  final FloorPlanSymbol? symbol;

  @override
  void paint(Canvas canvas, Size size) {
    paintFloorPlanSymbol(canvas, symbol, Offset.zero & size);
  }

  @override
  bool shouldRepaint(_SymbolPainter old) => old.symbol != symbol;
}

// ── Παλέτα ──────────────────────────────────────────────────────────────

const _ink = Color(0xFF444441);
const _tealFill = Color(0xFF9FE1CB);
const _tealLine = Color(0xFF0F6E56);
const _coralFill = Color(0xFFF5C4B3);
const _coralLine = Color(0xFF993C1D);
const _grayFill = Color(0xFFD3D1C7);
const _grayLine = Color(0xFF5F5E5A);
const _purpleFill = Color(0xFFCECBF6);
const _purpleLine = Color(0xFF534AB7);
const _amberFill = Color(0xFFFAC775);
const _amberLine = Color(0xFF854F0B);
const _paper = Color(0xFFFFFFFF);
const _paperLine = Color(0xFF888780);
const _ready = Color(0xFF1D9E75);

Paint _fill(Color c) => Paint()..color = c;

Paint _stroke(Color c, [double width = 2.5]) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeJoin = StrokeJoin.round
  ..strokeCap = StrokeCap.round;

void _shape(Canvas canvas, Path path, Color fill, Color line) {
  canvas.drawPath(path, _fill(fill));
  canvas.drawPath(path, _stroke(line));
}

void _rrect(Canvas canvas, Rect r, double radius, Color fill, Color line) {
  _shape(
    canvas,
    Path()..addRRect(RRect.fromRectAndRadius(r, Radius.circular(radius))),
    fill,
    line,
  );
}

void _dots(Canvas canvas, double left, double top, double step, double r) {
  final paint = _fill(_ink);
  for (var row = 0; row < 2; row++) {
    for (var col = 0; col < 3; col++) {
      canvas.drawCircle(
        Offset(left + col * step, top + row * step * 0.9),
        r,
        paint,
      );
    }
  }
}

// ── Τα σύμβολα ──────────────────────────────────────────────────────────

/// Προτομή: κεφάλι και ώμοι.
void _person(Canvas canvas) {
  _shape(
    canvas,
    Path()..addOval(Rect.fromCircle(center: const Offset(50, 30), radius: 18)),
    _tealFill,
    _tealLine,
  );
  _shape(
    canvas,
    Path()
      ..moveTo(14, 92)
      ..quadraticBezierTo(14, 54, 50, 54)
      ..quadraticBezierTo(86, 54, 86, 92)
      ..close(),
    _tealFill,
    _tealLine,
  );
}

/// Επιτραπέζιο τηλέφωνο: βάση με πλήκτρα και ακουστικό από πάνω.
void _phone(Canvas canvas) {
  _shape(
    canvas,
    Path()
      ..moveTo(10, 88)
      ..lineTo(18, 46)
      ..lineTo(82, 46)
      ..lineTo(90, 88)
      ..close(),
    _grayFill,
    _grayLine,
  );
  _shape(
    canvas,
    Path()
      ..moveTo(6, 38)
      ..quadraticBezierTo(6, 18, 24, 20)
      ..lineTo(76, 20)
      ..quadraticBezierTo(94, 18, 94, 38)
      ..lineTo(82, 42)
      ..lineTo(72, 30)
      ..lineTo(28, 30)
      ..lineTo(18, 42)
      ..close(),
    _coralFill,
    _coralLine,
  );
  _dots(canvas, 36, 60, 14, 3.2);
}

/// Υπολογιστής: μια οθόνη σε βάση.
void _computer(Canvas canvas) {
  _rrect(
    canvas,
    const Rect.fromLTRB(6, 10, 94, 72),
    5,
    _purpleFill,
    _purpleLine,
  );
  canvas.drawRect(const Rect.fromLTRB(14, 18, 86, 64), _stroke(_ink, 1.2));
  canvas.drawLine(const Offset(50, 72), const Offset(50, 86), _stroke(_ink, 4));
  canvas.drawLine(const Offset(28, 89), const Offset(72, 89), _stroke(_ink, 4));
}

/// Εκτυπωτής: χαρτί που μπαίνει από πάνω και βγαίνει μπροστά.
void _printer(Canvas canvas) {
  _rrect(canvas, const Rect.fromLTRB(24, 10, 76, 28), 2, _grayFill, _grayLine);
  _rrect(canvas, const Rect.fromLTRB(8, 28, 92, 70), 5, _grayFill, _grayLine);
  canvas.drawLine(
    const Offset(22, 56),
    const Offset(78, 56),
    _stroke(_ink, 1.5),
  );
  canvas.drawCircle(const Offset(82, 40), 3.5, _fill(_ready));
  _rrect(canvas, const Rect.fromLTRB(26, 70, 74, 92), 1, _paper, _paperLine);
  canvas.drawLine(
    const Offset(34, 78),
    const Offset(66, 78),
    _stroke(_paperLine, 1),
  );
  canvas.drawLine(
    const Offset(34, 85),
    const Offset(58, 85),
    _stroke(_paperLine, 1),
  );
}

/// Έπιπλο: παραλληλόγραμμο από πάνω. Στον χάρτη παίρνει το πραγματικό του
/// μέγεθος· εδώ, ως εικονίδιο, ένα γραφείο σε αναλογία 2:1.
void _furniture(Canvas canvas) {
  _rrect(canvas, const Rect.fromLTRB(4, 28, 96, 74), 2, _amberFill, _amberLine);
}

/// Καμπίνα: το rack από μπροστά, με τις δύο ράγες και τρία αντικείμενα σε
/// θέσεις U — patch panel, switch, και ένα ψηλότερο UPS στο κάτω μέρος.
void _cabinet(Canvas canvas) {
  _rrect(canvas, const Rect.fromLTRB(23, 4, 77, 96), 3, _paper, _ink);
  final rail = _stroke(_ink, 1.2);
  canvas.drawLine(const Offset(28.5, 8), const Offset(28.5, 92), rail);
  canvas.drawLine(const Offset(71.5, 8), const Offset(71.5, 92), rail);
  _rrect(canvas, const Rect.fromLTRB(31, 15, 69, 23), 1, _tealFill, _tealLine);
  _rrect(
    canvas,
    const Rect.fromLTRB(31, 27.5, 69, 35.5),
    1,
    _purpleFill,
    _purpleLine,
  );
  _rrect(
    canvas,
    const Rect.fromLTRB(31, 70.5, 69, 87),
    1,
    _grayFill,
    _grayLine,
  );
}

/// Σειρά θυρών: [count] τετραγωνάκια πλάτους [w] και ύψους [h] από το
/// [left] με βήμα [step].
void _ports(
  Canvas canvas,
  double left,
  double top,
  int count,
  double step,
  double w,
  double h,
) {
  final paint = _fill(_ink);
  for (var i = 0; i < count; i++) {
    canvas.drawRect(Rect.fromLTWH(left + i * step, top, w, h), paint);
  }
}

/// Patch panel: μία σειρά θυρών και η διακεκομμένη γραμμή των ετικετών.
void _patchPanel(Canvas canvas) {
  _rrect(canvas, const Rect.fromLTRB(4, 36, 96, 64), 2, _tealFill, _tealLine);
  _ports(canvas, 10, 43.5, 7, 11.5, 7.3, 6.3);
  _dashed(canvas, const Offset(10, 56.5), 76.5, _ink);
}

/// Switch: δύο σειρές θυρών και λυχνίες κατάστασης.
void _switch(Canvas canvas) {
  _rrect(
    canvas,
    const Rect.fromLTRB(4, 36, 96, 64),
    2,
    _purpleFill,
    _purpleLine,
  );
  _ports(canvas, 10, 40.5, 6, 9.4, 6.3, 5.2);
  _ports(canvas, 10, 51, 6, 9.4, 6.3, 5.2);
  canvas.drawCircle(const Offset(77, 44.8), 2.3, _fill(_ready));
  canvas.drawCircle(const Offset(85.5, 44.8), 2.3, _fill(_ready));
  canvas.drawCircle(const Offset(77, 54.2), 2.3, _fill(_amberLine));
}

/// Πρίζα: πλάκα στον τοίχο με δύο θύρες.
void _outlet(Canvas canvas) {
  _rrect(canvas, const Rect.fromLTRB(19, 7, 81, 93), 6.5, _paper, _grayLine);
  for (final top in const [22.5, 56.5]) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(34.5, top, 31, 21),
        const Radius.circular(2.5),
      ),
      _stroke(_ink, 1.6),
    );
    canvas.drawRect(Rect.fromLTWH(42, top + 8, 16, 9), _fill(_ink));
  }
}

/// Router: σώμα με λυχνίες και θύρες, και δύο κεραίες.
void _router(Canvas canvas) {
  final antenna = _stroke(_ink, 2.6);
  canvas.drawLine(const Offset(23.5, 53.5), const Offset(14, 10.5), antenna);
  canvas.drawLine(const Offset(76.5, 53.5), const Offset(86, 10.5), antenna);
  _rrect(
    canvas,
    const Rect.fromLTRB(4, 53.5, 96, 89.5),
    6,
    _grayFill,
    _grayLine,
  );
  canvas.drawCircle(const Offset(19, 71.5), 2.4, _fill(_ready));
  canvas.drawCircle(const Offset(29.5, 71.5), 2.4, _fill(_ready));
  _ports(canvas, 47.5, 67, 3, 13.2, 8.4, 8.4);
}

/// POE: θύρες και ο κεραυνός του ρεύματος.
void _poe(Canvas canvas) {
  _rrect(canvas, const Rect.fromLTRB(4, 36, 96, 64), 3, _tealFill, _tealLine);
  _ports(canvas, 12, 43.5, 4, 10.45, 6.7, 5.7);
  canvas.drawPath(
    Path()
      ..moveTo(72.8, 39.5)
      ..lineTo(67.1, 51)
      ..lineTo(72.8, 51)
      ..lineTo(69, 60.5)
      ..lineTo(80.4, 47.2)
      ..lineTo(74.7, 47.2)
      ..lineTo(78.5, 39.5)
      ..close(),
    _fill(_amberLine),
  );
}

/// UPS: οθόνη με την μπαταρία, κουμπί λειτουργίας, χωρίς θύρες.
void _ups(Canvas canvas) {
  _rrect(
    canvas,
    const Rect.fromLTRB(4, 23.5, 96, 76.5),
    4,
    _grayFill,
    _grayLine,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTRB(14, 33, 42.5, 48),
      const Radius.circular(2),
    ),
    _stroke(_ink, 1.2),
  );
  canvas.drawRect(const Rect.fromLTRB(17.5, 36.5, 36.5, 44.5), _fill(_ready));
  canvas.drawRect(const Rect.fromLTRB(36.5, 38.5, 39.5, 42.5), _fill(_ink));
  final power = _stroke(_ink, 1.6);
  canvas.drawCircle(const Offset(78.5, 40.5), 6.6, power);
  canvas.drawLine(const Offset(78.5, 35.5), const Offset(78.5, 41.5), power);
  _dashed(canvas, const Offset(14, 63.5), 72, _ink);
}

/// Διακεκομμένη οριζόντια γραμμή μήκους [length] από το [start].
void _dashed(Canvas canvas, Offset start, double length, Color color) {
  final paint = _stroke(color, 0.9);
  for (var x = 0.0; x < length; x += 5) {
    canvas.drawLine(
      start + Offset(x, 0),
      start + Offset(x + 2.5 > length ? length : x + 2.5, 0),
      paint,
    );
  }
}

void _unknown(Canvas canvas) {
  _rrect(canvas, const Rect.fromLTRB(14, 14, 86, 86), 6, _grayFill, _grayLine);
  final text = TextPainter(
    text: const TextSpan(
      text: '?',
      style: TextStyle(fontSize: 48, color: _ink, fontWeight: FontWeight.w500),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  text.paint(canvas, Offset(50 - text.width / 2, 50 - text.height / 2));
  text.dispose();
}
