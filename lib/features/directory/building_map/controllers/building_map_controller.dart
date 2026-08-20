import 'dart:async';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/utils/picker_location_memory.dart';
import '../../../../core/database/building_map_repository.dart';
import '../../../../core/database/department_repository.dart';
import '../../../../core/database/omnisearch_service.dart';
import '../../../../core/models/building_map_floor.dart';
import '../../../../core/services/lookup_service.dart';
import '../../../calls/models/equipment_model.dart';
import '../../../calls/models/user_model.dart';
import '../../../../core/services/building_map_storage.dart';
import '../../../floor_map/services/floor_color_assignment_service.dart';
import '../../models/department_model.dart';
import '../../providers/department_directory_provider.dart';
import '../models/building_map_jump_target.dart';
import '../../screens/widgets/department_color_palette.dart';
import '../building_map_label_layout.dart';
import '../providers/building_map_providers.dart';
import '../widgets/building_map_commit_color_dialog.dart';
import '../widgets/building_map_confirm_dialogs.dart';
import '../widgets/building_map_floor_delete_dialog.dart';
import '../services/building_map_floor_ordering.dart';
import '../widgets/building_map_floor_sheet_add_dialog.dart';
import '../widgets/building_map_floor_sheet_edit_dialog.dart';
import '../widgets/building_map_jump_pick_dialogs.dart';
import '../widgets/building_map_portable_image_copy_dialog.dart';

final buildingMapControllerProvider = Provider<BuildingMapController>(
  (ref) => BuildingMapController(ref),
);

/// Επιλογή διαγραφής εικόνας από το διάλογο διαγραφής φύλλου.
/// Συντονισμός βάσης, αποθήκευσης εικόνων και καταστάσεων Riverpod για τον χάρτη κτιρίου.
class BuildingMapController {
  BuildingMapController(this._ref);

  final Ref _ref;

  /// Αρχικός συγχρονισμός επιλεγμένου φύλλου μετά φόρτωση λίστας (μία φορά ανά φόρτωμα).
  bool appliedInitialFloorSync = false;

  void resetSession() {
    appliedInitialFloorSync = false;
  }

  Future<void> decodeImageForPath(String imagePath) async {
    final decoded = _ref.read(buildingMapDecodedImageSizeProvider.notifier);
    if (imagePath.isEmpty) {
      decoded.setSize(null);
      return;
    }
    final f = await BuildingMapStorage.fileForStoredPath(imagePath);
    if (!await f.exists()) {
      decoded.setSize(null);
      return;
    }
    try {
      final bytes = await f.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final sz = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      decoded.setSize(sz);
    } catch (_) {
      decoded.setSize(null);
    }
  }

  Future<void> syncSheetSelection(List<BuildingMapFloor> floors) async {
    if (floors.isEmpty) return;
    final sel = _ref.read(buildingMapSelectedSheetIdProvider);
    if (sel == null || !floors.any((f) => f.id == sel)) {
      _ref
          .read(buildingMapSelectedSheetIdProvider.notifier)
          .setSheet(floors.first.id);
    }
    final sid = _ref.read(buildingMapSelectedSheetIdProvider);
    final sheet = floors.cast<BuildingMapFloor?>().firstWhere(
      (fl) => fl?.id == sid,
      orElse: () => null,
    );
    await decodeImageForPath(sheet?.imagePath ?? '');
  }

  Future<void> selectFloorFromList(
    int floorId,
    List<BuildingMapFloor> floors, {
    bool clearSelectedDepartment = true,
  }) async {
    _ref.read(buildingMapSelectedSheetIdProvider.notifier).setSheet(floorId);
    if (clearSelectedDepartment) {
      _ref
          .read(buildingMapSelectedDepartmentIdToMapProvider.notifier)
          .setDept(null);
      _ref.read(buildingMapSearchUnresolvedNoticeProvider.notifier).clear();
    }
    _ref.read(buildingMapDraftShapeProvider.notifier).clear();
    _ref.read(buildingMapEditFromSelectionTapProvider.notifier).clear();
    _ref.read(buildingMapSearchRevealedDepartmentIdProvider.notifier).clear();
    _ref.read(buildingMapToolProvider.notifier).setMode(MapToolMode.select);
    final path = floors
        .cast<BuildingMapFloor?>()
        .firstWhere((fl) => fl?.id == floorId, orElse: () => null)
        ?.imagePath;
    await decodeImageForPath(path ?? '');
  }

  bool draftOverlapsOthers(Rect draft, String sheetStr, int excludeDeptId) {
    final deps = _ref
        .read(departmentDirectoryProvider)
        .allDepartments
        .where((d) => !d.isDeleted);
    for (final d in deps) {
      if (d.id == excludeDeptId) continue;
      if ((d.mapFloor ?? '') != sheetStr) continue;
      final nx = d.mapX;
      final ny = d.mapY;
      final nw = d.mapWidth;
      final nh = d.mapHeight;
      if (nx == null || ny == null || nw == null || nh == null) continue;
      if (nw <= 0 || nh <= 0) continue;
      final other = Rect.fromLTWH(nx, ny, nw, nh);
      if (draft.overlaps(other)) return true;
    }
    return false;
  }

