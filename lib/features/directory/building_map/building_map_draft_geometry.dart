import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../models/department_model.dart';
import 'building_map_geometry.dart';
import 'building_map_label_layout.dart';
import 'providers/building_map_providers.dart';

/// Γεωμετρία του προσχεδίου τμήματος στον καμβά: πού έπεσε ο δείκτης και πώς
/// αλλάζει το σχήμα όταν σύρεται μια λαβή. Καθαροί υπολογισμοί — καμία
/// κατάσταση οθόνης· ο καμβάς αποφασίζει τι κάνει με το αποτέλεσμα.

/// Ελάχιστη πλευρά προσχεδίου σε normalized συντεταγμένες.
const double kBuildingMapMinDraftSize = 0.005;

/// Θέση του μολυβιού επωνυμίας: δεξιά από το κείμενο, ή πάνω/κάτω όταν η
/// δεξιά θέση βγαίνει από τον καμβά· πάντα μέσα στα όριά του.
Rect resolvePencilHitRect({
  required Rect raw,
  required Rect textRect,
  required Size canvasSize,
}) {
  const edgePadding = 4.0;
  const textGap = 3.0;
  bool rectOutOfBounds(Rect r) {
    return r.left < edgePadding ||
        r.top < edgePadding ||
        r.right > (canvasSize.width - edgePadding) ||
        r.bottom > (canvasSize.height - edgePadding);
  }

  final inlineTop = textRect.center.dy - (raw.height / 2);
  final inlineRect = Rect.fromLTWH(
    textRect.right + textGap,
    inlineTop,
    raw.width,
    raw.height,
  );

  var desiredLeft = inlineRect.left;
  var desiredTop = inlineRect.top;

  // Ειδικός κανόνας μόνο όταν η default inline θέση βγαίνει εκτός καμβά.
  if (rectOutOfBounds(inlineRect)) {
    desiredLeft = textRect.right - raw.width;
    desiredTop = textRect.top - raw.height - textGap;
    if (desiredTop < edgePadding) {
      desiredTop = textRect.bottom + textGap;
    }
  }

  final maxLeft = math.max(
    edgePadding,
    canvasSize.width - raw.width - edgePadding,
  );
  final maxTop = math.max(
    edgePadding,
    canvasSize.height - raw.height - edgePadding,
  );
  return Rect.fromLTWH(
    desiredLeft.clamp(edgePadding, maxLeft).toDouble(),
    desiredTop.clamp(edgePadding, maxTop).toDouble(),
    raw.width,
    raw.height,
  );
}

