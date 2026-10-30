// ΑΞΙΟΛΟΓΗΘΗΚΕ ΓΙΑ ΔΙΑΣΠΑΣΗ — Ο ΣΥΝΤΟΝΙΣΜΟΣ ΜΕΝΕΙ ΩΣ ΕΧΕΙ (11/10/2026).
//
// Ρόλος: ένας — ο συντονισμός κάθε ενέργειας του χρήστη στον χάρτη κτιρίου:
// τι ρωτάμε (διάλογοι), τι γράφουμε (μέσω των repositories), τι ανανεώνουμε
// (καταστάσεις του χάρτη και του Καταλόγου). Τέσσερις ομάδες ενεργειών:
// επιλογή φύλλου/τμήματος, αποθήκευση θέσης τμήματος, διαχείριση φύλλων,
// μετάβαση από αναζήτηση.
//
// Γιατί δεν διασπάστηκε: οι ομάδες μοιράζονται την ίδια κατάσταση και τα ίδια
// βήματα — η διαχείριση φύλλων και η μετάβαση από αναζήτηση στηρίζονται
// συνεχώς στην αλλαγή φύλλου, στον συγχρονισμό προσχεδίου και στη φόρτωση
// εικόνας. Χωρισμένες σε αρχεία θα ξαναρωτούσαν τον χειριστή για όλα. Οι
// αποφάσεις (επιλογή τμήματος, μετακόμιση, χρώμα στο ✓, πού πηγαίνει η
// αναζήτηση) και οι διάλογοι ζουν ήδη σε δικά τους αρχεία, με τεστ.
//
// Τι θα το άλλαζε: απόφαση ή υπολογισμός που μπορεί να γραφτεί χωρίς βάση και
// διάλογο (θα έβγαινε δίπλα στις αδελφές του στο services/), ωμό ερώτημα SQL,
// ή κατασκευή διεπαφής εδώ — τότε ξαναξετάζεται από την αρχή.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/utils/department_floor_sync.dart';
import '../../../../core/utils/file_picker_session.dart';
import '../../../../core/utils/picker_location_memory.dart';
import '../../../../core/database/building_map_repository.dart';
import '../../../../core/database/floor_plan_repository.dart';
import '../../../../core/database/department_repository.dart';
import '../../../../core/database/omnisearch_service.dart';
import '../../../../core/models/app_permission.dart';
import '../../../../core/models/building_map_floor.dart';
import '../../../../core/services/permission_service.dart';
import '../../../../core/services/lookup_service.dart';
import '../../../calls/models/equipment_model.dart';
import '../../../calls/models/user_model.dart';
import '../../../../core/services/building_map_storage.dart';
import '../../../floor_map/services/floor_color_assignment_service.dart';
import '../../models/department_model.dart';
import '../../providers/department_directory_provider.dart';
import '../services/building_map_commit_color_plan.dart';
import '../services/building_map_department_bulk_actions.dart';
import '../services/building_map_department_eligibility.dart';
import '../services/building_map_foreign_change.dart';
import '../../../../core/widgets/stale_write_conflict_dialog.dart';
import '../services/building_map_department_pick_outcome.dart';
import '../services/building_map_placement_replacement.dart';
import '../models/building_map_jump_target.dart';
import '../../screens/widgets/department_color_palette.dart';
import '../building_map_draft_geometry.dart';
import '../building_map_label_layout.dart';
import '../providers/building_map_providers.dart';
import '../widgets/building_map_commit_color_dialog.dart';
import '../widgets/building_map_confirm_dialogs.dart';
import '../widgets/building_map_floor_delete_dialog.dart';
import '../services/building_map_floor_ordering.dart';
import '../services/floor_plan_image_cache.dart';
import '../services/floor_plan_image_encoder.dart';
import '../services/building_map_jump_fallback.dart';
import '../services/building_map_last_floor_preference.dart';
import '../widgets/building_map_floor_sheet_add_dialog.dart';
import '../widgets/building_map_floor_sheet_edit_dialog.dart';
import '../widgets/building_map_jump_pick_dialogs.dart';
import '../widgets/building_map_floor_upload_report_dialog.dart';
import '../../../../core/utils/user_facing_error_messages.dart';

final buildingMapControllerProvider = Provider<BuildingMapController>(
  (ref) => BuildingMapController(ref),
);

/// Συντονισμός βάσης, αποθήκευσης εικόνων και καταστάσεων Riverpod για τον χάρτη κτιρίου.
class BuildingMapController {
  BuildingMapController(this._ref);

  final Ref _ref;

  /// Αρχικός συγχρονισμός επιλεγμένου φύλλου μετά φόρτωση λίστας (μία φορά ανά φόρτωμα).
  bool appliedInitialFloorSync = false;

  void resetSession() {
    appliedInitialFloorSync = false;
    _sessionPickSeq = _floorPickSeq;
    _decodeKey = null;
  }

  /// Η εικόνα της οποίας το μέγεθος ζητήθηκε **τελευταία**.
  String? _decodeKey;
  bool _decoding = false;

  /// Μετρά το μέγεθος της κάτοψης στο τοπικό αρχείο [filePath].
  ///
  /// **Μία ανάγνωση ανά εικόνα:** η οθόνη ζητά το μέγεθος σε κάθε ξαναχτίσιμο
  /// όσο λείπει· ίδιο αίτημα ενώ τρέχει ή αφού απαντήθηκε δεν ξαναδιαβάζει.
  ///
  /// **Το μέγεθος ανήκει στην εικόνα του:** όταν ο χρήστης αλλάξει όροφο πριν
  /// τελειώσει η μέτρηση, η παλιά απάντηση πετιέται — αλλιώς ο νέος όροφος θα
  /// ζωγραφιζόταν με τις διαστάσεις του προηγούμενου, με τα τμήματα σε λάθος
  /// θέσεις. Το όνομα του τοπικού αρχείου είναι το αποτύπωμα των bytes, άρα
  /// ίδιο κλειδί σημαίνει ίδια εικόνα.
  Future<void> decodeImageFile(String? filePath) async {
    final decoded = _ref.read(buildingMapDecodedImageSizeProvider.notifier);
    final key = filePath ?? '';
    if (key == _decodeKey &&
        (_decoding || _ref.read(buildingMapDecodedImageSizeProvider) != null)) {
      return;
    }
    _decodeKey = key;
    decoded.setSize(null);
    if (key.isEmpty) return;

    _decoding = true;
    Size? size;
    try {
      final bytes = await File(key).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      size = Size(frame.image.width.toDouble(), frame.image.height.toDouble());
      frame.image.dispose();
    } catch (_) {
      // Χωρίς μέγεθος ο καμβάς δείχνει «φόρτωση»· η επόμενη αλλαγή εικόνας
      // (νέο αποτύπωμα) ξαναδοκιμάζει.
    } finally {
      if (_decodeKey == key) _decoding = false;
    }
    if (_decodeKey != key) return;
    decoded.setSize(size);
  }

