import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/department_model.dart';
import 'providers/building_map_providers.dart';

/// Μέγιστες γραμμές ετικέτας χάρτη (συμπ. ρητές αλλαγές γραμμής με Shift+Enter).
const int kBuildingMapLabelMaxLines = 4;

/// Προεπιλεγμένη κλίμακα μεγέθους ετικέτας (`departments.map_label_font_scale`).
const double kBuildingMapLabelFontScaleDefault = 1.0;
const double kBuildingMapLabelFontScaleStep = 0.1;
const double kBuildingMapLabelFontScaleMin = 0.5;
const double kBuildingMapLabelFontScaleMax = 2.0;

/// Προεπιλεγμένες διαστάσεις πλαισίου ετικέτας (`departments.map_label_width/height`).
const double kBuildingMapLabelWidthDefault = 150.0;
const double kBuildingMapLabelHeightDefault = 50.0;
const double kBuildingMapLabelMinWidth = 48.0;
const double kBuildingMapLabelMinHeight = 24.0;
const double kBuildingMapLabelBoxPadding = 4.0;

/// Ελάχιστο μέγεθος γραμματοσειράς για auto-fit ετικέτας χάρτη.
const double kBuildingMapLabelMinFontSize = 6.0;

TextStyle _mapLabelTextStyle(double fontSize) => TextStyle(
      color: Colors.black87,
      fontSize: fontSize,
      fontWeight: FontWeight.w500,
      height: 1.15,
    );

double _measureMapLabelLineWidth(String text, TextStyle style) {
  if (text.isEmpty) return 0;
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  return tp.width;
}

/// Ελάχιστο πλάτος πλαισίου ώστε η μεγαλύτερη λέξη να χωρά σε μία γραμμή στο min font.
double computeMinMapLabelBoxWidthForText(String text) {
  final style = _mapLabelTextStyle(kBuildingMapLabelMinFontSize);
  var maxWordWidth = 0.0;
  for (final paragraph in text.split('\n')) {
    for (final word in paragraph.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      maxWordWidth = math.max(
        maxWordWidth,
        _measureMapLabelLineWidth(word, style),
      );
    }
  }
  final contentMin = maxWordWidth + (kBuildingMapLabelBoxPadding * 2) + 1.0;
  return math.max(kBuildingMapLabelMinWidth, contentMin);
}

/// Αναδίπλωση μόνο σε κενά ή ρητές αλλαγές γραμμής (Shift+Enter)· χωρίς τεμαχισμό λέξεων.
String? wrapMapLabelTextAtWordBoundaries({
  required String text,
  required double maxLineWidth,
  required TextStyle style,
  required int maxLines,
}) {
  if (maxLineWidth <= 0) return null;
  final resultLines = <String>[];

  for (final paragraph in text.split('\n')) {
    if (paragraph.trim().isEmpty) {
      resultLines.add('');
      if (resultLines.length > maxLines) return null;
      continue;
    }

    var current = '';
    for (final word in paragraph.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      final candidate = current.isEmpty ? word : '$current $word';
      if (_measureMapLabelLineWidth(candidate, style) <= maxLineWidth + 0.5) {
        current = candidate;
        continue;
      }

      if (current.isNotEmpty) {
        resultLines.add(current);
        if (resultLines.length >= maxLines) return null;
        current = word;
      } else {
        current = word;
      }

      if (_measureMapLabelLineWidth(current, style) > maxLineWidth + 0.5) {
        return null;
      }
    }

    if (current.isNotEmpty) {
      resultLines.add(current);
      if (resultLines.length > maxLines) return null;
    }
  }

  return resultLines.join('\n');
}

TextPainter _layoutWrappedMapLabelText({
  required String wrappedText,
  required TextStyle style,
  required int maxLines,
  required double innerW,
}) {
  return TextPainter(
    text: TextSpan(text: wrappedText, style: style),
    textDirection: TextDirection.ltr,
    maxLines: maxLines,
    ellipsis: '…',
  )..layout(maxWidth: innerW);
}

