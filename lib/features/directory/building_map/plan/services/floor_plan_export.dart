import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../../core/database/building_map_repository.dart';
import '../../../../../core/database/database_helper.dart';
import '../../../../../core/database/department_repository.dart';
import '../../../../../core/database/floor_plan_objects_repository.dart';
import '../../../../../core/database/floor_plan_placements_repository.dart';
import '../../../../../core/database/floor_plan_repository.dart';
import '../../../../../core/models/floor_plan_element.dart';
import '../../../../../core/models/floor_plan_state.dart';
import '../../../models/department_model.dart';
import '../../services/building_map_department_eligibility.dart';
import '../../services/building_map_sheet_export.dart';
import '../floor_plan_geometry.dart';
import '../floor_plan_layers.dart';
import '../floor_plan_objects.dart';
import '../floor_plan_output.dart';
import '../floor_plan_selection.dart';
import '../floor_plan_view_transform.dart';
import '../widgets/floor_plan_painter.dart';
import '../widgets/floor_plan_room_views.dart';

/// Το μήκος της μεγάλης πλευράς της εικόνας που εξάγεται, σε pixel.
const double _kExportLongSide = 3000;

/// Πόσο πιο πυκνό από την οθόνη βγαίνει το στιγμιότυπο, για να διαβάζεται σε
/// χαρτί και σε μεγέθυνση.
const double _kSnapshotPixelRatio = 2.5;

/// Το όνομα αρχείου που προτείνεται για την έξοδο.
String floorPlanOutputFileName(String floorLabel, FloorPlanOutputScope scope) =>
    scope == FloorPlanOutputScope.snapshot
    ? '$floorLabel - στιγμιότυπο'
    : floorLabel;

/// Εξαγωγή ενεργοποιημένου ορόφου σε εικόνα (PNG ή JPG).
Future<void> exportFloorPlanToImageFile({
  required BuildContext context,
  required int floorId,
  required String floorLabel,
  required FloorPlanOutputScope scope,
  required GlobalKey snapshotKey,
  Set<String> hiddenLayers = const {},
}) async {
  final render = await prepareFloorPlanOutput(
    context: context,
    floorId: floorId,
    floorLabel: floorLabel,
    scope: scope,
    snapshotKey: snapshotKey,
    hiddenLayers: hiddenLayers,
  );
  if (render == null || !context.mounted) return;
  await exportRasterToImageFile(
    context: context,
    defaultFloorBaseName: floorPlanOutputFileName(floorLabel, scope),
    render: render,
  );
}

/// Ετοιμάζει ό,τι θα βγει σε εικόνα ή σε χαρτί, με τον όροφο και την ημερομηνία
/// από πάνω: το [FloorPlanOutputScope.snapshot] βγάζει ό,τι δείχνει το
/// [snapshotKey], ο ολόκληρος όροφος βγαίνει χωρίς τις [hiddenLayers]. Το
/// [snapshotMaxLongSide] περιορίζει το μέγεθος του στιγμιότυπου.
///
/// Επιστρέφει `null`, αφού το πει στον χρήστη, όταν δεν υπάρχει τίποτα να βγει.
Future<Future<ui.Image> Function()?> prepareFloorPlanOutput({
  required BuildContext context,
  required int floorId,
  required String floorLabel,
  required FloorPlanOutputScope scope,
  required GlobalKey snapshotKey,
  Set<String> hiddenLayers = const {},
  double? snapshotMaxLongSide,
}) async {
  final caption = floorPlanOutputCaption(floorLabel, DateTime.now());
  if (scope == FloorPlanOutputScope.snapshot) {
    return () async => addFloorPlanCaption(
      await captureFloorPlanSnapshot(
        snapshotKey,
        maxLongSide: snapshotMaxLongSide,
      ),
      caption,
    );
  }
  final db = await DatabaseHelper.instance.database;
  final elements = await FloorPlanRepository(db).listElements(floorId);
  final objectsRepo = FloorPlanObjectsRepository(db);
  final placementsRepo = FloorPlanPlacementsRepository(db);
  final objects = visibleFloorPlanLayers([
    ...buildFloorPlanObjectViews(
      await objectsRepo.listObjects(floorId),
      await objectsRepo.kinds(),
    ),
    ...buildFloorPlanPlacementViews(
      await placementsRepo.listPlacements(floorId),
      {for (final e in await placementsRepo.catalogEntries()) e.key: e},
    ),
  ], hiddenLayers);
  final floors = await BuildingMapRepository(db).listBuildingMapFloors();
  final rotation =
      floors.where((f) => f.id == floorId).firstOrNull?.rotationDegrees ?? 0;
  final rows = await DepartmentRepository(db).getActiveDepartments();
  final departments = <int, DepartmentModel>{
    for (final d in departmentsEligibleForBuildingMap(
      rows.map(DepartmentModel.fromMap),
    ))
      if (d.id != null) d.id!: d,
  };
  if (!context.mounted) return null;
  if (elements.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ο όροφος δεν έχει ακόμη σχέδιο.')),
    );
    return null;
  }
  final colors = Theme.of(context).colorScheme;
  return () async => addFloorPlanCaption(
    await renderFloorPlanImage(
      elements: elements,
      departments: departments,
      rotationDegrees: rotation,
      colors: colors,
      objects: objects,
    ),
    caption,
  );
}

