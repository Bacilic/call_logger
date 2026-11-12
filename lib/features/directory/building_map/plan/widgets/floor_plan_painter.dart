import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../../core/models/floor_plan_element.dart';
import '../../../../../core/models/floor_plan_state.dart';
import '../floor_plan_geometry.dart';
import '../floor_plan_objects.dart';
import '../floor_plan_rooms.dart';
import '../floor_plan_selection.dart';
import '../floor_plan_view_transform.dart';
import 'floor_plan_symbol_painter.dart';

/// Ένας χώρος έτοιμος για σχεδίαση: γωνίες, όνομα, χρώμα.
class FloorPlanRoomView {
  const FloorPlanRoomView({
    required this.id,
    required this.corners,
    required this.label,
    this.color,
    this.labelOffset,
    this.labelSizeCm = kFloorPlanDefaultRoomLabelSizeCm,
  });

  final int id;
  final List<Offset> corners;
  final String label;

  /// Πόσο έχει μετακινηθεί το όνομα από το κέντρο του χώρου· `null` = κέντρο.
  final Offset? labelOffset;

  /// Το μέγεθος των γραμμάτων του ονόματος, σε εκατοστά πραγματικού χώρου.
  final double labelSizeCm;

  /// Πού στέκεται το κέντρο του ονόματος, σε συντεταγμένες σχεδίου.
  Offset get labelCenter =>
      polygonLabelPoint(corners) + (labelOffset ?? Offset.zero);

  /// Το όνομα βγήκε έξω από τον χώρο: θέλει γραμμή-οδηγό προς αυτόν.
  bool get labelOutside =>
      labelOffset != null && !polygonContains(corners, labelCenter);

  /// Το χρώμα του τμήματος· `null` για χώρο με ελεύθερο όνομα.
  final Color? color;
}

/// Ό,τι σχεδιάζεται «στον αέρα», πάνω από το αποθηκευμένο σχέδιο: το κομμάτι
/// τοίχου που ακολουθεί τον δείκτη, το άνοιγμα που σύρεται, η γραμμή
/// βαθμονόμησης.
class FloorPlanOverlay {
  const FloorPlanOverlay({
    this.rubberStart,
    this.rubberEnd,
    this.snapPoint,
    this.snapKind = FloorPlanSnapKind.none,
    this.openingWall,
    this.openingRange,
    this.measureStart,
    this.measureEnd,
    this.roomCorners = const [],
    this.dimensionDraft,
    this.selectionRectScreen,
    this.rotationHandleScreen,
    this.selectionFrameScreen,
    this.resizeHandlesScreen = const [],
    this.volumeDraft = const [],
    this.lengthStart,
    this.lengthEnd,
    this.rubberThickness = kFloorPlanWallThicknessCm,
    this.guideLines = const [],
    this.angleMarks = const [],
  });

  final Offset? rubberStart;
  final Offset? rubberEnd;

  /// Το πάχος του τοίχου που σχεδιάζεται τώρα.
  final double rubberThickness;

  /// Οι γραμμές-οδηγοί πάνω στις οποίες κούμπωσε το σημείο: από την άκρη
  /// του τοίχου που τις δίνει ως το σημείο.
  final List<(Offset, Offset)> guideLines;

  /// Οι μοίρες τομής του τοίχου που σχεδιάζεται ή είναι επιλεγμένος.
  final List<FloorPlanAngleMark> angleMarks;
  final Offset? snapPoint;
  final FloorPlanSnapKind snapKind;
  final FloorPlanSegment? openingWall;
  final ({double start, double end})? openingRange;
  final Offset? measureStart;
  final Offset? measureEnd;

  /// Οι γωνίες του χώρου που σχεδιάζεται με κλικ.
  final List<Offset> roomCorners;

  /// Η διάσταση που σχεδιάζεται: άκρα και σημείο απόστασης.
  final List<Offset>? dimensionDraft;

  /// Το ορθογώνιο επιλογής που σύρεται, σε pixel οθόνης.
  final Rect? selectionRectScreen;

  /// Η λαβή περιστροφής της επιλογής, σε pixel οθόνης.
  final Offset? rotationHandleScreen;

  /// Το πλαίσιο γύρω από την επιλογή, σε pixel οθόνης.
  final Rect? selectionFrameScreen;

  /// Οι λαβές μεγέθους στις γωνίες του επιλεγμένου επίπλου, σε pixel οθόνης.
  final List<Offset> resizeHandlesScreen;

  /// Οι γωνίες του επίπλου που σχεδιάζεται τώρα, σε συντεταγμένες σχεδίου.
  final List<Offset> volumeDraft;

  /// Τα άκρα του τοίχου του οποίου το μήκος αλλάζει τώρα — για να φαίνεται
  /// το μήκος του όσο σύρεται η άκρη.
  final Offset? lengthStart;
  final Offset? lengthEnd;
}