  /// Κατεβάζει (αν χρειάζεται) την κάτοψη του [floor] και μετρά το μέγεθός της.
  Future<void> decodeImageForFloor(BuildingMapFloor? floor) async {
    if (floor == null) return decodeImageFile(null);
    final file = await FloorPlanImageCache.instance.fileFor(floor);
    await decodeImageFile(file?.path);
  }

  /// Οι όροφοι που πέρασαν στον νέο χάρτη· κενό όταν η βάση δεν απαντά.
  Future<Set<int>> _activeNewMapFloorIds() async {
    try {
      final db = await DatabaseHelper.instance.database;
      return await FloorPlanRepository(db).activeFloorIds();
    } catch (_) {
      return const {};
    }
  }

  /// Αυξάνει με κάθε όροφο που διαλέγει ο χρήστης (ή μια μετάβαση της
  /// αναζήτησης) — ώστε η αρχική επιλογή να μην πατήσει πάνω σε δική του.
  int _floorPickSeq = 0;

  /// Η τιμή του [_floorPickSeq] όταν άνοιξε ο χάρτης: διαφορά σημαίνει ότι σε
  /// αυτό το άνοιγμα έχει ήδη διαλεχτεί όροφος.
  int _sessionPickSeq = 0;

  /// Από πού διαβάζει η αρχική επιλογή: ο τελευταίος όροφος του χρήστη, οι
  /// όροφοι του τμήματος πληροφορικής και του νέου χάρτη. Αλλάζει στα τεστ.
  @visibleForTesting
  late Future<
    ({int? rememberedId, Set<int> itFloorIds, Set<int> newMapFloorIds})
  >
  Function(List<BuildingMapFloor> floors)
  initialFloorInputs = _readInitialFloorInputs;

  /// Πού γράφεται ο όροφος που διάλεξε ο χρήστης. Αλλάζει στα τεστ.
  @visibleForTesting
  Future<void> Function(int floorId) rememberFloor =
      BuildingMapLastFloorPreference.write;

  Future<({int? rememberedId, Set<int> itFloorIds, Set<int> newMapFloorIds})>
  _readInitialFloorInputs(List<BuildingMapFloor> floors) async => (
    rememberedId: await BuildingMapLastFloorPreference.read(),
    itFloorIds: {
      for (final d in _ref.read(departmentDirectoryProvider).allDepartments)
        if (d.floorId != null && isItDepartmentName(d.name)) d.floorId!,
    },
    newMapFloorIds: await _activeNewMapFloorIds(),
  );

  /// Με [initial] (ο χάρτης μόλις άνοιξε): ο όροφος που πρέπει να ανοίξει,
  /// **όποιος κι αν είναι επιλεγμένος τώρα** — η οθόνη βάζει προσωρινά τον
  /// πρώτο της βάσης πριν φτάσει εδώ, και αυτός δεν είναι επιλογή του
  /// χρήστη (περιστατικό 30/10/2026). Μόνο όροφος που διαλέχτηκε σε αυτό το
  /// άνοιγμα μένει. Χωρίς [initial]: διορθώνεται μόνο επιλογή που δεν ισχύει.
  Future<void> syncSheetSelection(
    List<BuildingMapFloor> floors, {
    bool initial = false,
  }) async {
    if (floors.isEmpty) return;
    final sel = _ref.read(buildingMapSelectedSheetIdProvider);
    final invalid = sel == null || !floors.any((f) => f.id == sel);
    final pickedThisSession = _floorPickSeq != _sessionPickSeq;
    if (invalid || (initial && !pickedThisSession)) {
      final pickSeq = _floorPickSeq;
      final inputs = await initialFloorInputs(floors);
      final chosen = chooseInitialBuildingMapFloor(
        floors: floors,
        rememberedId: inputs.rememberedId,
        itFloorIds: inputs.itFloorIds,
        newMapFloorIds: inputs.newMapFloorIds,
      );
      if (pickSeq != _floorPickSeq) return;
      _ref
          .read(buildingMapSelectedSheetIdProvider.notifier)
          .setSheet(chosen ?? floors.first.id);
    }
    final sid = _ref.read(buildingMapSelectedSheetIdProvider);
    final sheet = floors.cast<BuildingMapFloor?>().firstWhere(
      (fl) => fl?.id == sid,
      orElse: () => null,
    );
    await decodeImageForFloor(sheet);
  }

  Future<void> selectFloorFromList(
    int floorId,
    List<BuildingMapFloor> floors, {
    bool clearSelectedDepartment = true,
  }) async {
    _floorPickSeq++;
    _ref.read(buildingMapSelectedSheetIdProvider.notifier).setSheet(floorId);
    // Εκεί θα ξανανοίξει ο χάρτης, και μετά από επανεκκίνηση.
    unawaited(rememberFloor(floorId));
    if (clearSelectedDepartment) {
      _ref
          .read(buildingMapSelectedDepartmentIdToMapProvider.notifier)
          .setDept(null);
      _ref.read(buildingMapSearchUnresolvedNoticeProvider.notifier).clear();
      _ref.read(buildingMapSearchFocusProvider.notifier).clear();
    }
    _ref.read(buildingMapDraftShapeProvider.notifier).clear();
    _ref.read(buildingMapEditFromSelectionTapProvider.notifier).clear();
    _ref.read(buildingMapSearchRevealedDepartmentIdProvider.notifier).clear();
    _ref.read(buildingMapToolProvider.notifier).setMode(MapToolMode.select);
    await decodeImageForFloor(
      floors.cast<BuildingMapFloor?>().firstWhere(
        (fl) => fl?.id == floorId,
        orElse: () => null,
      ),
    );
  }

