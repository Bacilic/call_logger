import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/database/directory_repository.dart';
import '../../../../core/models/building_map_floor.dart';
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
        const SnackBar(content: Text('Ενημερώθηκε το χρώμα περιοχής στο χάρτη.')),
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
    if (manualFloorId != null &&
        manualFloorId != floorId &&
        context.mounted) {
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
        final picked = FloorColorAssignmentService.instance.getNextDistinctColor(
          floorId,
          additionalUsed: additionalUsed,
        );
        colorHex = colorToDepartmentHex(picked);
        removeOldFloorColorIfMoved();
      } else {
        final suggested =
            FloorColorAssignmentService.instance.peekNextDistinctColor(
          floorId,
          additionalUsed: additionalUsed,
        );
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
          final picked =
              FloorColorAssignmentService.instance.getNextDistinctColor(
            floorId,
            additionalUsed: additionalUsed,
          );
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
    final String? custom =
        trimmed.isEmpty || trimmed == canon ? null : trimmed;
    final db = await DatabaseHelper.instance.database;
    await DirectoryRepository(db).updateDepartment(departmentId, {
      'map_custom_name': custom,
    });
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
    await DirectoryRepository(db).updateDepartment(dept.id!, {
      'map_floor': null,
      'map_x': 0.0,
      'map_y': 0.0,
      'map_width': 0.0,
      'map_height': 0.0,
      'map_rotation': 0.0,
      'map_label_offset_x': null,
      'map_label_offset_y': null,
      'map_anchor_offset_x': null,
      'map_anchor_offset_y': null,
      'map_custom_name': null,
      'color': null,
    });
    final fid = int.tryParse(sheetStr);
    if (fid != null && removedColor != null) {
      FloorColorAssignmentService.instance.removeColorFromFloor(fid, removedColor);
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
    final picked = await FilePicker.platform.pickFiles(
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
                    final picked = await FilePicker.platform.pickFiles(
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
      break;
    }
  }
}