/// Οι ετικέτες των αντικειμένων, μορφοποιημένες **μία φορά** σε σταθερό
/// μέγεθος και ζωγραφισμένες με κλίμακα. Χωρίς αυτό, 1.500 ετικέτες
/// ξαναμορφοποιούνταν σε κάθε καρέ ενός συρσίματος — μετρημένο, το βαρύτερο
/// κομμάτι της ζωγραφικής του ορόφου.
///
/// Την κρατά όποιος ζει περισσότερο από ένα καρέ (η οθόνη σχεδίασης, ο
/// χάρτης) και την κλείνει με [dispose].
class FloorPlanLabelCache {
  static const double baseFontPx = 20;
  static const int _maxEntries = 4000;

  final Map<(String, bool), TextPainter> _painters = {};

  /// Η ετικέτα [label] μορφοποιημένη στα [baseFontPx]· [onPaper] = με λευκό
  /// φόντο (σύμβολα), αλλιώς χωρίς (έπιπλα).
  TextPainter painterFor(String label, {required bool onPaper}) {
    final key = (label, onPaper);
    final existing = _painters[key];
    if (existing != null) return existing;
    if (_painters.length >= _maxEntries) clear();
    return _painters[key] = _layoutObjectLabel(
      label,
      fontPx: baseFontPx,
      onPaper: onPaper,
    );
  }

  void clear() {
    for (final p in _painters.values) {
      p.dispose();
    }
    _painters.clear();
  }

  void dispose() => clear();
}

TextPainter _layoutObjectLabel(
  String label, {
  required double fontPx,
  required bool onPaper,
}) => TextPainter(
  text: TextSpan(
    text: label,
    style: TextStyle(
      fontSize: fontPx,
      color: Colors.black87,
      fontWeight: FontWeight.w500,
      backgroundColor: onPaper ? const Color(0xCCFFFFFF) : null,
    ),
  ),
  textDirection: TextDirection.ltr,
  maxLines: 1,
  ellipsis: '…',
)..layout(maxWidth: fontPx * 16);

class FloorPlanPainter extends CustomPainter {
  FloorPlanPainter({
    required this.view,
    required this.walls,
    required this.openingsByWall,
    required this.rooms,
    required this.texts,
    required this.dimensions,
    required this.state,
    required this.patternImage,
    required this.gridVisible,
    required this.selectedIds,
    required this.openingSegments,
    required this.overlay,
    required this.colors,
    this.labelScale = 1,
    this.objects = const [],
    this.selectedObjectIds = const {},
    this.selectedPlacementIds = const {},
    this.labelCache,
  });

  final FloorPlanViewTransform view;
  final List<FloorPlanSegment> walls;
  final Map<int, List<({double start, double end})>> openingsByWall;
  final List<FloorPlanRoomView> rooms;
  final List<FloorPlanElement> texts;
  final List<FloorPlanElement> dimensions;
  final FloorPlanState state;
  final ui.Image? patternImage;
  final bool gridVisible;
  final Set<int> selectedIds;

  /// Τα ανοίγματα ως τμήματα πάνω στους τοίχους, για την επισήμανσή τους.
  final Map<int, FloorPlanSegment> openingSegments;
  final FloorPlanOverlay overlay;
  final ColorScheme colors;

  /// Μεγέθυνση των ονομάτων χώρων και των μηκών — για την εξαγωγή σε μεγάλη
  /// εικόνα, όπου τα 12 pixel της οθόνης θα έβγαιναν ψιλά γράμματα.
  final double labelScale;

  /// Τα αντικείμενα του χάρτη, τα έπιπλα πρώτα.
  final List<FloorPlanObjectView> objects;
  final Set<int> selectedObjectIds;

  /// Οι θέσεις του Καταλόγου που είναι επιλεγμένες.
  final Set<int> selectedPlacementIds;

  bool _isSelected(FloorPlanObjectView o) =>
      (o.source == FloorPlanItemSource.object
              ? selectedObjectIds
              : selectedPlacementIds)
          .contains(o.id);

  /// Ετικέτες έτοιμες από προηγούμενα καρέ· χωρίς αυτήν μορφοποιούνται κάθε
  /// φορά (εξαγωγή, μία μόνο ζωγραφική).
  final FloorPlanLabelCache? labelCache;

  /// Ό,τι φαίνεται στην οθόνη, σε συντεταγμένες σχεδίου — τα αντικείμενα
  /// έξω από αυτό δεν ζωγραφίζονται (ένας όροφος έχει ως 1.500).
  Rect _visibleWorld = Rect.largest;
  Size _size = Size.zero;

  bool _onScreen(FloorPlanObjectView o) =>
      _visibleWorld.inflate(o.size.longestSide).contains(o.center);