  bool draftOverlapsOthers(Rect draft, String sheetStr, int excludeDeptId) {
    final deps = departmentsEligibleForBuildingMap(
      _ref.read(departmentDirectoryProvider).allDepartments,
    );
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
    if (!await _beforeMapWrite(
      context,
      [dept.id!],
      const ['color', 'floor_id'],
    )) {
      return;
    }
    final db = await DatabaseHelper.instance.database;
    await DepartmentRepository(db)
        .updateDepartment(dept.id!, {'color': hex}, expected: null);
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

  /// Ερώτηση πριν από μετακόμιση σε άλλο φύλλο. Η μετακίνηση μέσα στο ίδιο
  /// φύλλο περνά σιωπηλά — ο χρήστης βλέπει και την παλιά και τη νέα θέση.
  Future<bool> confirmPlacementReplacementIfNeeded(
    BuildContext context, {
    required DepartmentModel dept,
    required int floorId,
    required List<BuildingMapFloor> floors,
  }) async {
    final replacement = resolveBuildingMapPlacementReplacement(
      department: dept,
      targetSheetId: floorId,
    );
    if (!replacement.movesFromAnotherSheet) return true;
    return showBuildingMapMovePlacementConfirmDialog(
      context,
      departmentName: dept.displayName,
      fromFloorLabel: _floorLabel(replacement.previousFloorId, floors),
      toFloorLabel: _floorLabel(floorId, floors),
    );
  }

  String _floorLabel(int? floorId, List<BuildingMapFloor> floors) {
    if (floorId == null) return 'άγνωστο φύλλο';
    for (final f in floors) {
      if (f.id == floorId) return buildingMapFloorDisplayLabel(f);
    }
    return 'Όροφος #$floorId';
  }

  /// Το ✓ του προσχεδίου: γράφει μόνο ό,τι άλλαξε (επωνυμία, θέση ή και τα
  /// δύο) και το λέει με **ένα** μήνυμα. Επιστρέφει τι έγινε με την επωνυμία
  /// (`null` αν δεν γράφτηκε), ώστε η οθόνη να καθαρίσει την τοπική της.
  Future<MapDisplayNameSaved?> confirmDraft({
    required BuildContext context,
    required DraftDepartmentShape draft,
    required DepartmentModel dept,
    required int floorId,
    required List<BuildingMapFloor> floors,
    required String? editedMapName,
  }) async {
    final plan = planDraftConfirm(
      dept: dept,
      draft: draft,
      sheetStr: floorId.toString(),
      editedMapName: editedMapName,
    );
    MapDisplayNameSaved? nameSaved;
    if (plan.saveName) {
      nameSaved = await saveDepartmentMapDisplayName(
        context: context,
        departmentId: dept.id!,
        canonicalDepartmentName: dept.name,
        editedText: editedMapName!,
        announce: false,
      );
      if (nameSaved == null || !context.mounted) return nameSaved;
    }
    var placementSaved = false;
    if (plan.savePlacement) {
      placementSaved = await _commitDraftPlacement(
        context: context,
        draft: draft,
        dept: dept,
        floorId: floorId,
        floors: floors,
      );
    } else if (nameSaved != null) {
      _finishDraftEditing();
    }
    if (!context.mounted || (!placementSaved && nameSaved == null)) {
      return nameSaved;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          draftConfirmMessage(
            placementSaved: placementSaved,
            nameSaved: nameSaved,
          ),
        ),
      ),
    );
    return nameSaved;
  }

  /// Γράφει τη θέση του προσχεδίου. `false` όταν ο χρήστης ακύρωσε κάποια
  /// ερώτηση στη διαδρομή ή η εγγραφή δεν επιτράπηκε.
  Future<bool> _commitDraftPlacement({
    required BuildContext context,
    required DraftDepartmentShape draft,
    required DepartmentModel dept,
    required int floorId,
    required List<BuildingMapFloor> floors,
  }) async {
    final draftRect = draft.rect;
    final sheetStr = floorId.toString();
    if (!await confirmOverlapIfNeeded(context, draftRect, sheetStr, dept.id!)) {
      return false;
    }
    if (!context.mounted) return false;
    if (!await confirmPlacementReplacementIfNeeded(
      context,
      dept: dept,
      floorId: floorId,
      floors: floors,
    )) {
      return false;
    }
    if (!context.mounted) return false;

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
    final colorPlan = resolveBuildingMapCommitColorPlan(
      dept: dept,
      sheetStr: sheetStr,
    );

    void removeOldFloorColorIfMoved() {
      final previousFloorId = colorPlan.releaseFromFloorId;
      final oldColor = colorPlan.currentColor;
      if (previousFloorId != null && oldColor != null) {
        FloorColorAssignmentService.instance.removeColorFromFloor(
          previousFloorId,
          oldColor,
        );
      }
    }

    String? colorHex;

    switch (colorPlan.action) {
      case BuildingMapCommitColorAction.keepCurrent:
        colorHex = null;
      case BuildingMapCommitColorAction.assignNew:
        final picked = FloorColorAssignmentService.instance
            .getNextDistinctColor(floorId, additionalUsed: additionalUsed);
        colorHex = colorToDepartmentHex(picked);
        removeOldFloorColorIfMoved();
      case BuildingMapCommitColorAction.askUser:
        final currentParsed = colorPlan.currentColor!;
        final suggested = FloorColorAssignmentService.instance
            .peekNextDistinctColor(floorId, additionalUsed: additionalUsed);
        if (!context.mounted) return false;
        final choice = await showBuildingMapCommitColorDialog(
          context,
          departmentName: dept.name,
          currentColor: currentParsed,
          suggestedColor: suggested,
        );
        if (!context.mounted) return false;
        if (choice == null) {
          return false;
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
    if (!context.mounted ||
        !await _beforeMapWrite(
          context,
          [dept.id!],
          DepartmentFloorSync.mergeFloorContext(
            updates,
            drawingFloorId: floorId,
          ).keys,
        )) {
      return false;
    }
    await DepartmentRepository(db).saveDepartmentWithFloorContext(
      dept.id!,
      updates,
      drawingFloorId: floorId,
    );
    if (colorPlan.action == BuildingMapCommitColorAction.keepCurrent) {
      final keep = colorPlan.currentColor;
      if (keep != null) {
        FloorColorAssignmentService.instance.overrideColor(floorId, keep);
      }
    }
    await _ref.read(departmentDirectoryProvider.notifier).loadDepartments();
    _finishDraftEditing();
    return true;
  }

  /// Κλείνει το προσχέδιο και γυρίζει στο εργαλείο από όπου ξεκίνησε.
  void _finishDraftEditing() {
    final backToSelection = _ref.read(buildingMapEditFromSelectionTapProvider);
    _ref.read(buildingMapDraftShapeProvider.notifier).clear();
    _ref.read(buildingMapEditFromSelectionTapProvider.notifier).clear();
    _ref
        .read(buildingMapToolProvider.notifier)
        .setMode(backToSelection ? MapToolMode.select : MapToolMode.draw);
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

  /// Κρύβει ή εμφανίζει τμήματα στην κάτοψη — ένα ή πολλά, μία ενέργεια.
  Future<void> setDepartmentsHiddenOnMap(
    BuildContext context,
    Iterable<int> departmentIds, {
    required bool hidden,
  }) async {
    final ids = departmentIds.toList(growable: false);
    if (ids.isEmpty) return;
    if (!await _beforeMapWrite(context, ids, const ['map_hidden'])) return;
    final db = await DatabaseHelper.instance.database;
    final repo = DepartmentRepository(db);
    await db.transaction(
      (txn) => setDepartmentsHiddenOnMapInTxn(
        txn,
        repository: repo,
        departmentIds: ids,
        hidden: hidden,
      ),
    );
    await _ref.read(departmentDirectoryProvider.notifier).loadDepartments();
  }

  /// Αφαιρεί πολλά τμήματα από το φύλλο [floorId] σε μία συναλλαγή.
  ///
  /// Τα χρώματα ελευθερώνονται **μετά** την επιτυχή εγγραφή: το μητρώο
  /// χρωμάτων ζει στη μνήμη και δεν γυρίζει πίσω μαζί με τη συναλλαγή.
  Future<void> removeDepartmentsFromFloor(
    BuildContext context,
    List<DepartmentModel> departments, {
    required int floorId,
  }) async {
    if (departments.isEmpty) return;
    if (!await _beforeMapWrite(
      context,
      [for (final d in departments) ?d.id],
      BuildingMapRepository.clearedBuildingMapPlacementColumns(
        clearFloorId: true,
        clearDepartmentHex: true,
      ).keys,
    )) {
      return;
    }
    final db = await DatabaseHelper.instance.database;
    final repo = DepartmentRepository(db);
    final releasedColors = await db.transaction(
      (txn) => removeDepartmentsFromFloorInTxn(
        txn,
        repository: repo,
        departments: departments,
      ),
    );
    for (final color in releasedColors) {
      FloorColorAssignmentService.instance.removeColorFromFloor(floorId, color);
    }
    await _ref.read(departmentDirectoryProvider.notifier).loadDepartments();
  }

  /// Αποθηκεύει το προσαρμοσμένο όνομα εμφάνισης στο χάρτη (`map_custom_name`).
  /// Κενό ή ταύτιση με το κανονικό όνομα τμήματος → NULL στη βάση (χρήση `name`).
  ///
  /// Με [announce] `false` δεν δείχνει δικό του μήνυμα — το λέει ο καλών
  /// μαζί με ό,τι άλλο αποθήκευσε. Επιστρέφει `null` όταν δεν γράφτηκε.
  Future<MapDisplayNameSaved?> saveDepartmentMapDisplayName({
    required BuildContext context,
    required int departmentId,
    required String canonicalDepartmentName,
    required String editedText,
    bool announce = true,
  }) async {
    final custom = resolveMapCustomName(
      editedText: editedText,
      canonicalName: canonicalDepartmentName,
    );
    if (!await _beforeMapWrite(
      context,
      [departmentId],
      const ['map_custom_name'],
    )) {
      return null;
    }
    final db = await DatabaseHelper.instance.database;
    await DepartmentRepository(db).updateDepartment(departmentId, {
      'map_custom_name': custom,
    }, expected: null);
    await _ref.read(departmentDirectoryProvider.notifier).loadDepartments();
    final saved = custom == null
        ? MapDisplayNameSaved.resetToName
        : MapDisplayNameSaved.custom;
    if (announce && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            draftConfirmMessage(placementSaved: false, nameSaved: saved),
          ),
        ),
      );
    }
    return saved;
  }

  /// Διαγράφει τη χαρτογράφηση του τμήματος στο τρέχον φύλλο, αφού ρωτήσει τον χρήστη.
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

    final cleared = BuildingMapRepository.clearedBuildingMapPlacementColumns(
      clearFloorId: true,
      clearDepartmentHex: true,
    );
    if (!await _beforeMapWrite(context, [dept.id!], cleared.keys)) return;
    final db = await DatabaseHelper.instance.database;
    final removedColor = tryParseDepartmentHex(dept.color);
    await DepartmentRepository(db)
        .updateDepartment(dept.id!, cleared, expected: null);
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

  /// Επιλογή τμήματος στην κατάσταση που αντιστοιχεί στο τι έχει ήδη ο χάρτης:
  /// σχεδίαση όταν δεν έχει θέση, επεξεργασία όταν έχει θέση εδώ.
  void _selectDepartmentForSheet({
    required int departmentId,
    required List<DepartmentModel> departments,
    required int floorId,
    required bool asExistingPlacement,
  }) {
    _ref
        .read(buildingMapSelectedDepartmentIdToMapProvider.notifier)
        .setDept(departmentId);
    syncDraftWithSelectedDepartment(
      departments: departments,
      departmentId: departmentId,
      floorId: floorId,
    );
    if (asExistingPlacement) {
      _ref
          .read(buildingMapEditFromSelectionTapProvider.notifier)
          .setValue(true);
      _ref.read(buildingMapToolProvider.notifier).setMode(MapToolMode.edit);
      return;
    }
    _ref.read(buildingMapDraftShapeProvider.notifier).clear();
    _ref.read(buildingMapEditFromSelectionTapProvider.notifier).clear();
    _ref.read(buildingMapToolProvider.notifier).setMode(MapToolMode.draw);
  }

  /// Εφαρμόζει την επιλογή τμήματος από τη λίστα «Επιλογή τμήματος».
  ///
  /// Συμβόλαιο: η επιλογή δεν ξεκινά ποτέ σιωπηλά νέα σχεδίαση για τμήμα που
  /// έχει ήδη θέση — ή το δείχνει εκεί που είναι, ή ρωτά.
  Future<void> applyDepartmentPickFromList({
    required BuildContext context,
    required DepartmentModel department,
    required List<DepartmentModel> departments,
    required List<BuildingMapFloor> floors,
    required int currentSheetId,
  }) async {
    final deptId = department.id;
    if (deptId == null) return;
    final pick = resolveBuildingMapDepartmentPick(
      department: department,
      currentSheetId: currentSheetId,
      floors: floors,
    );

    switch (pick.action) {
      case BuildingMapDepartmentPickAction.drawHere:
        _selectDepartmentForSheet(
          departmentId: deptId,
          departments: departments,
          floorId: currentSheetId,
          asExistingPlacement: false,
        );
      case BuildingMapDepartmentPickAction.editHere:
        _selectDepartmentForSheet(
          departmentId: deptId,
          departments: departments,
          floorId: currentSheetId,
          asExistingPlacement: true,
        );
      case BuildingMapDepartmentPickAction.orphanedPlacement:
        _selectDepartmentForSheet(
          departmentId: deptId,
          departments: departments,
          floorId: currentSheetId,
          asExistingPlacement: false,
        );
        _showMapSnack(
          context,
          'Το τμήμα «${department.displayName}» δείχνει σε όροφο που δεν υπάρχει '
          'πια. Σχεδίασέ το εδώ για να αποκτήσει ξανά θέση.',
        );
      case BuildingMapDepartmentPickAction.askFloorChoice:
        final choice = await showBuildingMapMappedDepartmentChoiceDialog(
          context,
          departmentName: department.displayName,
          itsFloorLabel: pick.otherFloorLabel ?? 'άλλος όροφος',
          currentFloorLabel: _floorLabel(currentSheetId, floors),
        );
        if (choice == null || !context.mounted) return;
        switch (choice) {
          case BuildingMapMappedDepartmentChoice.goToItsFloor:
            await jumpToMappedDepartment(
              department: department,
              floors: floors,
              departments: departments,
            );
            _selectDepartmentForSheet(
              departmentId: deptId,
              departments: departments,
              floorId: pick.otherFloorId!,
              asExistingPlacement: true,
            );
          case BuildingMapMappedDepartmentChoice.moveToCurrentFloor:
            _selectDepartmentForSheet(
              departmentId: deptId,
              departments: departments,
              floorId: currentSheetId,
              asExistingPlacement: false,
            );
            _showMapSnack(
              context,
              'Σχεδίασε τη νέα θέση και πάτησε ✓ για να ολοκληρωθεί η μετακίνηση.',
            );
        }
    }
  }

  /// Έχει ο χρήστης το δικαίωμα «Σχεδίαση χάρτη»;
  ///
  /// Ρωτιέται σε **κάθε** ενέργεια και όχι μία φορά: η «Αλλαγή χρήστη» αλλάζει
  /// την απάντηση ζωντανά. Οι οθόνες κρύβουν τα κουμπιά με την ίδια ερώτηση·
  /// ο έλεγχος εδώ είναι η δεύτερη γραμμή, για όποια πόρτα ξεχάσει να τα κρύψει.
  bool get canManageFloorPlans =>
      PermissionService.instance.can(AppPermission.manageFloorPlans);

  /// Κοινός επιλογέας εικόνας κάτοψης: ανοίγει στον τελευταίο φάκελο εικόνων
  /// του χάρτη (όχι στην καθολική «τελευταία θέση» των Windows) και τον
  /// θυμάται μετά από επιτυχή επιλογή. null σε ακύρωση.
  Future<String?> _pickFloorSheetImagePath() async {
    final session = await FilePickerSession.run(_pickFloorSheetImagePathImpl);
    // Το δεύτερο κλικ εστίασε τον ήδη ανοιχτό διάλογο — καμία νέα επιλογή.
    if (session.refocusedExisting) return null;
    return session.value;
  }

  Future<String?> _pickFloorSheetImagePathImpl() async {
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

  /// Διαβάζει την εικόνα του [file] και τη μετατρέπει στη μορφή της βάσης.
  ///
  /// Η μετατροπή γίνεται σε δικό της νήμα: μια μεγάλη κάτοψη θέλει
  /// δευτερόλεπτα, και η οθόνη δεν πρέπει να παγώσει όσο κρατά.
  static Future<Uint8List> _encodeFloorPlanFile(File file) async {
    final source = await file.readAsBytes();
    return Isolate.run(() => encodeFloorPlanImage(source));
  }

  /// Όπως το [_encodeFloorPlanFile], με μήνυμα στον χρήστη αν η εικόνα δεν
  /// διαβάζεται· `null` τότε.
  Future<Uint8List?> _encodePickedImage(
    BuildContext context,
    String srcPath,
  ) async {
    try {
      return await _encodeFloorPlanFile(File(srcPath));
    } on FloorPlanImageUnreadable catch (e) {
      _showMapSnack(context, humanizeUserFacingError(e));
    } on FileSystemException catch (e) {
      _showMapSnack(
        context,
        'Η εικόνα δεν διαβάστηκε: ${e.osError?.message ?? e.message}',
      );
    }
    return null;
  }

  Future<void> addFloorSheet(BuildContext context) async {
    if (!canManageFloorPlans) return;
    final srcPath = await _pickFloorSheetImagePath();
    if (srcPath == null || !context.mounted) return;

    final result = await showBuildingMapFloorSheetAddDialog(context);
    if (result == null || !context.mounted) return;

    final image = await _encodePickedImage(context, srcPath);
    if (image == null || !context.mounted) return;

    final db = await DatabaseHelper.instance.database;
    final maps = BuildingMapRepository(db);
    final id = await maps.insertBuildingMapFloor(
      label: result.label,
      floorGroup: result.floorGroup,
      rotationDegrees: 0,
    );
    await maps.saveFloorImage(id, image);
    // Ο νέος όροφος είναι επιλογή του χρήστη: η επαναφόρτωση της λίστας δεν
    // τον αντικαθιστά με τον τελευταίο που θυμόταν.
    _floorPickSeq++;
    unawaited(rememberFloor(id));
    _ref.read(buildingMapSelectedSheetIdProvider.notifier).setSheet(id);
    final floors = await maps.listBuildingMapFloors();
    if (!context.mounted) return;
    await syncSheetSelection(floors);
    appliedInitialFloorSync = false;
    _ref.read(buildingMapFloorReloadSeqProvider.notifier).bump();
  }

  /// Ο διάλογος «Επεξεργασία κάτοψης» για τον όροφο [floorId] — π.χ. από την
  /// ένδειξη «Η κάτοψη δεν έχει ανέβει ακόμη» του καμβά.
  Future<void> editFloorSheetById(BuildContext context, int floorId) async {
    final db = await DatabaseHelper.instance.database;
    final floors = await BuildingMapRepository(db).listBuildingMapFloors();
    final floor = floors.cast<BuildingMapFloor?>().firstWhere(
      (f) => f?.id == floorId,
      orElse: () => null,
    );
    if (floor == null || !context.mounted) return;
    await editFloorSheet(context, floor);
  }

  Future<void> editFloorSheet(
    BuildContext context,
    BuildingMapFloor floor,
  ) async {
    if (!canManageFloorPlans) return;
    final current = await FloorPlanImageCache.instance.fileFor(floor);
    if (!context.mounted) return;
    final previewDepartments = departmentsEligibleForBuildingMap(
      _ref.read(departmentDirectoryProvider).allDepartments,
    );

    final result = await showBuildingMapFloorSheetEditDialog(
      context,
      floor: floor,
      previewDepartments: previewDepartments,
      currentImagePath: current?.path ?? '',
      pickImagePath: _pickFloorSheetImagePath,
    );
    if (result == null || !context.mounted) return;

    Uint8List? image;
    if (result.pickedSrcPath != null) {
      image = await _encodePickedImage(context, result.pickedSrcPath!);
      if (image == null) return;
    }

    final db = await DatabaseHelper.instance.database;
    final maps = BuildingMapRepository(db);
    await maps.updateBuildingMapFloor(
      floor.id,
      label: result.label,
      floorGroup: result.floorGroupRaw,
    );
    if (image != null) {
      await maps.saveFloorImage(floor.id, image);
    }
    _ref.read(buildingMapFloorReloadSeqProvider.notifier).bump();
    if (image != null && context.mounted) {
      _showMapSnack(
        context,
        'Η κάτοψη ενημερώθηκε για όλους τους σταθμούς. Η προηγούμενη '
        'επανέρχεται με «Επαναφορά προηγούμενης κάτοψης».',
      );
    }
  }

  /// «Επαναφορά προηγούμενης κάτοψης»: ανταλλάσσει τρέχουσα και προηγούμενη.
  ///
  /// Χωρίς ερώτηση επιβεβαίωσης, επίτηδες: τίποτα δεν χάνεται — μια δεύτερη
  /// επαναφορά φέρνει πίσω αυτήν που μόλις αντικαταστάθηκε.
  Future<void> revertFloorImage(
    BuildContext context,
    BuildingMapFloor floor,
  ) async {
    if (!canManageFloorPlans) return;
    final db = await DatabaseHelper.instance.database;
    final swapped = await BuildingMapRepository(db)
        .swapFloorImageWithPrevious(floor.id);
    _ref.read(buildingMapFloorReloadSeqProvider.notifier).bump();
    if (!context.mounted) return;
    _showMapSnack(
      context,
      swapped
          ? 'Επανήλθε η προηγούμενη κάτοψη του ορόφου «${floor.label}». '
                'Με νέα επαναφορά επιστρέφει αυτή που αντικαταστάθηκε.'
          : 'Δεν υπάρχει προηγούμενη κάτοψη για τον όροφο «${floor.label}».',
    );
  }

  /// «Ανέβασμα κατόψεων στη βάση»: για κάθε όροφο που δεν έχει ακόμη εικόνα
  /// στη βάση, ανεβάζει την παλιά τοπική εικόνα **αυτού** του σταθμού.
  ///
  /// Ρητή ενέργεια του διαχειριστή, επίτηδες (απόφαση Διευθυντή 17/10/2026):
  /// κάθε σταθμός μπορεί να έχει άλλη εικόνα για τον ίδιο όροφο, και ποια
  /// είναι η σωστή το ξέρει μόνο εκείνος. Όροφοι που έχουν ήδη εικόνα δεν
  /// αγγίζονται ποτέ.
  Future<void> uploadLocalFloorPlans(BuildContext context) async {
    if (!canManageFloorPlans) return;
    final db = await DatabaseHelper.instance.database;
    final maps = BuildingMapRepository(db);
    final floors = await maps.listBuildingMapFloors();

    final uploaded = <String>[];
    final notFound = <String>[];
    final unreadable = <String>[];
    for (final floor in floors) {
      if (floor.hasImage) continue;
      final label = buildingMapFloorDisplayLabel(floor);
      final stored = floor.imagePath.trim();
      final file = stored.isEmpty
          ? null
          : File(await BuildingMapStorage.resolveToAbsolute(stored));
      if (file == null || !await file.exists()) {
        notFound.add(label);
        continue;
      }
      try {
        await maps.saveFloorImage(floor.id, await _encodeFloorPlanFile(file));
        uploaded.add(label);
      } on FloorPlanImageUnreadable {
        unreadable.add(label);
      } on FileSystemException {
        unreadable.add(label);
      }
    }

    if (uploaded.isNotEmpty) {
      _ref.read(buildingMapFloorReloadSeqProvider.notifier).bump();
    }
    if (!context.mounted) return;
    await showFloorPlanUploadReportDialog(
      context,
      uploaded: uploaded,
      notFound: notFound,
      unreadable: unreadable,
    );
  }

  Future<void> deleteFloorSheet(BuildContext context, int sheetId) async {
    if (!canManageFloorPlans) return;
    final go = await showBuildingMapFloorDeleteDialog(context);
    if (!go || !context.mounted) return;
    try {
      final db = await DatabaseHelper.instance.database;
      final departments = DepartmentRepository(db);
      final maps = BuildingMapRepository(db);
      // Ο χάρτης γράφει ΜΟΝΟ τις δικές του στήλες, ποτέ ολόκληρη την
      // καρτέλα — άρα δεν υπάρχει αφετηρία να συγκριθεί.
      maps.bindUpdateDepartment(
        (id, values) =>
            departments.updateDepartment(id, values, expected: null),
      );
      await maps.deleteBuildingMapFloorClearingDepartmentMaps(sheetId);
      // Η διαγραφή ορόφου δεν αναιρείται (η κάτοψη χάθηκε μαζί του)· μια
      // παλιότερη Αναίρεση θα έβαζε τμήμα σε όροφο που δεν υπάρχει πια.
      _ref.read(buildingMapUndoProvider.notifier).clear();
      _ref.read(buildingMapSelectedSheetIdProvider.notifier).setSheet(null);
      appliedInitialFloorSync = false;
      _ref.read(buildingMapFloorReloadSeqProvider.notifier).bump();
      await _ref.read(departmentDirectoryProvider.notifier).loadDepartments();
      if (context.mounted) {
        _showMapSnack(
          context,
          'Ο όροφος διαγράφηκε μαζί με την κάτοψή του, και καθαρίστηκαν οι '
          'θέσεις χάρτη των σχετικών τμημάτων.',
        );
      }
    } catch (e) {
      if (context.mounted) {
        _showMapSnack(
          context,
          'Αποτυχία διαγραφής: ${humanizeUserFacingError(e)}',
        );
      }
    }
  }

  Future<void> applySheetRotation(int sheetId, double degrees) async {
    if (!canManageFloorPlans) return;
    final db = await DatabaseHelper.instance.database;
    await BuildingMapRepository(db)
        .updateBuildingMapFloor(sheetId, rotationDegrees: degrees);
    _ref.read(buildingMapFloorReloadSeqProvider.notifier).bump();
  }

  /// Το βήμα πριν από **κάθε** εγγραφή του χάρτη σε τμήματα.
  ///
  /// 1. **Διένεξη:** άλλαξε άλλος σταθμός, στις ίδιες στήλες, κάτι που ο
  ///    χάρτης δεν έχει δει; Τότε ρωτά «Κάποιος πρόλαβε», όπως οι καρτέλες
  ///    του Καταλόγου. Ο χάρτης μένει ακίνητος στην επεξεργασία (απόφαση
  ///    25/08/2026)· η ερώτηση εμποδίζει μόνο τη σιωπηλή απώλεια.
  /// 2. **Αναίρεση:** στιγμιότυπο των στηλών πριν γραφτούν.
  ///
  /// Επιστρέφει `false` όταν ο χρήστης κράτησε την αλλαγή του συναδέλφου:
  /// τότε δεν γράφεται τίποτα, και ο χάρτης ξαναδιαβάζει τα τμήματα ώστε να
  /// τη δείχνει.
  Future<bool> _beforeMapWrite(
    BuildContext context,
    Iterable<int> departmentIds,
    Iterable<String> columns,
  ) async {
    final ids = departmentIds.toList(growable: false);
    final cols = columns.toList(growable: false);
    final seenById = {
      for (final d in _ref.read(departmentDirectoryProvider).allDepartments)
        if (d.id != null && ids.contains(d.id)) d.id!: d,
    };
    final repo = DepartmentRepository(await DatabaseHelper.instance.database);
    var keepTheirs = false;
    for (final id in ids) {
      final seen = seenById[id];
      if (seen == null) continue;
      final fresh = await repo.getDepartmentRowById(id);
      if (fresh == null) continue;
      final conflict = buildingMapForeignChange(
        seen: seen,
        freshRow: fresh,
        columns: cols,
      );
      if (conflict == null) continue;
      final actor = await repo.lastActorFor(id);
      if (!context.mounted) return false;
      final overwrite = await showStaleWriteConflictDialog(
        context,
        headline: buildingMapConflictHeadline(
          departmentName: seen.displayName,
          changedBy: actor.who,
          changedAt: actor.at,
          now: DateTime.now(),
        ),
        warning: conflict.overwriteWarning,
        changedFields: conflict.changedFields,
      );
      keepTheirs = overwrite != true;
      break;
    }
    if (keepTheirs) {
      await _ref.read(departmentDirectoryProvider.notifier).loadDepartments();
      if (context.mounted) {
        _showMapSnack(
          context,
          'Η αλλαγή ακυρώθηκε — ο χάρτης δείχνει τώρα την αλλαγή του '
          'συναδέλφου.',
        );
      }
      return false;
    }
    await _captureUndo(ids, cols);
    return true;
  }

  /// Κρατά τις τιμές που έχουν **τώρα** οι [columns] των [departmentIds] —
  /// ακριβώς όσες θα γράψει η ενέργεια που ακολουθεί, ώστε η Αναίρεση να τις
  /// φέρει όλες πίσω.
  ///
  /// **Κάθε** ενέργεια χάρτη που γράφει τμήματα περνά από εδώ πριν γράψει:
  /// η Αναίρεση αναιρεί την τελευταία ενέργεια — μια ενέργεια που δεν
  /// κρατούσε στιγμιότυπο άφηνε ενεργό το στιγμιότυπο μιας παλιότερης.
  Future<void> _captureUndo(
    Iterable<int> departmentIds,
    Iterable<String> columns,
  ) async {
    final db = await DatabaseHelper.instance.database;
    final repo = BuildingMapRepository(db);
    final snapshot = <int, Map<String, Object?>>{};
    for (final id in departmentIds) {
      final values = await repo.readDepartmentColumns(id, columns);
      if (values.isNotEmpty) snapshot[id] = values;
    }
    final undo = _ref.read(buildingMapUndoProvider.notifier);
    if (snapshot.isEmpty) {
      undo.clear();
    } else {
      undo.capture(BuildingMapUndoSnapshot(snapshot));
    }
  }

  Future<void> undoLastGeometry(BuildContext context) async {
    final snap = _ref.read(buildingMapUndoProvider);
    if (snap == null) return;
    final db = await DatabaseHelper.instance.database;
    final repo = DepartmentRepository(db);
    await db.transaction((txn) async {
      for (final entry in snap.valuesByDepartment.entries) {
        await repo.updateDepartment(
          entry.key,
          entry.value,
          executor: txn,
          expected: null,
        );
      }
    });
    // Το χρώμα που επιστρέφει ξαναπιάνει τη θέση του στον όροφο, ώστε το
    // επόμενο τμήμα να μην πάρει το ίδιο.
    for (final values in snap.valuesByDepartment.values) {
      final floorId = values['floor_id'] as int?;
      final color = tryParseDepartmentHex(values['color'] as String?);
      if (floorId != null && color != null) {
        FloorColorAssignmentService.instance.overrideColor(floorId, color);
      }
    }
    _ref.read(buildingMapUndoProvider.notifier).clear();
    await _ref.read(departmentDirectoryProvider.notifier).loadDepartments();
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Αναίρεση εφαρμόστηκε.')));
    }
  }

  void _showMapSnack(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<List<int>> _departmentIdsForUserId(int userId) async {
    final db = await DatabaseHelper.instance.database;
    return DepartmentRepository(db).resolveActiveDepartmentIdsForUserId(userId);
  }

  Future<List<int>> _departmentIdsForPhone(String phoneText) async {
    final db = await DatabaseHelper.instance.database;
    return DepartmentRepository(db)
        .resolveActiveDepartmentIdsForPhone(phoneText);
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

    // Νέος χάρτης: το τμήμα έχει χώρο σε όροφο που ενεργοποιήθηκε — εκεί
    // πηγαίνει, προτιμώντας τον όροφο που γράφει ο Κατάλογος.
    final db = await DatabaseHelper.instance.database;
    final roomFloors = (await FloorPlanRepository(db)
        .activeFloorsWithRoomsOf({departmentId}))[departmentId];
    if (roomFloors != null && roomFloors.isNotEmpty) {
      final catalogFloor = department.floorId;
      final target = catalogFloor != null && roomFloors.contains(catalogFloor)
          ? catalogFloor
          : roomFloors.first;
      if (floors.any((f) => f.id == target)) {
        _ref.read(buildingMapSearchUnresolvedNoticeProvider.notifier).clear();
        await selectFloorFromList(
          target,
          floors,
          clearSelectedDepartment: false,
        );
        _ref
            .read(buildingMapSelectedDepartmentIdToMapProvider.notifier)
            .setDept(departmentId);
        _ref.read(buildingMapViewportCenterRequestSeqProvider.notifier).bump();
        return;
      }
    }

    final outcome = resolveBuildingMapJumpFallback(
      department: department,
      floors: floors,
    );

    if (outcome.isMapped) {
      _ref.read(buildingMapSearchUnresolvedNoticeProvider.notifier).clear();
      await jumpToMappedDepartment(
        department: department,
        floors: floors,
        departments: departments,
      );
      return;
    }

    final fallbackFloorId = outcome.fallbackFloorId;
    if (fallbackFloorId == null) return;
    await selectFloorFromList(
      fallbackFloorId,
      floors,
      clearSelectedDepartment: false,
    );
    _ref
        .read(buildingMapSelectedDepartmentIdToMapProvider.notifier)
        .setDept(departmentId);

    final message = outcome.message!;
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
      // Τηλέφωνο χωρίς θέση: τα τμήματα που το έχουν. Αντικείμενο του
      // χάρτη έχει πάντα θέση, άρα δεν φτάνει ως εδώ.
      case BuildingMapOmnisearchEntityKind.phone:
      case BuildingMapOmnisearchEntityKind.mapObject:
        return hit.departmentIds;
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

    // Αποτέλεσμα με θέση στον νέο χάρτη: πηγαίνει στο ίδιο το σύμβολο.
    if (target case BuildingMapSearchHitJump(:final hit)) {
      final spot = hit.spot;
      if (spot != null && floors.any((f) => f.id == spot.floorId)) {
        await selectFloorFromList(spot.floorId, floors);
        _ref.read(buildingMapSearchFocusProvider.notifier).set(spot);
        _ref.read(buildingMapViewportCenterRequestSeqProvider.notifier).bump();
        return;
      }
    }
    _ref.read(buildingMapSearchFocusProvider.notifier).clear();

    await _ref.read(departmentDirectoryProvider.notifier).loadDepartments();
    if (!context.mounted) return;
    final departments = departmentsEligibleForBuildingMap(
      _ref.read(departmentDirectoryProvider).allDepartments,
    );

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
