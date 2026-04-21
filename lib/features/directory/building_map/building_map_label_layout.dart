import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/department_model.dart';
import 'providers/building_map_providers.dart';

/// Γεωμετρία ετικέτας χάρτη (ίδια λογική με [BuildingMapSheetPainter]).
class MapLabelLayout {
  MapLabelLayout({
    required this.textTopLeft,
    required this.textPainterSize,
    required this.labelCenter,
    required this.fontSize,
  });

  final Offset textTopLeft;
  final Size textPainterSize;
  final Offset labelCenter;
  final double fontSize;

  /// Περιοχή κειμένου + υπογράμμισης για hit-test (χαλαρό padding).
  Rect get textAndUnderlineHitRect {
    const underlineGap = 2.0;
    const pad = 6.0;
    return Rect.fromLTRB(
      textTopLeft.dx - pad,
      textTopLeft.dy - pad,
      textTopLeft.dx + textPainterSize.width + pad,
      textTopLeft.dy + textPainterSize.height + underlineGap + pad,
    );
  }

  /// Μικρή περιοχή για το εικονίδιο μολυβιού δίπλα στο κείμενο.
  Rect get pencilHitRect {
    const k = 40.0;
    final left = textTopLeft.dx + textPainterSize.width + 4;
    final top = textTopLeft.dy + (textPainterSize.height / 2) - (k / 2);
    return Rect.fromLTWH(left, top, k, k);
  }
}

Offset _rotateAroundCenter(Offset p, Offset center, double radians) {
  final dx = p.dx - center.dx;
  final dy = p.dy - center.dy;
  final c = math.cos(radians);
  final s = math.sin(radians);
  return Offset(
    center.dx + (dx * c) - (dy * s),
    center.dy + (dx * s) + (dy * c),
  );
}

/// Επιστρέφει null αν το τμήμα δεν σχεδιάζεται σε αυτό το φύλλο ή λείπει γεωμετρία.
MapLabelLayout? computeMapLabelLayout({
  required DepartmentModel dep,
  required String sheetIdString,
  required DraftDepartmentShape? draftShape,
  required MapToolMode toolMode,
  required int? highlightDepartmentId,
  required Size canvasSize,
  required double sheetRotationRadians,
  /// Κείμενο ετικέτας (π.χ. τοπικό draft πριν την αποθήκευση στο ✓).
  String? labelTextOverride,
}) {
  if ((dep.mapFloor ?? '') != sheetIdString) return null;

  final draft = draftShape;
  final isEditingSelectedDraft =
      toolMode == MapToolMode.edit &&
      draft != null &&
      highlightDepartmentId != null &&
      dep.id == highlightDepartmentId;

  final nx = isEditingSelectedDraft ? draft.x : dep.mapX;
  final ny = isEditingSelectedDraft ? draft.y : dep.mapY;
  final nw = isEditingSelectedDraft ? draft.width : dep.mapWidth;
  final nh = isEditingSelectedDraft ? draft.height : dep.mapHeight;
  if (nx == null || ny == null || nw == null || nh == null) return null;
  if (nw <= 0 || nh <= 0) return null;

  final effectiveLabelOffsetX =
      isEditingSelectedDraft ? draft.labelOffsetX : dep.mapLabelOffsetX;
  final effectiveLabelOffsetY =
      isEditingSelectedDraft ? draft.labelOffsetY : dep.mapLabelOffsetY;

  final r = Rect.fromLTWH(
    nx * canvasSize.width,
    ny * canvasSize.height,
    nw * canvasSize.width,
    nh * canvasSize.height,
  );

  final labelCenterBeforeSheetRotation = Offset(
    r.center.dx + ((effectiveLabelOffsetX ?? 0.0) * canvasSize.width),
    r.center.dy + ((effectiveLabelOffsetY ?? 0.0) * canvasSize.height),
  );
  final canvasCenter = Offset(canvasSize.width / 2, canvasSize.height / 2);
  final labelCenter = _rotateAroundCenter(
    labelCenterBeforeSheetRotation,
    canvasCenter,
    sheetRotationRadians,
  );

  final fontSize = math.max(10.0, canvasSize.shortestSide * 0.018);
  final labelText = labelTextOverride ?? dep.displayName;
  final tp = TextPainter(
    text: TextSpan(
      text: labelText,
      style: TextStyle(
        color: Colors.black87,
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 2,
    ellipsis: '…',
  )..layout(maxWidth: math.max(72.0, canvasSize.width * 0.24));

  final textTopLeft = Offset(
    labelCenter.dx - (tp.width / 2),
    labelCenter.dy - (tp.height / 2),
  );

  return MapLabelLayout(
    textTopLeft: textTopLeft,
    textPainterSize: Size(tp.width, tp.height),
    labelCenter: labelCenter,
    fontSize: fontSize,
  );
}
