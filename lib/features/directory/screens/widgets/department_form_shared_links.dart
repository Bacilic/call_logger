part of 'department_form_dialog.dart';

enum _ConflictResolutionChoice { moveToDepartment, keepCurrentOwnership }

class _SharedConflictItem {
  _SharedConflictItem({
    required this.key,
    required this.value,
    required this.isPhone,
    required this.ownerDetails,
    required this.sourceForMoveText,
    required this.sourceIsPersonal,
  });

  final String key;
  final String value;
  final bool isPhone;
  final String ownerDetails;
  final String sourceForMoveText;

  /// True όταν το [sourceForMoveText] είναι κάτοχος (όνομα + τμήμα), όχι άλλο τμήμα.
  final bool sourceIsPersonal;
}

const TextStyle _kSharedConflictEmphasisStyle = TextStyle(
  fontWeight: FontWeight.bold,
);

Widget _sharedConflictMoveLabel(
  _SharedConflictItem item,
  String targetDepartmentName,
) {
  final removePronoun = item.isPhone ? 'το' : 'τον';
  return Text.rich(
    TextSpan(
      children: [
        TextSpan(text: 'Κάνε $removePronoun '),
        const TextSpan(
          text: 'κοινόχρηστο',
          style: _kSharedConflictEmphasisStyle,
        ),
        TextSpan(text: ' της «$targetDepartmentName» '),
        TextSpan(
          text:
              '(αφαίρεσέ $removePronoun από «${item.sourceForMoveText}»)',
        ),
      ],
    ),
  );
}

Widget _sharedConflictKeepLabel(_SharedConflictItem item) {
  if (item.sourceIsPersonal) {
    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: 'Κράτα το '),
          const TextSpan(
            text: 'προσωπικό',
            style: _kSharedConflictEmphasisStyle,
          ),
          TextSpan(text: ' του «${item.sourceForMoveText}» (μην το καταχωρήσεις ως '),
          const TextSpan(
            text: 'κοινόχρηστο',
            style: _kSharedConflictEmphasisStyle,
          ),
          const TextSpan(text: ' τμήματος)'),
        ],
      ),
    );
  }
  return Text.rich(
    TextSpan(
      children: [
        const TextSpan(text: 'Μην το καταχωρήσεις ως '),
        const TextSpan(
          text: 'κοινόχρηστο',
          style: _kSharedConflictEmphasisStyle,
        ),
        TextSpan(text: ' τμήματος (παραμονή στο «${item.sourceForMoveText}»)'),
      ],
    ),
  );
}

