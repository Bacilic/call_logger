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

  Future<void> save() async {
    if (!(host.formKey.currentState?.validate() ?? false)) return;
    final name = host.nameController.text.trim();
    if (name.isEmpty) return;

    final building = host.buildingController.text.trim();
    final group = host.groupController.text.trim();
    final parsedHex = tryParseDepartmentHex(host.hexController.text.trim());
    final color = colorToDepartmentHex(parsedHex ?? host.selectedColor);
    final notes = host.notesController.text.trim();
    var sharedPhones =
        host.sharedPhones
            .map((v) => v.trim())
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.compareTo(b));
    // Το Είδος αποφασίζει τι επιτρέπεται να κρατά η καρτέλα, και η φόρμα κρύβει
    // την ενότητα όταν δεν επιτρέπεται. Ό,τι κρύβεται ΔΕΝ γράφεται: αλλιώς η
    // εταιρεία έμενε σιωπηλά χρεωμένη με μηχανήματα που κανείς δεν βλέπει πια.
    //
    // Το άδειασμα περνά από την ίδια πύλη με κάθε άλλη αφαίρεση κοινόχρηστου
    // (`applySharedOnlyRemovalConfirmations`): ο χρήστης ρωτιέται πού πάει κάθε
    // μηχάνημα, με τις ίδιες λέξεις που ήδη ξέρει, και χωρίς επιλογή «μένει
    // εδώ» — ο εξοπλισμός δεν μένει ποτέ ορφανός.
    var sharedEquipmentCodes = host.selectedKind.canOwnEquipment
        ? (host.sharedEquipmentCodes
              .map((v) => v.trim())
              .where((v) => v.isNotEmpty)
              .toSet()
              .toList()
            ..sort((a, b) => a.compareTo(b)))
        : <String>[];
    var phonesToMoveFromUsers = <String>{};
    var equipmentToMoveFromUsers = <String>{};

    final ini = host.widget.initialDepartment;

    // Οι ερωτήσεις της κάτοψης προηγούνται κάθε εγγραφής: ό,τι κι αν απαντηθεί,
    // ως εδώ δεν έχει γραφτεί τίποτα και μια ακύρωση δεν αφήνει ίχνος.
    final placement = await askDepartmentMapPlacement(
      host,
      name: name,
      building: building,
      group: group,
      initial: ini,
      floorLabel: _floorLabelForSaveConfirmation,
    );
    if (placement.cancelled) return;

    final effectiveFloorId = placement.effectiveFloorId;
    final placementFloorId = placement.placementFloorId;
    final clearBuildingMapPlacement = placement.clearPlacement;
    final movesPlacementToNewFloor = placement.movesPlacementToNewFloor;

    // Ό,τι έχει μείνει πληκτρολογημένο χωρίς να γίνει chip μετράει κανονικά —
    // ο χρήστης δεν πρέπει να χάνει γραμμένο αναγνωριστικό επειδή πάτησε
    // «Αποθήκευση» χωρίς να πατήσει πρώτα Enter.
    host.commitLansweeperAccountInput();

    final model = buildDepartmentModelToSave(
      host,
      name: name,
      building: building,
      group: group,
      color: color,
      notes: notes,
      initial: ini,
      placement: placement,
    );

    try {
      if (host.isEdit) {
        final did = model.id;
        if (did != null) {
          final resolved = await host.sharedLinks.resolveCrossUsageConflicts(
            did,
            name,
            sharedPhones,
            sharedEquipmentCodes,
          );
          if (resolved == null) return;
          sharedPhones = resolved.acceptedPhones;
          sharedEquipmentCodes = resolved.acceptedEquipmentCodes;
          phonesToMoveFromUsers = resolved.phonesToMoveFromUsers;
          equipmentToMoveFromUsers = resolved.equipmentToMoveFromUsers;

          if (!host.mounted) return;
          final confirmed = await host.sharedLinks
              .applySharedOnlyRemovalConfirmations(
                departmentId: did,
                departmentName: name,
                sharedPhones: sharedPhones,
                sharedEquipmentCodes: sharedEquipmentCodes,
              );
          if (confirmed == null || !host.mounted) return;
          sharedPhones = confirmed.sharedPhones;
          sharedEquipmentCodes = confirmed.sharedEquipmentCodes;

          // Το ίδιο ερώτημα και για τον εξοπλισμό που κρατούν οι ΥΠΑΛΛΗΛΟΙ
          // του τμήματος: εκεί το μηχάνημα δεν είναι κοινόχρηστο, είναι
          // χρεωμένο σε πρόσωπο — και μια εταιρεία δεν κρατά δικά μας
          // μηχανήματα ούτε έτσι. (Στη δημιουργία δεν χρειάζεται: το καινούριο
          // τμήμα δεν έχει ακόμη υπαλλήλους.)
          final personal = host.selectedKind.canOwnEquipment
              ? null
              : await host.sharedLinks.applyKindForbiddenEquipmentRemoval(
                  departmentId: did,
                  departmentName: name,
                );
          if (!host.selectedKind.canOwnEquipment &&
              (personal == null || !host.mounted)) {
            return;
          }

          await host.widget.notifier.updateDepartmentSharedAssets(
            did,
            sharedPhones: sharedPhones,
            sharedEquipmentCodes: sharedEquipmentCodes,
            phonesToMoveFromUsers: phonesToMoveFromUsers,
            equipmentToMoveFromUsers: equipmentToMoveFromUsers,
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
            equipmentOwnersToUnlink:
                personal?.equipmentOwnersToUnlink ?? const {},
          );
        }
        // Η καρτέλα γράφεται ολόκληρη: αν κάποιος πρόλαβε, ρωτιέται ο άνθρωπος.
        if (!host.mounted) return;
        final saved = await saveDirectoryRecordWithConflictPrompt(
          host.context,
          save: ({required force}) => host.widget.notifier.updateDepartment(
            model,
            expected: force ? null : ini,
            force: force,
            clearBuildingMapPlacement: clearBuildingMapPlacement,
          ),
        );
        if (!host.mounted) return;
        if (!saved) {
          ScaffoldMessenger.of(host.context).showSnackBar(
            const SnackBar(
              content: Text(
                'Η αποθήκευση ακυρώθηκε — η καρτέλα κρατά τα στοιχεία του '
                'συναδέλφου. Κλείστε την και ανοίξτε την ξανά για να τα δείτε.',
              ),
            ),
          );
          return;
        }
        // Το χρώμα ακολουθεί τη σχεδίαση. Είτε σβήνει είτε μετακομίζει,
        // ελευθερώνεται από τον παλιό όροφο — και στη μεταφορά δηλώνεται στον
        // νέο, αλλιώς δύο τμήματα της ίδιας κάτοψης θα έπαιρναν το ίδιο.
        final placementLeavesOldFloor =
            clearBuildingMapPlacement || movesPlacementToNewFloor;
        if (placementLeavesOldFloor && ini?.id != null) {
          final hex = tryParseDepartmentHex(ini!.color);
          if (hex != null) {
            if (placementFloorId != null) {
              FloorColorAssignmentService.instance.removeColorFromFloor(
                placementFloorId,
                hex,
              );
            }
            if (movesPlacementToNewFloor && effectiveFloorId != null) {
              FloorColorAssignmentService.instance.overrideColor(
                effectiveFloorId,
                hex,
              );
            }
          }
        }
      } else {
        final resolved = await host.sharedLinks.resolveCrossUsageConflicts(
          null,
          name,
          sharedPhones,
          sharedEquipmentCodes,
        );
        if (resolved == null) return;
        sharedPhones = resolved.acceptedPhones;
        sharedEquipmentCodes = resolved.acceptedEquipmentCodes;
        phonesToMoveFromUsers = resolved.phonesToMoveFromUsers;
        equipmentToMoveFromUsers = resolved.equipmentToMoveFromUsers;
        // Το ίδιο ακριβώς μοντέλο που χτίστηκε από τη φόρμα — ΟΧΙ αντίγραφο
        // πεδίο-πεδίο. Το χειροκίνητο αντίγραφο ξεχνούσε ό,τι προστίθετο
        // αργότερα: τα αναγνωριστικά Lansweeper χάνονταν σιωπηλά σε κάθε νέο
        // τμήμα, και το είδος θα χανόταν με τον ίδιο τρόπο. Στη δημιουργία το
        // `model` έχει ήδη `id: null` και `isDeleted: false`.
        await host.widget.notifier.addDepartment(model);
        final dbDid = await DatabaseHelper.instance.database;
        final did = await DepartmentRepository(
          dbDid,
        ).getOrCreateDepartmentIdByName(name);
        if (did != null) {
          if (!host.mounted) return;
          final confirmed = await host.sharedLinks
              .applySharedOnlyRemovalConfirmations(
                departmentId: did,
                departmentName: name,
                sharedPhones: sharedPhones,
                sharedEquipmentCodes: sharedEquipmentCodes,
              );
          if (confirmed == null || !host.mounted) return;
          sharedPhones = confirmed.sharedPhones;
          sharedEquipmentCodes = confirmed.sharedEquipmentCodes;

          await host.widget.notifier.updateDepartmentSharedAssets(
            did,
            sharedPhones: sharedPhones,
            sharedEquipmentCodes: sharedEquipmentCodes,
            phonesToMoveFromUsers: phonesToMoveFromUsers,
            equipmentToMoveFromUsers: equipmentToMoveFromUsers,
            phoneTransfers: confirmed.phoneTransfers,
            equipmentTransfers: confirmed.equipmentTransfers,
            phonesToSoftDelete: confirmed.phonesToDelete,
            equipmentToSoftDelete: confirmed.equipmentToDelete,
          );
        }
      }
      if (!host.mounted) return;
      final saveMessage = host.isEdit
          ? buildSaveConfirmationMessage(
              entityType: AuditEntityTypes.department,
              entityLabel: name,
              oldMap: _departmentMapsForSaveConfirmation(
                ini!.toMap(),
                sharedPhones: host.snapSharedPhones,
                sharedEquipmentCodes: host.snapSharedEquipmentCodes,
              ),
              newMap: _departmentMapsForSaveConfirmation(
                model.toMap(),
                sharedPhones: sharedPhones,
                sharedEquipmentCodes: sharedEquipmentCodes,
              ),
              isNew: false,
            )
          : buildSaveConfirmationMessage(
              entityType: AuditEntityTypes.department,
              entityLabel: name,
              oldMap: const {},
              newMap: _departmentMapsForSaveConfirmation(
                model.toMap(),
                sharedPhones: sharedPhones,
                sharedEquipmentCodes: sharedEquipmentCodes,
              ),
              isNew: true,
            );
      host.widget.onSaved?.call();
      host.closeForm(true);
      showSaveConfirmationSnackBar(host.context, saveMessage);
    } on DepartmentExistsException catch (e) {
      await handleDepartmentNameConflict(
        host,
        e,
        name: name,
        building: building,
        color: color,
        notes: notes,
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
