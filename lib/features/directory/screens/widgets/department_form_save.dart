import 'package:flutter/material.dart';
import 'directory_conflict_dialog.dart';

import '../../../../core/database/audit_service.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/database/department_repository.dart';
import '../../../../core/errors/department_exists_exception.dart';
import '../../../../core/services/save_confirmation_summary.dart';
import '../../../../core/widgets/audit_summary_rich_text.dart';
import '../../../../core/widgets/database_persistence_error_snackbar.dart';
import '../../building_map/services/building_map_floor_ordering.dart';
import '../../../floor_map/services/floor_color_assignment_service.dart';
import '../../models/department_model.dart';
import 'department_color_palette.dart';
import 'department_form_dialog.dart';
import 'department_save_map_questions.dart';
import 'department_save_model_builder.dart';
import 'department_save_name_conflict.dart';

/// Ροή αποθήκευσης της φόρμας τμήματος: μοντέλο, συγκρούσεις κοινόχρηστων,
/// εγγραφή, επαναφορά διαγραμμένου και μηνύματα επιβεβαίωσης.
///
/// Συνεργάτης του [DepartmentFormDialogState] (Σύνθεση).
class DepartmentFormSave {
  DepartmentFormSave(this.host);

  final DepartmentFormDialogState host;

  /// Η «Αποθήκευση» της καρτέλας τμήματος.
  ///
  /// Σειρά: τιμές της φόρμας → ερωτήσεις κάτοψης → (επεξεργασία ή
  /// δημιουργία, η καθεμιά με τις δικές της ερωτήσεις πριν από τις εγγραφές)
  /// → μήνυμα επιβεβαίωσης. Κάθε ακύρωση στη διαδρομή αφήνει τη φόρμα
  /// ανοιχτή.
  Future<void> save() async {
    if (!(host.formKey.currentState?.validate() ?? false)) return;
    final input = _readForm();
    if (input == null) return;
    final ini = host.widget.initialDepartment;

    // Οι ερωτήσεις της κάτοψης προηγούνται κάθε εγγραφής: ό,τι κι αν απαντηθεί,
    // ως εδώ δεν έχει γραφτεί τίποτα και μια ακύρωση δεν αφήνει ίχνος.
    final placement = await askDepartmentMapPlacement(
      host,
      name: input.name,
      building: input.building,
      group: input.group,
      initial: ini,
      floorLabel: _floorLabelForSaveConfirmation,
    );
    if (placement.cancelled) return;

    // Ό,τι έχει μείνει πληκτρολογημένο χωρίς να γίνει chip μετράει κανονικά —
    // ο χρήστης δεν πρέπει να χάνει γραμμένο αναγνωριστικό επειδή πάτησε
    // «Αποθήκευση» χωρίς να πατήσει πρώτα Enter.
    host.commitLansweeperAccountInput();

    final model = buildDepartmentModelToSave(
      host,
      name: input.name,
      building: input.building,
      group: input.group,
      color: input.color,
      notes: input.notes,
      initial: ini,
      placement: placement,
    );

    try {
      final shared = host.isEdit
          ? await _saveEdit(model, input, placement)
          : await _saveNew(model, input);
      if (shared == null || !host.mounted) return;
      final saveMessage = _confirmationMessage(model, input.name, shared);
      host.widget.onSaved?.call();
      host.closeForm(true);
      showSaveConfirmationSnackBar(host.context, saveMessage);
    } on DepartmentExistsException catch (e) {
      await handleDepartmentNameConflict(
        host,
        e,
        name: input.name,
        building: input.building,
        color: input.color,
        notes: input.notes,
      );
    } on StateError catch (e) {
      if (!host.mounted) return;
      ScaffoldMessenger.of(
        host.context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e, st) {
      if (!host.mounted) return;
      showDatabasePersistenceErrorSnackBar(host.context, e, st);
    }
  }

  /// Οι τιμές της φόρμας, καθαρισμένες· `null` όταν λείπει όνομα.
  _DepartmentFormInput? _readForm() {
    final name = host.nameController.text.trim();
    if (name.isEmpty) return null;
    final parsedHex = tryParseDepartmentHex(host.hexController.text.trim());
    return (
      name: name,
      building: host.buildingController.text.trim(),
      group: host.groupController.text.trim(),
      color: colorToDepartmentHex(parsedHex ?? host.selectedColor),
      notes: host.notesController.text.trim(),
      shared: (
        phones: _cleanSorted(host.sharedPhones),
        // Το Είδος αποφασίζει τι επιτρέπεται να κρατά η καρτέλα, και η φόρμα
        // κρύβει την ενότητα όταν δεν επιτρέπεται. Ό,τι κρύβεται ΔΕΝ
        // γράφεται: αλλιώς η εταιρεία έμενε σιωπηλά χρεωμένη με μηχανήματα
        // που κανείς δεν βλέπει πια.
        //
        // Το άδειασμα περνά από την ίδια πύλη με κάθε άλλη αφαίρεση
        // κοινόχρηστου (`applySharedOnlyRemovalConfirmations`): ο χρήστης
        // ρωτιέται πού πάει κάθε μηχάνημα, με τις ίδιες λέξεις που ήδη ξέρει,
        // και χωρίς επιλογή «μένει εδώ» — ο εξοπλισμός δεν μένει ποτέ ορφανός.
        equipment: host.selectedKind.canOwnEquipment
            ? _cleanSorted(host.sharedEquipmentCodes)
            : <String>[],
      ),
    );
  }

  static List<String> _cleanSorted(Iterable<String> values) =>
      values.map((v) => v.trim()).where((v) => v.isNotEmpty).toSet().toList()
        ..sort((a, b) => a.compareTo(b));

  /// Επεξεργασία υπάρχοντος τμήματος. Επιστρέφει τα κοινόχρηστα όπως
  /// γράφτηκαν, ή `null` αν η αποθήκευση σταμάτησε (ακύρωση ή διένεξη).
  ///
  /// Σειρά: **όλες** οι ερωτήσεις → η καρτέλα (με την ερώτηση διένεξης) →
  /// τα κοινόχρηστα. Η διένεξη ρωτιέται πριν γραφτεί οτιδήποτε: «Ακύρωσε
  /// την αλλαγή μου» αφήνει ανέγγιχτα και τα κοινόχρηστα, όπως υπόσχεται
  /// το μήνυμα.
  Future<_SharedAssets?> _saveEdit(
    DepartmentModel model,
    _DepartmentFormInput input,
    DepartmentMapPlacementDecision placement,
  ) async {
    final did = model.id;
    final sharedPlan = did == null
        ? null
        : await _askEditShared(did, input.name, input.shared);
    if (did != null && sharedPlan == null) return null;

    // Η καρτέλα γράφεται ολόκληρη: αν κάποιος πρόλαβε, ρωτιέται ο άνθρωπος.
    if (!host.mounted) return null;
    final ini = host.widget.initialDepartment;
    final saved = await saveDirectoryRecordWithConflictPrompt(
      host.context,
      save: ({required force}) => host.widget.notifier.updateDepartment(
        model,
        expected: force ? null : ini,
        force: force,
        clearBuildingMapPlacement: placement.clearPlacement,
      ),
    );
    if (!host.mounted) return null;
    if (!saved) {
      showDirectorySaveCancelledSnackBar(host.context);
      return null;
    }
    await sharedPlan?.write();
    _moveFloorColor(placement);
    return sharedPlan?.shared ?? input.shared;
  }

  /// Οι τρεις ερωτήσεις των κοινόχρηστων της επεξεργασίας, με σειρά —
  /// **χωρίς** καμία εγγραφή. Επιστρέφει τι θα γραφτεί και την εγγραφή που
  /// το κάνει· `null` = ακύρωση σε κάποια ερώτηση.
  Future<({_SharedAssets shared, Future<void> Function() write})?>
  _askEditShared(int departmentId, String name, _SharedAssets requested) async {
    // 1. Τηλέφωνα/εξοπλισμός που χρησιμοποιεί και άλλος.
    final resolved = await host.sharedLinks.resolveCrossUsageConflicts(
      departmentId,
      name,
      requested.phones,
      requested.equipment,
    );
    if (resolved == null || !host.mounted) return null;

    // 2. Πού πάει ό,τι αφαιρείται από τα κοινόχρηστα.
    final confirmed = await host.sharedLinks
        .applySharedOnlyRemovalConfirmations(
          departmentId: departmentId,
          departmentName: name,
          sharedPhones: resolved.acceptedPhones,
          sharedEquipmentCodes: resolved.acceptedEquipmentCodes,
        );
    if (confirmed == null || !host.mounted) return null;

    // 3. Το ίδιο ερώτημα και για τον εξοπλισμό που κρατούν οι ΥΠΑΛΛΗΛΟΙ του
    // τμήματος: εκεί το μηχάνημα δεν είναι κοινόχρηστο, είναι χρεωμένο σε
    // πρόσωπο — και μια εταιρεία δεν κρατά δικά μας μηχανήματα ούτε έτσι.
    // (Στη δημιουργία δεν χρειάζεται: το καινούριο τμήμα δεν έχει ακόμη
    // υπαλλήλους.)
    final canOwnEquipment = host.selectedKind.canOwnEquipment;
    final personal = canOwnEquipment
        ? null
        : await host.sharedLinks.applyKindForbiddenEquipmentRemoval(
            departmentId: departmentId,
            departmentName: name,
          );
    if (!canOwnEquipment && (personal == null || !host.mounted)) return null;

    Future<void> write() => host.widget.notifier.updateDepartmentSharedAssets(
      departmentId,
      sharedPhones: confirmed.sharedPhones,
      sharedEquipmentCodes: confirmed.sharedEquipmentCodes,
      phonesToMoveFromUsers: resolved.phonesToMoveFromUsers,
      equipmentToMoveFromUsers: resolved.equipmentToMoveFromUsers,
      phoneTransfers: confirmed.phoneTransfers,
      equipmentTransfers: {
        ...confirmed.equipmentTransfers,
        if (personal != null) ...personal.equipmentTransfers,
      },
      phonesToSoftDelete: confirmed.phonesToDelete,
      equipmentToSoftDelete: [
        ...confirmed.equipmentToDelete,
        if (personal != null) ...personal.equipmentToDelete,
      ],
      equipmentOwnersToUnlink: personal?.equipmentOwnersToUnlink ?? const {},
    );
    return (
      shared: (
        phones: confirmed.sharedPhones,
        equipment: confirmed.sharedEquipmentCodes,
      ),
      write: write,
    );
  }

  /// Το χρώμα ακολουθεί τη σχεδίαση. Είτε σβήνει είτε μετακομίζει,
  /// ελευθερώνεται από τον παλιό όροφο — και στη μεταφορά δηλώνεται στον
  /// νέο, αλλιώς δύο τμήματα της ίδιας κάτοψης θα έπαιρναν το ίδιο.
  void _moveFloorColor(DepartmentMapPlacementDecision placement) {
    final ini = host.widget.initialDepartment;
    final leavesOldFloor =
        placement.clearPlacement || placement.movesPlacementToNewFloor;
    if (!leavesOldFloor || ini?.id == null) return;
    final hex = tryParseDepartmentHex(ini!.color);
    if (hex == null) return;
    final oldFloorId = placement.placementFloorId;
    if (oldFloorId != null) {
      FloorColorAssignmentService.instance.removeColorFromFloor(
        oldFloorId,
        hex,
      );
    }
    final newFloorId = placement.effectiveFloorId;
    if (placement.movesPlacementToNewFloor && newFloorId != null) {
      FloorColorAssignmentService.instance.overrideColor(newFloorId, hex);
    }
  }

  /// Δημιουργία νέου τμήματος. Επιστρέφει τα κοινόχρηστα όπως γράφτηκαν, ή
  /// `null` αν η αποθήκευση σταμάτησε.
  Future<_SharedAssets?> _saveNew(
    DepartmentModel model,
    _DepartmentFormInput input,
  ) async {
    final resolved = await host.sharedLinks.resolveCrossUsageConflicts(
      null,
      input.name,
      input.shared.phones,
      input.shared.equipment,
    );
    if (resolved == null) return null;
    // Το ίδιο ακριβώς μοντέλο που χτίστηκε από τη φόρμα — ΟΧΙ αντίγραφο
    // πεδίο-πεδίο. Το χειροκίνητο αντίγραφο ξεχνούσε ό,τι προστίθετο
    // αργότερα: τα αναγνωριστικά Lansweeper χάνονταν σιωπηλά σε κάθε νέο
    // τμήμα, και το είδος θα χανόταν με τον ίδιο τρόπο. Στη δημιουργία το
    // `model` έχει ήδη `id: null` και `isDeleted: false`.
    await host.widget.notifier.addDepartment(model);
    final db = await DatabaseHelper.instance.database;
    final did = await DepartmentRepository(
      db,
    ).getOrCreateDepartmentIdByName(input.name);
    if (did == null) {
      return (
        phones: resolved.acceptedPhones,
        equipment: resolved.acceptedEquipmentCodes,
      );
    }
    if (!host.mounted) return null;
    final confirmed = await host.sharedLinks
        .applySharedOnlyRemovalConfirmations(
          departmentId: did,
          departmentName: input.name,
          sharedPhones: resolved.acceptedPhones,
          sharedEquipmentCodes: resolved.acceptedEquipmentCodes,
        );
    if (confirmed == null || !host.mounted) return null;

    await host.widget.notifier.updateDepartmentSharedAssets(
      did,
      sharedPhones: confirmed.sharedPhones,
      sharedEquipmentCodes: confirmed.sharedEquipmentCodes,
      phonesToMoveFromUsers: resolved.phonesToMoveFromUsers,
      equipmentToMoveFromUsers: resolved.equipmentToMoveFromUsers,
      phoneTransfers: confirmed.phoneTransfers,
      equipmentTransfers: confirmed.equipmentTransfers,
      phonesToSoftDelete: confirmed.phonesToDelete,
      equipmentToSoftDelete: confirmed.equipmentToDelete,
    );
    return (
      phones: confirmed.sharedPhones,
      equipment: confirmed.sharedEquipmentCodes,
    );
  }

  /// Το μήνυμα επιβεβαίωσης: τι άλλαξε (επεξεργασία) ή τι γράφτηκε
  /// (δημιουργία) — μαζί με τα κοινόχρηστα.
  String _confirmationMessage(
    DepartmentModel model,
    String name,
    _SharedAssets shared,
  ) {
    final ini = host.widget.initialDepartment;
    final isNew = !host.isEdit;
    return buildSaveConfirmationMessage(
      entityType: AuditEntityTypes.department,
      entityLabel: name,
      oldMap: isNew
          ? const {}
          : _departmentMapsForSaveConfirmation(
              ini!.toMap(),
              sharedPhones: host.snapSharedPhones,
              sharedEquipmentCodes: host.snapSharedEquipmentCodes,
            ),
      newMap: _departmentMapsForSaveConfirmation(
        model.toMap(),
        sharedPhones: shared.phones,
        sharedEquipmentCodes: shared.equipment,
      ),
      isNew: isNew,
    );
  }

  /// Τα κοινόχρηστα τηλέφωνα και ο εξοπλισμός δεν ζουν στον πίνακα
  /// `departments` — αποθηκεύονται χωριστά, οπότε λείπουν από το `toMap()` και
  /// ως τώρα ήταν αόρατα στην επιβεβαίωση. Μπαίνουν εδώ, ώστε η αποθήκευση να
  /// λέει και γι' αυτά τι άλλαξε.
  Map<String, dynamic> _departmentMapsForSaveConfirmation(
    Map<String, dynamic> source, {
    required List<String> sharedPhones,
    required List<String> sharedEquipmentCodes,
  }) {
    final map = Map<String, dynamic>.from(source);
    map['shared_phones'] = [...sharedPhones]..sort();
    map['shared_equipment_codes'] = [...sharedEquipmentCodes]..sort();
    if (map.containsKey('floor_id')) {
      final raw = map['floor_id'];
      final id = raw is int ? raw : int.tryParse('$raw');
      map['floor_id'] = _floorLabelForSaveConfirmation(id);
    }
    return map;
  }

  String? _floorLabelForSaveConfirmation(int? floorId) {
    if (floorId == null) return null;
    for (final f in host.floors) {
      if (f.id == floorId) {
        return buildingMapFloorDisplayLabel(f);
      }
    }
    return '$floorId';
  }
}

/// Τα κοινόχρηστα της καρτέλας: όπως ζητήθηκαν, ή όπως τελικά γράφτηκαν.
typedef _SharedAssets = ({List<String> phones, List<String> equipment});

/// Οι τιμές της φόρμας τμήματος τη στιγμή της «Αποθήκευσης».
typedef _DepartmentFormInput = ({
  String name,
  String building,
  String group,
  String color,
  String notes,
  _SharedAssets shared,
});