  @override
  void paint(Canvas canvas, Size size) {
    _size = size;
    final corners = [
      view.toWorld(Offset.zero),
      view.toWorld(Offset(size.width, 0)),
      view.toWorld(Offset(0, size.height)),
      view.toWorld(Offset(size.width, size.height)),
    ];
    _visibleWorld = Rect.fromLTRB(
      corners.map((p) => p.dx).reduce(math.min),
      corners.map((p) => p.dy).reduce(math.min),
      corners.map((p) => p.dx).reduce(math.max),
      corners.map((p) => p.dy).reduce(math.max),
    );
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    // Όλα μένουν μέσα στον καμβά — και τα ονόματα που ζωγραφίζονται σε
    // συντεταγμένες οθόνης: αλλιώς ένα όνομα κοντά στην άκρη βγαίνει πάνω
    // στο διπλανό πάνελ.
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    view.applyTo(canvas);
    final pixel = 1 / view.pixelsPerCm;

    _paintPattern(canvas);
    if (gridVisible) _paintGrid(canvas, size, pixel);
    _paintRooms(canvas, pixel);
    _paintVolumes(canvas, pixel);
    _paintWalls(canvas, pixel);
    _paintSelectedOpenings(canvas, pixel);
    _paintTexts(canvas, pixel);
    _paintDimensions(canvas, pixel);
    _paintSymbols(canvas, pixel);
    _paintVolumeDraft(canvas, pixel);
    _paintRoomDraft(canvas, pixel);
    _paintDimensionDraft(canvas, pixel);
    _paintOpeningDraft(canvas, pixel);
    _paintRubberBand(canvas, pixel);
    _paintMeasure(canvas, pixel);
    _paintGuides(canvas, pixel);
    _paintAngleArcs(canvas, pixel);
    _paintSnap(canvas, pixel);
    canvas.restore();

    _paintRoomLabels(canvas);
    _paintObjectLabels(canvas);
    _paintDimensionLabels(canvas);
    _paintRubberLength(canvas);
    _paintAngleLabels(canvas);
    _paintSelectionChrome(canvas);
    canvas.restore();
  }

