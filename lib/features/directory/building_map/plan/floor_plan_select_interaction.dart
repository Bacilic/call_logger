import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import '../../../../core/models/floor_plan_element.dart';
import 'floor_plan_editor_controller.dart';
import 'floor_plan_objects.dart';
import 'floor_plan_selection.dart';
import 'floor_plan_view_transform.dart';

enum _SelectMode { none, rect, move, moveObject, rotate, label, resize }

/// Η συμπεριφορά του εργαλείου «Επιλογή» με το ποντίκι:
///
/// - κλικ σε στοιχείο → επιλογή μόνο αυτού· Ctrl+κλικ → προσθήκη/αφαίρεση·
/// - κλικ στο κενό → καμία επιλογή·
/// - σύρσιμο από το κενό → ορθογώνιο επιλογής (ό,τι χωρά ολόκληρο)·
/// - σύρσιμο από στοιχείο → μετακίνηση όλης της επιλογής·
/// - σύρσιμο της λαβής πάνω από την επιλογή → περιστροφή, ανά 15° (Shift:
///   ελεύθερα)·
/// - σύρσιμο του ονόματος ενός χώρου → μετακίνηση μόνο του ονόματος· ο χώρος
///   μένει όπου ήταν·
/// - σύρσιμο μιας γωνίας του μόνου επιλεγμένου επίπλου → αλλαγή μεγέθους, με
///   την απέναντι γωνία ακίνητη.
///
/// Τα αντικείμενα πιάνονται πρώτα, πριν από τα στοιχεία του σχεδίου, και
/// πιάνονται **και με κλειδωμένο σχέδιο**.
///
/// Κάθε σύρσιμο γράφεται ως **μία** κίνηση όταν αφήσετε το ποντίκι.
class FloorPlanSelectInteraction {
  FloorPlanSelectInteraction(this.controller, {this.roomLabelAt});

  final FloorPlanEditorController controller;

  /// Ο χώρος του οποίου το όνομα βρίσκεται στο σημείο της οθόνης· `null` όταν
  /// εκεί δεν υπάρχει όνομα χώρου.
  final int? Function(Offset screen, FloorPlanViewTransform view)? roomLabelAt;
  Offset _labelStart = Offset.zero;

  static const double handleDistancePixels = 30;
  static const double handleRadiusPixels = 10;
  static const double pickPixels = 10;

  _SelectMode _mode = _SelectMode.none;
  Offset? _downWorld;
  Offset? _downScreen;
  FloorPlanElement? _hit;
  FloorPlanObjectView? _hitObject;
  int _resizeCorner = 0;
  Rect? _rectScreen;
  Offset? _rotateCenterWorld;
  Offset? _rotateCenterScreen;

  /// Το ορθογώνιο που σύρεται, για να ζωγραφιστεί.
  Rect? get selectionRectScreen => _rectScreen;

  /// Το στοιχείο που πατήθηκε τελευταίο — για το διπλό κλικ.
  FloorPlanElement? get lastHit => _hit;

  /// Το αντικείμενο που πατήθηκε τελευταίο — για το διπλό κλικ.
  FloorPlanObjectView? get lastHitObject => _hitObject;

  /// Το πλαίσιο της επιλογής στην οθόνη· `null` χωρίς επιλογή.
  Rect? selectionFrame(FloorPlanViewTransform view) {
    final ids = controller.selectedIds;
    if (!controller.hasSelection) return null;
    final walls = {
      for (final e in controller.elements)
        if (e.kind == FloorPlanElementKind.wall) e.id: e,
    };
    Rect? frame;
    void include(Offset p) {
      final s = view.toScreen(p);
      final r = Rect.fromLTWH(s.dx, s.dy, 0, 0);
      frame = frame == null ? r : frame!.expandToInclude(r);
    }

    for (final e in controller.elements) {
      if (!ids.contains(e.id)) continue;
      elementWorldPoints(e, walls).forEach(include);
    }
    for (final o in controller.objectViews) {
      if (controller.isItemSelected(o)) o.corners.forEach(include);
    }
    return frame;
  }

  /// Το έπιπλο που αλλάζει μέγεθος από τις γωνίες του: μόνο όταν είναι το
  /// μόνο επιλεγμένο.
  FloorPlanObjectView? _resizable() {
    if (controller.selectedIds.isNotEmpty ||
        controller.selectedPlacementIds.isNotEmpty) {
      return null;
    }
    final ids = controller.selectedObjectIds;
    if (ids.length != 1) return null;
    for (final o in controller.objectViews) {
      if (o.source == FloorPlanItemSource.object && o.id == ids.single) {
        return o.isVolume ? o : null;
      }
    }
    return null;
  }

  /// Οι λαβές μεγέθους στις γωνίες του επίπλου, σε pixel οθόνης· κενό όταν
  /// η επιλογή δεν είναι ένα έπιπλο.
  List<Offset> resizeHandles(FloorPlanViewTransform view) {
    final volume = _resizable();
    if (volume == null) return const [];
    return [for (final c in volume.corners) view.toScreen(c)];
  }

  /// Η λαβή περιστροφής, πάνω από το πλαίσιο.
  Offset? rotationHandle(FloorPlanViewTransform view) {
    final frame = selectionFrame(view);
    if (frame == null) return null;
    return Offset(frame.center.dx, frame.top - handleDistancePixels);
  }

