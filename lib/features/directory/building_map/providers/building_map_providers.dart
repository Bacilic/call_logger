import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/database/directory_repository.dart';
import '../../../../core/models/building_map_floor.dart';

/// Undo ενός βήματος: στιγμιότυπο γεωμετρίας τμήματος πριν την τελευταία εγγραφή.
@immutable
class BuildingMapUndoSnapshot {
  const BuildingMapUndoSnapshot({
    required this.departmentId,
    required this.mapFloor,
    required this.mapX,
    required this.mapY,
    required this.mapWidth,
    required this.mapHeight,
    required this.mapRotation,
    required this.mapLabelOffsetX,
    required this.mapLabelOffsetY,
    required this.mapAnchorOffsetX,
    required this.mapAnchorOffsetY,
  });

  final int departmentId;
  final String? mapFloor;
  final double? mapX;
  final double? mapY;
  final double? mapWidth;
  final double? mapHeight;
  final double mapRotation;
  final double? mapLabelOffsetX;
  final double? mapLabelOffsetY;
  final double? mapAnchorOffsetX;
  final double? mapAnchorOffsetY;
}

class BuildingMapUndoController extends Notifier<BuildingMapUndoSnapshot?> {
  @override
  BuildingMapUndoSnapshot? build() => null;

  void captureFromValues({
    required int departmentId,
    required String? mapFloor,
    required double? mapX,
    required double? mapY,
    required double? mapWidth,
    required double? mapHeight,
    required double mapRotation,
    required double? mapLabelOffsetX,
    required double? mapLabelOffsetY,
    required double? mapAnchorOffsetX,
    required double? mapAnchorOffsetY,
  }) {
    state = BuildingMapUndoSnapshot(
      departmentId: departmentId,
      mapFloor: mapFloor,
      mapX: mapX,
      mapY: mapY,
      mapWidth: mapWidth,
      mapHeight: mapHeight,
      mapRotation: mapRotation,
      mapLabelOffsetX: mapLabelOffsetX,
      mapLabelOffsetY: mapLabelOffsetY,
      mapAnchorOffsetX: mapAnchorOffsetX,
      mapAnchorOffsetY: mapAnchorOffsetY,
    );
  }

  void clear() {
    state = null;
  }
}

final buildingMapUndoProvider =
    NotifierProvider<BuildingMapUndoController, BuildingMapUndoSnapshot?>(
      BuildingMapUndoController.new,
    );

final buildingMapDirectoryRepositoryProvider =
    FutureProvider<DirectoryRepository>((ref) async {
      final db = await DatabaseHelper.instance.database;
      return DirectoryRepository(db);
    });

final buildingMapSelectedSheetIdProvider =
    NotifierProvider<BuildingMapSelectedSheetIdNotifier, int?>(
      BuildingMapSelectedSheetIdNotifier.new,
    );

class BuildingMapSelectedSheetIdNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void setSheet(int? id) {
    state = id;
  }
}

final buildingMapSelectedDepartmentIdToMapProvider =
    NotifierProvider<BuildingMapSelectedDeptNotifier, int?>(
      BuildingMapSelectedDeptNotifier.new,
    );

class BuildingMapSelectedDeptNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void setDept(int? id) {
    state = id;
  }
}

/// Πλέγμα επιλογής τμήματος (HUD) πάνω από τον καμβά επεξεργασίας.
final buildingMapDeptSelectionHudVisibleProvider =
    NotifierProvider<BuildingMapDeptHudVisibleNotifier, bool>(
      BuildingMapDeptHudVisibleNotifier.new,
    );

class BuildingMapDeptHudVisibleNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setVisible(bool value) {
    state = value;
  }
}

/// Προσωρινή (ephemeral) τιμή περιστροφής σε μοίρες κατά τη διάρκεια του drag.
final buildingMapDragRotationProvider =
    NotifierProvider<BuildingMapDragRotationNotifier, double?>(
      BuildingMapDragRotationNotifier.new,
    );

class BuildingMapDragRotationNotifier extends Notifier<double?> {
  @override
  double? build() => null;

  void setRotation(double? value) {
    state = value;
  }
}

enum MapToolMode { select, draw, edit }

enum EditHandleType {
  none,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  rotate,
  move,
  label,
  anchor,
}

@immutable
class DraftDepartmentShape {
  const DraftDepartmentShape({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.rotation = 0.0,
    this.labelOffsetX,
    this.labelOffsetY,
    this.anchorOffsetX,
    this.anchorOffsetY,
  });

  final double x;
  final double y;
  final double width;
  final double height;
  final double rotation;
  final double? labelOffsetX;
  final double? labelOffsetY;
  final double? anchorOffsetX;
  final double? anchorOffsetY;

  Rect get rect => Rect.fromLTWH(x, y, width, height);

  Offset get center => Offset(x + (width / 2), y + (height / 2));

  DraftDepartmentShape copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    double? rotation,
    double? labelOffsetX,
    double? labelOffsetY,
    double? anchorOffsetX,
    double? anchorOffsetY,
  }) {
    return DraftDepartmentShape(
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      rotation: rotation ?? this.rotation,
      labelOffsetX: labelOffsetX ?? this.labelOffsetX,
      labelOffsetY: labelOffsetY ?? this.labelOffsetY,
      anchorOffsetX: anchorOffsetX ?? this.anchorOffsetX,
      anchorOffsetY: anchorOffsetY ?? this.anchorOffsetY,
    );
  }

  static DraftDepartmentShape fromCorners(
    Offset a,
    Offset b, {
    double rotation = 0.0,
  }) {
    final left = math.min(a.dx, b.dx);
    final top = math.min(a.dy, b.dy);
    final right = math.max(a.dx, b.dx);
    final bottom = math.max(a.dy, b.dy);
    return DraftDepartmentShape(
      x: left,
      y: top,
      width: right - left,
      height: bottom - top,
      rotation: rotation,
    );
  }
}