double effectiveMapLabelFontScale(double? stored) =>
    stored ?? kBuildingMapLabelFontScaleDefault;

double effectiveMapLabelWidth(double? stored) =>
    stored ?? kBuildingMapLabelWidthDefault;

double effectiveMapLabelHeight(double? stored) =>
    stored ?? kBuildingMapLabelHeightDefault;

double computeBuildingMapLabelFontSize(Size canvasSize, double fontScale) {
  final base = math.max(10.0, canvasSize.shortestSide * 0.018);
  final scaled = base * fontScale;
  return math.max(8.0, scaled);
}

/// Τιμή για αποθήκευση· `NULL` όταν ισούται με την προεπιλογή.
double? mapLabelFontScaleForDatabase(double scale) {
  final clamped = scale.clamp(
    kBuildingMapLabelFontScaleMin,
    kBuildingMapLabelFontScaleMax,
  );
  if ((clamped - kBuildingMapLabelFontScaleDefault).abs() < 0.001) {
    return null;
  }
  return clamped;
}

double? mapLabelWidthForDatabase(double width) {
  final clamped = width.clamp(kBuildingMapLabelMinWidth, 2000.0);
  if ((clamped - kBuildingMapLabelWidthDefault).abs() < 0.5) {
    return null;
  }
  return clamped;
}

double? mapLabelHeightForDatabase(double height) {
  final clamped = height.clamp(kBuildingMapLabelMinHeight, 2000.0);
  if ((clamped - kBuildingMapLabelHeightDefault).abs() < 0.5) {
    return null;
  }
  return clamped;
}

double stepMapLabelFontScale(double current, {required bool increase}) {
  final next = increase
      ? current + kBuildingMapLabelFontScaleStep
      : current - kBuildingMapLabelFontScaleStep;
  return next.clamp(
    kBuildingMapLabelFontScaleMin,
    kBuildingMapLabelFontScaleMax,
  );
}

/// Αποτέλεσμα διάταξης κειμένου εντός πλαισίου ετικέτας.
class MapLabelTextLayout {
  MapLabelTextLayout({
    required this.textPainter,
    required this.fontSize,
    required this.textTopLeft,
  });

  final TextPainter textPainter;
  final double fontSize;
  final Offset textTopLeft;
}

/// Βρίσκει το μέγιστο fontSize (δυαδική αναζήτηση) που χωρά αυστηρά στο πλαίσιο,
/// με αναδίπλωση μόνο σε όρια λέξεων (χωρίς τεμαχισμό).
MapLabelTextLayout layoutMapLabelTextInBox({
  required String text,
  required double boxWidth,
  required double boxHeight,
  required double maxFontSize,
  int maxLines = kBuildingMapLabelMaxLines,
}) {
  final innerW = math.max(8.0, boxWidth - (kBuildingMapLabelBoxPadding * 2));
  final innerH = math.max(8.0, boxHeight - (kBuildingMapLabelBoxPadding * 2));
  var lo = kBuildingMapLabelMinFontSize;
  var hi = math.max(kBuildingMapLabelMinFontSize, maxFontSize);
  TextPainter? bestPainter;
  var bestSize = kBuildingMapLabelMinFontSize;
  String? bestWrapped;

  while (hi - lo > 0.25) {
    final mid = (lo + hi) / 2;
    final style = _mapLabelTextStyle(mid);
    final wrapped = wrapMapLabelTextAtWordBoundaries(
      text: text,
      maxLineWidth: innerW,
      style: style,
      maxLines: maxLines,
    );
    if (wrapped == null) {
      hi = mid;
      continue;
    }
    final tp = _layoutWrappedMapLabelText(
      wrappedText: wrapped,
      style: style,
      maxLines: maxLines,
      innerW: innerW,
    );
    final fits = !tp.didExceedMaxLines &&
        tp.height <= innerH + 0.5 &&
        tp.width <= innerW + 0.5;
    if (fits) {
      lo = mid;
      bestPainter = tp;
      bestSize = mid;
      bestWrapped = wrapped;
    } else {
      hi = mid;
    }
  }

  if (bestPainter == null || bestWrapped == null) {
    final style = _mapLabelTextStyle(kBuildingMapLabelMinFontSize);
    bestWrapped = wrapMapLabelTextAtWordBoundaries(
      text: text,
      maxLineWidth: innerW,
      style: style,
      maxLines: maxLines,
    );
    bestPainter = _layoutWrappedMapLabelText(
      wrappedText: bestWrapped ?? text,
      style: style,
      maxLines: maxLines,
      innerW: innerW,
    );
    bestSize = kBuildingMapLabelMinFontSize;
  }

  final textTopLeft = Offset(
    (boxWidth - bestPainter.width) / 2,
    (boxHeight - bestPainter.height) / 2,
  );

  return MapLabelTextLayout(
    textPainter: bestPainter,
    fontSize: bestSize,
    textTopLeft: textTopLeft,
  );
}

