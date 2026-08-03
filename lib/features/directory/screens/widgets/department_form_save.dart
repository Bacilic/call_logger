import 'package:flutter/material.dart';

import '../../../../core/database/audit_service.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/database/department_repository.dart';
import '../../../../core/errors/department_exists_exception.dart';
import '../../../../core/services/save_confirmation_summary.dart';
import '../../../../core/widgets/audit_summary_rich_text.dart';
import '../../../../core/widgets/database_persistence_error_snackbar.dart';
import '../../building_map/services/building_map_floor_ordering.dart';
import '../../models/department_model.dart';
import '../../../floor_map/services/floor_color_assignment_service.dart';
import 'department_color_palette.dart';
import 'department_form_dialog.dart';

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
    var sharedEquipmentCodes =
        host.sharedEquipmentCodes
            .map((v) => v.trim())
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.compareTo(b));
    var phonesToMoveFromUsers = <String>{};
    var equipmentToMoveFromUsers = <String>{};

    final ini = host.widget.initialDepartment;
    final clearBuildingMapPlacement =
        host.isEdit &&
        host.selectedFloorId == null &&
        (host.snapFloorId != null || ini?.floorId != null);

    final model = DepartmentModel(
      id: host.isEdit ? ini?.id : null,
      name: name,
      building: building.isEmpty ? null : building,
      color: color,
      notes: notes.isEmpty ? null : notes,
      floorId: host.selectedFloorId,
      groupName: ini?.groupName,
      mapFloor: host.selectedFloorId != null
          ? host.selectedFloorId!.toString()
          : (clearBuildingMapPlacement ? null : ini?.mapFloor),
      mapX: clearBuildingMapPlacement ? null : ini?.mapX,
      mapY: clearBuildingMapPlacement ? null : ini?.mapY,
      mapWidth: clearBuildingMapPlacement ? null : ini?.mapWidth,
      mapHeight: clearBuildingMapPlacement ? null : ini?.mapHeight,
      mapRotation: clearBuildingMapPlacement ? 0.0 : (ini?.mapRotation ?? 0.0),
      mapLabelOffsetX: clearBuildingMapPlacement ? null : ini?.mapLabelOffsetX,
      mapLabelOffsetY: clearBuildingMapPlacement ? null : ini?.mapLabelOffsetY,
      mapAnchorOffsetX: clearBuildingMapPlacement
          ? null
          : ini?.mapAnchorOffsetX,
      mapAnchorOffsetY: clearBuildingMapPlacement
          ? null
          : ini?.mapAnchorOffsetY,
      mapCustomName: clearBuildingMapPlacement ? null : ini?.mapCustomName,
      directPhones: ini?.directPhones,
      isDeleted: ini?.isDeleted ?? false,
      isHiddenOnMap: ini?.isHiddenOnMap ?? false,
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
        await host.widget.notifier.updateDepartment(
          model,
          clearBuildingMapPlacement: clearBuildingMapPlacement,
        );
        if (clearBuildingMapPlacement && ini?.id != null) {
          final fid = int.tryParse(ini!.mapFloor?.trim() ?? '');
          final removedHex = tryParseDepartmentHex(ini.color);
          if (fid != null && removedHex != null) {
            FloorColorAssignmentService.instance.removeColorFromFloor(
              fid,
              removedHex,
            );
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
        await host.widget.notifier.addDepartment(
          DepartmentModel(
            id: null,
            name: name,
            building: model.building,
            color: model.color,
            notes: model.notes,
            floorId: model.floorId,
            groupName: model.groupName,
            mapFloor: model.mapFloor,
            mapX: model.mapX,
            mapY: model.mapY,
            mapWidth: model.mapWidth,
            mapHeight: model.mapHeight,
            mapRotation: model.mapRotation,
            mapLabelOffsetX: model.mapLabelOffsetX,
            mapLabelOffsetY: model.mapLabelOffsetY,
            mapAnchorOffsetX: model.mapAnchorOffsetX,
            mapAnchorOffsetY: model.mapAnchorOffsetY,
            mapCustomName: model.mapCustomName,
            isDeleted: false,
          ),
        );
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
              oldMap: _departmentMapsForSaveConfirmation(ini!.toMap()),
              newMap: _departmentMapsForSaveConfirmation(model.toMap()),
              isNew: false,
            )
          : buildSaveConfirmationMessage(
              entityType: AuditEntityTypes.department,
              entityLabel: name,
              oldMap: const {},
              newMap: _departmentMapsForSaveConfirmation(model.toMap()),
              isNew: true,
            );
      host.widget.onSaved?.call();
      Navigator.of(host.context).pop(true);
      showSaveConfirmationSnackBar(host.context, saveMessage);
    } on DepartmentExistsException catch (e) {
      if (!host.mounted) return;
      if (e.isDeleted) {
        final restore = await showDialog<bool>(
          context: host.context,
          builder: (ctx) => AlertDialog(
            title: const Text('Τμήμα ως διαγραμμένο'),
            content: const Text(
              'Υπάρχει ήδη καταχώρηση με αυτό το όνομα, σημειωμένη ως διαγραμμένη. '
              'Θέλετε να την επαναφέρετε;\n\n'
              'Τα πεδία κτίριο, χρώμα και σημειώσεις από τη φόρμα θα εφαρμοστούν μετά την επαναφορά. '
              'Αν δεν πρόκειται για το ίδιο τμήμα, πατήστε «Άκυρο» και δώστε νέο, διακριτό όνομα (π.χ. «Μαγειρείο 2026»).',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Άκυρο'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Επαναφορά'),
              ),
            ],
          ),
        );
        if (!host.mounted) return;
        if (restore == true) {
          try {
            await host.widget.notifier.restoreDepartmentByName(
              name,
              building: building.isEmpty ? null : building,
              color: color,
              notes: notes.isEmpty ? null : notes,
            );
            if (!host.mounted) return;
            host.widget.onSaved?.call();
            Navigator.of(host.context).pop(true);
            final restoreMessage = 'Επαναφέρθηκε το τμήμα «$name»';
            ScaffoldMessenger.of(host.context).showSnackBar(
              SnackBar(
                content: Text(restoreMessage),
                duration: saveConfirmationSnackBarDuration(restoreMessage),
              ),
            );
          } catch (err, st) {
            if (!host.mounted) return;
            showDatabasePersistenceErrorSnackBar(host.context, err, st);
          }
        }
      } else {
        await showDialog<void>(
          context: host.context,
          builder: (ctx) {
            final example = suggestDistinctDepartmentNameExample(name);
            final bodyStyle = Theme.of(ctx).textTheme.bodyMedium;
            return AlertDialog(
              title: const Text('Όνομα σε χρήση'),
              content: Text.rich(
                TextSpan(
                  style: bodyStyle,
                  children: [
                    const TextSpan(text: 'Υπάρχει ήδη τμήμα με το όνομα '),
                    TextSpan(
                      text: name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const TextSpan(text: '. Δώστε νέο διακριτικό όνομα (π.χ. '),
                    TextSpan(text: '«$example»'),
                    const TextSpan(text: ').'),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      }
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

  Map<String, dynamic> _departmentMapsForSaveConfirmation(
    Map<String, dynamic> source,
  ) {
    final map = Map<String, dynamic>.from(source);
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
