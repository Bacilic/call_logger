import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../providers/building_map_providers.dart';
import '../../models/department_model.dart';

/// Σχεδίαση χρωματισμένων περιοχών τμημάτων σε normalized συντεταγμένες στο [size].
class BuildingMapSheetPainter extends CustomPainter {
  BuildingMapSheetPainter({
    required this.sheetIdString,
    required this.departments,
    required this.rotationRadians,
    required this.toolMode,
    this.highlightDepartmentId,
    this.hoveredDepartmentId,
    this.draftShape,
    this.suppressMapLabelForDepartmentId,
    this.mapLabelOverrideDepartmentId,
    this.mapLabelOverrideText,
  });

  final String sheetIdString;
  final List<DepartmentModel> departments;
  final double rotationRadians;
  final MapToolMode toolMode;
  final int? highlightDepartmentId;
  final int? hoveredDepartmentId;
  final DraftDepartmentShape? draftShape;
  /// Όταν γίνεται inline επεξεργασία ονόματος — κρύβει κείμενο/γραμμές ετικέτας (το TextField είναι overlay).
  final int? suppressMapLabelForDepartmentId;

  /// Τοπικό κείμενο επωνυμίας χάρτη πριν Επιβεβαίωση draft (ίδιο τμήμα με [mapLabelOverrideDepartmentId]).
  final int? mapLabelOverrideDepartmentId;
  final String? mapLabelOverrideText;

  static const double _kMapFillOpacity = 0.78;
  static const double _kMapFillOpacityHovered = 0.86;

  /// RGB χωρίς διαφάνεια — η διαφάνεια εφαρμόζεται στο [Paint].
  static Color _parseOpaqueFillColor(String? hex, Color fallback) {
    if (hex == null || hex.trim().isEmpty) return fallback;
    var h = hex.trim();
    if (h.startsWith('#')) h = h.substring(1);
    if (h.length == 6) {
      final v = int.tryParse(h, radix: 16);
      if (v != null) {
        return Color(0xFF000000 | v);
      }
    }
    return fallback;
  }

  static Offset _rotateAroundCenter(Offset p, Offset center, double radians) {
    final dx = p.dx - center.dx;
    final dy = p.dy - center.dy;
    final c = math.cos(radians);
    final s = math.sin(radians);
    return Offset(
      center.dx + (dx * c) - (dy * s),
      center.dy + (dx * s) + (dy * c),
    );
  }

  static Offset _pointOnRotatedRectBoundaryToward(
    Rect rect,
    double rotationRadians,
    Offset targetPoint,
  ) {
    final center = rect.center;
    final targetLocal = _rotateAroundCenter(targetPoint, center, -rotationRadians);
    final vx = targetLocal.dx - center.dx;
    final vy = targetLocal.dy - center.dy;
    if (vx == 0 && vy == 0) {
      return _rotateAroundCenter(
        Offset(center.dx, rect.top),
        center,
        rotationRadians,
      );
    }
    final halfW = rect.width / 2;
    final halfH = rect.height / 2;
    final sx = vx == 0 ? double.infinity : (halfW / vx.abs());
    final sy = vy == 0 ? double.infinity : (halfH / vy.abs());
    final s = math.min(sx, sy);
    final edgeLocal = Offset(center.dx + (vx * s), center.dy + (vy * s));
    return _rotateAroundCenter(edgeLocal, center, rotationRadians);
  }

