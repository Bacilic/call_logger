import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../floor_plan_item_info.dart';
import '../floor_plan_view_transform.dart';

/// Ζωγραφίζει τη διαδρομή μιας πρίζας πάνω από τον χάρτη, σε pixel οθόνης: μια
/// ευθεία ως κάθε καμπίνα του ορόφου και ως τη σκάλα ή τον αγωγό προς άλλον
/// όροφο. Ευθεία και όχι η πραγματική πορεία, αφού οι αποστάσεις των καλωδίων
/// δεν καταγράφονται.
///
/// Κοινό για τη σχεδίαση και την προβολή του χάρτη.
class FloorPlanRoutePainter extends CustomPainter {
  const FloorPlanRoutePainter({
    required this.view,
    required this.route,
    required this.color,
  });

  final FloorPlanViewTransform view;
  final FloorPlanOutletRoute route;
  final Color color;

  @override
  void paint(ui.Canvas canvas, Size size) {
    final from = route.from;
    if (from == null) return;
    final line = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final start = view.toScreen(from);
    for (final target in [...route.targets, ?route.riser]) {
      final end = view.toScreen(target.center);
      canvas.drawLine(start, end, line);
      canvas.drawCircle(end, 4, line);
    }
    canvas.drawCircle(start, 4, line);
  }

  @override
  bool shouldRepaint(FloorPlanRoutePainter old) =>
      old.view != view || old.route != route || old.color != color;
}