  /// Τα έπιπλα και οι καμπίνες: παραλληλόγραμμα με τον πραγματικό τους
  /// όγκο, κάτω από τους τοίχους και ό,τι κάθεται πάνω τους. Η καμπίνα
  /// ξεχωρίζει με το σύμβολο του rack στη μέση, όταν χωρά.
  void _paintVolumes(Canvas canvas, double pixel) {
    final fill = Paint()..color = const Color(0xFFFAC775);
    final cabinetFill = Paint()..color = const Color(0xFFF1EFE8);
    final width = math.max(1.5 * pixel, 1.0);
    final line = Paint()
      ..color = const Color(0xFF854F0B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    final cabinetLine = Paint()
      ..color = const Color(0xFF444441)
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    final symbolsVisible = floorPlanSymbolsVisible(view.pixelsPerCm);
    for (final o in objects) {
      if (!o.isVolume || !_onScreen(o)) continue;
      final path = Path()..addPolygon(o.corners, true);
      final cabinet = o.isCabinet;
      canvas
        ..drawPath(path, cabinet ? cabinetFill : fill)
        ..drawPath(path, cabinet ? cabinetLine : line);
      if (cabinet && symbolsVisible) {
        final side = math.min(
          o.size.shortestSide * 0.8,
          kFloorPlanSymbolSizeCm,
        );
        canvas.save();
        canvas.translate(o.center.dx, o.center.dy);
        canvas.rotate(o.rotationDegrees * math.pi / 180);
        paintFloorPlanSymbol(
          canvas,
          o.symbol,
          Rect.fromCenter(center: Offset.zero, width: side, height: side),
        );
        canvas.restore();
      }
      if (_isSelected(o)) {
        _paintObjectSelection(canvas, o, pixel);
      }
    }
  }

  /// Τα σύμβολα (εκτυπωτής…), με μέγεθος σχεδίου· όταν θα έβγαιναν μικρότερα
  /// από [_kMinSymbolPx] κρύβονται — από μακριά φαίνονται μόνο οι χώροι.
  void _paintSymbols(Canvas canvas, double pixel) {
    if (!floorPlanSymbolsVisible(view.pixelsPerCm)) return;
    for (final o in objects) {
      if (o.isVolume || !_onScreen(o)) continue;
      canvas.save();
      canvas.translate(o.center.dx, o.center.dy);
      canvas.rotate(o.rotationDegrees * math.pi / 180);
      paintFloorPlanSymbol(
        canvas,
        o.symbol,
        Rect.fromCenter(
          center: Offset.zero,
          width: o.size.width,
          height: o.size.height,
        ),
      );
      canvas.restore();
      if (_isSelected(o)) {
        _paintObjectSelection(canvas, o, pixel);
      }
    }
  }

  void _paintObjectSelection(
    Canvas canvas,
    FloorPlanObjectView o,
    double pixel,
  ) {
    canvas.drawPath(
      Path()..addPolygon(o.corners, true),
      Paint()
        ..color = colors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 * pixel,
    );
  }

  void _paintVolumeDraft(Canvas canvas, double pixel) {
    final corners = overlay.volumeDraft;
    if (corners.length < 4) return;
    final path = Path()..addPolygon(corners, true);
    canvas
      ..drawPath(path, Paint()..color = const Color(0x88FAC775))
      ..drawPath(
        path,
        Paint()
          ..color = colors.tertiary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * pixel,
      );
  }

  /// Οι ετικέτες των αντικειμένων, **πάντα όρθιες** όπως τα ονόματα χώρων,
  /// με μέγεθος σχεδίου. Του επίπλου στη μέση του, των συμβόλων από κάτω.
  void _paintObjectLabels(Canvas canvas) {
    final fontPx = kFloorPlanObjectLabelSizeCm * view.pixelsPerCm * labelScale;
    if (fontPx < _kMinObjectLabelPx) return;
    final symbolsVisible = floorPlanSymbolsVisible(view.pixelsPerCm);
    final screen = (Offset.zero & _size).inflate(fontPx * 16);
    for (final o in objects) {
      if (o.label.isEmpty) continue;
      if (!o.isVolume && !symbolsVisible) continue;
      if (!screen.contains(view.toScreen(o.center))) continue;
      final cache = labelCache;
      final onPaper = !o.isVolume;
      final text = cache == null
          ? _layoutObjectLabel(o.label, fontPx: fontPx, onPaper: onPaper)
          : cache.painterFor(o.label, onPaper: onPaper);
      final scale = cache == null
          ? 1.0
          : fontPx / FloorPlanLabelCache.baseFontPx;
      final width = text.width * scale;
      final height = text.height * scale;
      final center = view.toScreen(o.center);
      // Της καμπίνας κάτω από το σύμβολο του rack, όταν αυτό φαίνεται.
      final below = o.isCabinet && symbolsVisible
          ? math.min(o.size.shortestSide * 0.8, kFloorPlanSymbolSizeCm) *
                    view.pixelsPerCm /
                    2 +
                2
          : o.isVolume
          ? -height / 2
          : kFloorPlanSymbolSizeCm * view.pixelsPerCm / 2 + 2;
      canvas.save();
      canvas.translate(center.dx - width / 2, center.dy + below);
      canvas.scale(scale);
      text.paint(canvas, Offset.zero);
      canvas.restore();
      if (cache == null) text.dispose();
    }
  }

  void _paintSelectedOpenings(Canvas canvas, double pixel) {
    for (final entry in openingSegments.entries) {
      if (!selectedIds.contains(entry.key)) continue;
      final paint = Paint()
        ..color = colors.primary.withValues(alpha: 0.7)
        ..strokeWidth = entry.value.thickness + 6 * pixel;
      canvas.drawLine(entry.value.a, entry.value.b, paint);
    }
  }

  /// Το ελεύθερο κείμενο **γυρίζει μαζί με το σχέδιο**, σε αντίθεση με τα
  /// ονόματα χώρων: τοποθετήθηκε με συγκεκριμένη κλίση.
  void _paintTexts(Canvas canvas, double pixel) {
    for (final t in texts) {
      final size = t.fontSize ?? kFloorPlanDefaultTextSizeCm;
      final painter = TextPainter(
        text: TextSpan(
          text: t.name ?? '',
          style: TextStyle(fontSize: size, color: Colors.black87),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();
      canvas.save();
      canvas.translate(t.points.first.dx, t.points.first.dy);
      canvas.rotate(t.rotationDegrees * math.pi / 180);
      painter
        ..paint(canvas, Offset(-painter.width / 2, -painter.height / 2))
        ..dispose();
      canvas.restore();
      if (selectedIds.contains(t.id)) {
        final corners = textBoxCorners(t);
        canvas.drawPath(
          Path()..addPolygon(corners, true),
          Paint()
            ..color = colors.primary
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 * pixel,
        );
      }
    }
  }

  void _paintDimensions(Canvas canvas, double pixel) {
    for (final d in dimensions) {
      _paintDimensionGeometry(
        canvas,
        pixel,
        d.points,
        selectedIds.contains(d.id) ? colors.primary : const Color(0xFF1565C0),
      );
    }
  }

  void _paintDimensionDraft(Canvas canvas, double pixel) {
    final draft = overlay.dimensionDraft;
    if (draft == null || draft.length < 2) return;
    _paintDimensionGeometry(canvas, pixel, draft, colors.tertiary);
  }

  /// Γραμμές βοήθειας από τα άκρα ως τη γραμμή διάστασης, η ίδια η γραμμή,
  /// και μικρές πλάγιες γραμμούλες στις άκρες της.
  void _paintDimensionGeometry(
    Canvas canvas,
    double pixel,
    List<Offset> points,
    Color color,
  ) {
    final line = dimensionLine(
      FloorPlanElement(
        id: 0,
        floorId: 0,
        kind: FloorPlanElementKind.dimension,
        points: points,
      ),
    );
    if (line == null) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5 * pixel;
    canvas.drawLine(points[0], line.a, paint);
    canvas.drawLine(points[1], line.b, paint);
    canvas.drawLine(line.a, line.b, paint);
    final d = line.b - line.a;
    final len = d.distance;
    if (len == 0) return;
    final tick = Offset(d.dx - d.dy, d.dy + d.dx) / len * (5 * pixel);
    for (final end in [line.a, line.b]) {
      canvas.drawLine(end - tick, end + tick, paint);
    }
  }

  /// Το μήκος πάνω σε κάθε διάσταση, κατά μήκος της γραμμής αλλά ποτέ
  /// ανάποδα.
  void _paintDimensionLabels(Canvas canvas) {
    final all = [for (final d in dimensions) d.points, ?overlay.dimensionDraft];
    for (final points in all) {
      if (points.length < 2) continue;
      final line = dimensionLine(
        FloorPlanElement(
          id: 0,
          floorId: 0,
          kind: FloorPlanElementKind.dimension,
          points: points,
        ),
      );
      if (line == null) continue;
      final length = (points[1] - points[0]).distance;
      if (length < 1) continue;
      final a = view.toScreen(line.a);
      final b = view.toScreen(line.b);
      var angle = math.atan2(b.dy - a.dy, b.dx - a.dx);
      if (angle > math.pi / 2) angle -= math.pi;
      if (angle < -math.pi / 2) angle += math.pi;
      final text = TextPainter(
        text: TextSpan(
          text: formatCmAsMeters(length),
          style: TextStyle(
            fontSize: 12 * labelScale,
            color: Color(0xFF0D47A1),
            fontWeight: FontWeight.w600,
            backgroundColor: Color(0xCCFFFFFF),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      canvas.rotate(angle);
      text
        ..paint(canvas, Offset(-text.width / 2, -text.height - 2))
        ..dispose();
      canvas.restore();
    }
  }

  /// Το ορθογώνιο επιλογής, το πλαίσιο της επιλογής και η λαβή περιστροφής.
  void _paintSelectionChrome(Canvas canvas) {
    final rect = overlay.selectionRectScreen;
    if (rect != null) {
      canvas.drawRect(
        rect,
        Paint()..color = colors.primary.withValues(alpha: 0.08),
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = colors.primary
          ..style = PaintingStyle.stroke,
      );
    }
    for (final corner in overlay.resizeHandlesScreen) {
      final box = Rect.fromCenter(center: corner, width: 10, height: 10);
      canvas
        ..drawRect(box, Paint()..color = Colors.white)
        ..drawRect(
          box,
          Paint()
            ..color = colors.primary
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
    }
    final frame = overlay.selectionFrameScreen;
    final handle = overlay.rotationHandleScreen;
    if (frame == null || handle == null) return;
    final stroke = Paint()
      ..color = colors.primary.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke;
    canvas.drawRect(frame.inflate(6), stroke);
    canvas.drawLine(Offset(frame.center.dx, frame.top - 6), handle, stroke);
    canvas.drawCircle(handle, 7, Paint()..color = Colors.white);
    canvas.drawCircle(
      handle,
      7,
      stroke
        ..color = colors.primary
        ..strokeWidth = 2,
    );
  }

  Path _polygonPath(List<Offset> corners) {
    final path = Path()..moveTo(corners.first.dx, corners.first.dy);
    for (final p in corners.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  void _paintRooms(Canvas canvas, double pixel) {
    for (final room in rooms) {
      final path = _polygonPath(room.corners);
      final base = room.color ?? const Color(0xFF9E9E9E);
      canvas.drawPath(path, Paint()..color = base.withValues(alpha: 0.22));
      if (selectedIds.contains(room.id)) {
        canvas.drawPath(
          path,
          Paint()
            ..color = colors.primary.withValues(alpha: 0.18)
            ..style = PaintingStyle.fill,
        );
        canvas.drawPath(
          path,
          Paint()
            ..color = colors.primary
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3 * pixel,
        );
      }
    }
  }

  void _paintRoomDraft(Canvas canvas, double pixel) {
    final corners = overlay.roomCorners;
    if (corners.isEmpty) return;
    final hover = overlay.snapPoint;
    final points = [...corners, ?hover];
    final line = Paint()
      ..color = colors.tertiary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * pixel;
    if (points.length >= 3) {
      canvas.drawPath(
        _polygonPath(points),
        Paint()..color = colors.tertiary.withValues(alpha: 0.15),
      );
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, line);
    for (final c in corners) {
      canvas.drawCircle(c, 4 * pixel, Paint()..color = colors.tertiary);
    }
  }

  /// Τα ονόματα των χώρων, **πάντα όρθια** στην οθόνη όπως κι αν γυρίσει ο
  /// όροφος (απόφαση Διευθυντή), με μέγεθος του σχεδίου: μεγαλώνουν και
  /// μικραίνουν με το ζουμ, όπως το ελεύθερο κείμενο. Όνομα που βγήκε έξω
  /// από τον χώρο του δένεται μαζί του με γραμμή-οδηγό.
  void _paintRoomLabels(Canvas canvas) {
    for (final room in rooms) {
      if (room.label.isEmpty) continue;
      final rect = floorPlanRoomLabelRect(room, view);
      if (rect == null) continue;
      if (room.labelOutside) {
        final target = view.toScreen(polygonLabelPoint(room.corners));
        final from = Offset(
          target.dx.clamp(rect.left, rect.right),
          target.dy.clamp(rect.top, rect.bottom),
        );
        final ink = Paint()
          ..color = Colors.black54
          ..strokeWidth = 1;
        canvas
          ..drawLine(rect.bottomLeft, rect.bottomRight, ink)
          ..drawLine(from, target, ink)
          ..drawCircle(target, 2.5, ink);
      }
      final text = _layoutRoomLabel(room, view);
      text
        ..paint(canvas, rect.topLeft)
        ..dispose();
    }
  }

  void _paintPattern(Canvas canvas) {
    final image = patternImage;
    if (image == null || state.patternHidden) return;
    canvas.save();
    canvas.translate(state.patternCenter.dx, state.patternCenter.dy);
    canvas.rotate(state.patternRotationDegrees * math.pi / 180);
    canvas.scale(state.cmPerPixel);
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..color = Color.fromRGBO(0, 0, 0, state.patternOpacity);
    canvas.drawImage(image, Offset(-image.width / 2, -image.height / 2), paint);
    canvas.restore();
  }

  void _paintGrid(Canvas canvas, Size size, double pixel) {
    final corners = [
      view.toWorld(Offset.zero),
      view.toWorld(Offset(size.width, 0)),
      view.toWorld(Offset(0, size.height)),
      view.toWorld(Offset(size.width, size.height)),
    ];
    final minX = corners.map((p) => p.dx).reduce(math.min);
    final maxX = corners.map((p) => p.dx).reduce(math.max);
    final minY = corners.map((p) => p.dy).reduce(math.min);
    final maxY = corners.map((p) => p.dy).reduce(math.max);

    final step = gridStepCm(view.pixelsPerCm);
    final major = step * 10;
    final minor = Paint()
      ..color = const Color(0x1A1565C0)
      ..strokeWidth = pixel;
    final strong = Paint()
      ..color = const Color(0x401565C0)
      ..strokeWidth = pixel;

    bool isMajor(double v) => (v / major - (v / major).round()).abs() < 1e-6;

    for (var x = (minX / step).floor() * step; x <= maxX; x += step) {
      canvas.drawLine(
        Offset(x, minY),
        Offset(x, maxY),
        isMajor(x) ? strong : minor,
      );
    }
    for (var y = (minY / step).floor() * step; y <= maxY; y += step) {
      canvas.drawLine(
        Offset(minX, y),
        Offset(maxX, y),
        isMajor(y) ? strong : minor,
      );
    }
  }

  void _paintWalls(Canvas canvas, double pixel) {
    // Ένα ευδιάκριτο ελάχιστο πάχος και στο πιο μακρινό ζουμ.
    double shown(double thickness) => math.max(thickness, 2.5 * pixel);
    // Οι τοίχοι ενώνονται σε συνεχείς γραμμές ανά πάχος: μια γραμμή
    // ζωγραφίζεται με ένα μόνο πάχος.
    final piecesByThickness = <double, List<FloorPlanSegment>>{};
    for (final w in walls) {
      (piecesByThickness[w.thickness] ??= []).addAll(
        wallPiecesWithOpenings(w, openingsByWall[w.id] ?? const []),
      );
    }
    for (final entry in piecesByThickness.entries) {
      final wallPaint = Paint()
        ..color = const Color(0xFF37474F)
        ..style = PaintingStyle.stroke
        ..strokeWidth = shown(entry.key)
        ..strokeJoin = StrokeJoin.miter
        ..strokeCap = StrokeCap.square;
      for (final chain in chainSegments(entry.value)) {
        final path = Path()..moveTo(chain.first.dx, chain.first.dy);
        for (final p in chain.skip(1)) {
          path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path, wallPaint);
      }
    }

    if (selectedIds.isEmpty) return;
    for (final w in walls) {
      if (!selectedIds.contains(w.id)) continue;
      canvas.drawLine(
        w.a,
        w.b,
        Paint()
          ..color = colors.primary.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = shown(w.thickness) + 6 * pixel
          ..strokeCap = StrokeCap.square,
      );
    }
  }

  void _paintOpeningDraft(Canvas canvas, double pixel) {
    final wall = overlay.openingWall;
    final range = overlay.openingRange;
    if (wall == null || range == null || wall.length == 0) return;
    final dir = (wall.b - wall.a) / wall.length;
    final paint = Paint()
      ..color = colors.tertiary.withValues(alpha: 0.7)
      ..strokeWidth = wall.thickness + 8 * pixel
      ..strokeCap = StrokeCap.butt;
    canvas.drawLine(
      wall.a + dir * range.start,
      wall.a + dir * range.end,
      paint,
    );
  }

  void _paintRubberBand(Canvas canvas, double pixel) {
    final a = overlay.rubberStart;
    final b = overlay.rubberEnd;
    if (a == null || b == null) return;
    final paint = Paint()
      ..color = const Color(0xA037474F)
      ..strokeWidth = math.max(overlay.rubberThickness, 2.5 * pixel)
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(a, b, paint);
  }

  void _paintMeasure(Canvas canvas, double pixel) {
    final a = overlay.measureStart;
    final b = overlay.measureEnd;
    if (a == null || b == null) return;
    final paint = Paint()
      ..color = Colors.red.shade700
      ..strokeWidth = 2 * pixel;
    canvas.drawLine(a, b, paint);
    for (final p in [a, b]) {
      canvas.drawCircle(p, 4 * pixel, paint);
    }
  }

  /// Οι γραμμές-οδηγοί: λεπτές μοβ διακεκομμένες, από την άκρη του τοίχου
  /// ως το σημείο που κούμπωσε — και λίγο πιο πέρα, για να φαίνεται η ευθεία.
  void _paintGuides(Canvas canvas, double pixel) {
    if (overlay.guideLines.isEmpty) return;
    final paint = Paint()
      ..color = const Color(0xFFAA00FF)
      ..strokeWidth = 1.6 * pixel;
    final dash = 6 * pixel;
    final gap = 4 * pixel;
    for (final (from, to) in overlay.guideLines) {
      final d = to - from;
      final length = d.distance;
      if (length == 0) continue;
      final dir = d / length;
      final total = length + 24 * pixel;
      for (var at = 0.0; at < total; at += dash + gap) {
        canvas.drawLine(
          from + dir * at,
          from + dir * math.min(at + dash, total),
          paint,
        );
      }
      canvas.drawCircle(from, 3 * pixel, paint);
    }
  }

  static const Color _guideColor = Color(0xFFAA00FF);
  static const Color _angleColor = Color(0xFF263238);

  /// Το τόξο κάθε γωνίας τομής· η ορθή σημειώνεται με τετραγωνάκι.
  void _paintAngleArcs(Canvas canvas, double pixel) {
    for (final mark in overlay.angleMarks) {
      final paint = Paint()
        ..color = mark.toGuide ? _guideColor : _angleColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * pixel;
      // Σε παχύ τοίχο το σημάδι μεγαλώνει ώσπου να βγει από το σώμα του —
      // αλλιώς το σκεπάζει ο τοίχος.
      final body = mark.bodyHalfWidthCm;
      if (mark.isRight) {
        final side = math.max(12 * pixel, body + 6 * pixel);
        canvas.drawPath(
          Path()
            ..moveTo(
              mark.vertex.dx + mark.armA.dx * side,
              mark.vertex.dy + mark.armA.dy * side,
            )
            ..lineTo(
              mark.vertex.dx + (mark.armA.dx + mark.armB.dx) * side,
              mark.vertex.dy + (mark.armA.dy + mark.armB.dy) * side,
            )
            ..lineTo(
              mark.vertex.dx + mark.armB.dx * side,
              mark.vertex.dy + mark.armB.dy * side,
            ),
          paint,
        );
        continue;
      }
      final start = math.atan2(mark.armA.dy, mark.armA.dx);
      var sweep = math.atan2(mark.armB.dy, mark.armB.dx) - start;
      if (sweep > math.pi) sweep -= 2 * math.pi;
      if (sweep < -math.pi) sweep += 2 * math.pi;
      final radius = math.max(
        20 * pixel,
        mark.clearanceAlongBisector(body) + 6 * pixel,
      );
      canvas.drawArc(
        Rect.fromCircle(center: mark.vertex, radius: radius),
        start,
        sweep,
        false,
        paint,
      );
    }
  }

  /// Ο αριθμός κάθε γωνίας, όρθιος στην οθόνη, μέσα στο άνοιγμά της.
  void _paintAngleLabels(Canvas canvas) {
    for (final mark in overlay.angleMarks) {
      final vertex = view.toScreen(mark.vertex);
      Offset screenDir(Offset arm) {
        final d = view.toScreen(mark.vertex + arm * 100) - vertex;
        return d.distance == 0 ? Offset.zero : d / d.distance;
      }

      final a = screenDir(mark.armA);
      final b = screenDir(mark.armB);
      var bisector = a + b;
      // Σε ευθεία (180°) οι δύο κατευθύνσεις αλληλοαναιρούνται: ο αριθμός
      // μπαίνει κάθετα.
      bisector = bisector.distance < 1e-6
          ? Offset(-a.dy, a.dx)
          : bisector / bisector.distance;
      final text = TextPainter(
        text: TextSpan(
          text: formatAngleDegrees(mark.degrees),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: mark.toGuide ? _guideColor : _angleColor,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      // Έξω από το σώμα των τοίχων, και πέρα από το τόξο.
      final bodyPx = mark.bodyHalfWidthCm * view.pixelsPerCm;
      final reach = math.max(
        38.0,
        mark.clearanceAlongBisector(bodyPx) + 6 + text.height,
      );
      final box = Rect.fromCenter(
        center: vertex + bisector * reach,
        width: text.width + 8,
        height: text.height + 2,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(4)),
        Paint()..color = const Color(0xEEFFFFFF),
      );
      text
        ..paint(canvas, box.topLeft + const Offset(4, 1))
        ..dispose();
    }
  }

  void _paintSnap(Canvas canvas, double pixel) {
    final p = overlay.snapPoint;
    if (p == null) return;
    final color = switch (overlay.snapKind) {
      FloorPlanSnapKind.endpoint => Colors.green.shade700,
      FloorPlanSnapKind.wallBody => Colors.orange.shade800,
      FloorPlanSnapKind.midpoint => Colors.teal.shade700,
      FloorPlanSnapKind.guide => const Color(0xFFAA00FF),
      _ => colors.primary,
    };
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * pixel;
    if (overlay.snapKind == FloorPlanSnapKind.midpoint) {
      // Η μέση τοίχου σημειώνεται με τρίγωνο, για να ξεχωρίζει από το απλό
      // «πάνω στον τοίχο».
      final r = 8 * pixel;
      canvas.drawPath(
        Path()
          ..moveTo(p.dx, p.dy - r)
          ..lineTo(p.dx + r, p.dy + r * 0.8)
          ..lineTo(p.dx - r, p.dy + r * 0.8)
          ..close(),
        paint,
      );
      return;
    }
    canvas.drawCircle(p, 6 * pixel, paint);
  }

  /// Το μήκος του τοίχου που σχεδιάζεται ή αλλάζει μήκος, σε οθόνη — όρθιο,
  /// όπως κι αν έχει γυρίσει ο όροφος.
  void _paintRubberLength(Canvas canvas) {
    final a = overlay.rubberStart ?? overlay.lengthStart;
    final b = overlay.rubberEnd ?? overlay.lengthEnd;
    if (a == null || b == null) return;
    final length = (b - a).distance;
    if (length < 1) return;
    final mid = view.toScreen(Offset.lerp(a, b, 0.5)!);
    final text = TextPainter(
      text: TextSpan(
        text: formatCmAsMeters(length),
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final box = Rect.fromCenter(
      center: mid + const Offset(0, -18),
      width: text.width + 10,
      height: text.height + 4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(4)),
      Paint()..color = const Color(0xEEFFFFFF),
    );
    text
      ..paint(canvas, box.topLeft + const Offset(5, 2))
      ..dispose();
  }

  @override
  bool shouldRepaint(FloorPlanPainter old) => true;
}

/// Κάτω από αυτό το μέγεθος (σε pixel) το όνομα δεν διαβάζεται και δεν
/// ζωγραφίζεται: ο χάρτης είναι πολύ μακριά.
const double _kMinRoomLabelPx = 3;

/// Οι ετικέτες των αντικειμένων κρύβονται λίγο νωρίτερα από τα σύμβολα.
const double _kMinObjectLabelPx = 9;

TextPainter _layoutRoomLabel(
  FloorPlanRoomView room,
  FloorPlanViewTransform view,
) {
  final fontPx = room.labelSizeCm * view.pixelsPerCm;
  return TextPainter(
    text: TextSpan(
      text: room.label,
      style: TextStyle(
        fontSize: fontPx,
        fontWeight: FontWeight.w600,
        color: Colors.black87,
      ),
    ),
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
    maxLines: 3,
    ellipsis: '…',
  )..layout(maxWidth: fontPx * 14);
}

/// Πού πέφτει στην οθόνη το όνομα του [room], ακριβώς όπως το ζωγραφίζει ο
/// [FloorPlanPainter] — `null` όταν ο χώρος δεν έχει όνομα. Από εδώ το
/// παίρνει και το κλικ του εργαλείου «Κείμενο», ώστε «πού είναι η ετικέτα»
/// να μην έχει δεύτερη απάντηση.
Rect? floorPlanRoomLabelRect(
  FloorPlanRoomView room,
  FloorPlanViewTransform view,
) {
  if (room.label.isEmpty) return null;
  if (room.labelSizeCm * view.pixelsPerCm < _kMinRoomLabelPx) return null;
  final text = _layoutRoomLabel(room, view);
  final rect = Rect.fromCenter(
    center: view.toScreen(room.labelCenter),
    width: text.width,
    height: text.height,
  );
  text.dispose();
  return rect;
}