/// Ό,τι φαίνεται τώρα στον χάρτη, χωρίς πάνελ και κουμπιά. Περιμένει να
/// τελειώσει το τρέχον καρέ: το κλείσιμο ενός διαλόγου αφήνει τον χάρτη με
/// εκκρεμή ζωγραφική, και τότε η λήψη αποτυγχάνει.
Future<ui.Image> captureFloorPlanSnapshot(
  GlobalKey snapshotKey, {
  double? maxLongSide,
}) async {
  await WidgetsBinding.instance.endOfFrame;
  final boundary = snapshotKey.currentContext?.findRenderObject();
  if (boundary is! RenderRepaintBoundary) {
    throw StateError('Ο χάρτης δεν είναι διαθέσιμος.');
  }
  final longSide = boundary.size.longestSide;
  return boundary.toImage(
    pixelRatio: maxLongSide == null || longSide <= 0
        ? _kSnapshotPixelRatio
        : math.min(_kSnapshotPixelRatio, maxLongSide / longSide),
  );
}

/// Νέα εικόνα με τη γραμμή [caption] πάνω από τον χάρτη [map]. Το μέγεθος των
/// γραμμάτων ακολουθεί το πλάτος, ώστε να διαβάζονται σε κάθε εικόνα. Κλείνει
/// την αρχική.
Future<ui.Image> addFloorPlanCaption(ui.Image map, String caption) async {
  final width = map.width.toDouble();
  final fontSize = math.max(20.0, width / 70);
  final stripHeight = (fontSize * 2).roundToDouble();
  final text = TextPainter(
    text: TextSpan(
      text: caption,
      style: TextStyle(
        fontSize: fontSize,
        color: Colors.black87,
        fontWeight: FontWeight.w600,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: width - fontSize * 2);

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width, stripHeight),
    Paint()..color = Colors.white,
  );
  text.paint(canvas, Offset(fontSize, (stripHeight - text.height) / 2));
  canvas.drawImage(map, Offset(0, stripHeight), Paint());
  text.dispose();
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    map.width,
    map.height + stripHeight.toInt(),
  );
  picture.dispose();
  map.dispose();
  return image;
}

/// Ζωγραφίζει τον όροφο σε εικόνα με λευκό φόντο, χωρίς να φαίνεται πουθενά
/// στην οθόνη.
Future<ui.Image> renderFloorPlanImage({
  required List<FloorPlanElement> elements,
  required Map<int, DepartmentModel> departments,
  required double rotationDegrees,
  required ColorScheme colors,
  List<FloorPlanObjectView> objects = const [],
}) async {
  final drawing = selectionBounds({for (final e in elements) e.id}, elements);
  final things = floorPlanObjectsBounds({
    for (final o in objects) o.id,
  }, objects);
  final bounds = drawing == null
      ? things ??
            Rect.fromCenter(center: Offset.zero, width: 1000, height: 1000)
      : things == null
      ? drawing
      : drawing.expandToInclude(things);
  final rotation = rotationDegrees * math.pi / 180;
  // Το μέγεθος της εικόνας ακολουθεί το σχήμα του ορόφου όπως φαίνεται.
  final c = math.cos(rotation).abs();
  final s = math.sin(rotation).abs();
  final w = bounds.width * c + bounds.height * s;
  final h = bounds.width * s + bounds.height * c;
  final scale = _kExportLongSide / math.max(1, math.max(w, h));
  final size = Size(
    (w * scale + 160).clamp(200, 4000).roundToDouble(),
    (h * scale + 160).clamp(200, 4000).roundToDouble(),
  );
  final view = FloorPlanViewTransform.fit(
    worldRect: bounds,
    viewport: size,
    rotationRadians: rotation,
    margin: 80,
  );

  final walls = [
    for (final e in elements)
      if (e.kind == FloorPlanElementKind.wall && e.points.length >= 2)
        FloorPlanSegment(e.points[0], e.points[1], id: e.id),
  ];
  final openingsByWall = <int, List<({double start, double end})>>{};
  for (final e in elements) {
    final parent = e.parentId;
    if (e.kind != FloorPlanElementKind.opening || parent == null) continue;
    if (e.points.length < 2) continue;
    (openingsByWall[parent] ??= []).add((
      start: e.points[0].dx,
      end: e.points[1].dx,
    ));
  }

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  FloorPlanPainter(
    view: view,
    walls: walls,
    openingsByWall: openingsByWall,
    rooms: buildFloorPlanRoomViews(elements, departments),
    texts: [
      for (final e in elements)
        if (e.kind == FloorPlanElementKind.text && e.points.isNotEmpty) e,
    ],
    dimensions: [
      for (final e in elements)
        if (e.kind == FloorPlanElementKind.dimension && e.points.length >= 3) e,
    ],
    state: const FloorPlanState(floorId: 0, patternHidden: true),
    patternImage: null,
    gridVisible: false,
    selectedIds: const {},
    openingSegments: const {},
    overlay: const FloorPlanOverlay(),
    colors: colors,
    labelScale: 2.5,
    objects: objects,
  ).paint(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  picture.dispose();
  return image;
}
