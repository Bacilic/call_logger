import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:custom_mouse_cursor/custom_mouse_cursor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/department_model.dart';
import '../../screens/widgets/department_color_palette.dart';
import '../building_map_geometry.dart';
import '../building_map_label_layout.dart';
import '../controllers/building_map_controller.dart';
import '../providers/building_map_providers.dart';
import 'building_map_fill_color_dialog.dart';
import 'building_map_sheet_painter.dart';

/// Καμβάς χάρτη με [InteractiveViewer], σχεδίαση και χειρισμό draft (επεξεργασία).
class BuildingMapSheetViewport extends ConsumerStatefulWidget {
  const BuildingMapSheetViewport({
    super.key,
    required this.designModeActive,
    required this.sheetStr,
    required this.rotRad,
    required this.imgPath,
    required this.imgFile,
    required this.decodedSize,
    required this.activeDepartments,
    required this.currentSheetId,
    required this.onFloorsChanged,
  });

  final bool designModeActive;
  final String sheetStr;
  final double rotRad;
  final String imgPath;
  final File imgFile;
  final Size? decodedSize;
  final List<DepartmentModel> activeDepartments;
  final int? currentSheetId;
  final VoidCallback onFloorsChanged;

  @override
  ConsumerState<BuildingMapSheetViewport> createState() =>
      _BuildingMapSheetViewportState();
}