final buildingMapToolProvider =
    NotifierProvider<BuildingMapToolNotifier, MapToolMode>(
      BuildingMapToolNotifier.new,
    );

class BuildingMapToolNotifier extends Notifier<MapToolMode> {
  @override
  MapToolMode build() => MapToolMode.select;

  void setMode(MapToolMode mode) {
    state = mode;
  }
}

final buildingMapDraftShapeProvider =
    NotifierProvider<BuildingMapDraftShapeNotifier, DraftDepartmentShape?>(
      BuildingMapDraftShapeNotifier.new,
    );

class BuildingMapDraftShapeNotifier extends Notifier<DraftDepartmentShape?> {
  @override
  DraftDepartmentShape? build() => null;

  void setDraft(DraftDepartmentShape? draft) {
    state = draft;
  }

  void clear() {
    state = null;
  }
}

/// Αν true, η τρέχουσα επεξεργασία στον χάρτη ξεκίνησε με κλικ σε χαρτογραφημένο τμήμα
/// από κατάσταση [MapToolMode.select]· μετά ✓/✕ επανερχόμαστε στην Επιλογή αντί για Σχεδίαση.
final buildingMapEditFromSelectionTapProvider =
    NotifierProvider<BuildingMapEditFromSelectionTapNotifier, bool>(
      BuildingMapEditFromSelectionTapNotifier.new,
    );

class BuildingMapEditFromSelectionTapNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setValue(bool value) {
    state = value;
  }

  void clear() {
    state = false;
  }
}

/// Προβολή (`false`) vs επεξεργασία χάρτη (`true`) στο fullscreen dialog.
final buildingMapUiEditModeProvider =
    NotifierProvider<BuildingMapUiEditModeNotifier, bool>(
      BuildingMapUiEditModeNotifier.new,
    );

class BuildingMapUiEditModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setEditing(bool value) {
    state = value;
  }
}

/// Εικονικές διαστάσεις της τρέχουσας εικόνας κατόψης (για τον καμβά).
final buildingMapDecodedImageSizeProvider =
    NotifierProvider<BuildingMapDecodedImageSizeNotifier, Size?>(
      BuildingMapDecodedImageSizeNotifier.new,
    );

class BuildingMapDecodedImageSizeNotifier extends Notifier<Size?> {
  @override
  Size? build() => null;

  void setSize(Size? value) {
    state = value;
  }
}

/// Ανανέωση της λίστας ορόφων ([FutureBuilder] key).
final buildingMapFloorReloadSeqProvider =
    NotifierProvider<BuildingMapFloorReloadSeqNotifier, int>(
      BuildingMapFloorReloadSeqNotifier.new,
    );

class BuildingMapFloorReloadSeqNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() {
    state = state + 1;
  }

  void reset() {
    state = 0;
  }
}

/// Κατάλογος φύλλων κατόψης (`building_map_floors`) για ετικέτες ορόφου στο UI (π.χ. καρτέλα τμήματα).
final buildingMapFloorsCatalogProvider =
    FutureProvider<List<BuildingMapFloor>>((ref) async {
  ref.watch(buildingMapFloorReloadSeqProvider);
  final db = await DatabaseHelper.instance.database;
  return DirectoryRepository(db).listBuildingMapFloors();
});

/// Αύξων αριθμός όταν η αναζήτηση χάρτη ζητά κεντράρισμα στο επιλεγμένο τμήμα (μόνο pan, ίδιο zoom).
final buildingMapViewportCenterRequestSeqProvider =
    NotifierProvider<BuildingMapViewportCenterRequestNotifier, int>(
      BuildingMapViewportCenterRequestNotifier.new,
    );

class BuildingMapViewportCenterRequestNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() {
    state = state + 1;
  }
}

/// Τμήμα που αποκαλύπτεται προσωρινά λόγω αναζήτησης, ενώ είναι κρυμμένο στον χάρτη
/// (στήλη `departments.map_hidden = 1`). Καθαρίζεται όταν αδειάσει το πεδίο αναζήτησης
/// ή όταν αλλάξει φύλλο κατόψης.
final buildingMapSearchRevealedDepartmentIdProvider =
    NotifierProvider<BuildingMapSearchRevealedDeptNotifier, int?>(
      BuildingMapSearchRevealedDeptNotifier.new,
    );

class BuildingMapSearchRevealedDeptNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void setRevealed(int? departmentId) {
    state = departmentId;
  }

  void clear() {
    state = null;
  }
}

@immutable
class BuildingMapPendingJumpPayload {
  const BuildingMapPendingJumpPayload({
    required this.entity,
  });

  final dynamic entity;
}

final buildingMapPendingJumpProvider =
    NotifierProvider<
      BuildingMapPendingJumpNotifier,
      BuildingMapPendingJumpPayload?
    >(BuildingMapPendingJumpNotifier.new);

class BuildingMapPendingJumpNotifier
    extends Notifier<BuildingMapPendingJumpPayload?> {
  @override
  BuildingMapPendingJumpPayload? build() => null;

  void setEntity(dynamic entity) {
    state = BuildingMapPendingJumpPayload(entity: entity);
  }

  BuildingMapPendingJumpPayload? consume() {
    final current = state;
    state = null;
    return current;
  }

  void clear() {
    state = null;
  }
}
