import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:custom_mouse_cursor/custom_mouse_cursor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/building_map_floor.dart';
import '../../models/department_model.dart';
import '../../screens/widgets/department_color_palette.dart';
import '../building_map_draft_geometry.dart';
import '../building_map_geometry.dart';
import '../building_map_label_layout.dart';
import '../building_map_sheet_export_key.dart';
import '../controllers/building_map_controller.dart';
import '../providers/building_map_providers.dart';
import '../services/building_map_placement_replacement.dart';
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
    required this.imgExists,
    required this.decodedSize,
    required this.activeDepartments,
    required this.floors,
    required this.currentSheetId,
    required this.onFloorsChanged,
  });

  final bool designModeActive;
  final String sheetStr;
  final double rotRad;
  final String imgPath;
  final File imgFile;

  /// Το απάντησε ο γονέας, μία φορά ανά διαδρομή.
  ///
  /// Ο καμβάς ξαναχτίζεται σε κάθε σύρσιμο του ποντικιού· ένας έλεγχος δίσκου
  /// εδώ σήμαινε ερώτημα στο αρχείο σύστημα δεκάδες φορές το δευτερόλεπτο.
  final bool imgExists;

  final Size? decodedSize;
  final List<DepartmentModel> activeDepartments;

  /// Κατάλογος φύλλων — ονοματίζει ορόφους στα μηνύματα αντικατάστασης θέσης.
  final List<BuildingMapFloor> floors;
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

  /// Μετατόπιση εργαλειοθήκης (από σύρσιμο χρήστη).
  Offset _toolbarDragOffset = Offset.zero;

  static const Duration _kLabelDoubleTapGap = Duration(milliseconds: 400);
  static const double _kLabelDoubleTapSlopPx = 28;

  /// Απόκρυψη από hit-test διπλού κλικ περιοχής που επικαλύπτει το handle της ετικέτας.
  static const double _kLabelDragHandleExcludeRadiusPx = 14;

  Offset? _rubberStart;
  Offset? _editPointerStart;
  DraftDepartmentShape? _editDraftStart;
  EditHandleType _activeHandle = EditHandleType.none;
  int? _hoveredDepartmentId;

  /// Space κρατημένο = προσωρινό pan στη Σχεδίαση/Επεξεργασία (μοτίβο Photoshop/Figma).
  bool _spaceHeld = false;

  /// Ενεργό σύρσιμο με το μεσαίο πλήκτρο ποντικιού (μοτίβο CAD/Blender).
  bool _middlePanActive = false;

  DateTime? _labelDoubleTapTime;
  Offset? _labelDoubleTapPosCanvas;

  bool _mapDisplayNameEditing = false;
  int? _mapDisplayNameDeptId;
  TextEditingController? _mapDisplayNameCtrl;
  FocusNode? _mapDisplayNameFocus;

  /// Τμήματα που δεν πρέπει να σχεδιάζονται/πιάνονται από hit-test λόγω [`map_hidden`].
  /// Ενημερώνεται στο `build` και διαβάζεται από `_hitTestDepartmentAtLocalPosition`.
  Set<int> _currentHiddenIds = const <int>{};

  /// Τοπικό κείμενο επωνυμίας χάρτη μετά blur/Enter — αποθηκεύεται στη βάση μόνο με Επιβεβαίωση draft (✓).
  int? _pendingMapDisplayNameDeptId;
  String? _pendingMapDisplayNameText;

  /// Native κέρσορες (Windows/desktop)· το [custom_mouse_cursor] τους περνά στο σύστημα.
  CustomMouseCursor? _nativeSelectHandCursor;
  CustomMouseCursor? _nativeDrawCrossCursor;
  CustomMouseCursor? _nativeGrabCursor;

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
    HardwareKeyboard.instance.removeHandler(_handleGlobalSpaceKey);
    _mapDisplayNameCtrl?.dispose();
    _mapDisplayNameFocus?.dispose();
    _transform.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleGlobalSpaceKey);
    unawaited(_preloadNativeToolCursors());
  }

  /// True όταν το πληκτρολόγιο «ανήκει» σε πεδίο κειμένου (π.χ. αναζήτηση, επωνυμία χάρτη)
  /// — εκεί το Space πρέπει να γράφει κενό, όχι να κάνει pan.
  bool _isTextInputFocused() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    if (focusContext.widget is EditableText) return true;
    return focusContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  /// Καθολικός χειριστής Space: όσο κρατιέται, το αριστερό σύρσιμο κάνει pan.
  bool _handleGlobalSpaceKey(KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.space) return false;

    if (event is KeyUpEvent) {
      if (!_spaceHeld) return false;
      if (mounted) {
        setState(() => _spaceHeld = false);
      } else {
        _spaceHeld = false;
      }
      return true;
    }

    if (!mounted || !widget.designModeActive) return false;
    if (_mapDisplayNameEditing || _isTextInputFocused()) return false;
    // Μην διακόπτεις σύρσιμο σχήματος/λαβής που είναι σε εξέλιξη.
    if (_rubberStart != null || _activeHandle != EditHandleType.none) {
      return false;
    }

    if (event is KeyDownEvent && !_spaceHeld) {
      setState(() => _spaceHeld = true);
    }
    // Καταναλώνει και τα επαναλαμβανόμενα events όσο κρατιέται το πλήκτρο.
    return _spaceHeld;
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
      final grab = await CustomMouseCursor.icon(
        Icons.open_with,
        size: 26,
        hotX: 13,
        hotY: 13,
        color: const Color(0xFF212121),
      );
      if (!mounted) return;
      setState(() {
        _nativeSelectHandCursor = hand;
        _nativeDrawCrossCursor = cross;
        _nativeGrabCursor = grab;
      });
    } catch (_) {
      // Αφήνουμε null· χρησιμοποιείται το υπόλοιπο fallback στο build.
    }
  }

  MouseCursor _mapViewportCursor({
    required bool designModeActive,
    required bool isSelectTool,
    required bool panActive,
  }) {
    if (!designModeActive) return SystemMouseCursors.basic;
    if (panActive) {
      return _nativeGrabCursor ?? SystemMouseCursors.grab;
    }
    final nativeReady =
        _nativeSelectHandCursor != null && _nativeDrawCrossCursor != null;
    if (isSelectTool) {
      return nativeReady ? _nativeSelectHandCursor! : SystemMouseCursors.grab;
    }
    return nativeReady ? _nativeDrawCrossCursor! : SystemMouseCursors.basic;
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
    final Matrix4 pan = Matrix4.translationValues(delta.dx, delta.dy, 0.0);
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

  bool _hasDraftChanges(DepartmentModel dept, DraftDepartmentShape draft) {
    if (draftShapeDiffersFromSaved(
      dept: dept,
      draft: draft,
      sheetStr: widget.sheetStr,
    )) {
      return true;
    }
    String? edited;
    if (_mapDisplayNameEditing &&
        _mapDisplayNameDeptId == dept.id &&
        _mapDisplayNameCtrl != null) {
      edited = _mapDisplayNameCtrl!.text;
    } else if (_pendingMapDisplayNameDeptId == dept.id) {
      edited = _pendingMapDisplayNameText;
    }

    if (edited != null &&
        edited != (dept.mapCustomName ?? dept.name) &&
        edited != dept.name) {
      return true;
    }

    return false;
  }

  bool _detectLabelDoubleTap(Offset tapPosPx) {
    final now = DateTime.now();
    final prev = _labelDoubleTapTime;
    final prevPos = _labelDoubleTapPosCanvas;
    _labelDoubleTapTime = now;
    _labelDoubleTapPosCanvas = tapPosPx;
    if (prev == null ||
        prevPos == null ||
        now.difference(prev) > _kLabelDoubleTapGap ||
        (tapPosPx - prevPos).distance > _kLabelDoubleTapSlopPx) {
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

  void _insertMapDisplayNameNewline() {
    final ctrl = _mapDisplayNameCtrl;
    if (ctrl == null) return;
    final text = ctrl.text;
    final sel = ctrl.selection;
    final start = sel.start >= 0 ? sel.start : text.length;
    final end = sel.end >= 0 ? sel.end : start;
    final updated = text.replaceRange(start, end, '\n');
    ctrl.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: start + 1),
    );
  }

  KeyEventResult _onMapDisplayNameFieldKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.enter) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      _insertMapDisplayNameNewline();
      return KeyEventResult.handled;
    }
    _softEndMapDisplayNameEditing();
    return KeyEventResult.handled;
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
    _mapDisplayNameFocus = FocusNode(onKeyEvent: _onMapDisplayNameFieldKey)
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

  DepartmentModel? _hitTestDepartmentAtLocalPosition({
    required Offset localPosition,
    required Size imageSize,
    required double rotationRad,
  }) {
    final normalized = localToNormalized(localPosition, imageSize, rotationRad);
    final deps = widget.activeDepartments.reversed;
    for (final dep in deps) {
      if ((dep.mapFloor ?? '') != widget.sheetStr) continue;
      if (dep.id != null && _currentHiddenIds.contains(dep.id)) continue;
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
      if (pointInsideDepartmentRect(
        pointNormalized: normalized,
        departmentShape: shape,
      )) {
        return dep;
      }
    }
    // Ετικέτα / γραμμές ονόματος (ίδια γεωμετρία με τον painter): ανύψωση στο hover όπως το ορθογώνιο.
    for (final dep in deps) {
      if (dep.id != null && _currentHiddenIds.contains(dep.id)) continue;
      final labelLayout = computeMapLabelLayout(
        dep: dep,
        sheetIdString: widget.sheetStr,
        draftShape: null,
        toolMode: MapToolMode.select,
        highlightDepartmentId: null,
        canvasSize: imageSize,
        sheetRotationRadians: rotationRad,
        labelTextOverride: _effectiveMapLabelTextForDepartment(dep),
      );
      if (labelLayout != null &&
          labelLayout.textAndUnderlineHitRect.contains(localPosition)) {
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
    final normalized = localToNormalized(local, imageSize, rotationRad);

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

    // Σχεδίαση/επιλογή/επεξεργασία ΜΟΝΟ με το αριστερό πλήκτρο —
    // το μεσαίο ανήκει στο pan και δεν πρέπει να ξεκινά σχήμα.
    if (event.buttons != kPrimaryMouseButton) return;

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
        _toolbarDragOffset = Offset.zero;
        ref.read(buildingMapToolProvider.notifier).setMode(MapToolMode.edit);
      }
      return;
    }

    if (toolMode == MapToolMode.draw && drawEnabled) {
      setState(() {
        _rubberStart = normalized;
        _toolbarDragOffset = Offset.zero;
      });
      ref
          .read(buildingMapDraftShapeProvider.notifier)
          .setDraft(DraftDepartmentShape.fromCorners(normalized, normalized));
      return;
    }

    if (toolMode == MapToolMode.edit && draft != null) {
      final deptToMap = ref.read(buildingMapSelectedDepartmentIdToMapProvider);
      final selectedDept = _departmentById(widget.activeDepartments, deptToMap);
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
          sheetRotationRadians: rotationRad,
          labelTextOverride: _effectiveMapLabelTextForDepartment(selectedDept),
        );
        if (labelLayout != null) {
          final inText = labelLayout.textAndUnderlineHitRect.contains(local);
          final onPurpleHandle =
              (local - labelLayout.labelCenter).distance <=
              _kLabelDragHandleExcludeRadiusPx;
          if (inText && !onPurpleHandle) {
            if (_detectLabelDoubleTap(local)) {
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

      final hit = hitTestDraftHandle(draft, local, imageSize, rotationRad);
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
    final currentNorm = localToNormalized(local, imageSize, rotationRad);

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
      case EditHandleType.labelBoxTopLeft:
      case EditHandleType.labelBoxTopRight:
      case EditHandleType.labelBoxBottomLeft:
      case EditHandleType.labelBoxBottomRight:
        final deptToMap = ref.read(
          buildingMapSelectedDepartmentIdToMapProvider,
        );
        final selectedDept = _departmentById(
          widget.activeDepartments,
          deptToMap,
        );
        final labelText = selectedDept != null
            ? _effectiveMapLabelTextForDepartment(selectedDept)
            : '';
        final resized = resizeLabelBoxFromHandle(
          startDraft: startDraft,
          handle: _activeHandle,
          localPositionCanvas: local,
          canvasSize: imageSize,
          sheetRotationRad: rotationRad,
          labelText: labelText,
        );
        ref
            .read(buildingMapControllerProvider)
            .updateDepartmentLabelDimensions(
              width: resized.labelWidth,
              height: resized.labelHeight,
              labelText: labelText,
            );
        break;
      default:
        final next = dragDraftWithHandle(
          startDraft: startDraft,
          handle: _activeHandle,
          pointerStartNormalized: _editPointerStart!,
          currentNormalized: currentNorm,
        );
        if (next != null) {
          ref.read(buildingMapDraftShapeProvider.notifier).setDraft(next);
        }
        break;
    }
  }

  void _handlePointerUp({
    required MapToolMode toolMode,
    required bool drawEnabled,
    required Size imageSize,
    required double rotationRad,
  }) {
    if (toolMode == MapToolMode.draw && drawEnabled) {
      final draft = ref.read(buildingMapDraftShapeProvider);
      setState(() {
        _rubberStart = null;
      });
      if (draft == null ||
          draft.width < kBuildingMapMinDraftSize ||
          draft.height < kBuildingMapMinDraftSize) {
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

    if (!w.imgExists) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.broken_image_outlined, size: 48),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Η εικόνα κάτοψης δεν βρέθηκε.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            if (w.currentSheetId != null) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () async {
                  await ref
                      .read(buildingMapControllerProvider)
                      .replaceFloorSheetImageById(context, w.currentSheetId!);
                  w.onFloorsChanged();
                },
                icon: const Icon(Icons.image_outlined),
                label: const Text('Επανεπιλογή εικόνας'),
              ),
            ],
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

    final revealedDeptId = ref.watch(
      buildingMapSearchRevealedDepartmentIdProvider,
    );
    final hiddenIds = <int>{};
    for (final d in w.activeDepartments) {
      if (d.id == null) continue;
      if (!d.isHiddenOnMap) continue;
      if ((d.mapFloor ?? '') != w.sheetStr) continue;
      if (revealedDeptId != null && d.id == revealedDeptId) continue;
      hiddenIds.add(d.id!);
    }
    _currentHiddenIds = hiddenIds;

    final dragRotation = ref.watch(buildingMapDragRotationProvider);
    final effectiveRotationDegrees = dragRotation ?? w.rotRad * 180 / math.pi;
    final effectiveRotRad = effectiveRotationDegrees * math.pi / 180;
    final isSelectMode = toolMode == MapToolMode.select;

    // Pan στη Σχεδίαση/Επεξεργασία: διακόπτης εργαλειοθήκης ή κρατημένο Space
    // ενεργοποιούν το ενσωματωμένο pan του InteractiveViewer (αριστερό σύρσιμο)·
    // το μεσαίο πλήκτρο μετατοπίζει χειροκίνητα όταν το ενσωματωμένο είναι κλειστό.
    final panLock = ref.watch(buildingMapPanLockProvider);
    final panOverlayActive =
        w.designModeActive && !isSelectMode && (panLock || _spaceHeld);
    final builtInPanEnabled =
        !w.designModeActive || isSelectMode || panOverlayActive;

    final cursor = _mapViewportCursor(
      designModeActive: w.designModeActive,
      isSelectTool: isSelectMode,
      panActive: panOverlayActive || _middlePanActive,
    );

    final selectedDeptForLabel = _departmentById(
      w.activeDepartments,
      deptToMap,
    );
    MapLabelLayout? mapLabelLayout;
    Rect? effectivePencilRect;
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
        sheetRotationRadians: effectiveRotRad,
        labelTextOverride: _effectiveMapLabelTextForDepartment(
          selectedDeptForLabel,
        ),
      );
      if (mapLabelLayout != null) {
        final raw = mapLabelLayout.pencilHitRect;
        final textRect = mapLabelLayout.textAndUnderlineHitRect;
        final resolved = resolvePencilHitRect(
          raw: raw,
          textRect: textRect,
          canvasSize: sz,
        );
        effectivePencilRect = resolved;
      }
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
        sheetRotationRadians: effectiveRotRad,
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
          return Listener(
            // Pan με το μεσαίο πλήκτρο: μετατόπιση σε συντεταγμένες viewport,
            // μόνο όταν το ενσωματωμένο pan είναι απενεργοποιημένο (Σχεδίαση/Επεξεργασία).
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) {
              if (builtInPanEnabled) return;
              if (event.buttons == kMiddleMouseButton) {
                setState(() => _middlePanActive = true);
              }
            },
            onPointerMove: (event) {
              if (!_middlePanActive) return;
              if ((event.buttons & kMiddleMouseButton) == 0) return;
              _transform.value =
                  Matrix4.translationValues(
                    event.delta.dx,
                    event.delta.dy,
                    0.0,
                  ) *
                  _transform.value;
            },
            onPointerUp: (_) {
              if (_middlePanActive) {
                setState(() => _middlePanActive = false);
              }
            },
            onPointerCancel: (_) {
              if (_middlePanActive) {
                setState(() => _middlePanActive = false);
              }
            },
            child: InteractiveViewer(
              transformationController: _transform,
              constrained: false,
              boundaryMargin: const EdgeInsets.all(480),
              minScale: 0.2,
              maxScale: 6,
              panEnabled: builtInPanEnabled,
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
                    // Όσο γίνεται pan (διακόπτης/Space/μεσαίο), δεν ξεκινά σχεδίαση.
                    if (panOverlayActive || _middlePanActive) return;
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
                    if (panOverlayActive || _middlePanActive) return;
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
                    if (_middlePanActive) return;
                    _handlePointerUp(
                      toolMode: toolMode,
                      drawEnabled: drawEnabled,
                      imageSize: sz,
                      rotationRad: effectiveRotRad,
                    );
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      RepaintBoundary(
                        key: buildingMapSheetExportRepaintKey,
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
                                hiddenDepartmentIds: hiddenIds,
                                suppressMapLabelForDepartmentId:
                                    _mapDisplayNameEditing
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
                          ],
                        ),
                      ),
                      if (!_mapDisplayNameEditing &&
                          mapLabelLayout != null &&
                          selectedDeptForLabel != null)
                        Builder(
                          builder: (context) {
                            final pencilRect =
                                effectivePencilRect ??
                                resolvePencilHitRect(
                                  raw: mapLabelLayout!.pencilHitRect,
                                  textRect:
                                      mapLabelLayout.textAndUnderlineHitRect,
                                  canvasSize: sz,
                                );
                            return SizedBox(
                              width: sz.width,
                              height: sz.height,
                              child: Stack(
                                clipBehavior: Clip.none,
                                fit: StackFit.expand,
                                children: [
                                  Positioned(
                                    left: pencilRect.left,
                                    top: pencilRect.top,
                                    width: pencilRect.width,
                                    height: pencilRect.height,
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
                                        onPressed: () {
                                          _beginMapDisplayNameEditing(
                                            selectedDeptForLabel,
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      if (_mapDisplayNameEditing &&
                          editingLabelLayout != null &&
                          _mapDisplayNameCtrl != null &&
                          _mapDisplayNameFocus != null)
                        SizedBox(
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
                                    .clamp(0.0, sz.height - 96),
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
                                          'Enter: τέλος · Shift+Enter: νέα γραμμή · ✓ για αποθήκευση',
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
                                    keyboardType: TextInputType.multiline,
                                    minLines: 1,
                                    maxLines: kBuildingMapLabelMaxLines,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (toolMode == MapToolMode.edit && draftShape != null)
                        Builder(
                          builder: (context) {
                            final sheetCenter = Offset(
                              sz.width / 2,
                              sz.height / 2,
                            );
                            final mapCenter = Offset(
                              draftShape.center.dx * sz.width,
                              draftShape.center.dy * sz.height,
                            );
                            final screenCenter = rotateAroundCenter(
                              mapCenter,
                              sheetCenter,
                              effectiveRotRad,
                            );
                            final toolbarLeft =
                                (screenCenter.dx + 80 + _toolbarDragOffset.dx)
                                    .clamp(
                                      12.0,
                                      math.max(12.0, sz.width - 280.0),
                                    )
                                    .toDouble();
                            final toolbarTop =
                                (screenCenter.dy - 56 + _toolbarDragOffset.dy)
                                    .clamp(
                                      12.0,
                                      math.max(12.0, sz.height - 56.0),
                                    )
                                    .toDouble();

                            DepartmentModel? selectedDept;
                            for (final dep in w.activeDepartments) {
                              if (dep.id == deptToMap) {
                                selectedDept = dep;
                                break;
                              }
                            }
                            final bool hasChanges = selectedDept != null
                                ? _hasDraftChanges(selectedDept, draftShape)
                                : true;

                            return Positioned(
                              left: toolbarLeft,
                              top: toolbarTop,
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
                                      MouseRegion(
                                        cursor:
                                            _nativeGrabCursor ??
                                            SystemMouseCursors.grab,
                                        child: GestureDetector(
                                          onPanUpdate: (details) {
                                            setState(() {
                                              _toolbarDragOffset +=
                                                  details.delta;
                                            });
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              right: 8.0,
                                              left: 4.0,
                                            ),
                                            child: Icon(
                                              Icons.drag_indicator,
                                              size: 20,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Ακύρωση draft',
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(Icons.close),
                                        onPressed: () {
                                          _toolbarDragOffset = Offset.zero;
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
                                              .read(
                                                buildingMapToolProvider
                                                    .notifier,
                                              )
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
                                        icon: const Icon(
                                          Icons.palette_outlined,
                                        ),
                                        onPressed: () async {
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
                                        tooltip:
                                            selectedDept != null &&
                                                resolveBuildingMapPlacementReplacement(
                                                  department: selectedDept,
                                                  targetSheetId:
                                                      w.currentSheetId ?? -1,
                                                ).replacesPlacementOnThisSheet
                                            ? 'Αποθήκευση — αντικαθιστά την '
                                                  'αποθηκευμένη θέση σε αυτό το φύλλο'
                                            : 'Επιβεβαίωση draft',
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(Icons.check),
                                        onPressed: !hasChanges
                                            ? null
                                            : () async {
                                                _toolbarDragOffset =
                                                    Offset.zero;
                                                if (selectedDept?.id == null) {
                                                  return;
                                                }
                                                await _persistMapDisplayNameForDraftDepartment(
                                                  selectedDept!.id!,
                                                );
                                                if (!context.mounted) return;
                                                await ref
                                                    .read(
                                                      buildingMapControllerProvider,
                                                    )
                                                    .commitDraftToDatabase(
                                                      context: context,
                                                      draft: draftShape,
                                                      dept: selectedDept!,
                                                      floorId:
                                                          w.currentSheetId!,
                                                      floors: w.floors,
                                                    );
                                                if (context.mounted) {
                                                  setState(() {});
                                                }
                                              },
                                      ),
                                      Builder(
                                        builder: (ctx) {
                                          final mappedOnSheet =
                                              selectedDept != null &&
                                              (selectedDept.mapFloor ?? '') ==
                                                  w.sheetStr &&
                                              selectedDept.isMapped;
                                          return IconButton(
                                            tooltip: mappedOnSheet
                                                ? 'Αφαίρεση τμήματος από τον χάρτη'
                                                : 'Δεν υπάρχει αποθηκευμένη θέση σε αυτό το φύλλο',
                                            visualDensity:
                                                VisualDensity.compact,
                                            icon: const Icon(
                                              Icons.delete_outline,
                                            ),
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
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
