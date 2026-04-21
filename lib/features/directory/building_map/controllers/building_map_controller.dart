import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/database/directory_repository.dart';
import '../../../../core/models/building_map_floor.dart';
import '../../../../core/services/lookup_service.dart';
import '../../../calls/models/equipment_model.dart';
import '../../../calls/models/user_model.dart';
import '../../../../core/services/building_map_storage.dart';
import '../../../floor_map/services/floor_color_assignment_service.dart';
import '../../models/department_model.dart';
import '../../providers/department_directory_provider.dart';
import '../../screens/widgets/department_color_palette.dart';
import '../providers/building_map_providers.dart';
import '../widgets/building_map_commit_color_dialog.dart';

final buildingMapControllerProvider = Provider<BuildingMapController>(
  (ref) => BuildingMapController(ref),
);

/// Επιλογή διαγραφής εικόνας από το διάλογο διαγραφής φύλλου.
class BuildingMapFloorDeleteChoice {
  const BuildingMapFloorDeleteChoice({required this.deleteImageFile});

  final bool deleteImageFile;
}

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
    final f = File(imagePath);
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
    }
    _ref.read(buildingMapDraftShapeProvider.notifier).clear();
    _ref.read(buildingMapEditFromSelectionTapProvider.notifier).clear();
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
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Επικάλυψη'),
        content: const Text(
          'Το ορθογώνιο επικαλύπτει άλλο τμήμα σε αυτό το φύλλο. Να συνεχιστεί;',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Άκυρο'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Συνέχεια'),
          ),
        ],
      ),
    );
    return go ?? false;
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
    await DirectoryRepository(db).updateDepartment(dept.id!, {'color': hex});
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
    };
    if (colorHex != null) {
      updates['color'] = colorHex;
    }
    await DirectoryRepository(db).saveDepartmentWithFloorContext(
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
    await DirectoryRepository(
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

    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Αφαίρεση από τον χάρτη'),
        content: Text(
          'Να αφαιρεθεί το τμήμα «${dept.name}» από αυτό το φύλλο κατόψης;',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Άκυρο'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Αφαίρεση'),
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return;

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
    await DirectoryRepository(db).updateDepartment(
      dept.id!,
      DirectoryRepository.clearedBuildingMapPlacementColumns(
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
        selected.mapX == null ||
        selected.mapY == null ||
        selected.mapWidth == null ||
        selected.mapHeight == null) {
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
          ),
        );
  }

  Future<void> addFloorSheet(BuildContext context) async {
    final labelCtrl = TextEditingController();
    final groupCtrl = TextEditingController();
    final picked = await FilePicker.pickFiles(
      type: FileType.image,
      withData: false,
    );
    if (picked == null || picked.files.isEmpty) return;
    final srcPath = picked.files.single.path;
    if (srcPath == null) return;
    if (!context.mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Νέο φύλλο κατόψης'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelCtrl,
                decoration: const InputDecoration(
                  labelText: 'Ετικέτα',
                  hintText: 'π.χ. 1ος — Γραφεία',
                ),
                autofocus: true,
              ),
              TextField(
                controller: groupCtrl,
                decoration: const InputDecoration(
                  labelText: 'Ομάδα ορόφου (προαιρετικό)',
                  hintText: 'π.χ. L1',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Άκυρο'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Προσθήκη'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final label = labelCtrl.text.trim();
    if (label.isEmpty) return;

    final copied = await BuildingMapStorage.copyPickedImageToStorage(srcPath);
    final db = await DatabaseHelper.instance.database;
    final repo = DirectoryRepository(db);
    final id = await repo.insertBuildingMapFloor(
      label: label,
      floorGroup: groupCtrl.text.trim().isEmpty ? null : groupCtrl.text.trim(),
      copiedImagePath: copied,
      rotationDegrees: 0,
    );
    _ref.read(buildingMapSelectedSheetIdProvider.notifier).setSheet(id);
    final floors = await repo.listBuildingMapFloors();
    if (!context.mounted) return;
    await syncSheetSelection(floors);
    appliedInitialFloorSync = false;
    _ref.read(buildingMapFloorReloadSeqProvider.notifier).bump();
  }

  Future<void> editFloorSheet(
    BuildContext context,
    BuildingMapFloor floor,
  ) async {
    final labelCtrl = TextEditingController(text: floor.label);
    final groupCtrl = TextEditingController(text: floor.floorGroup ?? '');
    String? pickedSrcPath;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Επεξεργασία κατόψης'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: labelCtrl,
                  decoration: const InputDecoration(labelText: 'Ετικέτα'),
                  autofocus: true,
                ),
                TextField(
                  controller: groupCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Περιοχή ορόφου (προαιρετικό)',
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await FilePicker.pickFiles(
                      type: FileType.image,
                      withData: false,
                    );
                    if (picked == null || picked.files.isEmpty) return;
                    final srcPath = picked.files.single.path;
                    if (srcPath == null) return;
                    pickedSrcPath = srcPath;
                    setDlg(() {});
                  },
                  icon: const Icon(Icons.image_outlined),
                  label: Text(
                    pickedSrcPath != null
                        ? 'Επιλέχθηκε νέα κατόψη'
                        : 'Αλλαγή κατόψης',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Άκυρο'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Αποθήκευση'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final label = labelCtrl.text.trim();
    if (label.isEmpty) return;

    var imagePathUpdate = floor.imagePath;
    if (pickedSrcPath != null) {
      imagePathUpdate = await BuildingMapStorage.copyPickedImageToStorage(
        pickedSrcPath!,
      );
    }

    final db = await DatabaseHelper.instance.database;
    await DirectoryRepository(db).updateBuildingMapFloor(
      floor.id,
      rotationDegrees: floor.rotationDegrees,
      label: label,
      floorGroup: groupCtrl.text,
      imagePath: pickedSrcPath != null ? imagePathUpdate : null,
    );

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
    var deleteImageFile = false;
    final choice = await showDialog<BuildingMapFloorDeleteChoice?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogLocal) {
          return AlertDialog(
            title: const Text('Διαγραφή φύλλου'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Να διαγραφεί το φύλλο κατόψης;\n\n'
                    'Ο σχεδιασμός στο χάρτη για τα τμήματα που δένονται σε αυτό το φύλλο '
                    'θα χαθεί: η θέση και η περιοχή στο χάρτη θα μηδενιστούν.',
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Διαγραφή αρχείου εικόνας από το δίσκο'),
                    subtitle: const Text(
                      'Από προεπιλογή η εικόνα διατηρείται στον φάκελο της εφαρμογής.',
                    ),
                    value: deleteImageFile,
                    onChanged: (v) => setDialogLocal(() => deleteImageFile = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Άκυρο'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  ctx,
                  BuildingMapFloorDeleteChoice(
                    deleteImageFile: deleteImageFile,
                  ),
                ),
                child: const Text('Διαγραφή'),
              ),
            ],
          );
        },
      ),
    );
    if (choice == null || !context.mounted) return;
    try {
      final db = await DatabaseHelper.instance.database;
      await DirectoryRepository(
        db,
      ).deleteBuildingMapFloorClearingDepartmentMaps(sheetId);
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
    await DirectoryRepository(
      db,
    ).updateBuildingMapFloor(sheetId, rotationDegrees: degrees);
    _ref.read(buildingMapFloorReloadSeqProvider.notifier).bump();
  }

  Future<void> undoLastGeometry(BuildContext context) async {
    final snap = _ref.read(buildingMapUndoProvider);
    if (snap == null) return;
    final db = await DatabaseHelper.instance.database;
    await DirectoryRepository(db).updateDepartment(snap.departmentId, {
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<List<int>> _departmentIdsForUserId(int userId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery(
      '''
      WITH phone_dept AS (
        SELECT p.id AS phone_id, p.department_id AS department_id
        FROM phones p
        WHERE p.department_id IS NOT NULL
        UNION
        SELECT dp.phone_id AS phone_id, dp.department_id AS department_id
        FROM department_phones dp
      )
      SELECT DISTINCT src.department_id AS department_id
      FROM (
        SELECT u.department_id AS department_id
        FROM users u
        WHERE u.id = ? AND u.department_id IS NOT NULL
        UNION
        SELECT pd.department_id AS department_id
        FROM user_phones up
        JOIN phone_dept pd ON pd.phone_id = up.phone_id
        WHERE up.user_id = ?
      ) src
      JOIN departments d ON d.id = src.department_id
      WHERE COALESCE(d.is_deleted, 0) = 0
      ORDER BY src.department_id ASC
      ''',
      [userId, userId],
    );
    return rows
        .map((row) => row['department_id'] as int?)
        .whereType<int>()
        .toList(growable: false);
  }

  Future<List<int>> _departmentIdsForPhone(String phoneText) async {
    final trimmed = phoneText.trim();
    if (trimmed.isEmpty) return const [];
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery(
      '''
      WITH phone_dept AS (
        SELECT p.id AS phone_id, p.department_id AS department_id
        FROM phones p
        WHERE p.department_id IS NOT NULL
        UNION
        SELECT dp.phone_id AS phone_id, dp.department_id AS department_id
        FROM department_phones dp
      )
      SELECT DISTINCT pd.department_id AS department_id
      FROM phones p
      JOIN phone_dept pd ON pd.phone_id = p.id
      JOIN departments d ON d.id = pd.department_id
      WHERE COALESCE(d.is_deleted, 0) = 0
        AND p.number = ?
      ORDER BY pd.department_id ASC
      ''',
      [trimmed],
    );
    return rows
        .map((row) => row['department_id'] as int?)
        .whereType<int>()
        .toList(growable: false);
  }

  Future<UserModel?> _pickUserForEquipment(
    BuildContext context,
    List<UserModel> users,
  ) async {
    if (users.isEmpty) return null;
    if (users.length == 1) return users.first;
    final selected = await showDialog<UserModel>(
      context: context,
      builder: (ctx) {
        return SimpleDialog(
          title: const Text('Επιλογή υπαλλήλου'),
          children: [
            for (final user in users)
              SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(user),
                child: Text(user.name?.trim().isNotEmpty == true ? user.name! : 'Χωρίς όνομα'),
              ),
          ],
        );
      },
    );
    return selected;
  }

  Future<bool> _confirmJumpToUser(
    BuildContext context,
    String userDisplayName,
  ) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Εντοπισμός μέσω υπαλλήλου'),
          content: Text(
            'Δεν έχει οριστεί τμήμα για τον εξοπλισμό. Επιθυμείτε εντοπισμό του υπαλλήλου $userDisplayName;',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Άκυρο'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Συνέχεια'),
            ),
          ],
        );
      },
    );
    return approved ?? false;
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
    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return SimpleDialog(
          title: const Text('Επιλογή τμήματος'),
          children: [
            for (final deptId in unique)
              SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(deptId),
                child: Text(byId[deptId]?.name ?? 'Τμήμα #$deptId'),
              ),
          ],
        );
      },
    );
    return selected;
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
    final shouldContinue = await _confirmJumpToUser(context, userDisplayName);
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
      await jumpToMappedDepartment(
        department: department,
        floors: floors,
        departments: departments,
      );
      return;
    }

    int? fallbackFloorId;
    final preferredFloorId = department.floorId;
    if (preferredFloorId != null && floors.any((f) => f.id == preferredFloorId)) {
      fallbackFloorId = preferredFloorId;
    } else if (mappedFloorId != null && floors.any((f) => f.id == mappedFloorId)) {
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
  }

  Future<void> resolveAndJumpToEntity(
    BuildContext context,
    dynamic entity,
  ) async {
    final repo = _ref.read(buildingMapDirectoryRepositoryProvider).asData?.value;
    if (repo == null) {
      _showMapSnack(context, 'Ο χάρτης δεν είναι έτοιμος ακόμη.');
      return;
    }
    final floors = await repo.listBuildingMapFloors();
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

    List<int> candidateDepartmentIds = const [];
    if (entity is BuildingMapOmnisearchHit) {
      switch (entity.kind) {
        case BuildingMapOmnisearchEntityKind.department:
          candidateDepartmentIds = [entity.entityId];
          break;
        case BuildingMapOmnisearchEntityKind.user:
          candidateDepartmentIds = entity.departmentIds.isNotEmpty
              ? entity.departmentIds
              : await _departmentIdsForUserId(entity.entityId);
          break;
        case BuildingMapOmnisearchEntityKind.equipment:
          if (entity.departmentIds.isNotEmpty) {
            candidateDepartmentIds = entity.departmentIds;
          } else {
            final lookup = LookupService.instance;
            await lookup.loadFromDatabase(forceRefresh: true);
            if (!context.mounted) return;
            final equipment = lookup
                .findEquipmentsByCode(entity.title)
                .firstWhere(
                  (eq) => eq.id == entity.entityId,
                  orElse: () => EquipmentModel(id: entity.entityId),
                );
            candidateDepartmentIds = await _resolveDepartmentIdsFromEquipment(
              context,
              equipment,
            );
          }
          break;
      }
    } else if (entity is DepartmentModel) {
      if (entity.id != null) candidateDepartmentIds = [entity.id!];
    } else if (entity is UserModel) {
      final userId = entity.id;
      if (userId != null) {
        candidateDepartmentIds = await _departmentIdsForUserId(userId);
      }
    } else if (entity is EquipmentModel) {
      if (!context.mounted) return;
      candidateDepartmentIds = await _resolveDepartmentIdsFromEquipment(
        context,
        entity,
      );
    } else if (entity is int) {
      candidateDepartmentIds = [entity];
    } else if (entity is String) {
      candidateDepartmentIds = await _departmentIdsForPhone(entity);
    } else if (entity is Map<String, dynamic>) {
      final kind = (entity['kind'] as String?)?.trim().toLowerCase();
      final id = entity['id'];
      if (kind == 'department' && id is int) {
        candidateDepartmentIds = [id];
      } else if (kind == 'user' && id is int) {
        candidateDepartmentIds = await _departmentIdsForUserId(id);
      } else if (kind == 'phone' && entity['phone'] is String) {
        candidateDepartmentIds = await _departmentIdsForPhone(
          entity['phone'] as String,
        );
      }
    }

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
