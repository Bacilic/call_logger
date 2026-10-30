import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

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
import '../floor_plan_objects.dart';
import '../floor_plan_selection.dart';
import '../floor_plan_view_transform.dart';
import '../widgets/floor_plan_painter.dart';
import '../widgets/floor_plan_room_views.dart';

/// Το μήκος της μεγάλης πλευράς της εικόνας που εξάγεται, σε pixel.
const double _kExportLongSide = 3000;

/// Εξαγωγή **ολόκληρου** του ενεργοποιημένου ορόφου σε εικόνα (PNG ή JPG),
/// με τον προσανατολισμό του ορόφου. Το «στιγμιότυπο» και τα φίλτρα έρχονται
/// στη Φάση 4.
Future<void> exportFloorPlanToImageFile({
  required BuildContext context,
  required int floorId,
  required String defaultFloorBaseName,
}) async {
  final db = await DatabaseHelper.instance.database;
  final elements = await FloorPlanRepository(db).listElements(floorId);
  final objectsRepo = FloorPlanObjectsRepository(db);
  final placementsRepo = FloorPlanPlacementsRepository(db);
  final objects = [
    ...buildFloorPlanObjectViews(
      await objectsRepo.listObjects(floorId),
      await objectsRepo.kinds(),
    ),
    ...buildFloorPlanPlacementViews(
      await placementsRepo.listPlacements(floorId),
      {for (final e in await placementsRepo.catalogEntries()) e.key: e},
    ),
  ];
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
  if (!context.mounted) return;
  if (elements.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ο όροφος δεν έχει ακόμη σχέδιο.')),
    );
    return;
  }
  final colors = Theme.of(context).colorScheme;
  await exportRasterToImageFile(
    context: context,
    defaultFloorBaseName: defaultFloorBaseName,
    render: () async => renderFloorPlanImage(
      elements: elements,
      departments: departments,
      rotationDegrees: rotation,
      colors: colors,
      objects: objects,
    ),
  );
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