  void _drawRotatedRect({
    required Canvas canvas,
    required Rect rect,
    required double radians,
    required Paint fill,
    required Paint border,
  }) {
    final center = rect.center;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(radians);
    final centered = Rect.fromCenter(
      center: Offset.zero,
      width: rect.width,
      height: rect.height,
    );
    canvas.drawRect(centered, fill);
    canvas.drawRect(centered, border);
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(rotationRadians);
    canvas.translate(-cx, -cy);

    for (final d in departments) {
      if ((d.mapFloor ?? '') != sheetIdString) continue;
      final isEditingSelectedDraft =
          toolMode == MapToolMode.edit &&
          draftShape != null &&
          highlightDepartmentId != null &&
          d.id == highlightDepartmentId;
      final nx = isEditingSelectedDraft ? draftShape!.x : d.mapX;
      final ny = isEditingSelectedDraft ? draftShape!.y : d.mapY;
      final nw = isEditingSelectedDraft ? draftShape!.width : d.mapWidth;
      final nh = isEditingSelectedDraft ? draftShape!.height : d.mapHeight;
      if (nx == null || ny == null || nw == null || nh == null) continue;
      if (nw <= 0 || nh <= 0) continue;
      final effectiveRotation = isEditingSelectedDraft
          ? draftShape!.rotation
          : d.mapRotation;
      final effectiveLabelOffsetX = isEditingSelectedDraft
          ? draftShape!.labelOffsetX
          : d.mapLabelOffsetX;
      final effectiveLabelOffsetY = isEditingSelectedDraft
          ? draftShape!.labelOffsetY
          : d.mapLabelOffsetY;
      final effectiveAnchorOffsetX = isEditingSelectedDraft
          ? draftShape!.anchorOffsetX
          : d.mapAnchorOffsetX;
      final effectiveAnchorOffsetY = isEditingSelectedDraft
          ? draftShape!.anchorOffsetY
          : d.mapAnchorOffsetY;
      final r = Rect.fromLTWH(
        nx * size.width,
        ny * size.height,
        nw * size.width,
        nh * size.height,
      );
      final isHovered = toolMode == MapToolMode.select && hoveredDepartmentId == d.id;
      final opaqueFill = _parseOpaqueFillColor(d.color, const Color(0xFF1976D2));
      final fillOpacity =
          isHovered ? _kMapFillOpacityHovered : _kMapFillOpacity;
      final strokeW = highlightDepartmentId == d.id
          ? 3.0
          : (isHovered ? 2.6 : 1.5);
      final paint = Paint()
        ..color = opaqueFill.withValues(alpha: fillOpacity)
        ..style = PaintingStyle.fill;
      final border = Paint()
        ..color = Colors.black.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW;
      canvas.save();
      if (isHovered) {
        canvas.translate(0, -3);
        final shadow = Paint()
          ..color = Colors.black.withValues(alpha: 0.22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
        _drawRotatedRect(
          canvas: canvas,
          rect: r,
          radians: effectiveRotation,
          fill: shadow,
          border: Paint()..color = Colors.transparent,
        );
      }
      _drawRotatedRect(
        canvas: canvas,
        rect: r,
        radians: effectiveRotation,
        fill: paint,
        border: border,
      );
      final labelCenter = Offset(
        r.center.dx + ((effectiveLabelOffsetX ?? 0.0) * size.width),
        r.center.dy + ((effectiveLabelOffsetY ?? 0.0) * size.height),
      );
      final suppressLabel = suppressMapLabelForDepartmentId != null &&
          d.id == suppressMapLabelForDepartmentId;
      if (!suppressLabel) {
        final override = mapLabelOverrideDepartmentId != null &&
                mapLabelOverrideText != null &&
                d.id == mapLabelOverrideDepartmentId
            ? mapLabelOverrideText!
            : d.displayName;
        final tp = TextPainter(
          text: TextSpan(
            text: override,
            style: TextStyle(
              color: Colors.black87,
              fontSize: math.max(10, size.shortestSide * 0.018),
              fontWeight: FontWeight.w500,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 2,
          ellipsis: '…',
        )..layout(maxWidth: math.max(72, size.width * 0.24));
        final textTopLeft = Offset(
          labelCenter.dx - (tp.width / 2),
          labelCenter.dy - (tp.height / 2),
        );
        tp.paint(canvas, textTopLeft);

        final underlineStart =
            Offset(textTopLeft.dx, textTopLeft.dy + tp.height + 2);
        final underlineEnd = Offset(
          textTopLeft.dx + tp.width,
          textTopLeft.dy + tp.height + 2,
        );
        final anchorPoint =
            effectiveAnchorOffsetX != null && effectiveAnchorOffsetY != null
            ? Offset(
                r.center.dx + (effectiveAnchorOffsetX * size.width),
                r.center.dy + (effectiveAnchorOffsetY * size.height),
              )
            : _pointOnRotatedRectBoundaryToward(
                r,
                effectiveRotation,
                labelCenter,
              );
        final connectToLeft = labelCenter.dx >= anchorPoint.dx;
        final leaderTarget = connectToLeft ? underlineStart : underlineEnd;
        final annotationStroke = Paint()
          ..color = Colors.black.withValues(alpha: 0.75)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.35;
        canvas.drawLine(underlineStart, underlineEnd, annotationStroke);
        canvas.drawLine(anchorPoint, leaderTarget, annotationStroke);
      }
      canvas.restore();
    }

    if (draftShape != null) {
      final dr = Rect.fromLTWH(
        draftShape!.x * size.width,
        draftShape!.y * size.height,
        draftShape!.width * size.width,
        draftShape!.height * size.height,
      );
      final p = Paint()
        ..color = Colors.orange.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill;
      final b = Paint()
        ..color = Colors.orange
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      _drawRotatedRect(
        canvas: canvas,
        rect: dr,
        radians: draftShape!.rotation,
        fill: p,
        border: b,
      );

      if (toolMode == MapToolMode.edit) {
        final center = dr.center;
        final corners = <Offset>[
          dr.topLeft,
          dr.topRight,
          dr.bottomLeft,
          dr.bottomRight,
        ].map((p) => _rotateAroundCenter(p, center, draftShape!.rotation));
        final handlesPaint = Paint()
          ..color = Colors.orange
          ..style = PaintingStyle.fill;
        final handleStroke = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        for (final corner in corners) {
          canvas.drawCircle(corner, 6, handlesPaint);
          canvas.drawCircle(corner, 6, handleStroke);
        }

        final topCenter = Offset(dr.center.dx, dr.top);
        final rotatedTopCenter = _rotateAroundCenter(
          topCenter,
          center,
          draftShape!.rotation,
        );
        final rotateAnchor = _rotateAroundCenter(
          Offset(dr.center.dx, dr.top - 24),
          center,
          draftShape!.rotation,
        );
        final stem = Paint()
          ..color = Colors.orange.withValues(alpha: 0.95)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawLine(rotatedTopCenter, rotateAnchor, stem);
        canvas.drawCircle(rotateAnchor, 7, handlesPaint);
        canvas.drawCircle(rotateAnchor, 7, handleStroke);

        final labelCenter = Offset(
          dr.center.dx + ((draftShape!.labelOffsetX ?? 0.0) * size.width),
          dr.center.dy + ((draftShape!.labelOffsetY ?? 0.0) * size.height),
        );
        final anchorPoint =
            draftShape!.anchorOffsetX != null && draftShape!.anchorOffsetY != null
            ? Offset(
                dr.center.dx + (draftShape!.anchorOffsetX! * size.width),
                dr.center.dy + (draftShape!.anchorOffsetY! * size.height),
              )
            : _pointOnRotatedRectBoundaryToward(dr, draftShape!.rotation, labelCenter);
        final labelHandlePaint = Paint()
          ..color = Colors.deepPurple
          ..style = PaintingStyle.fill;
        final anchorHandlePaint = Paint()
          ..color = Colors.teal
          ..style = PaintingStyle.fill;
        canvas.drawCircle(labelCenter, 7, labelHandlePaint);
        canvas.drawCircle(labelCenter, 7, handleStroke);
        canvas.drawCircle(anchorPoint, 7, anchorHandlePaint);
        canvas.drawCircle(anchorPoint, 7, handleStroke);
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant BuildingMapSheetPainter oldDelegate) {
    return oldDelegate.sheetIdString != sheetIdString ||
        oldDelegate.departments != departments ||
        oldDelegate.rotationRadians != rotationRadians ||
        oldDelegate.toolMode != toolMode ||
        oldDelegate.highlightDepartmentId != highlightDepartmentId ||
        oldDelegate.hoveredDepartmentId != hoveredDepartmentId ||
        oldDelegate.draftShape != draftShape ||
        oldDelegate.suppressMapLabelForDepartmentId !=
            suppressMapLabelForDepartmentId ||
        oldDelegate.mapLabelOverrideDepartmentId !=
            mapLabelOverrideDepartmentId ||
        oldDelegate.mapLabelOverrideText != mapLabelOverrideText;
  }
}