class _BuildingMapSheetViewportState
    extends ConsumerState<BuildingMapSheetViewport> {
  final TransformationController _transform = TransformationController();

  /// Τελευταίο μέγεθος οπτικού πεδίου [InteractiveViewer] — για κεντράρισμα μετά από αναζήτηση.
  Size _viewportSize = Size.zero;

  static const double _kMinDraftSize = 0.005;
  static const Duration _kLabelDoubleTapGap = Duration(milliseconds: 400);
  static const double _kLabelDoubleTapSlopPx = 28;

  /// Απόκρυψη από hit-test διπλού κλικ περιοχής που επικαλύπτει το handle της ετικέτας.
  static const double _kLabelDragHandleExcludeRadiusPx = 14;

  Offset? _rubberStart;
  Offset? _editPointerStart;
  DraftDepartmentShape? _editDraftStart;
  EditHandleType _activeHandle = EditHandleType.none;
  int? _hoveredDepartmentId;

  DateTime? _labelDoubleTapTime;
  Offset? _labelDoubleTapPosCanvas;

  bool _mapDisplayNameEditing = false;
  int? _mapDisplayNameDeptId;
  TextEditingController? _mapDisplayNameCtrl;
  FocusNode? _mapDisplayNameFocus;

  /// Τοπικό κείμενο επωνυμίας χάρτη μετά blur/Enter — αποθηκεύεται στη βάση μόνο με Επιβεβαίωση draft (✓).
  int? _pendingMapDisplayNameDeptId;
  String? _pendingMapDisplayNameText;

  /// Native κέρσορες (Windows/desktop)· το [custom_mouse_cursor] τους περνά στο σύστημα.
  CustomMouseCursor? _nativeSelectHandCursor;
  CustomMouseCursor? _nativeDrawCrossCursor;

  /// Δεν επιτρέπεται [FocusNode.dispose] μέσα στο [FocusNode.notifyListeners] (blur, ✓ που αρπάζει focus).
  void _scheduleDisposeMapNameField(TextEditingController? c, FocusNode? f) {
    if (c == null && f == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      f?.dispose();
      c?.dispose();
    });
  }

  @override
  void dispose() {
    _mapDisplayNameCtrl?.dispose();
    _mapDisplayNameFocus?.dispose();
    _transform.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    unawaited(_preloadNativeToolCursors());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    CustomMouseCursor.ensurePointersMatchDevicePixelRatio(context);
  }

  /// Φόρτωση κέρσορων από εικονίδια· αν αποτύχει, μένουν τα [SystemMouseCursors] ως fallback.
  Future<void> _preloadNativeToolCursors() async {
    try {
      final hand = await CustomMouseCursor.icon(
        Icons.pan_tool_alt_outlined,
        size: 28,
        hotX: 11,
        hotY: 9,
        color: const Color(0xFF212121),
      );
      final cross = await CustomMouseCursor.icon(
        Icons.add,
        size: 26,
        hotX: 13,
        hotY: 13,
        color: const Color(0xFF212121),
      );
      if (!mounted) return;
      setState(() {
        _nativeSelectHandCursor = hand;
        _nativeDrawCrossCursor = cross;
      });
    } catch (_) {
      // Αφήνουμε null· χρησιμοποιείται το υπόλοιπο fallback στο build.
    }
  }

  MouseCursor _mapViewportCursor({
    required bool designModeActive,
    required bool isSelectTool,
  }) {
    if (!designModeActive) return SystemMouseCursors.basic;
    final nativeReady =
        _nativeSelectHandCursor != null && _nativeDrawCrossCursor != null;
    if (isSelectTool) {
      return nativeReady
          ? _nativeSelectHandCursor!
          : SystemMouseCursors.grab;
    }
    return nativeReady
        ? _nativeDrawCrossCursor!
        : SystemMouseCursors.basic;
  }

  DepartmentModel? _departmentById(List<DepartmentModel> deps, int? id) {
    if (id == null) return null;
    for (final d in deps) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// Μετατοπίζει το [InteractiveViewer] ώστε το κέντρο της περιοχής τμήματος να συμπίπτει με το κέντρο προβολής· διατηρεί το τρέχον zoom.
  void _panViewportToDepartmentCenter(Size viewportSize) {
    if (!mounted) return;
    if (viewportSize.width <= 0 || viewportSize.height <= 0) return;
    if (widget.designModeActive) return;

    final deptId = ref.read(buildingMapSelectedDepartmentIdToMapProvider);
    if (deptId == null) return;

    final dept = _departmentById(widget.activeDepartments, deptId);
    if (dept == null) return;
    if ((dept.mapFloor ?? '') != widget.sheetStr) return;

    final nx = dept.mapX;
    final ny = dept.mapY;
    final nw = dept.mapWidth;
    final nh = dept.mapHeight;
    if (nx == null || ny == null || nw == null || nh == null) return;
    if (nw <= 0 || nh <= 0) return;

    final sz = widget.decodedSize;
    if (sz == null) return;

    final focal = Rect.fromLTWH(
      nx * sz.width,
      ny * sz.height,
      nw * sz.width,
      nh * sz.height,
    ).center;

    final Matrix4 m = _transform.value.clone();
    final Offset inViewport = MatrixUtils.transformPoint(m, focal);
    final Offset viewportCenter = Offset(
      viewportSize.width / 2,
      viewportSize.height / 2,
    );
    final Offset delta = viewportCenter - inViewport;
    final Matrix4 pan =
        Matrix4.translationValues(delta.dx, delta.dy, 0.0);
    _transform.value = pan * m;
  }

  String _effectiveMapLabelTextForDepartment(DepartmentModel dep) {
    final id = dep.id;
    if (id == null) return dep.displayName;
    if (_mapDisplayNameEditing &&
        _mapDisplayNameDeptId == id &&
        _mapDisplayNameCtrl != null) {
      return _mapDisplayNameCtrl!.text;
    }
    if (_pendingMapDisplayNameDeptId == id &&
        _pendingMapDisplayNameText != null) {
      return _pendingMapDisplayNameText!;
    }
    return dep.displayName;
  }

  void _resetLabelDoubleTapTracking() {
    _labelDoubleTapTime = null;
    _labelDoubleTapPosCanvas = null;
  }

  bool _detectLabelDoubleTap(Offset invCanvasPx) {
    final now = DateTime.now();
    final prev = _labelDoubleTapTime;
    final prevPos = _labelDoubleTapPosCanvas;
    _labelDoubleTapTime = now;
    _labelDoubleTapPosCanvas = invCanvasPx;
    if (prev == null ||
        prevPos == null ||
        now.difference(prev) > _kLabelDoubleTapGap ||
        (invCanvasPx - prevPos).distance > _kLabelDoubleTapSlopPx) {
      return false;
    }
    _resetLabelDoubleTapTracking();
    return true;
  }

  void _cancelMapDisplayNameEditing() {
    final c = _mapDisplayNameCtrl;
    final f = _mapDisplayNameFocus;
    _mapDisplayNameCtrl = null;
    _mapDisplayNameFocus = null;
    _mapDisplayNameDeptId = null;
    _mapDisplayNameEditing = false;
    _pendingMapDisplayNameDeptId = null;
    _pendingMapDisplayNameText = null;
    _scheduleDisposeMapNameField(c, f);
  }

  void _beginMapDisplayNameEditing(DepartmentModel dept) {
    if (dept.id == null) return;
    final did = dept.id!;
    final initial =
        (_pendingMapDisplayNameDeptId == did &&
            _pendingMapDisplayNameText != null)
        ? _pendingMapDisplayNameText!
        : dept.displayName;
    _pendingMapDisplayNameDeptId = null;
    _pendingMapDisplayNameText = null;
    final oldC = _mapDisplayNameCtrl;
    final oldF = _mapDisplayNameFocus;
    _mapDisplayNameCtrl = null;
    _mapDisplayNameFocus = null;
    _scheduleDisposeMapNameField(oldC, oldF);
    _mapDisplayNameDeptId = did;
    _mapDisplayNameEditing = true;
    _mapDisplayNameCtrl = TextEditingController(text: initial);
    _mapDisplayNameFocus = FocusNode()
      ..addListener(() {
        if (_mapDisplayNameFocus?.hasFocus ?? false) return;
        if (!_mapDisplayNameEditing) return;
        _softEndMapDisplayNameEditing();
      });
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapDisplayNameFocus?.requestFocus();
      _mapDisplayNameCtrl?.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _mapDisplayNameCtrl?.text.length ?? 0,
      );
    });
  }

  /// Κλείνει το TextField χωρίς εγγραφή στη βάση — το κείμενο μένει σε [_pendingMapDisplayNameText].
  void _softEndMapDisplayNameEditing() {
    if (!_mapDisplayNameEditing) return;
    final id = _mapDisplayNameDeptId;
    final ctrl = _mapDisplayNameCtrl;
    final focus = _mapDisplayNameFocus;
    if (id == null || ctrl == null) return;
    _pendingMapDisplayNameDeptId = id;
    _pendingMapDisplayNameText = ctrl.text;
    _mapDisplayNameCtrl = null;
    _mapDisplayNameFocus = null;
    _mapDisplayNameDeptId = null;
    _mapDisplayNameEditing = false;
    _scheduleDisposeMapNameField(ctrl, focus);
    if (mounted) setState(() {});
  }

  /// Αποθήκευση επωνυμίας χάρτη στη βάση — καλείται μόνο από Επιβεβαίωση draft (✓).
  Future<void> _persistMapDisplayNameForDraftDepartment(
    int departmentId,
  ) async {
    final dept = _departmentById(widget.activeDepartments, departmentId);
    if (dept == null) return;
    final canonical = dept.name;
    String? edited;
    if (_mapDisplayNameEditing &&
        _mapDisplayNameDeptId == departmentId &&
        _mapDisplayNameCtrl != null) {
      edited = _mapDisplayNameCtrl!.text;
    } else if (_pendingMapDisplayNameDeptId == departmentId) {
      edited = _pendingMapDisplayNameText;
    }
    if (edited == null) {
      return;
    }
    await ref
        .read(buildingMapControllerProvider)
        .saveDepartmentMapDisplayName(
          context: context,
          departmentId: departmentId,
          canonicalDepartmentName: canonical,
          editedText: edited,
        );
    _pendingMapDisplayNameDeptId = null;
    _pendingMapDisplayNameText = null;
    if (_mapDisplayNameEditing && _mapDisplayNameDeptId == departmentId) {
      final c = _mapDisplayNameCtrl;
      final f = _mapDisplayNameFocus;
      _mapDisplayNameCtrl = null;
      _mapDisplayNameFocus = null;
      _mapDisplayNameDeptId = null;
      _mapDisplayNameEditing = false;
      _scheduleDisposeMapNameField(c, f);
    }
    if (mounted) setState(() {});
  }

  Future<void> _changeMapFillColorForDepartment(DepartmentModel dept) async {
    if (!mounted || dept.id == null || widget.currentSheetId == null) return;
    final initial =
        tryParseDepartmentHex(dept.color) ?? const Color(0xFF1976D2);
    final picked = await showBuildingMapFillColorPicker(
      context,
      initialColor: initial,
    );
    if (!mounted || picked == null) return;
    await ref
        .read(buildingMapControllerProvider)
        .applyDepartmentMapFillColor(
          context: context,
          dept: dept,
          floorId: widget.currentSheetId!,
          newColor: picked,
        );
    if (mounted) setState(() {});
  }

  Offset _rotateAroundCenter(Offset point, Offset center, double radians) {
    final dx = point.dx - center.dx;
    final dy = point.dy - center.dy;
    final c = math.cos(radians);
    final s = math.sin(radians);
    return Offset(
      center.dx + (dx * c) - (dy * s),
      center.dy + (dx * s) + (dy * c),
    );
  }

  Offset _pointOnRotatedRectBoundaryToward({
    required Rect rect,
    required double rotation,
    required Offset targetPoint,
  }) {
    final center = rect.center;
    final targetLocal = _rotateAroundCenter(targetPoint, center, -rotation);
    final vx = targetLocal.dx - center.dx;
    final vy = targetLocal.dy - center.dy;
    if (vx == 0 && vy == 0) {
      return _rotateAroundCenter(Offset(center.dx, rect.top), center, rotation);
    }
    final halfW = rect.width / 2;
    final halfH = rect.height / 2;
    final sx = vx == 0 ? double.infinity : (halfW / vx.abs());
    final sy = vy == 0 ? double.infinity : (halfH / vy.abs());
    final s = math.min(sx, sy);
    final edgeLocal = Offset(center.dx + (vx * s), center.dy + (vy * s));
    return _rotateAroundCenter(edgeLocal, center, rotation);
  }

  Offset _draftLabelCenter(DraftDepartmentShape draft, Size canvasSize) {
    return Offset(
      (draft.x + (draft.width / 2)) * canvasSize.width +
          ((draft.labelOffsetX ?? 0.0) * canvasSize.width),
      (draft.y + (draft.height / 2)) * canvasSize.height +
          ((draft.labelOffsetY ?? 0.0) * canvasSize.height),
    );
  }

  Offset _draftAnchorPoint(DraftDepartmentShape draft, Size canvasSize) {
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
    final labelCenter = _draftLabelCenter(draft, canvasSize);
    return _pointOnRotatedRectBoundaryToward(
      rect: rect,
      rotation: draft.rotation,
      targetPoint: labelCenter,
    );
  }

  EditHandleType _hitTestDraftHandle(
    DraftDepartmentShape draft,
    Offset localPosition,
    Size canvasSize,
  ) {
    final rect = Rect.fromLTWH(
      draft.x * canvasSize.width,
      draft.y * canvasSize.height,
      draft.width * canvasSize.width,
      draft.height * canvasSize.height,
    );
    final center = rect.center;
    final corners =
        <EditHandleType, Offset>{
          EditHandleType.topLeft: rect.topLeft,
          EditHandleType.topRight: rect.topRight,
          EditHandleType.bottomLeft: rect.bottomLeft,
          EditHandleType.bottomRight: rect.bottomRight,
        }.map((key, value) {
          return MapEntry(
            key,
            _rotateAroundCenter(value, center, draft.rotation),
          );
        });
    const handleRadius = 12.0;
    final labelCenter = _draftLabelCenter(draft, canvasSize);
    if ((labelCenter - localPosition).distance <= handleRadius) {
      return EditHandleType.label;
    }
    final anchorPoint = _draftAnchorPoint(draft, canvasSize);
    if ((anchorPoint - localPosition).distance <= handleRadius) {
      return EditHandleType.anchor;
    }
    for (final entry in corners.entries) {
      if ((entry.value - localPosition).distance <= handleRadius) {
        return entry.key;
      }
    }

    final rotateHandle = _rotateAroundCenter(
      Offset(rect.center.dx, rect.top - 24),
      center,
      draft.rotation,
    );
    if ((rotateHandle - localPosition).distance <= 14) {
      return EditHandleType.rotate;
    }

    final normalizedPoint = Offset(
      (localPosition.dx / canvasSize.width).clamp(0.0, 1.0).toDouble(),
      (localPosition.dy / canvasSize.height).clamp(0.0, 1.0).toDouble(),
    );
    final localPoint = _rotateAroundCenter(
      normalizedPoint,
      draft.center,
      -draft.rotation,
    );
    if (draft.rect.contains(localPoint)) {
      return EditHandleType.move;
    }
    return EditHandleType.none;
  }

  DraftDepartmentShape _resizeDraftFromHandle({
    required DraftDepartmentShape startDraft,
    required EditHandleType handle,
    required Offset currentNormalized,
  }) {
    final startRect = startDraft.rect;
    final center = startDraft.center;
    final currentLocal = _rotateAroundCenter(
      currentNormalized,
      center,
      -startDraft.rotation,
    );
    const minEdge = _kMinDraftSize;

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
        break;
    }

    return startDraft.copyWith(
      x: left.clamp(0.0, 1.0).toDouble(),
      y: top.clamp(0.0, 1.0).toDouble(),
      width: (right - left).clamp(minEdge, 1.0).toDouble(),
      height: (bottom - top).clamp(minEdge, 1.0).toDouble(),
    );
  }

  Offset _localToNormalized(
    Offset localInImageStack,
    Size box,
    double rotationRad,
  ) {
    final inv = inverseRotateAroundCenter(localInImageStack, box, rotationRad);
    final nx = (inv.dx / box.width).clamp(0.0, 1.0).toDouble();
    final ny = (inv.dy / box.height).clamp(0.0, 1.0).toDouble();
    return Offset(nx, ny);
  }

  bool _pointInsideDepartmentRect({
    required Offset pointNormalized,
    required DraftDepartmentShape departmentShape,
  }) {
    final localPoint = _rotateAroundCenter(
      pointNormalized,
      departmentShape.center,
      -departmentShape.rotation,
    );
    return departmentShape.rect.contains(localPoint);
  }

  DepartmentModel? _hitTestDepartmentAtLocalPosition({
    required Offset localPosition,
    required Size imageSize,
    required double rotationRad,
  }) {
    final normalized = _localToNormalized(
      localPosition,
      imageSize,
      rotationRad,
    );
    final invPix = inverseRotateAroundCenter(
      localPosition,
      imageSize,
      rotationRad,
    );
    final deps = widget.activeDepartments.reversed;
    for (final dep in deps) {
      if ((dep.mapFloor ?? '') != widget.sheetStr) continue;
      final nx = dep.mapX;
      final ny = dep.mapY;
      final nw = dep.mapWidth;
      final nh = dep.mapHeight;
      if (nx == null || ny == null || nw == null || nh == null) continue;
      if (nw <= 0 || nh <= 0) continue;
      final shape = DraftDepartmentShape(
        x: nx,
        y: ny,
        width: nw,
        height: nh,
        rotation: dep.mapRotation,
      );
      if (_pointInsideDepartmentRect(
        pointNormalized: normalized,
        departmentShape: shape,
      )) {
        return dep;
      }
    }
    // Ετικέτα / γραμμές ονόματος (ίδια γεωμετρία με τον painter): ανύψωση στο hover όπως το ορθογώνιο.
    for (final dep in deps) {
      final labelLayout = computeMapLabelLayout(
        dep: dep,
        sheetIdString: widget.sheetStr,
        draftShape: null,
        toolMode: MapToolMode.select,
        highlightDepartmentId: null,
        canvasSize: imageSize,
        labelTextOverride: _effectiveMapLabelTextForDepartment(dep),
      );
      if (labelLayout != null &&
          labelLayout.textAndUnderlineHitRect.contains(invPix)) {
        return dep;
      }
    }
    return null;
  }

  void _setHoveredDepartmentId(int? value) {
    if (_hoveredDepartmentId == value) return;
    setState(() {
      _hoveredDepartmentId = value;
    });
  }

  void _handlePointerDown({
    required PointerDownEvent event,
    required Size imageSize,
    required double rotationRad,
    required MapToolMode toolMode,
    required bool drawEnabled,
    required DraftDepartmentShape? draft,
  }) {
    final local = event.localPosition;
    final normalized = _localToNormalized(local, imageSize, rotationRad);

    if (event.buttons == kSecondaryMouseButton &&
        widget.currentSheetId != null) {
      final hitDepartment = _hitTestDepartmentAtLocalPosition(
        localPosition: local,
        imageSize: imageSize,
        rotationRad: rotationRad,
      );
      if (hitDepartment?.id != null) {
        unawaited(_changeMapFillColorForDepartment(hitDepartment!));
      }
      return;
    }

    if (toolMode == MapToolMode.select) {
      final hitDepartment = _hitTestDepartmentAtLocalPosition(
        localPosition: local,
        imageSize: imageSize,
        rotationRad: rotationRad,
      );
      if (hitDepartment?.id != null) {
        _setHoveredDepartmentId(hitDepartment!.id);
        ref
            .read(buildingMapSelectedDepartmentIdToMapProvider.notifier)
            .setDept(hitDepartment.id);
        final sheetId = widget.currentSheetId;
        if (sheetId != null) {
          ref
              .read(buildingMapControllerProvider)
              .syncDraftWithSelectedDepartment(
                departments: widget.activeDepartments,
                departmentId: hitDepartment.id,
                floorId: sheetId,
              );
        }
        ref
            .read(buildingMapEditFromSelectionTapProvider.notifier)
            .setValue(true);
        ref.read(buildingMapToolProvider.notifier).setMode(MapToolMode.edit);
      }
      return;
    }

    if (toolMode == MapToolMode.draw && drawEnabled) {
      setState(() {
        _rubberStart = normalized;
      });
      ref
          .read(buildingMapDraftShapeProvider.notifier)
          .setDraft(DraftDepartmentShape.fromCorners(normalized, normalized));
      return;
    }

    if (toolMode == MapToolMode.edit && draft != null) {
      final deptToMap = ref.read(buildingMapSelectedDepartmentIdToMapProvider);
      final selectedDept = _departmentById(widget.activeDepartments, deptToMap);
      final invPix = inverseRotateAroundCenter(local, imageSize, rotationRad);

      if (!_mapDisplayNameEditing &&
          widget.designModeActive &&
          selectedDept != null &&
          deptToMap != null &&
          selectedDept.id == deptToMap) {
        final labelLayout = computeMapLabelLayout(
          dep: selectedDept,
          sheetIdString: widget.sheetStr,
          draftShape: draft,
          toolMode: toolMode,
          highlightDepartmentId: deptToMap,
          canvasSize: imageSize,
          labelTextOverride: _effectiveMapLabelTextForDepartment(selectedDept),
        );
        if (labelLayout != null) {
          final inText = labelLayout.textAndUnderlineHitRect.contains(invPix);
          final onPurpleHandle =
              (invPix - labelLayout.labelCenter).distance <=
              _kLabelDragHandleExcludeRadiusPx;
          if (inText && !onPurpleHandle) {
            if (_detectLabelDoubleTap(invPix)) {
              _beginMapDisplayNameEditing(selectedDept);
              return;
            }
          } else {
            _resetLabelDoubleTapTracking();
          }
        } else {
          _resetLabelDoubleTapTracking();
        }
      }

      final hit = _hitTestDraftHandle(draft, local, imageSize);
      if (hit == EditHandleType.none) return;
      setState(() {
        _activeHandle = hit;
        _editPointerStart = normalized;
        _editDraftStart = draft;
      });
    }
  }

  void _handlePointerHover({
    required PointerHoverEvent event,
    required Size imageSize,
    required double rotationRad,
    required MapToolMode toolMode,
  }) {
    if (toolMode != MapToolMode.select) {
      _setHoveredDepartmentId(null);
      return;
    }
    final hitDepartment = _hitTestDepartmentAtLocalPosition(
      localPosition: event.localPosition,
      imageSize: imageSize,
      rotationRad: rotationRad,
    );
    _setHoveredDepartmentId(hitDepartment?.id);
  }

  void _handlePointerMove({
    required PointerMoveEvent event,
    required Size imageSize,
    required double rotationRad,
    required MapToolMode toolMode,
    required bool drawEnabled,
  }) {
    final local = event.localPosition;
    final currentNorm = _localToNormalized(local, imageSize, rotationRad);

    if (toolMode == MapToolMode.draw && drawEnabled && _rubberStart != null) {
      ref
          .read(buildingMapDraftShapeProvider.notifier)
          .setDraft(
            DraftDepartmentShape.fromCorners(_rubberStart!, currentNorm),
          );
      return;
    }

    if (toolMode != MapToolMode.edit) return;
    if (_activeHandle == EditHandleType.none ||
        _editPointerStart == null ||
        _editDraftStart == null) {
      return;
    }

    final startDraft = _editDraftStart!;
    switch (_activeHandle) {
      case EditHandleType.move:
        final delta = currentNorm - _editPointerStart!;
        final newX = (startDraft.x + delta.dx)
            .clamp(0.0, 1.0 - startDraft.width)
            .toDouble();
        final newY = (startDraft.y + delta.dy)
            .clamp(0.0, 1.0 - startDraft.height)
            .toDouble();
        // Διατηρούμε σταθερή την απόλυτη θέση ετικέτας στον καμβά: offset − εφαρμοσμένη μετατόπιση.
        final appliedDx = newX - startDraft.x;
        final appliedDy = newY - startDraft.y;
        ref
            .read(buildingMapDraftShapeProvider.notifier)
            .setDraft(
              startDraft.copyWith(
                x: newX,
                y: newY,
                labelOffsetX: ((startDraft.labelOffsetX ?? 0) - appliedDx)
                    .clamp(-4.0, 4.0),
                labelOffsetY: ((startDraft.labelOffsetY ?? 0) - appliedDy)
                    .clamp(-4.0, 4.0),
              ),
            );
        break;
      case EditHandleType.label:
        final centerX = startDraft.x + (startDraft.width / 2);
        final centerY = startDraft.y + (startDraft.height / 2);
        ref
            .read(buildingMapDraftShapeProvider.notifier)
            .setDraft(
              startDraft.copyWith(
                labelOffsetX: (currentNorm.dx - centerX)
                    .clamp(-1.0, 1.0)
                    .toDouble(),
                labelOffsetY: (currentNorm.dy - centerY)
                    .clamp(-1.0, 1.0)
                    .toDouble(),
              ),
            );
        break;
      case EditHandleType.anchor:
        final centerX = startDraft.x + (startDraft.width / 2);
        final centerY = startDraft.y + (startDraft.height / 2);
        ref
            .read(buildingMapDraftShapeProvider.notifier)
            .setDraft(
              startDraft.copyWith(
                anchorOffsetX: (currentNorm.dx - centerX)
                    .clamp(-1.0, 1.0)
                    .toDouble(),
                anchorOffsetY: (currentNorm.dy - centerY)
                    .clamp(-1.0, 1.0)
                    .toDouble(),
              ),
            );
        break;
      case EditHandleType.rotate:
        final center = startDraft.center;
        final startAngle = math.atan2(
          _editPointerStart!.dy - center.dy,
          _editPointerStart!.dx - center.dx,
        );
        final currentAngle = math.atan2(
          currentNorm.dy - center.dy,
          currentNorm.dx - center.dx,
        );
        ref
            .read(buildingMapDraftShapeProvider.notifier)
            .setDraft(
              startDraft.copyWith(
                rotation: startDraft.rotation + (currentAngle - startAngle),
              ),
            );
        break;
      case EditHandleType.topLeft:
      case EditHandleType.topRight:
      case EditHandleType.bottomLeft:
      case EditHandleType.bottomRight:
        ref
            .read(buildingMapDraftShapeProvider.notifier)
            .setDraft(
              _resizeDraftFromHandle(
                startDraft: startDraft,
                handle: _activeHandle,
                currentNormalized: currentNorm,
              ),
            );
        break;
      case EditHandleType.none:
        break;
    }
  }

  void _handlePointerUp({
    required MapToolMode toolMode,
    required bool drawEnabled,
  }) {
    if (toolMode == MapToolMode.draw && drawEnabled) {
      final draft = ref.read(buildingMapDraftShapeProvider);
      setState(() {
        _rubberStart = null;
      });
      if (draft == null ||
          draft.width < _kMinDraftSize ||
          draft.height < _kMinDraftSize) {
        ref.read(buildingMapDraftShapeProvider.notifier).clear();
        ref.read(buildingMapEditFromSelectionTapProvider.notifier).clear();
        return;
      }
      ref
          .read(buildingMapEditFromSelectionTapProvider.notifier)
          .setValue(false);
      ref.read(buildingMapToolProvider.notifier).setMode(MapToolMode.edit);
    }

    if (toolMode == MapToolMode.edit) {
      setState(() {
        _activeHandle = EditHandleType.none;
        _editPointerStart = null;
        _editDraftStart = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final toolMode = ref.watch(buildingMapToolProvider);
    final draftShape = ref.watch(buildingMapDraftShapeProvider);
    final deptToMap = ref.watch(buildingMapSelectedDepartmentIdToMapProvider);
    final w = widget;

    if (!w.imgFile.existsSync()) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.broken_image_outlined, size: 48),
            TextButton(
              onPressed: () async {
                await ref
                    .read(buildingMapControllerProvider)
                    .addFloorSheet(context);
                w.onFloorsChanged();
              },
              child: const Text('Επανεπιλογή εικόνας (νέο φύλλο)'),
            ),
          ],
        ),
      );
    }

    final sz = w.decodedSize;
    if (sz == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(buildingMapControllerProvider).decodeImageForPath(w.imgPath);
      });
      return const Center(child: CircularProgressIndicator());
    }

    final drawEnabled =
        w.designModeActive &&
        toolMode == MapToolMode.draw &&
        deptToMap != null &&
        deptToMap > 0;

    final dragRotation = ref.watch(buildingMapDragRotationProvider);
    final effectiveRotationDegrees = dragRotation ?? w.rotRad * 180 / math.pi;
    final effectiveRotRad = effectiveRotationDegrees * math.pi / 180;
    final isSelectMode = toolMode == MapToolMode.select;
    final cursor = _mapViewportCursor(
      designModeActive: w.designModeActive,
      isSelectTool: isSelectMode,
    );

    final selectedDeptForLabel = _departmentById(
      w.activeDepartments,
      deptToMap,
    );
    MapLabelLayout? mapLabelLayout;
    if (w.designModeActive &&
        toolMode == MapToolMode.edit &&
        draftShape != null &&
        selectedDeptForLabel != null &&
        deptToMap != null &&
        selectedDeptForLabel.id == deptToMap) {
      mapLabelLayout = computeMapLabelLayout(
        dep: selectedDeptForLabel,
        sheetIdString: w.sheetStr,
        draftShape: draftShape,
        toolMode: toolMode,
        highlightDepartmentId: deptToMap,
        canvasSize: sz,
        labelTextOverride: _effectiveMapLabelTextForDepartment(
          selectedDeptForLabel,
        ),
      );
    }

    final editingDept = _departmentById(
      w.activeDepartments,
      _mapDisplayNameDeptId,
    );
    MapLabelLayout? editingLabelLayout;
    if (_mapDisplayNameEditing &&
        editingDept != null &&
        draftShape != null &&
        deptToMap != null &&
        editingDept.id == deptToMap) {
      editingLabelLayout = computeMapLabelLayout(
        dep: editingDept,
        sheetIdString: w.sheetStr,
        draftShape: draftShape,
        toolMode: toolMode,
        highlightDepartmentId: deptToMap,
        canvasSize: sz,
        labelTextOverride: _effectiveMapLabelTextForDepartment(editingDept),
      );
    }

    if ((!w.designModeActive || deptToMap != _mapDisplayNameDeptId) &&
        _mapDisplayNameEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _cancelMapDisplayNameEditing();
      });
    }

    ref.listen<int>(buildingMapViewportCenterRequestSeqProvider, (
      int? previous,
      int next,
    ) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _panViewportToDepartmentCenter(_viewportSize);
      });
    });

    return MouseRegion(
      cursor: cursor,
      onExit: (_) => _setHoveredDepartmentId(null),
      child: LayoutBuilder(
        builder: (context, constraints) {
          _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
          return InteractiveViewer(
            transformationController: _transform,
            constrained: false,
            boundaryMargin: const EdgeInsets.all(480),
            minScale: 0.2,
            maxScale: 6,
            panEnabled: !w.designModeActive || toolMode == MapToolMode.select,
            child: SizedBox(
              width: sz.width,
              height: sz.height,
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerHover: (event) {
                  if (!w.designModeActive) return;
                  _handlePointerHover(
                    event: event,
                    imageSize: sz,
                    rotationRad: effectiveRotRad,
                    toolMode: toolMode,
                  );
                },
                onPointerDown: (event) {
                  if (!w.designModeActive) return;
                  _handlePointerDown(
                    event: event,
                    imageSize: sz,
                    rotationRad: effectiveRotRad,
                    toolMode: toolMode,
                    drawEnabled: drawEnabled,
                    draft: draftShape,
                  );
                },
                onPointerMove: (event) {
                  if (!w.designModeActive) return;
                  _handlePointerMove(
                    event: event,
                    imageSize: sz,
                    rotationRad: effectiveRotRad,
                    toolMode: toolMode,
                    drawEnabled: drawEnabled,
                  );
                },
                onPointerUp: (_) {
                  if (!w.designModeActive) return;
                  _handlePointerUp(
                    toolMode: toolMode,
                    drawEnabled: drawEnabled,
                  );
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Transform.rotate(
                      angle: effectiveRotRad,
                      child: Image.file(
                        w.imgFile,
                        fit: BoxFit.fill,
                        filterQuality: FilterQuality.medium,
                        cacheWidth: sz.width > 4096 ? 4096 : null,
                      ),
                    ),
                    CustomPaint(
                      painter: BuildingMapSheetPainter(
                        sheetIdString: w.sheetStr,
                        departments: w.activeDepartments,
                        rotationRadians: effectiveRotRad,
                        toolMode: toolMode,
                        highlightDepartmentId: deptToMap,
                        hoveredDepartmentId: _hoveredDepartmentId,
                        draftShape: draftShape,
                        suppressMapLabelForDepartmentId: _mapDisplayNameEditing
                            ? _mapDisplayNameDeptId
                            : null,
                        mapLabelOverrideDepartmentId:
                            (!_mapDisplayNameEditing &&
                                _pendingMapDisplayNameDeptId != null)
                            ? _pendingMapDisplayNameDeptId
                            : null,
                        mapLabelOverrideText:
                            (!_mapDisplayNameEditing &&
                                _pendingMapDisplayNameText != null)
                            ? _pendingMapDisplayNameText
                            : null,
                      ),
                      child: const SizedBox.expand(),
                    ),
                    if (!_mapDisplayNameEditing &&
                        mapLabelLayout != null &&
                        selectedDeptForLabel != null)
                      Transform.rotate(
                        alignment: Alignment.center,
                        angle: effectiveRotRad,
                        child: SizedBox(
                          width: sz.width,
                          height: sz.height,
                          child: Stack(
                            clipBehavior: Clip.none,
                            fit: StackFit.expand,
                            children: [
                              Positioned(
                                left: mapLabelLayout.pencilHitRect.left,
                                top: mapLabelLayout.pencilHitRect.top,
                                width: mapLabelLayout.pencilHitRect.width,
                                height: mapLabelLayout.pencilHitRect.height,
                                child: Tooltip(
                                  message:
                                      'Επωνυμία χάρτη (ή διπλό κλικ στην ετικέτα)',
                                  child: IconButton(
                                    padding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                    constraints: const BoxConstraints(
                                      minWidth: 40,
                                      minHeight: 40,
                                    ),
                                    icon: Icon(
                                      Icons.edit_outlined,
                                      size: 20,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                    onPressed: () =>
                                        _beginMapDisplayNameEditing(
                                          selectedDeptForLabel,
                                        ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_mapDisplayNameEditing &&
                        editingLabelLayout != null &&
                        _mapDisplayNameCtrl != null &&
                        _mapDisplayNameFocus != null)
                      Transform.rotate(
                        alignment: Alignment.center,
                        angle: effectiveRotRad,
                        child: SizedBox(
                          width: sz.width,
                          height: sz.height,
                          child: Stack(
                            clipBehavior: Clip.none,
                            fit: StackFit.expand,
                            children: [
                              Positioned(
                                left: (editingLabelLayout.textTopLeft.dx - 4)
                                    .clamp(0.0, sz.width - 120),
                                top: (editingLabelLayout.textTopLeft.dy - 4)
                                    .clamp(0.0, sz.height - 48),
                                width: math
                                    .min(
                                      sz.width -
                                          (editingLabelLayout.textTopLeft.dx -
                                                  4)
                                              .clamp(0.0, sz.width),
                                      math.max(
                                        200.0,
                                        editingLabelLayout
                                                .textPainterSize
                                                .width +
                                            160,
                                      ),
                                    )
                                    .clamp(120.0, sz.width),
                                child: Material(
                                  elevation: 6,
                                  borderRadius: BorderRadius.circular(8),
                                  child: TextField(
                                    controller: _mapDisplayNameCtrl,
                                    focusNode: _mapDisplayNameFocus,
                                    autofocus: true,
                                    style: TextStyle(
                                      fontSize: editingLabelLayout.fontSize,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black87,
                                    ),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      hintText:
                                          'Επιβεβαίωση draft (✓) για αποθήκευση — κενό = όνομα τμήματος',
                                      filled: true,
                                      fillColor: Theme.of(
                                        context,
                                      ).colorScheme.surface,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 8,
                                          ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    maxLines: 2,
                                    textInputAction: TextInputAction.done,
                                    onSubmitted: (_) =>
                                        _softEndMapDisplayNameEditing(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (toolMode == MapToolMode.edit && draftShape != null)
                      Positioned(
                        left: (draftShape.center.dx * sz.width + 80)
                            .clamp(12.0, math.max(12.0, sz.width - 280.0))
                            .toDouble(),
                        top: ((draftShape.y * sz.height) - 56)
                            .clamp(12.0, math.max(12.0, sz.height - 56.0))
                            .toDouble(),
                        child: Material(
                          elevation: 4,
                          borderRadius: BorderRadius.circular(10),
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHigh,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Ακύρωση draft',
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.close),
                                  onPressed: () {
                                    final mapDept = ref.read(
                                      buildingMapSelectedDepartmentIdToMapProvider,
                                    );
                                    if (_pendingMapDisplayNameDeptId ==
                                        mapDept) {
                                      _pendingMapDisplayNameDeptId = null;
                                      _pendingMapDisplayNameText = null;
                                    }
                                    final fromSelection = ref.read(
                                      buildingMapEditFromSelectionTapProvider,
                                    );
                                    ref
                                        .read(
                                          buildingMapDraftShapeProvider
                                              .notifier,
                                        )
                                        .clear();
                                    ref
                                        .read(
                                          buildingMapEditFromSelectionTapProvider
                                              .notifier,
                                        )
                                        .clear();
                                    ref
                                        .read(buildingMapToolProvider.notifier)
                                        .setMode(
                                          fromSelection
                                              ? MapToolMode.select
                                              : MapToolMode.draw,
                                        );
                                  },
                                ),
                                IconButton(
                                  tooltip: 'Χρώμα περιοχής στο χάρτη',
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.palette_outlined),
                                  onPressed: () async {
                                    DepartmentModel? selectedDept;
                                    for (final dep in w.activeDepartments) {
                                      if (dep.id == deptToMap) {
                                        selectedDept = dep;
                                        break;
                                      }
                                    }
                                    if (selectedDept?.id == null ||
                                        w.currentSheetId == null) {
                                      return;
                                    }
                                    await _changeMapFillColorForDepartment(
                                      selectedDept!,
                                    );
                                  },
                                ),
                                IconButton(
                                  tooltip: 'Επιβεβαίωση draft',
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.check),
                                  onPressed: () async {
                                    DepartmentModel? selectedDept;
                                    for (final dep in w.activeDepartments) {
                                      if (dep.id == deptToMap) {
                                        selectedDept = dep;
                                        break;
                                      }
                                    }
                                    if (selectedDept?.id == null) return;
                                    await _persistMapDisplayNameForDraftDepartment(
                                      selectedDept!.id!,
                                    );
                                    if (!context.mounted) return;
                                    await ref
                                        .read(buildingMapControllerProvider)
                                        .commitDraftToDatabase(
                                          context: context,
                                          draft: draftShape,
                                          dept: selectedDept,
                                          floorId: w.currentSheetId!,
                                        );
                                    if (context.mounted) {
                                      setState(() {});
                                    }
                                  },
                                ),
                                Builder(
                                  builder: (ctx) {
                                    DepartmentModel? selectedDept;
                                    for (final dep in w.activeDepartments) {
                                      if (dep.id == deptToMap) {
                                        selectedDept = dep;
                                        break;
                                      }
                                    }
                                    final mappedOnSheet =
                                        selectedDept != null &&
                                        (selectedDept.mapFloor ?? '') ==
                                            w.sheetStr &&
                                        selectedDept.isMapped;
                                    return IconButton(
                                      tooltip: mappedOnSheet
                                          ? 'Αφαίρεση τμήματος από τον χάρτη'
                                          : 'Δεν υπάρχει αποθηκευμένη θέση σε αυτό το φύλλο',
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: !mappedOnSheet
                                          ? null
                                          : () async {
                                              await ref
                                                  .read(
                                                    buildingMapControllerProvider,
                                                  )
                                                  .removeDepartmentFromFloorAfterConfirm(
                                                    context: context,
                                                    dept: selectedDept!,
                                                    sheetStr: w.sheetStr,
                                                  );
                                              if (ctx.mounted) {
                                                setState(() {});
                                              }
                                            },
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