/// True όταν το σχήμα του προσχεδίου διαφέρει από την αποθηκευμένη θέση του
/// τμήματος σε αυτό το φύλλο (θέση, μέγεθος, περιστροφή, ετικέτα, άγκυρα).
bool draftShapeDiffersFromSaved({
  required DepartmentModel dept,
  required DraftDepartmentShape draft,
  required String sheetStr,
}) {
  if ((dept.mapFloor ?? '') != sheetStr) return true;
  if (!dept.isMapped) return true;

  bool approxEq(double? a, double? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return (a - b).abs() < 1e-5;
  }

  if (!approxEq(dept.mapX, draft.x)) return true;
  if (!approxEq(dept.mapY, draft.y)) return true;
  if (!approxEq(dept.mapWidth, draft.width)) return true;
  if (!approxEq(dept.mapHeight, draft.height)) return true;
  if (!approxEq(dept.mapRotation, draft.rotation)) return true;

  final labelOffsetX = dept.mapLabelOffsetX ?? 0.0;
  final draftLabelOffsetX = draft.labelOffsetX ?? 0.0;
  if (!approxEq(labelOffsetX, draftLabelOffsetX)) return true;

  final labelOffsetY = dept.mapLabelOffsetY ?? 0.0;
  final draftLabelOffsetY = draft.labelOffsetY ?? 0.0;
  if (!approxEq(labelOffsetY, draftLabelOffsetY)) return true;

  final anchorOffsetX = dept.mapAnchorOffsetX ?? 0.0;
  final draftAnchorOffsetX = draft.anchorOffsetX ?? 0.0;
  if (!approxEq(anchorOffsetX, draftAnchorOffsetX)) return true;

  final anchorOffsetY = dept.mapAnchorOffsetY ?? 0.0;
  final draftAnchorOffsetY = draft.anchorOffsetY ?? 0.0;
  if (!approxEq(anchorOffsetY, draftAnchorOffsetY)) return true;

  if (!approxEq(
    effectiveMapLabelFontScale(dept.mapLabelFontScale),
    draft.labelFontScale,
  )) {
    return true;
  }

  if (!approxEq(effectiveMapLabelWidth(dept.mapLabelWidth), draft.labelWidth)) {
    return true;
  }
  if (!approxEq(
    effectiveMapLabelHeight(dept.mapLabelHeight),
    draft.labelHeight,
  )) {
    return true;
  }
  return false;
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

/// Κέντρο ετικέτας σε px καμβά, πριν από την περιστροφή του φύλλου.
Offset draftLabelCenter(DraftDepartmentShape draft, Size canvasSize) {
  return Offset(
    (draft.x + (draft.width / 2)) * canvasSize.width +
        ((draft.labelOffsetX ?? 0.0) * canvasSize.width),
    (draft.y + (draft.height / 2)) * canvasSize.height +
        ((draft.labelOffsetY ?? 0.0) * canvasSize.height),
  );
}

/// Σημείο αγκύρωσης της γραμμής ετικέτας: ρητή μετατόπιση αν υπάρχει, αλλιώς
/// το σημείο του περιγράμματος προς την ετικέτα.
Offset draftAnchorPoint(DraftDepartmentShape draft, Size canvasSize) {
  final rect = Rect.fromLTWH(
    draft.x * canvasSize.width,
    draft.y * canvasSize.height,
    draft.width * canvasSize.width,
    draft.height * canvasSize.height,
  );
  if (draft.anchorOffsetX != null && draft.anchorOffsetY != null) {
    return Offset(
      rect.center.dx + (draft.anchorOffsetX! * canvasSize.width),
      rect.center.dy + (draft.anchorOffsetY! * canvasSize.height),
    );
  }
  final labelCenter = draftLabelCenter(draft, canvasSize);
  return pointOnRotatedRectBoundaryToward(
    rect: rect,
    rotation: draft.rotation,
    targetPoint: labelCenter,
  );
}

/// Νέες διαστάσεις πλαισίου ετικέτας από σύρσιμο γωνίας· συμμετρικά γύρω από
/// το κέντρο, με ελάχιστο πλάτος ώστε να χωρά η μεγαλύτερη λέξη.
DraftDepartmentShape resizeLabelBoxFromHandle({
  required DraftDepartmentShape startDraft,
  required EditHandleType handle,
  required Offset localPositionCanvas,
  required Size canvasSize,
  required double sheetRotationRad,
  required String labelText,
}) {
  final minWidth = computeMinMapLabelBoxWidthForText(labelText);
  final sheetCenter = Offset(canvasSize.width / 2, canvasSize.height / 2);
  final labelCenter = rotateAroundCenter(
    draftLabelCenter(startDraft, canvasSize),
    sheetCenter,
    sheetRotationRad,
  );
  var newW = startDraft.labelWidth;
  var newH = startDraft.labelHeight;
  switch (handle) {
    case EditHandleType.labelBoxTopLeft:
      newW = math.max(minWidth, 2 * (labelCenter.dx - localPositionCanvas.dx));
      newH = math.max(
        kBuildingMapLabelMinHeight,
        2 * (labelCenter.dy - localPositionCanvas.dy),
      );
      break;
    case EditHandleType.labelBoxTopRight:
      newW = math.max(minWidth, 2 * (localPositionCanvas.dx - labelCenter.dx));
      newH = math.max(
        kBuildingMapLabelMinHeight,
        2 * (labelCenter.dy - localPositionCanvas.dy),
      );
      break;
    case EditHandleType.labelBoxBottomLeft:
      newW = math.max(minWidth, 2 * (labelCenter.dx - localPositionCanvas.dx));
      newH = math.max(
        kBuildingMapLabelMinHeight,
        2 * (localPositionCanvas.dy - labelCenter.dy),
      );
      break;
    case EditHandleType.labelBoxBottomRight:
      newW = math.max(minWidth, 2 * (localPositionCanvas.dx - labelCenter.dx));
      newH = math.max(
        kBuildingMapLabelMinHeight,
        2 * (localPositionCanvas.dy - labelCenter.dy),
      );
      break;
    default:
      break;
  }
  return startDraft.copyWith(
    labelWidth: newW.clamp(minWidth, 2000.0),
    labelHeight: newH.clamp(kBuildingMapLabelMinHeight, 2000.0),
  );
}

/// Ποια λαβή του προσχεδίου βρίσκεται κάτω από τον δείκτη. Σειρά προτεραιότητας:
/// γωνίες πλαισίου ετικέτας, ετικέτα, άγκυρα, γωνίες σχήματος, περιστροφή,
/// εσωτερικό (μετακίνηση).
EditHandleType hitTestDraftHandle(
  DraftDepartmentShape draft,
  Offset localPosition,
  Size canvasSize,
  double sheetRotationRad,
) {
  final rect = Rect.fromLTWH(
    draft.x * canvasSize.width,
    draft.y * canvasSize.height,
    draft.width * canvasSize.width,
    draft.height * canvasSize.height,
  );
  final center = rect.center;
  final sheetCenter = Offset(canvasSize.width / 2, canvasSize.height / 2);
  final corners =
      <EditHandleType, Offset>{
        EditHandleType.topLeft: rect.topLeft,
        EditHandleType.topRight: rect.topRight,
        EditHandleType.bottomLeft: rect.bottomLeft,
        EditHandleType.bottomRight: rect.bottomRight,
      }.map((key, value) {
        final onMap = rotateAroundCenter(value, center, draft.rotation);
        return MapEntry(
          key,
          rotateAroundCenter(onMap, sheetCenter, sheetRotationRad),
        );
      });
  const handleRadius = 12.0;
  final labelCenter = rotateAroundCenter(
    draftLabelCenter(draft, canvasSize),
    sheetCenter,
    sheetRotationRad,
  );
  final halfW = draft.labelWidth / 2;
  final halfH = draft.labelHeight / 2;
  final labelBoxCorners = <EditHandleType, Offset>{
    EditHandleType.labelBoxTopLeft: labelCenter + Offset(-halfW, -halfH),
    EditHandleType.labelBoxTopRight: labelCenter + Offset(halfW, -halfH),
    EditHandleType.labelBoxBottomLeft: labelCenter + Offset(-halfW, halfH),
    EditHandleType.labelBoxBottomRight: labelCenter + Offset(halfW, halfH),
  };
  for (final entry in labelBoxCorners.entries) {
    if ((entry.value - localPosition).distance <= handleRadius) {
      return entry.key;
    }
  }
  if ((labelCenter - localPosition).distance <= handleRadius) {
    return EditHandleType.label;
  }
  final anchorPoint = rotateAroundCenter(
    draftAnchorPoint(draft, canvasSize),
    sheetCenter,
    sheetRotationRad,
  );
  if ((anchorPoint - localPosition).distance <= handleRadius) {
    return EditHandleType.anchor;
  }
  for (final entry in corners.entries) {
    if ((entry.value - localPosition).distance <= handleRadius) {
      return entry.key;
    }
  }

  final rotateHandle = rotateAroundCenter(
    rotateAroundCenter(
      Offset(rect.center.dx, rect.top - 24),
      center,
      draft.rotation,
    ),
    sheetCenter,
    sheetRotationRad,
  );
  if ((rotateHandle - localPosition).distance <= 14) {
    return EditHandleType.rotate;
  }

  final unrotatedLocal = inverseRotateAroundCenter(
    localPosition,
    canvasSize,
    sheetRotationRad,
  );
  final normalizedPoint = Offset(
    (unrotatedLocal.dx / canvasSize.width).clamp(0.0, 1.0).toDouble(),
    (unrotatedLocal.dy / canvasSize.height).clamp(0.0, 1.0).toDouble(),
  );
  final localPoint = rotateAroundCenter(
    normalizedPoint,
    draft.center,
    -draft.rotation,
  );
  if (draft.rect.contains(localPoint)) {
    return EditHandleType.move;
  }
  return EditHandleType.none;
}

/// Αλλαγή μεγέθους σχήματος από γωνία· η απέναντι γωνία μένει σταθερή.
DraftDepartmentShape resizeDraftFromHandle({
  required DraftDepartmentShape startDraft,
  required EditHandleType handle,
  required Offset currentNormalized,
}) {
  final startRect = startDraft.rect;
  final center = startDraft.center;
  final currentLocal = rotateAroundCenter(
    currentNormalized,
    center,
    -startDraft.rotation,
  );
  const minEdge = kBuildingMapMinDraftSize;

  double left = startRect.left;
  double top = startRect.top;
  double right = startRect.right;
  double bottom = startRect.bottom;

  switch (handle) {
    case EditHandleType.topLeft:
      left = math.min(currentLocal.dx, right - minEdge);
      top = math.min(currentLocal.dy, bottom - minEdge);
      break;
    case EditHandleType.topRight:
      right = math.max(currentLocal.dx, left + minEdge);
      top = math.min(currentLocal.dy, bottom - minEdge);
      break;
    case EditHandleType.bottomLeft:
      left = math.min(currentLocal.dx, right - minEdge);
      bottom = math.max(currentLocal.dy, top + minEdge);
      break;
    case EditHandleType.bottomRight:
      right = math.max(currentLocal.dx, left + minEdge);
      bottom = math.max(currentLocal.dy, top + minEdge);
      break;
    case EditHandleType.none:
    case EditHandleType.rotate:
    case EditHandleType.move:
    case EditHandleType.label:
    case EditHandleType.anchor:
    case EditHandleType.labelBoxTopLeft:
    case EditHandleType.labelBoxTopRight:
    case EditHandleType.labelBoxBottomLeft:
    case EditHandleType.labelBoxBottomRight:
      break;
  }

  return startDraft.copyWith(
    x: left.clamp(0.0, 1.0).toDouble(),
    y: top.clamp(0.0, 1.0).toDouble(),
    width: (right - left).clamp(minEdge, 1.0).toDouble(),
    height: (bottom - top).clamp(minEdge, 1.0).toDouble(),
  );
}

/// Νέο προσχέδιο όταν σύρεται λαβή σχήματος, ετικέτας, άγκυρας ή περιστροφής.
///
/// Επιστρέφει null για τις γωνίες του πλαισίου ετικέτας (αυτές τις χειρίζεται
/// ο ελεγκτής, γιατί χρειάζονται το κείμενο της ετικέτας) και για το [EditHandleType.none].
DraftDepartmentShape? dragDraftWithHandle({
  required DraftDepartmentShape startDraft,
  required EditHandleType handle,
  required Offset pointerStartNormalized,
  required Offset currentNormalized,
}) {
  switch (handle) {
    case EditHandleType.move:
      final delta = currentNormalized - pointerStartNormalized;
      final newX = (startDraft.x + delta.dx)
          .clamp(0.0, 1.0 - startDraft.width)
          .toDouble();
      final newY = (startDraft.y + delta.dy)
          .clamp(0.0, 1.0 - startDraft.height)
          .toDouble();
      // Διατηρούμε σταθερή την απόλυτη θέση ετικέτας στον καμβά: offset − εφαρμοσμένη μετατόπιση.
      final appliedDx = newX - startDraft.x;
      final appliedDy = newY - startDraft.y;
      return startDraft.copyWith(
        x: newX,
        y: newY,
        labelOffsetX: ((startDraft.labelOffsetX ?? 0) - appliedDx).clamp(
          -4.0,
          4.0,
        ),
        labelOffsetY: ((startDraft.labelOffsetY ?? 0) - appliedDy).clamp(
          -4.0,
          4.0,
        ),
      );
    case EditHandleType.label:
      final centerX = startDraft.x + (startDraft.width / 2);
      final centerY = startDraft.y + (startDraft.height / 2);
      return startDraft.copyWith(
        labelOffsetX: (currentNormalized.dx - centerX)
            .clamp(-1.0, 1.0)
            .toDouble(),
        labelOffsetY: (currentNormalized.dy - centerY)
            .clamp(-1.0, 1.0)
            .toDouble(),
      );
    case EditHandleType.anchor:
      final centerX = startDraft.x + (startDraft.width / 2);
      final centerY = startDraft.y + (startDraft.height / 2);
      return startDraft.copyWith(
        anchorOffsetX: (currentNormalized.dx - centerX)
            .clamp(-1.0, 1.0)
            .toDouble(),
        anchorOffsetY: (currentNormalized.dy - centerY)
            .clamp(-1.0, 1.0)
            .toDouble(),
      );
    case EditHandleType.rotate:
      final center = startDraft.center;
      final startAngle = math.atan2(
        pointerStartNormalized.dy - center.dy,
        pointerStartNormalized.dx - center.dx,
      );
      final currentAngle = math.atan2(
        currentNormalized.dy - center.dy,
        currentNormalized.dx - center.dx,
      );
      return startDraft.copyWith(
        rotation: startDraft.rotation + (currentAngle - startAngle),
      );
    case EditHandleType.topLeft:
    case EditHandleType.topRight:
    case EditHandleType.bottomLeft:
    case EditHandleType.bottomRight:
      return resizeDraftFromHandle(
        startDraft: startDraft,
        handle: handle,
        currentNormalized: currentNormalized,
      );
    case EditHandleType.labelBoxTopLeft:
    case EditHandleType.labelBoxTopRight:
    case EditHandleType.labelBoxBottomLeft:
    case EditHandleType.labelBoxBottomRight:
    case EditHandleType.none:
      return null;
  }
}

/// Σημείο του καμβά (με περιστραμμένο φύλλο) σε normalized [0,1]².
Offset localToNormalized(
  Offset localInImageStack,
  Size box,
  double rotationRad,
) {
  final inv = inverseRotateAroundCenter(localInImageStack, box, rotationRad);
  final nx = (inv.dx / box.width).clamp(0.0, 1.0).toDouble();
  final ny = (inv.dy / box.height).clamp(0.0, 1.0).toDouble();
  return Offset(nx, ny);
}

/// True όταν το normalized σημείο βρίσκεται μέσα στο (περιστραμμένο) σχήμα τμήματος.
bool pointInsideDepartmentRect({
  required Offset pointNormalized,
  required DraftDepartmentShape departmentShape,
}) {
  final localPoint = rotateAroundCenter(
    pointNormalized,
    departmentShape.center,
    -departmentShape.rotation,
  );
  return departmentShape.rect.contains(localPoint);
}
