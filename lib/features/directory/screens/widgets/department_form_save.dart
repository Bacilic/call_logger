part of 'department_form_dialog.dart';

mixin DepartmentFormSaveMixin on DepartmentFormDialogStateHost {
  @override
  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final building = _buildingController.text.trim();
    final parsedHex = tryParseDepartmentHex(_hexController.text.trim());
    final color = colorToDepartmentHex(parsedHex ?? _selectedColor);
    final notes = _notesController.text.trim();
    var sharedPhones =
        _sharedPhones
            .map((v) => v.trim())
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.compareTo(b));
    var sharedEquipmentCodes =
        _sharedEquipmentCodes
            .map((v) => v.trim())
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.compareTo(b));
    var phonesToMoveFromUsers = <String>{};
    var equipmentToMoveFromUsers = <String>{};

    final ini = widget.initialDepartment;
    final clearBuildingMapPlacement =
        _isEdit &&
        _selectedFloorId == null &&
        (_snapFloorId != null || ini?.floorId != null);

    final model = DepartmentModel(
      id: _isEdit ? ini?.id : null,
      name: name,
      building: building.isEmpty ? null : building,
      color: color,
      notes: notes.isEmpty ? null : notes,
      floorId: _selectedFloorId,
      groupName: ini?.groupName,
      mapFloor: _selectedFloorId != null
          ? _selectedFloorId!.toString()
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
    );

    try {
      if (_isEdit) {
        final did = model.id;
        if (did != null) {
          final resolved = await _resolveCrossUsageConflicts(
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

          if (!mounted) return;
          final confirmed = await _applySharedOnlyRemovalConfirmations(
            departmentId: did,
            departmentName: name,
            sharedPhones: sharedPhones,
            sharedEquipmentCodes: sharedEquipmentCodes,
          );
          if (confirmed == null || !mounted) return;
          sharedPhones = confirmed.sharedPhones;
          sharedEquipmentCodes = confirmed.sharedEquipmentCodes;

          await widget.notifier.updateDepartmentSharedAssets(
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
        await widget.notifier.updateDepartment(
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
        final resolved = await _resolveCrossUsageConflicts(
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
        await widget.notifier.addDepartment(
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
          if (!mounted) return;
          final confirmed = await _applySharedOnlyRemovalConfirmations(
            departmentId: did,
            departmentName: name,
            sharedPhones: sharedPhones,
            sharedEquipmentCodes: sharedEquipmentCodes,
          );
          if (confirmed == null || !mounted) return;
          sharedPhones = confirmed.sharedPhones;
          sharedEquipmentCodes = confirmed.sharedEquipmentCodes;

          await widget.notifier.updateDepartmentSharedAssets(
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
      if (!mounted) return;
      widget.onSaved?.call();
      Navigator.of(context).pop(true);
    } on DepartmentExistsException catch (e) {
      if (!mounted) return;
      if (e.isDeleted) {
        final restore = await showDialog<bool>(
          context: context,
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
        if (!mounted) return;
        if (restore == true) {
          try {
            await widget.notifier.restoreDepartmentByName(
              name,
              building: building.isEmpty ? null : building,
              color: color,
              notes: notes.isEmpty ? null : notes,
            );
            if (!mounted) return;
            widget.onSaved?.call();
            Navigator.of(context).pop(true);
          } catch (err, st) {
            if (!mounted) return;
            showDatabasePersistenceErrorSnackBar(context, err, st);
          }
        }
      } else {
        await showDialog<void>(
          context: context,
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
                    const TextSpan(
                      text: '. Δώστε νέο διακριτικό όνομα (π.χ. ',
                    ),
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
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e, st) {
      if (!mounted) return;
      showDatabasePersistenceErrorSnackBar(context, e, st);
    }
  }
}