  void down(Offset screen, FloorPlanViewTransform view) {
    _downScreen = screen;
    _downWorld = view.toWorld(screen);
    _rectScreen = null;

    _hit = null;
    _hitObject = null;
    final handle = rotationHandle(view);
    if (handle != null && (handle - screen).distance <= handleRadiusPixels) {
      final frame = selectionFrame(view)!;
      _mode = _SelectMode.rotate;
      _rotateCenterScreen = frame.center;
      _rotateCenterWorld = view.toWorld(frame.center);
      return;
    }

    final corners = resizeHandles(view);
    for (var i = 0; i < corners.length; i++) {
      if ((corners[i] - screen).distance <= handleRadiusPixels) {
        _mode = _SelectMode.resize;
        _resizeCorner = i;
        _hitObject = _resizable();
        return;
      }
    }

    final labelRoom = controller.locked
        ? null
        : roomLabelAt?.call(screen, view);
    final labelHit = labelRoom == null
        ? null
        : controller.elementById(labelRoom);
    if (labelHit != null) {
      _mode = _SelectMode.label;
      _hit = labelHit;
      _labelStart = labelHit.labelOffset ?? Offset.zero;
      return;
    }

    // Ό,τι δεν φαίνεται σε αυτό το ζουμ δεν πιάνεται.
    final object = hitTestFloorPlanObject(
      _downWorld!,
      floorPlanObjectsAtZoom(controller.objectViews, view.pixelsPerCm),
    );
    if (object != null) {
      _hitObject = object;
      _mode = _SelectMode.moveObject;
      return;
    }

    _hit = controller.locked
        ? null
        : hitTestElement(
            _downWorld!,
            controller.elements,
            view.screenToCm(pickPixels),
          );
    _mode = _hit == null ? _SelectMode.rect : _SelectMode.move;
  }

  void move(
    Offset screen,
    FloorPlanViewTransform view, {
    required bool dragged,
    required bool freeAngle,
  }) {
    if (!dragged) return;
    switch (_mode) {
      case _SelectMode.rect:
        _rectScreen = Rect.fromPoints(_downScreen!, screen);
      case _SelectMode.move:
        final hit = _hit!;
        // Σύρσιμο από στοιχείο εκτός επιλογής: η επιλογή γίνεται αυτό.
        if (!controller.selectedIds.contains(hit.id)) {
          controller.select(hit.id);
        }
        controller.previewMove(view.toWorld(screen) - _downWorld!);
      case _SelectMode.moveObject:
        final hit = _hitObject!;
        if (!controller.isItemSelected(hit)) controller.selectItem(hit);
        controller.previewMove(view.toWorld(screen) - _downWorld!);
      case _SelectMode.resize:
        final volume = _hitObject;
        if (volume != null) {
          controller.previewResize(
            volume.id,
            _resizeCorner,
            view.toWorld(screen),
          );
        }
      case _SelectMode.label:
        controller.previewRoomLabel(
          _hit!.id,
          _labelStart + view.toWorld(screen) - _downWorld!,
        );
      case _SelectMode.rotate:
        final center = _rotateCenterScreen!;
        double angleOf(Offset p) =>
            math.atan2(p.dy - center.dy, p.dx - center.dx);
        var angle = angleOf(screen) - angleOf(_downScreen!);
        if (!freeAngle) angle = snapRadians(angle);
        controller.previewRotate(_rotateCenterWorld!, angle);
      case _SelectMode.none:
        break;
    }
  }

  Future<void> up(
    Offset screen,
    FloorPlanViewTransform view, {
    required bool dragged,
    required bool additive,
  }) async {
    final mode = _mode;
    _mode = _SelectMode.none;
    final rect = _rectScreen;
    _rectScreen = null;
    switch (mode) {
      case _SelectMode.rect:
        if (!dragged || rect == null) {
          if (!additive) controller.select(null);
          return;
        }
        // Μέτρηση στην οθόνη: σε περιστραμμένο όροφο το ορθογώνιο που
        // βλέπει ο χρήστης δεν είναι ορθογώνιο του σχεδίου.
        bool contains(Offset p) => rect.contains(view.toScreen(p));
        final inside = elementsInside(contains, controller.elements);
        final views = controller.objectViews;
        Set<int> insideOf(FloorPlanItemSource source) =>
            floorPlanObjectsInside(contains, [
              for (final v in views)
                if (v.source == source) v,
            ]);
        final objectsInside = insideOf(FloorPlanItemSource.object);
        final placementsInside = insideOf(FloorPlanItemSource.placement);
        controller.selectMany(
          additive ? {...controller.selectedIds, ...inside} : inside,
          objects: additive
              ? {...controller.selectedObjectIds, ...objectsInside}
              : objectsInside,
          placements: additive
              ? {...controller.selectedPlacementIds, ...placementsInside}
              : placementsInside,
        );
      case _SelectMode.move:
        if (dragged) {
          await controller.commitPreview();
          return;
        }
        final hit = _hit!;
        if (additive) {
          controller.toggleSelected(hit.id);
        } else {
          controller.select(hit.id);
        }
      case _SelectMode.moveObject:
        if (dragged) {
          // Αντικείμενο που αφέθηκε πάνω σε καμπίνα μπαίνει μέσα της.
          await controller.commitPreview(dropIntoCabinets: true);
          return;
        }
        final hit = _hitObject!;
        if (additive) {
          controller.toggleSelectedItem(hit);
        } else {
          controller.selectItem(hit);
        }
      case _SelectMode.label:
        if (dragged) await controller.commitPreview();
        controller.select(_hit!.id);
      case _SelectMode.rotate:
      case _SelectMode.resize:
        if (dragged) await controller.commitPreview();
      case _SelectMode.none:
        break;
    }
  }

  void cancel() {
    _mode = _SelectMode.none;
    _rectScreen = null;
    controller.cancelPreview();
  }
}