/// Γεωμετρία ετικέτας χάρτη (ίδια λογική με [BuildingMapSheetPainter]).
class MapLabelLayout {
  MapLabelLayout({
    required this.labelCenter,
    required this.labelBoxRect,
    required this.textTopLeft,
    required this.textPainterSize,
    required this.fontSize,
    required this.labelWidth,
    required this.labelHeight,
  });

  final Offset labelCenter;
  final Rect labelBoxRect;
  final Offset textTopLeft;
  final Size textPainterSize;
  final double fontSize;
  final double labelWidth;
  final double labelHeight;

  /// Περιοχή πλαισίου + κειμένου για hit-test (χαλαρό padding).
  Rect get textAndUnderlineHitRect {
    const underlineGap = 2.0;
    const pad = 6.0;
    return Rect.fromLTRB(
      labelBoxRect.left - pad,
      labelBoxRect.top - pad,
      labelBoxRect.right + pad,
      labelBoxRect.bottom + underlineGap + pad,
    );
  }

  /// Μικρή περιοχή για το εικονίδιο μολυβιού δίπλα στο πλαίσιο.
  Rect get pencilHitRect {
    const k = 40.0;
    final left = labelBoxRect.right + 4;
    final top = labelBoxRect.top + (labelBoxRect.height / 2) - (k / 2);
    return Rect.fromLTWH(left, top, k, k);
  }

  /// Γωνίες πλαισίου ετικέτας (TL, TR, BL, BR) για resize handles.
  List<Offset> get labelBoxCorners => [
        labelBoxRect.topLeft,
        labelBoxRect.topRight,
        labelBoxRect.bottomLeft,
        labelBoxRect.bottomRight,
      ];
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

  final effectiveLabelWidth = isEditingSelectedDraft
      ? draft.labelWidth
      : effectiveMapLabelWidth(dep.mapLabelWidth);
  final effectiveLabelHeight = isEditingSelectedDraft
      ? draft.labelHeight
      : effectiveMapLabelHeight(dep.mapLabelHeight);

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

  final effectiveFontScale = isEditingSelectedDraft
      ? draft.labelFontScale
      : effectiveMapLabelFontScale(dep.mapLabelFontScale);
  final maxFontSize = computeBuildingMapLabelFontSize(
    canvasSize,
    effectiveFontScale,
  );
  final labelText = labelTextOverride ?? dep.displayName;

  final labelBoxRect = Rect.fromCenter(
    center: labelCenter,
    width: effectiveLabelWidth,
    height: effectiveLabelHeight,
  );

  final textLayout = layoutMapLabelTextInBox(
    text: labelText,
    boxWidth: effectiveLabelWidth,
    boxHeight: effectiveLabelHeight,
    maxFontSize: maxFontSize,
  );

  final textTopLeft = labelBoxRect.topLeft + textLayout.textTopLeft;

  return MapLabelLayout(
    labelCenter: labelCenter,
    labelBoxRect: labelBoxRect,
    textTopLeft: textTopLeft,
    textPainterSize: Size(
      textLayout.textPainter.width,
      textLayout.textPainter.height,
    ),
    fontSize: textLayout.fontSize,
    labelWidth: effectiveLabelWidth,
    labelHeight: effectiveLabelHeight,
  );
}