  Future<bool> confirmOverlapIfNeeded(
    BuildContext context,
    Rect draft,
    String sheetStr,
    int deptId,
  ) async {
    if (!draftOverlapsOthers(draft, sheetStr, deptId)) return true;
    return showBuildingMapOverlapConfirmDialog(context);
  }

  List<Color> _distinctMapFillColorsOnSheet(
    List<DepartmentModel> all,
    String sheetStr,
    int? excludeDepartmentId,
  ) {
    final out = <Color>[];
    final seen = <String>{};
    for (final d in all) {
      if (d.isDeleted) continue;
      if ((d.mapFloor ?? '') != sheetStr) continue;
      if (excludeDepartmentId != null && d.id == excludeDepartmentId) continue;
      final c = tryParseDepartmentHex(d.color);
      if (c == null) continue;
      final key = colorToDepartmentHex(c);
      if (seen.add(key)) {
        out.add(c);
      }
    }
    return out;
  }

  /// Ενημέρωση χρώματος γεμίσματος περιοχής στο χάρτη + cache ανάθεσης χρωμάτων.
  Future<void> applyDepartmentMapFillColor({
    required BuildContext context,
    required DepartmentModel dept,
    required int floorId,
    required Color newColor,
  }) async {
    if (dept.id == null) return;
    final old = tryParseDepartmentHex(dept.color);
    final hex = colorToDepartmentHex(newColor);
    final db = await DatabaseHelper.instance.database;
    await DepartmentRepository(db).updateDepartment(dept.id!, {'color': hex});
    FloorColorAssignmentService.instance.overrideColor(
      floorId,
      newColor,
      replaceUsed: old,
    );
    await _ref.read(departmentDirectoryProvider.notifier).loadDepartments();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ενημερώθηκε το χρώμα περιοχής στο χάρτη.'),
        ),
      );
    }
  }

  Future<void> commitDraftToDatabase({
    required BuildContext context,
    required DraftDepartmentShape draft,
    required DepartmentModel dept,
    required int floorId,
  }) async {
    final draftRect = draft.rect;
    final sheetStr = floorId.toString();
    if (!await confirmOverlapIfNeeded(context, draftRect, sheetStr, dept.id!)) {
      return;
    }
    if (!context.mounted) return;

    final manualFloorId = dept.floorId;
    if (manualFloorId != null && manualFloorId != floorId && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Ο όροφος στη φόρμα τμήματος (#$manualFloorId) διαφέρει από το τρέχον φύλλο '
            '(#$floorId). Θα αποθηκευτεί η θέση στο τρέχον φύλλο (προτεραιότητα χάρτη).',
          ),
        ),
      );
    }

    final allDepts = _ref.read(departmentDirectoryProvider).allDepartments;
    final additionalUsed = _distinctMapFillColorsOnSheet(
      allDepts,
      sheetStr,
      dept.id,
    );
    final previousFloorStr = dept.mapFloor?.trim();
    final previousFloorId = int.tryParse(previousFloorStr ?? '');
    final movingToNewFloor =
        previousFloorStr != null && previousFloorStr != sheetStr;
    final existingColor = dept.color?.trim();
    final shouldKeepCurrentColor =
        previousFloorStr == sheetStr &&
        dept.isMapped &&
        existingColor != null &&
        existingColor.isNotEmpty;

    void removeOldFloorColorIfMoved() {
      if (movingToNewFloor && previousFloorId != null) {
        final oldColor = tryParseDepartmentHex(existingColor);
        if (oldColor != null) {
          FloorColorAssignmentService.instance.removeColorFromFloor(
            previousFloorId,
            oldColor,
          );
        }
      }
    }

    String? colorHex;

    if (shouldKeepCurrentColor) {
      colorHex = null;
    } else if (existingColor == null || existingColor.isEmpty) {
      final picked = FloorColorAssignmentService.instance.getNextDistinctColor(
        floorId,
        additionalUsed: additionalUsed,
      );
      colorHex = colorToDepartmentHex(picked);
      removeOldFloorColorIfMoved();
    } else {
      final currentParsed = tryParseDepartmentHex(existingColor);
      if (currentParsed == null) {
        final picked = FloorColorAssignmentService.instance
            .getNextDistinctColor(floorId, additionalUsed: additionalUsed);
        colorHex = colorToDepartmentHex(picked);
        removeOldFloorColorIfMoved();
      } else {
        final suggested = FloorColorAssignmentService.instance
            .peekNextDistinctColor(floorId, additionalUsed: additionalUsed);
        if (!context.mounted) return;
        final choice = await showBuildingMapCommitColorDialog(
          context,
          departmentName: dept.name,
          currentColor: currentParsed,
          suggestedColor: suggested,
        );
        if (!context.mounted) return;
        if (choice == null) {
          return;
        }
        if (choice) {
          final picked = FloorColorAssignmentService.instance
              .getNextDistinctColor(floorId, additionalUsed: additionalUsed);
          colorHex = colorToDepartmentHex(picked);
          removeOldFloorColorIfMoved();
        } else {
          colorHex = null;
          FloorColorAssignmentService.instance.overrideColor(
            floorId,
            currentParsed,
          );
          removeOldFloorColorIfMoved();
        }
      }
    }

    _ref
        .read(buildingMapUndoProvider.notifier)
        .captureFromValues(
          departmentId: dept.id!,
          mapFloor: dept.mapFloor,
          mapX: dept.mapX,
          mapY: dept.mapY,
          mapWidth: dept.mapWidth,
          mapHeight: dept.mapHeight,
          mapRotation: dept.mapRotation,
          mapLabelOffsetX: dept.mapLabelOffsetX,
          mapLabelOffsetY: dept.mapLabelOffsetY,
          mapAnchorOffsetX: dept.mapAnchorOffsetX,
          mapAnchorOffsetY: dept.mapAnchorOffsetY,
        );
    final db = await DatabaseHelper.instance.database;
    final updates = <String, dynamic>{
      'map_x': draft.x,
      'map_y': draft.y,
      'map_width': draft.width,
      'map_height': draft.height,
      'map_rotation': draft.rotation,
      'map_label_offset_x': draft.labelOffsetX,
      'map_label_offset_y': draft.labelOffsetY,
      'map_anchor_offset_x': draft.anchorOffsetX,
      'map_anchor_offset_y': draft.anchorOffsetY,
      'map_label_font_scale': mapLabelFontScaleForDatabase(
        draft.labelFontScale,
      ),
      'map_label_width': mapLabelWidthForDatabase(draft.labelWidth),
      'map_label_height': mapLabelHeightForDatabase(draft.labelHeight),
    };
    if (colorHex != null) {
      updates['color'] = colorHex;
    }
    await DepartmentRepository(db).saveDepartmentWithFloorContext(
      dept.id!,
      updates,
      drawingFloorId: floorId,
    );
    if (shouldKeepCurrentColor) {
      final keep = tryParseDepartmentHex(existingColor);
      if (keep != null) {
        FloorColorAssignmentService.instance.overrideColor(floorId, keep);
      }
    }
    await _ref.read(departmentDirectoryProvider.notifier).loadDepartments();
    final backToSelection = _ref.read(buildingMapEditFromSelectionTapProvider);
    _ref.read(buildingMapDraftShapeProvider.notifier).clear();
    _ref.read(buildingMapEditFromSelectionTapProvider.notifier).clear();
    _ref
        .read(buildingMapToolProvider.notifier)
        .setMode(backToSelection ? MapToolMode.select : MapToolMode.draw);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Αποθηκεύτηκε η θέση στο χάρτη.')),
      );
    }
  }

  /// Ενημέρωση διαστάσεων πλαισίου ετικέτας στο draft κατά τη διάρκεια resize.
  void updateDepartmentLabelDimensions({
    required double width,
    required double height,
    String? labelText,
  }) {
    final draft = _ref.read(buildingMapDraftShapeProvider);
    if (draft == null) return;
    final minW = labelText == null
        ? kBuildingMapLabelMinWidth
        : computeMinMapLabelBoxWidthForText(labelText);
    final w = width.clamp(minW, 2000.0);
    final h = height.clamp(kBuildingMapLabelMinHeight, 2000.0);
    if ((w - draft.labelWidth).abs() < 0.5 &&
        (h - draft.labelHeight).abs() < 0.5) {
      return;
    }
    _ref
        .read(buildingMapDraftShapeProvider.notifier)
        .setDraft(draft.copyWith(labelWidth: w, labelHeight: h));
  }

  /// Αύξηση/μείωση κλίμακας ετικέτας στο τρέχον draft (αποθήκευση με ✓).
  void adjustDraftLabelFontScale({required bool increase}) {
    final draft = _ref.read(buildingMapDraftShapeProvider);
    if (draft == null) return;
    final next = stepMapLabelFontScale(
      draft.labelFontScale,
      increase: increase,
    );
    if ((next - draft.labelFontScale).abs() < 0.001) return;
    _ref
        .read(buildingMapDraftShapeProvider.notifier)
        .setDraft(draft.copyWith(labelFontScale: next));
  }

  /// Αποθηκεύει το προσαρμοσμένο όνομα εμφάνισης στο χάρτη (`map_custom_name`).
  /// Κενό ή ταύτιση με το κανονικό όνομα τμήματος → NULL στη βάση (χρήση `name`).
  Future<void> saveDepartmentMapDisplayName({
    required BuildContext context,
    required int departmentId,
    required String canonicalDepartmentName,
    required String editedText,
  }) async {
    final trimmed = editedText.trim();
    final canon = canonicalDepartmentName.trim();
    final String? custom = trimmed.isEmpty || trimmed == canon ? null : trimmed;
    final db = await DatabaseHelper.instance.database;
    await DepartmentRepository(
      db,
    ).updateDepartment(departmentId, {'map_custom_name': custom});
    await _ref.read(departmentDirectoryProvider.notifier).loadDepartments();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            custom == null
                ? 'Η επωνυμία χάρτη επανήλθε στο όνομα τμήματος.'
                : 'Αποθηκεύτηκε η επωνυμία χάρτη.',
          ),
        ),
      );
    }
  }

  /// Διαγράφει τη χαρτογράφηση του τμήματος στο τρέχον φύλλο (χωρίς διάλογο επιβεβαίωσης).
  Future<void> removeDepartmentFromFloorAfterConfirm({
    required BuildContext context,
    required DepartmentModel dept,
    required String sheetStr,
  }) async {
    if (dept.id == null) return;
    final mappedHere =
        (dept.mapFloor ?? '') == sheetStr &&
        dept.mapX != null &&
        dept.mapY != null &&
        (dept.mapWidth ?? 0) > 0 &&
        (dept.mapHeight ?? 0) > 0;
    if (!mappedHere) return;

    final go = await showBuildingMapRemoveDepartmentConfirmDialog(
      context,
      departmentName: dept.name,
    );
    if (!go || !context.mounted) return;

    _ref
        .read(buildingMapUndoProvider.notifier)
        .captureFromValues(
          departmentId: dept.id!,
          mapFloor: dept.mapFloor,
          mapX: dept.mapX,
          mapY: dept.mapY,
          mapWidth: dept.mapWidth,
          mapHeight: dept.mapHeight,
          mapRotation: dept.mapRotation,
          mapLabelOffsetX: dept.mapLabelOffsetX,
          mapLabelOffsetY: dept.mapLabelOffsetY,
          mapAnchorOffsetX: dept.mapAnchorOffsetX,
          mapAnchorOffsetY: dept.mapAnchorOffsetY,
        );
    final db = await DatabaseHelper.instance.database;
    final removedColor = tryParseDepartmentHex(dept.color);
    await DepartmentRepository(db).updateDepartment(
      dept.id!,
      BuildingMapRepository.clearedBuildingMapPlacementColumns(
        clearFloorId: true,
        clearDepartmentHex: true,
      ),
    );
    final fid = int.tryParse(sheetStr);
    if (fid != null && removedColor != null) {
      FloorColorAssignmentService.instance.removeColorFromFloor(
        fid,
        removedColor,
      );
    }
    await _ref.read(departmentDirectoryProvider.notifier).loadDepartments();
    final fromSelection = _ref.read(buildingMapEditFromSelectionTapProvider);
    _ref.read(buildingMapDraftShapeProvider.notifier).clear();
    _ref.read(buildingMapEditFromSelectionTapProvider.notifier).clear();
    _ref
        .read(buildingMapSelectedDepartmentIdToMapProvider.notifier)
        .setDept(null);
    _ref
        .read(buildingMapToolProvider.notifier)
        .setMode(fromSelection ? MapToolMode.select : MapToolMode.draw);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Το τμήμα αφαιρέθηκε από τον χάρτη.')),
      );
    }
  }

  void syncDraftWithSelectedDepartment({
    required List<DepartmentModel> departments,
    required int? departmentId,
    required int floorId,
  }) {
    if (departmentId == null) {
      _ref.read(buildingMapDraftShapeProvider.notifier).clear();
      _ref.read(buildingMapEditFromSelectionTapProvider.notifier).clear();
      return;
    }
    DepartmentModel? selected;
    for (final dep in departments) {
      if (dep.id == departmentId) {
        selected = dep;
        break;
      }
    }
    if (selected == null ||
        selected.mapFloor != floorId.toString() ||
        !selected.isMapped) {
      _ref.read(buildingMapDraftShapeProvider.notifier).clear();
      _ref.read(buildingMapEditFromSelectionTapProvider.notifier).clear();
      return;
    }
    _ref
        .read(buildingMapDraftShapeProvider.notifier)
        .setDraft(
          DraftDepartmentShape(
            x: selected.mapX!,
            y: selected.mapY!,
            width: selected.mapWidth!,
            height: selected.mapHeight!,
            rotation: selected.mapRotation,
            labelOffsetX: selected.mapLabelOffsetX,
            labelOffsetY: selected.mapLabelOffsetY,
            anchorOffsetX: selected.mapAnchorOffsetX,
            anchorOffsetY: selected.mapAnchorOffsetY,
            labelFontScale: effectiveMapLabelFontScale(
              selected.mapLabelFontScale,
            ),
            labelWidth: effectiveMapLabelWidth(selected.mapLabelWidth),
            labelHeight: effectiveMapLabelHeight(selected.mapLabelHeight),
          ),
        );
  }

  Future<String?> _ingestPickedImagePath(
    BuildContext context,
    String srcPath, {
    required String floorLabel,
  }) async {
    var responded = false;
    var copyToPortable = true;
    String? targetFileName;
    ingestLoop:
    while (true) {
      final result = await BuildingMapStorage.ingestPickedImage(
        srcPath,
        userRespondedToPortablePrompt: responded,
        copyToPortable: copyToPortable,
        targetFileName: targetFileName,
      );
      if (result.ok && result.storedRelativePath != null) {
        return result.storedRelativePath;
      }
      if (result.needsPortableConfirmation) {
        if (!context.mounted) return null;
        final choice = await showBuildingMapPortableImageCopyDialog(
          context,
          sourceImagePath: srcPath,
        );
        if (choice == null) return null;
        responded = true;
        copyToPortable = choice.copyToPortable;
        targetFileName = choice.fileName;
        continue ingestLoop;
      }
      if (result.errorMessage != null && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.errorMessage!)));
      }
      return null;
    }
  }

  /// Αντικατάσταση εικόνας στο **υπάρχον** φύλλο (διατήρηση γεωμετρίας τμημάτων).
  Future<void> replaceFloorSheetImageById(
    BuildContext context,
    int floorId,
  ) async {
    final db = await DatabaseHelper.instance.database;
    final floors = await BuildingMapRepository(db).listBuildingMapFloors();
    BuildingMapFloor? floor;
    for (final f in floors) {
      if (f.id == floorId) {
        floor = f;
        break;
      }
    }
    if (floor == null || !context.mounted) return;
    await replaceFloorSheetImage(context, floor);
  }

  /// Κοινός επιλογέας εικόνας κατόψης: ανοίγει στον τελευταίο φάκελο εικόνων
  /// του χάρτη (όχι στην καθολική «τελευταία θέση» των Windows) και τον
  /// θυμάται μετά από επιτυχή επιλογή. null σε ακύρωση.
  Future<String?> _pickFloorSheetImagePath() async {
    const memory = PickerLocationMemory('building_map_image');
    final picked = await FilePicker.pickFile(
      type: FileType.image,
      initialDirectory: await memory.initialDirectory(),
    );
    final srcPath = picked?.path;
    if (srcPath == null) return null;
    await memory.remember(srcPath);
    return srcPath;
  }

  Future<void> replaceFloorSheetImage(
    BuildContext context,
    BuildingMapFloor floor,
  ) async {
    final srcPath = await _pickFloorSheetImagePath();
    if (srcPath == null || !context.mounted) return;

    final stored = await _ingestPickedImagePath(
      context,
      srcPath,
      floorLabel: floor.label,
    );
    if (stored == null || !context.mounted) return;

    try {
      final db = await DatabaseHelper.instance.database;
      final previousPath = floor.imagePath;
      await BuildingMapRepository(db).updateBuildingMapFloor(
        floor.id,
        rotationDegrees: floor.rotationDegrees,
        imagePath: stored,
      );
      if (previousPath != stored) {
        await BuildingMapStorage.deleteStoredImageBestEffort(previousPath);
      }
      final sel = _ref.read(buildingMapSelectedSheetIdProvider);
      if (sel == floor.id) {
        await decodeImageForPath(stored);
      }
      _ref.read(buildingMapFloorReloadSeqProvider.notifier).bump();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Η κατόψη ενημερώθηκε.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Αποτυχία ενημέρωσης κατόψης: $e')),
        );
      }
    }
  }

  Future<void> addFloorSheet(BuildContext context) async {
    final srcPath = await _pickFloorSheetImagePath();
    if (srcPath == null || !context.mounted) return;

    final result = await showBuildingMapFloorSheetAddDialog(context);
    if (result == null || !context.mounted) return;

    final copied = await _ingestPickedImagePath(
      context,
      srcPath,
      floorLabel: result.label,
    );
    if (copied == null || !context.mounted) return;

    final db = await DatabaseHelper.instance.database;
    final maps = BuildingMapRepository(db);
    final id = await maps.insertBuildingMapFloor(
      label: result.label,
      floorGroup: result.floorGroup,
      copiedImagePath: copied,
      rotationDegrees: 0,
    );
    _ref.read(buildingMapSelectedSheetIdProvider.notifier).setSheet(id);
    final floors = await maps.listBuildingMapFloors();
    if (!context.mounted) return;
    await syncSheetSelection(floors);
    appliedInitialFloorSync = false;
    _ref.read(buildingMapFloorReloadSeqProvider.notifier).bump();
  }

  Future<void> editFloorSheet(
    BuildContext context,
    BuildingMapFloor floor,
  ) async {
    var previewImageAvailable = false;
    if (floor.imagePath.trim().isNotEmpty) {
      final initialImage = await BuildingMapStorage.fileForStoredPath(
        floor.imagePath,
      );
      previewImageAvailable = await initialImage.exists();
    }
    if (!context.mounted) return;
    final previewDepartments = _ref
        .read(departmentDirectoryProvider)
        .allDepartments
        .where((d) => !d.isDeleted)
        .toList();

    final result = await showBuildingMapFloorSheetEditDialog(
      context,
      floor: floor,
      previewDepartments: previewDepartments,
      initialPreviewImageAvailable: previewImageAvailable,
      pickImagePath: _pickFloorSheetImagePath,
    );
    if (result == null || !context.mounted) return;

    var imagePathUpdate = floor.imagePath;
    final previousPath = floor.imagePath;
    if (result.pickedSrcPath != null) {
      final ingested = await _ingestPickedImagePath(
        context,
        result.pickedSrcPath!,
        floorLabel: result.label,
      );
      if (ingested == null) return;
      imagePathUpdate = ingested;
    }

    final db = await DatabaseHelper.instance.database;
    await BuildingMapRepository(db).updateBuildingMapFloor(
      floor.id,
      rotationDegrees: floor.rotationDegrees,
      label: result.label,
      floorGroup: result.floorGroupRaw,
      imagePath: result.pickedSrcPath != null ? imagePathUpdate : null,
    );
    if (result.pickedSrcPath != null && previousPath != imagePathUpdate) {
      await BuildingMapStorage.deleteStoredImageBestEffort(previousPath);
    }

    final sel = _ref.read(buildingMapSelectedSheetIdProvider);
    if (sel == floor.id) {
      await decodeImageForPath(imagePathUpdate);
    }
    _ref.read(buildingMapFloorReloadSeqProvider.notifier).bump();
  }

  Future<void> deleteFloorSheet(
    BuildContext context,
    int sheetId,
    String imagePath,
  ) async {
    final trimmedPath = imagePath.trim();
    String? resolvedImagePath;
    var imageFileExists = false;
    if (trimmedPath.isNotEmpty) {
      final imageFile = await BuildingMapStorage.fileForStoredPath(trimmedPath);
      resolvedImagePath = imageFile.path;
      imageFileExists = await imageFile.exists();
    }

    if (!context.mounted) return;
    final choice = await showBuildingMapFloorDeleteDialog(
      context,
      displayImagePath: resolvedImagePath,
      imageFileExists: imageFileExists,
      showMissingImageNote: !imageFileExists && trimmedPath.isNotEmpty,
    );
    if (choice == null || !context.mounted) return;
    try {
      final db = await DatabaseHelper.instance.database;
      final departments = DepartmentRepository(db);
      final maps = BuildingMapRepository(db);
      maps.bindUpdateDepartment(departments.updateDepartment);
      await maps.deleteBuildingMapFloorClearingDepartmentMaps(sheetId);
      var imageRemoved = false;
      if (choice.deleteImageFile) {
        imageRemoved = await BuildingMapStorage.deleteStoredImageBestEffort(
          imagePath,
        );
      }
      _ref.read(buildingMapSelectedSheetIdProvider.notifier).setSheet(null);
      appliedInitialFloorSync = false;
      _ref.read(buildingMapFloorReloadSeqProvider.notifier).bump();
      await _ref.read(departmentDirectoryProvider.notifier).loadDepartments();
      if (context.mounted) {
        final tail = choice.deleteImageFile
            ? (imageRemoved
                  ? ' Η εικόνα διαγράφηκε από το δίσκο.'
                  : ' Η εικόνα δεν διαγράφηκε (αρχείο δεν βρέθηκε ή σφάλμα εγγραφής).')
            : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Το φύλλο διαγράφηκε και καθαρίστηκαν οι θέσεις χάρτη των σχετικών τμημάτων.$tail',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Αποτυχία διαγραφής: $e')));
      }
    }
  }

  Future<void> applySheetRotation(int sheetId, double degrees) async {
    final db = await DatabaseHelper.instance.database;
    await BuildingMapRepository(
      db,
    ).updateBuildingMapFloor(sheetId, rotationDegrees: degrees);
    _ref.read(buildingMapFloorReloadSeqProvider.notifier).bump();
  }

  Future<void> undoLastGeometry(BuildContext context) async {
    final snap = _ref.read(buildingMapUndoProvider);
    if (snap == null) return;
    final db = await DatabaseHelper.instance.database;
    await DepartmentRepository(db).updateDepartment(snap.departmentId, {
      'map_floor': snap.mapFloor,
      'map_x': snap.mapX,
      'map_y': snap.mapY,
      'map_width': snap.mapWidth,
      'map_height': snap.mapHeight,
      'map_rotation': snap.mapRotation,
      'map_label_offset_x': snap.mapLabelOffsetX,
      'map_label_offset_y': snap.mapLabelOffsetY,
      'map_anchor_offset_x': snap.mapAnchorOffsetX,
      'map_anchor_offset_y': snap.mapAnchorOffsetY,
    });
    _ref.read(buildingMapUndoProvider.notifier).clear();
    await _ref.read(departmentDirectoryProvider.notifier).loadDepartments();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Αναίρεση εφαρμόστηκε.')));
    }
  }

  void _showMapSnack(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<List<int>> _departmentIdsForUserId(int userId) async {
    final db = await DatabaseHelper.instance.database;
    return DepartmentRepository(db).resolveActiveDepartmentIdsForUserId(userId);
  }

  Future<List<int>> _departmentIdsForPhone(String phoneText) async {
    final db = await DatabaseHelper.instance.database;
    return DepartmentRepository(
      db,
    ).resolveActiveDepartmentIdsForPhone(phoneText);
  }

  Future<UserModel?> _pickUserForEquipment(
    BuildContext context,
    List<UserModel> users,
  ) async {
    if (users.isEmpty) return null;
    if (users.length == 1) return users.first;
    return showBuildingMapUserPickDialog(context, users: users);
  }

  Future<int?> _pickDepartmentIdIfNeeded(
    BuildContext context,
    List<int> departmentIds,
    List<DepartmentModel> departments,
  ) async {
    final unique = departmentIds.toSet().toList()..sort();
    if (unique.isEmpty) return null;
    if (unique.length == 1) return unique.first;
    final byId = <int, DepartmentModel>{
      for (final d in departments)
        if (d.id != null) d.id!: d,
    };
    return showBuildingMapDepartmentPickDialog(
      context,
      options: [
        for (final deptId in unique)
          (id: deptId, label: byId[deptId]?.name ?? 'Τμήμα #$deptId'),
      ],
    );
  }

  Future<List<int>> _resolveDepartmentIdsFromEquipment(
    BuildContext context,
    EquipmentModel equipment,
  ) async {
    final directDeptId = equipment.departmentId;
    if (directDeptId != null) return [directDeptId];

    final equipmentId = equipment.id;
    if (equipmentId == null) return const [];
    final lookup = LookupService.instance;
    await lookup.loadFromDatabase(forceRefresh: true);
    if (!context.mounted) return const [];
    final users = lookup.findUsersForEquipment(equipmentId);
    final chosenUser = await _pickUserForEquipment(context, users);
    if (chosenUser == null) return const [];
    if (!context.mounted) return const [];
    final name = (chosenUser.name ?? '').trim();
    final userDisplayName = name.isEmpty ? 'χωρίς όνομα' : name;
    final shouldContinue = await showBuildingMapJumpToUserConfirmDialog(
      context,
      userDisplayName: userDisplayName,
    );
    if (!shouldContinue) return const [];
    final userId = chosenUser.id;
    if (userId == null) return const [];
    return _departmentIdsForUserId(userId);
  }

  Future<void> _jumpToDepartmentWithFallback({
    required int departmentId,
    required List<DepartmentModel> departments,
    required List<BuildingMapFloor> floors,
  }) async {
    final department = departments.cast<DepartmentModel?>().firstWhere(
      (d) => d?.id == departmentId,
      orElse: () => null,
    );
    if (department == null) return;

    final mapFloor = department.mapFloor?.trim();
    final mappedFloorId = mapFloor == null ? null : int.tryParse(mapFloor);
    final isMapped =
        department.mapX != null &&
        department.mapY != null &&
        (department.mapWidth ?? 0) > 0 &&
        (department.mapHeight ?? 0) > 0 &&
        mappedFloorId != null &&
        floors.any((f) => f.id == mappedFloorId);

    if (isMapped) {
      _ref.read(buildingMapSearchUnresolvedNoticeProvider.notifier).clear();
      await jumpToMappedDepartment(
        department: department,
        floors: floors,
        departments: departments,
      );
      return;
    }

    int? fallbackFloorId;
    final preferredFloorId = department.floorId;
    if (preferredFloorId != null &&
        floors.any((f) => f.id == preferredFloorId)) {
      fallbackFloorId = preferredFloorId;
    } else if (mappedFloorId != null &&
        floors.any((f) => f.id == mappedFloorId)) {
      fallbackFloorId = mappedFloorId;
    } else if (floors.isNotEmpty) {
      fallbackFloorId = floors.first.id;
    }
    if (fallbackFloorId == null) return;
    await selectFloorFromList(
      fallbackFloorId,
      floors,
      clearSelectedDepartment: false,
    );
    _ref
        .read(buildingMapSelectedDepartmentIdToMapProvider.notifier)
        .setDept(departmentId);

    BuildingMapFloor? fallbackFloor;
    for (final f in floors) {
      if (f.id == fallbackFloorId) {
        fallbackFloor = f;
        break;
      }
    }
    final deptName = department.displayName;
    final String message;
    if (preferredFloorId != null &&
        fallbackFloorId == preferredFloorId &&
        fallbackFloor != null) {
      message =
          'Το τμήμα «$deptName» βρίσκεται στον όροφο '
          '«${buildingMapFloorDisplayLabel(fallbackFloor)}», αλλά δεν έχει '
          'σχεδιαστεί ακόμα στον χάρτη.';
    } else {
      message = 'Το τμήμα «$deptName» δεν έχει καταχωρημένη θέση στον χάρτη.';
    }
    _ref
        .read(buildingMapSearchUnresolvedNoticeProvider.notifier)
        .setNotice(
          BuildingMapSearchUnresolvedNotice(
            message: message,
            departmentId: departmentId,
          ),
        );
  }

  /// Υποψήφια τμήματα ανά είδος στόχου.
  ///
  /// Εξαντλητικό switch σε sealed τύπο: νέο είδος στόχου δεν μεταγλωττίζεται
  /// μέχρι να αποκτήσει χειρισμό εδώ. Κενή λίστα σε αδιέξοδο — ο καλών
  /// δείχνει το ενιαίο «Δεν βρέθηκε τμήμα».
  Future<List<int>> _candidateDepartmentIdsFor(
    BuildContext context,
    BuildingMapJumpTarget target,
  ) {
    switch (target) {
      case BuildingMapDepartmentJump(:final departmentId):
        return Future.value([departmentId]);
      case BuildingMapPhoneJump(:final phoneNumber):
        return _departmentIdsForPhone(phoneNumber);
      case BuildingMapUserJump(:final user):
        final userId = user.id;
        return userId == null
            ? Future.value(const [])
            : _departmentIdsForUserId(userId);
      case BuildingMapEquipmentJump(:final equipment):
        return _resolveDepartmentIdsFromEquipment(context, equipment);
      case BuildingMapSearchHitJump(:final hit):
        return _departmentIdsForSearchHit(context, hit);
    }
  }

  /// Υποψήφια τμήματα για αποτέλεσμα της έξυπνης αναζήτησης.
  Future<List<int>> _departmentIdsForSearchHit(
    BuildContext context,
    BuildingMapOmnisearchHit hit,
  ) async {
    switch (hit.kind) {
      case BuildingMapOmnisearchEntityKind.department:
        return [hit.entityId];
      case BuildingMapOmnisearchEntityKind.user:
        return hit.departmentIds.isNotEmpty
            ? hit.departmentIds
            : _departmentIdsForUserId(hit.entityId);
      case BuildingMapOmnisearchEntityKind.equipment:
        if (hit.departmentIds.isNotEmpty) return hit.departmentIds;
        final lookup = LookupService.instance;
        await lookup.loadFromDatabase(forceRefresh: true);
        if (!context.mounted) return const [];
        final equipment = lookup
            .findEquipmentsByCode(hit.title)
            .firstWhere(
              (eq) => eq.id == hit.entityId,
              orElse: () => EquipmentModel(id: hit.entityId),
            );
        return _resolveDepartmentIdsFromEquipment(context, equipment);
    }
  }

  Future<void> resolveAndJumpToEntity(
    BuildContext context,
    BuildingMapJumpTarget target,
  ) async {
    final repos = _ref.read(buildingMapReposProvider).asData?.value;
    if (repos == null) {
      _showMapSnack(context, 'Ο χάρτης δεν είναι έτοιμος ακόμη.');
      return;
    }
    final floors = await repos.maps.listBuildingMapFloors();
    if (!context.mounted) return;
    if (floors.isEmpty) {
      _showMapSnack(context, 'Δεν υπάρχουν διαθέσιμα φύλλα χάρτη.');
      return;
    }

    await _ref.read(departmentDirectoryProvider.notifier).loadDepartments();
    if (!context.mounted) return;
    final departments = _ref
        .read(departmentDirectoryProvider)
        .allDepartments
        .where((d) => !d.isDeleted)
        .toList(growable: false);

    final candidateDepartmentIds = await _candidateDepartmentIdsFor(
      context,
      target,
    );

    if (!context.mounted) return;
    final selectedDepartmentId = await _pickDepartmentIdIfNeeded(
      context,
      candidateDepartmentIds,
      departments,
    );
    if (selectedDepartmentId == null) {
      if (!context.mounted) return;
      _showMapSnack(context, 'Δεν βρέθηκε τμήμα για την οντότητα.');
      return;
    }
    final selectedDept = departments.firstWhere(
      (d) => d.id == selectedDepartmentId,
      orElse: () => DepartmentModel(name: ''),
    );
    if (selectedDept.id != null && selectedDept.isHiddenOnMap) {
      _ref
          .read(buildingMapSearchRevealedDepartmentIdProvider.notifier)
          .setRevealed(selectedDept.id);
      if (context.mounted) {
        _showMapSnack(
          context,
          'Το τμήμα «${selectedDept.displayName}» είναι κρυμμένο — εμφανίζεται προσωρινά.',
        );
      }
    } else {
      _ref.read(buildingMapSearchRevealedDepartmentIdProvider.notifier).clear();
    }
    await _jumpToDepartmentWithFallback(
      departmentId: selectedDepartmentId,
      departments: departments,
      floors: floors,
    );
  }

  Future<void> jumpToDepartmentFromSearch({
    required String rawQuery,
    required List<BuildingMapFloor> floors,
    required List<DepartmentModel> departments,
  }) async {
    final qq = rawQuery.trim().toLowerCase();
    if (qq.isEmpty) return;
    for (final d in departments) {
      if (!d.name.toLowerCase().contains(qq)) continue;
      final mf = d.mapFloor;
      if (mf == null || mf.isEmpty) continue;
      final targetId = int.tryParse(mf);
      if (targetId == null) continue;
      final deptId = d.id;
      if (deptId == null) continue;
      await selectFloorFromList(
        targetId,
        floors,
        clearSelectedDepartment: false,
      );
      _ref
          .read(buildingMapSelectedDepartmentIdToMapProvider.notifier)
          .setDept(deptId);
      syncDraftWithSelectedDepartment(
        departments: departments,
        departmentId: deptId,
        floorId: targetId,
      );
      _ref.read(buildingMapViewportCenterRequestSeqProvider.notifier).bump();
      break;
    }
  }

  /// Μετάβαση στο φύλλο/τμήμα όταν είναι ήδη γνωστό το [DepartmentModel] (π.χ. από autocomplete).
  Future<void> jumpToMappedDepartment({
    required DepartmentModel department,
    required List<BuildingMapFloor> floors,
    required List<DepartmentModel> departments,
  }) async {
    _ref.read(buildingMapSearchUnresolvedNoticeProvider.notifier).clear();
    final mf = department.mapFloor?.trim();
    if (mf == null || mf.isEmpty) return;
    final targetId = int.tryParse(mf);
    if (targetId == null) return;
    if (!floors.any((f) => f.id == targetId)) return;
    final deptId = department.id;
    if (deptId == null) return;
    await selectFloorFromList(targetId, floors, clearSelectedDepartment: false);
    _ref
        .read(buildingMapSelectedDepartmentIdToMapProvider.notifier)
        .setDept(deptId);
    syncDraftWithSelectedDepartment(
      departments: departments,
      departmentId: deptId,
      floorId: targetId,
    );
    _ref.read(buildingMapViewportCenterRequestSeqProvider.notifier).bump();
  }
}