mixin DepartmentFormSharedLinksMixin on DepartmentFormDialogStateHost {
  void _onSharedPhoneFocusChanged() {
    if (!_sharedPhoneInputFocus.hasFocus) {
      _commitDelimitedInput(
        controller: _sharedPhoneInputController,
        target: _sharedPhones,
        keepLastIncomplete: false,
      );
    }
  }

  void _onSharedEquipmentFocusChanged() {
    if (!_sharedEquipmentInputFocus.hasFocus) {
      _commitDelimitedInput(
        controller: _sharedEquipmentInputController,
        target: _sharedEquipmentCodes,
        keepLastIncomplete: false,
      );
    }
  }

  void _commitDelimitedInput({
    required TextEditingController controller,
    required List<String> target,
    required bool keepLastIncomplete,
  }) {
    if (_isNormalizingDelimitedInput) return;
    final raw = controller.text;
    if (raw.trim().isEmpty) return;
    final hasDelimiter = raw.contains(',') || raw.contains(RegExp(r'\s'));
    if (!hasDelimiter && keepLastIncomplete) return;

    final endsWithDelimiter = RegExp(r'[,\s]$').hasMatch(raw);
    final pieces = raw
        .split(RegExp(r'[,\s]+'))
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toList();
    if (pieces.isEmpty) return;

    final commitCount = (!keepLastIncomplete || endsWithDelimiter)
        ? pieces.length
        : pieces.length - 1;
    if (commitCount <= 0) return;
    final toCommit = pieces.take(commitCount);
    final remainder = (keepLastIncomplete && !endsWithDelimiter)
        ? pieces.last
        : '';

    _isNormalizingDelimitedInput = true;
    setState(() {
      final set = target.toSet()..addAll(toCommit);
      target
        ..clear()
        ..addAll(set.toList()..sort((a, b) => a.compareTo(b)));
      controller.text = remainder;
      controller.selection = TextSelection.collapsed(offset: remainder.length);
    });
    _isNormalizingDelimitedInput = false;
  }

  List<String> _splitCommaSeparated(String raw) {
    return raw
        .split(',')
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toList();
  }

  @override
  Future<
    ({
      List<String> acceptedPhones,
      List<String> acceptedEquipmentCodes,
      Set<String> phonesToMoveFromUsers,
      Set<String> equipmentToMoveFromUsers,
    })?
  >
  _resolveCrossUsageConflicts(
    int? departmentId,
    String targetDepartmentName,
    List<String> sharedPhones,
    List<String> sharedEquipmentCodes,
  ) async {
    final lookup = LookupService.instance;
    final conflicts = <_SharedConflictItem>[];

    for (final phone in sharedPhones) {
      final usage = lookup.checkPhoneUsage(phone);
      final hasDeptConflict =
          usage.departmentId != null &&
          (departmentId == null || usage.departmentId != departmentId);
      if (usage.hasUserOwners || hasDeptConflict) {
        final owners = lookup.findUsersByPhone(phone);
        final ownerLabels =
            owners
                .map((u) {
                  final full = (u.name ?? '').trim();
                  if (full.isEmpty) return '';
                  final dep = (u.departmentName ?? '').trim();
                  if (dep.isEmpty) return full;
                  return '$full ($dep)';
                })
                .where((v) => v.isNotEmpty)
                .toSet()
                .toList()
              ..sort((a, b) => a.compareTo(b));
        final detailsParts = <String>[];
        if (ownerLabels.isNotEmpty) {
          detailsParts.add('Ονοματεπώνυμο: ${ownerLabels.join(', ')}');
        }
        if (hasDeptConflict) {
          detailsParts.add(
            'Τμήμα: ${usage.departmentName ?? usage.departmentId}',
          );
        }
        final source = hasDeptConflict
            ? (usage.departmentName ?? '${usage.departmentId}')
            : (ownerLabels.isNotEmpty
                  ? ownerLabels.join(', ')
                  : 'άλλη συσχέτιση');
        conflicts.add(
          _SharedConflictItem(
            key: 'phone::$phone',
            value: phone,
            isPhone: true,
            ownerDetails: detailsParts.join(' | '),
            sourceForMoveText: source,
            sourceIsPersonal: !hasDeptConflict && ownerLabels.isNotEmpty,
          ),
        );
      }
    }
    for (final code in sharedEquipmentCodes) {
      final usage = lookup.checkEquipmentUsage(code);
      final hasDeptConflict =
          usage.departmentId != null &&
          (departmentId == null || usage.departmentId != departmentId);
      if (usage.hasUserOwners || hasDeptConflict) {
        final ownerLabels = <String>{};
        final matches = lookup.findEquipmentsByCode(code);
        for (final e in matches) {
          if ((e.code ?? '').trim() != code) continue;
          final eid = e.id;
          if (eid == null) continue;
          for (final u in lookup.findUsersForEquipment(eid)) {
            final full = (u.name ?? '').trim();
            if (full.isEmpty) continue;
            final dep = (u.departmentName ?? '').trim();
            ownerLabels.add(dep.isEmpty ? full : '$full ($dep)');
          }
        }
        final ownerList = ownerLabels.toList()..sort((a, b) => a.compareTo(b));
        final detailsParts = <String>[];
        if (ownerList.isNotEmpty) {
          detailsParts.add('Ονοματεπώνυμο: ${ownerList.join(', ')}');
        }
        if (hasDeptConflict) {
          detailsParts.add(
            'Τμήμα: ${usage.departmentName ?? usage.departmentId}',
          );
        }
        final source = hasDeptConflict
            ? (usage.departmentName ?? '${usage.departmentId}')
            : (ownerList.isNotEmpty ? ownerList.join(', ') : 'άλλη συσχέτιση');
        conflicts.add(
          _SharedConflictItem(
            key: 'equipment::$code',
            value: code,
            isPhone: false,
            ownerDetails: detailsParts.join(' | '),
            sourceForMoveText: source,
            sourceIsPersonal: !hasDeptConflict && ownerList.isNotEmpty,
          ),
        );
      }
    }
    if (conflicts.isEmpty) {
      return (
        acceptedPhones: sharedPhones,
        acceptedEquipmentCodes: sharedEquipmentCodes,
        phonesToMoveFromUsers: <String>{},
        equipmentToMoveFromUsers: <String>{},
      );
    }

    final decisions = <String, _ConflictResolutionChoice>{};
    final result = await showDialog<Map<String, _ConflictResolutionChoice>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final allResolved = decisions.length == conflicts.length;
          final desiredHeight = (conflicts.length * 132.0)
              .clamp(220.0, 520.0)
              .toDouble();
          return AlertDialog(
            title: const Text('Εκκρεμή τηλέφωνα / εξοπλισμοί'),
            content: SizedBox(
              width: 680,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: desiredHeight),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Για κάθε στοιχείο επίλεξε αν θα μεταφερθεί στο τμήμα ή αν θα παραμείνει στην τωρινή του συσχέτιση.',
                      ),
                      const SizedBox(height: 10),
                      for (final item in conflicts) ...[
                        Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${item.isPhone ? 'Τηλέφωνο' : 'Εξοπλισμός'}: ${item.value}',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 4),
                                Text(item.ownerDetails),
                                RadioGroup<_ConflictResolutionChoice>(
                                  groupValue: decisions[item.key],
                                  onChanged: (v) {
                                    if (v == null) return;
                                    setDialogState(() {
                                      decisions[item.key] = v;
                                    });
                                  },
                                  child: Column(
                                    children: [
                                      RadioListTile<_ConflictResolutionChoice>(
                                        dense: true,
                                        value: _ConflictResolutionChoice
                                            .moveToDepartment,
                                        title: _sharedConflictMoveLabel(
                                          item,
                                          targetDepartmentName,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      RadioListTile<_ConflictResolutionChoice>(
                                        dense: true,
                                        value: _ConflictResolutionChoice
                                            .keepCurrentOwnership,
                                        title: _sharedConflictKeepLabel(item),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: const Text('Άκυρο'),
              ),
              FilledButton(
                onPressed: allResolved
                    ? () => Navigator.of(ctx).pop(
                        Map<String, _ConflictResolutionChoice>.from(decisions),
                      )
                    : null,
                child: const Text('Επιβεβαίωση'),
              ),
            ],
          );
        },
      ),
    );

    if (result == null) return null;
    final conflictKeys = {for (final item in conflicts) item.key};
    final acceptedPhones = <String>[];
    final acceptedEquipment = <String>[];
    final phonesToMoveFromUsers = <String>{};
    final equipmentToMoveFromUsers = <String>{};
    for (final phone in sharedPhones) {
      final key = 'phone::$phone';
      if (!conflictKeys.contains(key)) {
        acceptedPhones.add(phone);
        continue;
      }
      final decision = result[key];
      if (decision == _ConflictResolutionChoice.moveToDepartment) {
        acceptedPhones.add(phone);
        phonesToMoveFromUsers.add(phone);
      }
    }
    for (final code in sharedEquipmentCodes) {
      final key = 'equipment::$code';
      if (!conflictKeys.contains(key)) {
        acceptedEquipment.add(code);
        continue;
      }
      final decision = result[key];
      if (decision == _ConflictResolutionChoice.moveToDepartment) {
        acceptedEquipment.add(code);
        equipmentToMoveFromUsers.add(code);
      }
    }
    return (
      acceptedPhones: acceptedPhones,
      acceptedEquipmentCodes: acceptedEquipment,
      phonesToMoveFromUsers: phonesToMoveFromUsers,
      equipmentToMoveFromUsers: equipmentToMoveFromUsers,
    );
  }

  @override
  Future<
    ({
      List<String> sharedPhones,
      List<String> sharedEquipmentCodes,
      Map<String, int> phoneTransfers,
      Map<String, int> equipmentTransfers,
      List<String> phonesToDelete,
      List<String> equipmentToDelete,
    })?
  >
  _applySharedOnlyRemovalConfirmations({
    required int departmentId,
    required String departmentName,
    required List<String> sharedPhones,
    required List<String> sharedEquipmentCodes,
  }) async {
    final lookup = LookupService.instance;
    var phones = List<String>.from(sharedPhones);
    var equipment = List<String>.from(sharedEquipmentCodes);

    final existingPhones =
        lookup.getDirectPhonesByDepartment(departmentId).toSet();
    final existingEq =
        lookup.getSharedEquipmentCodesByDepartment(departmentId).toSet();
    final sharedOnlyPhonesRemoved =
        existingPhones
            .difference(phones.toSet())
            .where((p) => !lookup.checkPhoneUsage(p).hasUserOwners)
            .toList()
          ..sort();
    final sharedOnlyEqRemoved =
        existingEq
            .difference(equipment.toSet())
            .where((c) => !lookup.checkEquipmentUsage(c).hasUserOwners)
            .toList()
          ..sort();

    if (sharedOnlyPhonesRemoved.isEmpty && sharedOnlyEqRemoved.isEmpty) {
      return (
        sharedPhones: phones,
        sharedEquipmentCodes: equipment,
        phoneTransfers: <String, int>{},
        equipmentTransfers: <String, int>{},
        phonesToDelete: <String>[],
        equipmentToDelete: <String>[],
      );
    }

    if (!mounted) return null;
    final batch = await showSharedAssetDisconnectFlow(
      context: context,
      sourceDepartmentId: departmentId,
      sourceDepartmentName: departmentName,
      phones: sharedOnlyPhonesRemoved,
      equipmentCodes: sharedOnlyEqRemoved,
      availableDepartments: lookup.departments,
    );
    if (!mounted || batch == null) return null;

    phones = (phones.toSet()..addAll(batch.phonesToKeep)).toList()..sort();
    equipment = (equipment.toSet()..addAll(batch.equipmentToKeep)).toList()
      ..sort();

    final db = await DatabaseHelper.instance.database;
    final dir = DepartmentRepository(db);
    final phoneTransfers = <String, int>{};
    final equipmentTransfers = <String, int>{};

    for (final newName in batch.newDepartmentNamesToCreate.keys) {
      final deptId = await dir.getOrCreateDepartmentIdByName(newName);
      if (deptId == null) continue;
      for (final entry in batch.phoneTransfers.entries) {
        if (entry.value.newDepartmentName?.trim() == newName.trim()) {
          phoneTransfers[entry.key] = deptId;
        }
      }
      for (final entry in batch.equipmentTransfers.entries) {
        if (entry.value.newDepartmentName?.trim() == newName.trim()) {
          equipmentTransfers[entry.key] = deptId;
        }
      }
    }
    for (final entry in batch.phoneTransfers.entries) {
      final id = entry.value.departmentId;
      if (id != null) phoneTransfers[entry.key] = id;
    }
    for (final entry in batch.equipmentTransfers.entries) {
      final id = entry.value.departmentId;
      if (id != null) equipmentTransfers[entry.key] = id;
    }

    if (batch.newDepartmentNamesToCreate.isNotEmpty) {
      LookupService.instance.resetForReload();
      await LookupService.instance.loadFromDatabase();
      await widget.notifier.loadDepartments();
    }

    return (
      sharedPhones: phones,
      sharedEquipmentCodes: equipment,
      phoneTransfers: phoneTransfers,
      equipmentTransfers: equipmentTransfers,
      phonesToDelete: batch.phonesToDelete,
      equipmentToDelete: batch.equipmentToDelete,
    );
  }

  void _addSharedPhonesFromInput(String raw) {
    final incoming = _splitCommaSeparated(raw);
    if (incoming.isEmpty) return;
    setState(() {
      final set = _sharedPhones.toSet();
      for (final v in incoming) {
        set.add(v);
      }
      _sharedPhones = set.toList()..sort((a, b) => a.compareTo(b));
      _sharedPhoneInputController.clear();
    });
  }

  void _addSharedEquipmentFromInput(String raw) {
    final incoming = _splitCommaSeparated(raw);
    if (incoming.isEmpty) return;
    setState(() {
      final set = _sharedEquipmentCodes.toSet();
      for (final v in incoming) {
        set.add(v);
      }
      _sharedEquipmentCodes = set.toList()..sort((a, b) => a.compareTo(b));
      _sharedEquipmentInputController.clear();
    });
  }
}
