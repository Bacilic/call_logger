import '../../../core/database/database_helper.dart';
import '../../../core/database/directory_repository.dart';
import '../../../core/database/old_database/lamp_issue_resolution_service.dart';
import '../../../core/utils/name_parser.dart';
import '../../../core/utils/phone_list_parser.dart';
import '../../../core/utils/search_text_normalizer.dart';
import '../../../core/utils/user_identity_normalizer.dart';

enum LampTransferTarget { equipment, owner, department }

class LampMigrationCandidate {
  const LampMigrationCandidate({
    required this.id,
    required this.label,
    required this.confidence,
    required this.isExact,
  });

  final int id;
  final String label;
  final int confidence;
  final bool isExact;
}

class LampMigrationDraft {
  const LampMigrationDraft({
    required this.target,
    required this.oldValues,
    required this.formValues,
    required this.newRecordFormValues,
    required this.candidateFormValues,
    required this.candidates,
    required this.selectedCandidateId,
    required this.updatesExistingRecord,
    this.hint,
  });

  final LampTransferTarget target;
  final Map<String, String> oldValues;
  final Map<String, String> formValues;
  final Map<String, String> newRecordFormValues;
  final Map<int, Map<String, String>> candidateFormValues;
  final List<LampMigrationCandidate> candidates;
  final int? selectedCandidateId;
  final bool updatesExistingRecord;
  final String? hint;
}

class LampMigrationSaveResult {
  const LampMigrationSaveResult({
    required this.id,
    required this.updated,
    required this.message,
  });

  final int id;
  final bool updated;
  final String message;
}

enum LampOwnerConflictKind { phone, equipment }

enum LampOwnerConflictAction { transferToSelectedOwner, keepWithoutAssignment }

class LampOwnerConflict {
  const LampOwnerConflict({
    required this.conflictId,
    required this.kind,
    required this.value,
    required this.currentOwners,
  });

  final String conflictId;
  final LampOwnerConflictKind kind;
  final String value;
  final List<String> currentOwners;
}

class LampOwnerConflictDecision {
  const LampOwnerConflictDecision({
    required this.conflictId,
    required this.action,
  });

  final String conflictId;
  final LampOwnerConflictAction action;
}

class LampMigrationService {
  LampMigrationService({LampIssueResolutionService? resolutionService})
    : _resolutionService = resolutionService ?? LampIssueResolutionService();

  final LampIssueResolutionService _resolutionService;

  Future<LampMigrationDraft> buildDraft({
    required LampTransferTarget target,
    required Map<String, Object?> sourceRow,
  }) async {
    return switch (target) {
      LampTransferTarget.department => _buildDepartmentDraft(sourceRow),
      LampTransferTarget.owner => _buildOwnerDraft(sourceRow),
      LampTransferTarget.equipment => _buildEquipmentDraft(sourceRow),
    };
  }

  Future<LampMigrationSaveResult> save({
    required LampTransferTarget target,
    required Map<String, String> formValues,
    required int? selectedCandidateId,
    List<LampOwnerConflictDecision>? ownerConflictDecisions,
  }) async {
    return switch (target) {
      LampTransferTarget.department => _saveDepartment(
        formValues: formValues,
        selectedCandidateId: selectedCandidateId,
      ),
      LampTransferTarget.owner => _saveOwner(
        formValues: formValues,
        selectedCandidateId: selectedCandidateId,
        ownerConflictDecisions: ownerConflictDecisions,
      ),
      LampTransferTarget.equipment => _saveEquipment(
        formValues: formValues,
        selectedCandidateId: selectedCandidateId,
      ),
    };
  }

  Future<List<LampOwnerConflict>> detectOwnerConflicts({
    required Map<String, String> formValues,
    required int? selectedCandidateId,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final phones = PhoneListParser.splitPhones(formValues['phones']);
    final equipmentCodes = _parseEquipmentCodes(formValues['equipment_codes']);
    final conflicts = <LampOwnerConflict>[];

    if (phones.isNotEmpty) {
      final rows = await db.rawQuery(
        '''
        SELECT
          p.number AS number,
          u.id AS user_id,
          u.first_name AS first_name,
          u.last_name AS last_name
        FROM phones p
        JOIN user_phones up ON up.phone_id = p.id
        JOIN users u ON u.id = up.user_id
        WHERE p.number IN (${List.filled(phones.length, '?').join(',')})
          AND COALESCE(u.is_deleted, 0) = 0
          AND (${selectedCandidateId == null ? '1 = 1' : 'u.id != ?'})
        ORDER BY p.number COLLATE NOCASE ASC
        ''',
        <Object?>[
          ...phones,
          ?selectedCandidateId,
        ],
      );
      final ownersByPhone = <String, Set<String>>{};
      for (final row in rows) {
        final number = row['number']?.toString().trim() ?? '';
        final owner = _fullName(
          _text(row['first_name']),
          _text(row['last_name']),
        );
        if (number.isEmpty || owner.isEmpty) continue;
        ownersByPhone.putIfAbsent(number, () => <String>{}).add(owner);
      }
      for (final entry in ownersByPhone.entries) {
        conflicts.add(
          LampOwnerConflict(
            conflictId: 'phone:${_norm(entry.key)}',
            kind: LampOwnerConflictKind.phone,
            value: entry.key,
            currentOwners: entry.value.toList(growable: false),
          ),
        );
      }
    }

    if (equipmentCodes.isNotEmpty) {
      final rows = await db.rawQuery(
        '''
        SELECT
          e.code_equipment AS code_equipment,
          u.id AS user_id,
          u.first_name AS first_name,
          u.last_name AS last_name
        FROM equipment e
        JOIN user_equipment ue ON ue.equipment_id = e.id
        JOIN users u ON u.id = ue.user_id
        WHERE e.code_equipment IN (${List.filled(equipmentCodes.length, '?').join(',')})
          AND COALESCE(e.is_deleted, 0) = 0
          AND COALESCE(u.is_deleted, 0) = 0
          AND (${selectedCandidateId == null ? '1 = 1' : 'u.id != ?'})
        ORDER BY e.code_equipment COLLATE NOCASE ASC, u.last_name COLLATE NOCASE ASC, u.first_name COLLATE NOCASE ASC
        ''',
        <Object?>[
          ...equipmentCodes,
          ?selectedCandidateId,
        ],
      );
      final ownersByCode = <String, Set<String>>{};
      for (final row in rows) {
        final code = row['code_equipment']?.toString().trim() ?? '';
        final owner = _fullName(
          _text(row['first_name']),
          _text(row['last_name']),
        );
        if (code.isEmpty || owner.isEmpty) continue;
        ownersByCode.putIfAbsent(code, () => <String>{}).add(owner);
      }
      for (final entry in ownersByCode.entries) {
        conflicts.add(
          LampOwnerConflict(
            conflictId: 'equipment:${_norm(entry.key)}',
            kind: LampOwnerConflictKind.equipment,
            value: entry.key,
            currentOwners: entry.value.toList(growable: false),
          ),
        );
      }
    }

    return conflicts;
  }

  Future<LampMigrationDraft> _buildDepartmentDraft(
    Map<String, Object?> sourceRow,
  ) async {
    final oldName = _firstText(
      sourceRow['office_name'],
      sourceRow['department_name'],
      sourceRow['office_original_text'],
    );
    final oldBuilding = _text(sourceRow['building']);
    final oldLevel = _text(sourceRow['level']);
    final oldPhones = _text(sourceRow['office_phones']);
    final oldEmail = _text(sourceRow['office_email']);

    final db = await DatabaseHelper.instance.database;
    final dir = DirectoryRepository(db);
    final departments = await dir.getDepartments();
    final active = departments
        .where((row) => (row['is_deleted'] as int?) != 1)
        .toList(growable: false);

    final candidates = _topCandidates(
      source: oldName,
      rows: active,
      idKey: 'id',
      labelBuilder: (row) => _text(row['name']),
    );
    final exact = candidates.where((c) => c.isExact).toList(growable: false);
    final selected = exact.length == 1 ? exact.first.id : null;

    return LampMigrationDraft(
      target: LampTransferTarget.department,
      oldValues: <String, String>{
        'Παλιό τμήμα': oldName,
        'Παλιό email': oldEmail,
        'Παλιό τηλέφωνο': oldPhones,
        'Παλιό κτίριο': oldBuilding,
        'Παλιός όροφος': oldLevel,
      },
      formValues: <String, String>{
        'name': oldName,
        'building': oldBuilding,
        'level': oldLevel,
        'notes': '',
      },
      newRecordFormValues: <String, String>{
        'name': oldName,
        'building': oldBuilding,
        'level': oldLevel,
        'notes': '',
      },
      candidateFormValues: const <int, Map<String, String>>{},
      candidates: candidates,
      selectedCandidateId: selected,
      updatesExistingRecord: selected != null,
      hint: selected == null && oldName.isNotEmpty
          ? 'Παλιό τμήμα: $oldName'
          : null,
    );
  }

  Future<LampMigrationDraft> _buildOwnerDraft(
    Map<String, Object?> sourceRow,
  ) async {
    var oldLastName = _text(sourceRow['last_name']);
    var oldFirstName = _text(sourceRow['first_name']);
    final oldOwnerOriginalText = _text(sourceRow['owner_original_text']);
    if (oldFirstName.isEmpty &&
        oldLastName.isEmpty &&
        oldOwnerOriginalText.isNotEmpty) {
      final parsed = NameParserUtility.parse(oldOwnerOriginalText);
      oldFirstName = parsed.firstName.trim();
      oldLastName = parsed.lastName.trim();
    }
    final oldOwnerName = _firstText(
      _fullName(oldFirstName, oldLastName),
      oldOwnerOriginalText,
    );
    final oldPhones = _text(sourceRow['owner_phones']);
    final oldEmail = _text(sourceRow['owner_email']);
    final oldDepartment = _firstText(
      sourceRow['office_name'],
      sourceRow['department_name'],
      sourceRow['office_original_text'],
    );
    final oldEquipmentCodes = _firstText(
      sourceRow['code_equipment'],
      sourceRow['code'],
    );
    final db = await DatabaseHelper.instance.database;
    final dir = DirectoryRepository(db);
    final users = await dir.getAllUsers();
    final active = users
        .where((row) => (row['is_deleted'] as int?) != 1)
        .toList(growable: false);

    final sourceIdentity = UserIdentityNormalizer.identityKeyForPerson(
      oldFirstName,
      oldLastName,
    );
    final sourceIdentityCandidates = <String>{
      if (sourceIdentity.isNotEmpty) sourceIdentity,
      ..._identityCandidatesFromOwnerText(oldOwnerOriginalText),
    };
    final candidates = _topCandidates(
      source: oldOwnerName,
      rows: active,
      idKey: 'id',
      labelBuilder: (row) =>
          _fullName(_text(row['first_name']), _text(row['last_name'])),
    );
    final exactByIdentity = active
        .where((row) {
          final key = UserIdentityNormalizer.identityKeyForPerson(
            _text(row['first_name']),
            _text(row['last_name']),
          );
          return sourceIdentityCandidates.isNotEmpty &&
              sourceIdentityCandidates.contains(key);
        })
        .toList(growable: false);
    final selected = exactByIdentity.length == 1
        ? (exactByIdentity.first['id'] as int?)
        : null;
    final newRecordFormValues = <String, String>{
      'first_name': oldFirstName,
      'last_name': oldLastName,
      'phones': oldPhones,
      'equipment_codes': oldEquipmentCodes,
      'department_name': oldDepartment,
      'location': '',
      'notes': '',
    };
    final candidateFormValues = <int, Map<String, String>>{};
    String? selectedHint;
    if (selected != null) {
      final selectedUser = active.firstWhere(
        (row) => row['id'] == selected,
        orElse: () => const <String, Object?>{},
      );
      final selectedPhonesRaw = selectedUser['phones'];
      final selectedPhones = selectedPhonesRaw is List
          ? selectedPhonesRaw
                .map((v) => v.toString().trim())
                .where((v) => v.isNotEmpty)
                .toList(growable: false)
          : const <String>[];
      final linkedEquipmentRows = await db.rawQuery(
        '''
        SELECT e.code_equipment AS code
        FROM user_equipment ue
        JOIN equipment e ON e.id = ue.equipment_id
        WHERE ue.user_id = ? AND COALESCE(e.is_deleted, 0) = 0
        ORDER BY e.code_equipment COLLATE NOCASE ASC
        ''',
        <Object?>[selected],
      );
      final linkedEquipmentCodes = <String>[
        for (final row in linkedEquipmentRows)
          if ((row['code']?.toString().trim() ?? '').isNotEmpty)
            row['code'].toString().trim(),
      ];
      selectedHint =
          'Υπάρχων χρήστης: '
          '${selectedPhones.length} τηλέφωνα · '
          '${linkedEquipmentCodes.length} εξοπλισμοί στη νέα βάση.';
    }
    final userEquipmentRows = await db.rawQuery(
      '''
      SELECT
        ue.user_id AS user_id,
        e.code_equipment AS code
      FROM user_equipment ue
      JOIN equipment e ON e.id = ue.equipment_id
      WHERE COALESCE(e.is_deleted, 0) = 0
      ORDER BY ue.user_id ASC, e.code_equipment COLLATE NOCASE ASC
      ''',
    );
    final equipmentCodesByUserId = <int, List<String>>{};
    for (final row in userEquipmentRows) {
      final userId = row['user_id'] as int?;
      final code = row['code']?.toString().trim() ?? '';
      if (userId == null || code.isEmpty) continue;
      equipmentCodesByUserId.putIfAbsent(userId, () => <String>[]).add(code);
    }
    final departmentNameCache = <int, String>{};
    for (final row in active) {
      final id = row['id'] as int?;
      if (id == null) continue;
      final phonesRaw = row['phones'];
      final phonesCsv = phonesRaw is List
          ? phonesRaw
                .map((v) => v.toString().trim())
                .where((v) => v.isNotEmpty)
                .join(', ')
          : '';
      final linkedEquipmentCodesCsv = (equipmentCodesByUserId[id] ?? const <String>[])
          .join(', ');
      final departmentId = row['department_id'] as int?;
      var departmentName = '';
      if (departmentId != null) {
        departmentName = departmentNameCache.putIfAbsent(
          departmentId,
          () => '',
        );
        if (departmentName.isEmpty) {
          final fetched = await dir.getDepartmentNameById(departmentId);
          departmentName = fetched?.trim() ?? '';
          departmentNameCache[departmentId] = departmentName;
        }
      }
      candidateFormValues[id] = <String, String>{
        'first_name': _text(row['first_name']),
        'last_name': _text(row['last_name']),
        'phones': phonesCsv,
        'equipment_codes': linkedEquipmentCodesCsv,
        'department_name': departmentName,
        'location': _text(row['location']),
        'notes': _text(row['notes']),
      };
    }
    final formValues = selected == null
        ? Map<String, String>.from(newRecordFormValues)
        : Map<String, String>.from(
            candidateFormValues[selected] ?? newRecordFormValues,
          );
    return LampMigrationDraft(
      target: LampTransferTarget.owner,
      oldValues: <String, String>{
        'Παλιός κάτοχος': oldOwnerName,
        'Παλιό email': oldEmail,
        'Παλιά τηλέφωνα': oldPhones,
        'Παλιός εξοπλισμός': oldEquipmentCodes,
        'Παλιό τμήμα': oldDepartment,
      },
      formValues: formValues,
      newRecordFormValues: newRecordFormValues,
      candidateFormValues: candidateFormValues,
      candidates: candidates,
      selectedCandidateId: selected,
      updatesExistingRecord: selected != null,
      hint: selected != null
          ? selectedHint
          : oldDepartment.isNotEmpty
          ? 'Παλιό τμήμα: $oldDepartment'
          : null,
    );
  }

  Future<LampMigrationDraft> _buildEquipmentDraft(
    Map<String, Object?> sourceRow,
  ) async {
    final oldCode = _text(sourceRow['code']);
    final oldDescription = _text(sourceRow['description']);
    final oldDepartment = _firstText(
      sourceRow['office_name'],
      sourceRow['department_name'],
      sourceRow['office_original_text'],
    );
    final oldOwnerName = _fullName(
      _text(sourceRow['first_name']),
      _text(sourceRow['last_name']),
    );
    final oldNotes = _firstText(
      sourceRow['equipment_comments'],
      sourceRow['description'],
    );

    final db = await DatabaseHelper.instance.database;
    final dir = DirectoryRepository(db);
    final equipmentRows = await dir.getAllEquipment();
    final active = equipmentRows
        .where((row) => (row['is_deleted'] as int?) != 1)
        .toList(growable: false);
    final candidates = _topCandidates(
      source: oldCode,
      rows: active,
      idKey: 'id',
      labelBuilder: (row) => _text(row['code_equipment']),
    );
    final selected = active
        .where((row) => _norm(_text(row['code_equipment'])) == _norm(oldCode))
        .map((row) => row['id'] as int?)
        .whereType<int>()
        .toList(growable: false);
    final selectedId = selected.length == 1 ? selected.first : null;

    return LampMigrationDraft(
      target: LampTransferTarget.equipment,
      oldValues: <String, String>{
        'Παλιός κωδικός': oldCode,
        'Παλιά περιγραφή': oldDescription,
        'Παλιός κάτοχος': oldOwnerName,
        'Παλιό τμήμα': oldDepartment,
      },
      formValues: <String, String>{
        'code_equipment': oldCode,
        'type': oldDescription,
        'department_name': oldDepartment,
        'owner_name': oldOwnerName,
        'location': '',
        'notes': oldNotes,
      },
      newRecordFormValues: <String, String>{
        'code_equipment': oldCode,
        'type': oldDescription,
        'department_name': oldDepartment,
        'owner_name': oldOwnerName,
        'location': '',
        'notes': oldNotes,
      },
      candidateFormValues: const <int, Map<String, String>>{},
      candidates: candidates,
      selectedCandidateId: selectedId,
      updatesExistingRecord: selectedId != null,
      hint: selectedId == null && oldDepartment.isNotEmpty
          ? 'Παλιό τμήμα: $oldDepartment'
          : null,
    );
  }

  Future<LampMigrationSaveResult> _saveDepartment({
    required Map<String, String> formValues,
    required int? selectedCandidateId,
  }) async {
    final name = formValues['name']?.trim() ?? '';
    if (name.isEmpty) throw StateError('Το πεδίο τμήμα είναι υποχρεωτικό.');

    final map = <String, dynamic>{
      'name': name,
      'name_key': _norm(name),
      'building': _nullable(formValues['building']),
      'level': int.tryParse((formValues['level'] ?? '').trim()),
      'notes': _nullable(formValues['notes']),
      'map_hidden': 1,
      'is_deleted': 0,
    };
    final db = await DatabaseHelper.instance.database;
    final dir = DirectoryRepository(db);
    if (selectedCandidateId != null) {
      await dir.updateDepartment(selectedCandidateId, map);
      return LampMigrationSaveResult(
        id: selectedCandidateId,
        updated: true,
        message: 'Ενημερώθηκε υπάρχον τμήμα.',
      );
    }
    final id = await dir.insertDepartment(map);
    return LampMigrationSaveResult(
      id: id,
      updated: false,
      message: 'Δημιουργήθηκε νέο τμήμα.',
    );
  }

  Future<LampMigrationSaveResult> _saveOwner({
    required Map<String, String> formValues,
    required int? selectedCandidateId,
    List<LampOwnerConflictDecision>? ownerConflictDecisions,
  }) async {
    final firstName = (formValues['first_name'] ?? '').trim();
    final lastName = (formValues['last_name'] ?? '').trim();
    if (firstName.isEmpty && lastName.isEmpty) {
      throw StateError('Απαιτείται όνομα ή επώνυμο.');
    }
    final db = await DatabaseHelper.instance.database;
    final dir = DirectoryRepository(db);
    final departmentName = (formValues['department_name'] ?? '').trim();
    final departmentId = departmentName.isEmpty
        ? null
        : await dir.getOrCreateDepartmentIdByName(departmentName);
    final phones = PhoneListParser.splitPhones(formValues['phones']);
    final equipmentCodes = _parseEquipmentCodes(formValues['equipment_codes']);
    final conflicts = await detectOwnerConflicts(
      formValues: formValues,
      selectedCandidateId: selectedCandidateId,
    );
    final decisionsById = <String, LampOwnerConflictAction>{
      for (final decision in ownerConflictDecisions ?? const <LampOwnerConflictDecision>[])
        decision.conflictId: decision.action,
    };
    final unresolvedConflicts = conflicts
        .where((conflict) => !decisionsById.containsKey(conflict.conflictId))
        .toList(growable: false);
    if (unresolvedConflicts.isNotEmpty) {
      throw StateError('Απαιτείται επίλυση διενέξεων για τηλέφωνα/εξοπλισμό.');
    }

    final transferPhones = <String>{
      for (final conflict in conflicts)
        if (conflict.kind == LampOwnerConflictKind.phone &&
            decisionsById[conflict.conflictId] ==
                LampOwnerConflictAction.transferToSelectedOwner)
          conflict.value,
    };
    final skipPhones = <String>{
      for (final conflict in conflicts)
        if (conflict.kind == LampOwnerConflictKind.phone &&
            decisionsById[conflict.conflictId] ==
                LampOwnerConflictAction.keepWithoutAssignment)
          conflict.value,
    };
    final transferEquipmentCodes = <String>{
      for (final conflict in conflicts)
        if (conflict.kind == LampOwnerConflictKind.equipment &&
            decisionsById[conflict.conflictId] ==
                LampOwnerConflictAction.transferToSelectedOwner)
          conflict.value,
    };
    final skipEquipmentCodes = <String>{
      for (final conflict in conflicts)
        if (conflict.kind == LampOwnerConflictKind.equipment &&
            decisionsById[conflict.conflictId] ==
                LampOwnerConflictAction.keepWithoutAssignment)
          conflict.value,
    };

    for (final phone in transferPhones) {
      await dir.removePhoneFromAllUsers(phone);
    }
    for (final code in transferEquipmentCodes) {
      await dir.removeEquipmentFromAllUsers(code);
    }
    final resolvedPhones = <String>[
      for (final phone in phones)
        if (!skipPhones.contains(phone)) phone,
    ];
    final resolvedEquipmentCodes = <String>[
      for (final code in equipmentCodes)
        if (!skipEquipmentCodes.contains(code)) code,
    ];

    if (selectedCandidateId != null) {
      await dir.updateUser(selectedCandidateId, <String, dynamic>{
        'first_name': firstName,
        'last_name': lastName,
        'phones': resolvedPhones,
        'department_id': departmentId,
        'location': _nullable(formValues['location']),
        'notes': _nullable(formValues['notes']),
        'is_deleted': 0,
      });
      await _syncOwnerEquipmentLinks(
        userId: selectedCandidateId,
        equipmentCodes: resolvedEquipmentCodes,
      );
      return LampMigrationSaveResult(
        id: selectedCandidateId,
        updated: true,
        message: 'Ενημερώθηκε υπάρχων χρήστης.',
      );
    }
    final id = await dir.insertUser(
      firstName: firstName,
      lastName: lastName,
      phones: resolvedPhones,
      departmentId: departmentId,
      location: _nullable(formValues['location']),
      notes: _nullable(formValues['notes']),
    );
    await _syncOwnerEquipmentLinks(
      userId: id,
      equipmentCodes: resolvedEquipmentCodes,
    );
    return LampMigrationSaveResult(
      id: id,
      updated: false,
      message: 'Δημιουργήθηκε νέος χρήστης.',
    );
  }

  Future<void> _syncOwnerEquipmentLinks({
    required int userId,
    required List<String> equipmentCodes,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final dir = DirectoryRepository(db);
    final allEquipment = await dir.getAllEquipment();
    final desiredEquipmentIds = <int>{};
    for (final code in equipmentCodes) {
      final matched = allEquipment.firstWhere(
        (row) =>
            (row['is_deleted'] as int?) != 1 &&
            _norm(_text(row['code_equipment'])) == _norm(code),
        orElse: () => const <String, Object?>{},
      );
      final matchedId = matched['id'] as int?;
      if (matchedId != null) {
        desiredEquipmentIds.add(matchedId);
        continue;
      }
      final createdId = await dir.insertEquipmentFromMap(<String, dynamic>{
        'code_equipment': code.trim(),
        'is_deleted': 0,
      });
      desiredEquipmentIds.add(createdId);
    }
    final existingLinks = await db.query(
      'user_equipment',
      columns: <String>['equipment_id'],
      where: 'user_id = ?',
      whereArgs: <Object?>[userId],
    );
    final existingEquipmentIds = <int>{
      for (final row in existingLinks)
        if (row['equipment_id'] is int) row['equipment_id'] as int,
    };
    for (final equipmentId in existingEquipmentIds.difference(desiredEquipmentIds)) {
      await dir.unlinkUserFromEquipment(userId, equipmentId);
    }
    for (final equipmentId in desiredEquipmentIds.difference(existingEquipmentIds)) {
      await dir.linkUserToEquipment(userId, equipmentId);
    }
  }

  Future<LampMigrationSaveResult> _saveEquipment({
    required Map<String, String> formValues,
    required int? selectedCandidateId,
  }) async {
    final code = (formValues['code_equipment'] ?? '').trim();
    if (code.isEmpty) {
      throw StateError('Ο κωδικός εξοπλισμού είναι υποχρεωτικός.');
    }

    final db = await DatabaseHelper.instance.database;
    final dir = DirectoryRepository(db);
    final departmentName = (formValues['department_name'] ?? '').trim();
    final departmentId = departmentName.isEmpty
        ? null
        : await dir.getOrCreateDepartmentIdByName(departmentName);
    final ownerId = await _resolveOwnerId(formValues['owner_name']);
    final values = <String, dynamic>{
      'code_equipment': code,
      'type': _nullable(formValues['type']),
      'notes': _nullable(formValues['notes']),
      'department_id': departmentId,
      'location': _nullable(formValues['location']),
      'is_deleted': 0,
    };

    if (selectedCandidateId != null) {
      await dir.updateEquipment(selectedCandidateId, values);
      await dir.replaceEquipmentUsers(
        selectedCandidateId,
        ownerId == null ? const <int>[] : <int>[ownerId],
      );
      return LampMigrationSaveResult(
        id: selectedCandidateId,
        updated: true,
        message: 'Ενημερώθηκε υπάρχων εξοπλισμός.',
      );
    }
    final id = await dir.insertEquipmentFromMap(values);
    await dir.replaceEquipmentUsers(
      id,
      ownerId == null ? const <int>[] : <int>[ownerId],
    );
    return LampMigrationSaveResult(
      id: id,
      updated: false,
      message: 'Δημιουργήθηκε νέος εξοπλισμός.',
    );
  }

  Future<int?> _resolveOwnerId(String? ownerName) async {
    final text = ownerName?.trim() ?? '';
    if (text.isEmpty) return null;
    final parsed = NameParserUtility.parse(text);
    final target = UserIdentityNormalizer.identityKeyForPerson(
      parsed.firstName,
      parsed.lastName,
    );
    final db = await DatabaseHelper.instance.database;
    final dir = DirectoryRepository(db);
    final users = await dir.getAllUsers();
    for (final row in users) {
      if ((row['is_deleted'] as int?) == 1) continue;
      final key = UserIdentityNormalizer.identityKeyForPerson(
        _text(row['first_name']),
        _text(row['last_name']),
      );
      if (target.isNotEmpty && key == target) {
        return row['id'] as int?;
      }
    }
    return dir.insertUser(
      firstName: parsed.firstName,
      lastName: parsed.lastName,
    );
  }

  List<LampMigrationCandidate> _topCandidates({
    required String source,
    required List<Map<String, dynamic>> rows,
    required String idKey,
    required String Function(Map<String, dynamic> row) labelBuilder,
  }) {
    final normalizedSource = _norm(source);
    if (normalizedSource.isEmpty) return const <LampMigrationCandidate>[];
    final scored = <LampMigrationCandidate>[];
    for (final row in rows) {
      final id = row[idKey] as int?;
      final label = labelBuilder(row);
      if (id == null || label.isEmpty) continue;
      final confidence = _resolutionService.similarityConfidenceScore(
        source,
        label,
      );
      scored.add(
        LampMigrationCandidate(
          id: id,
          label: label,
          confidence: confidence,
          isExact: _norm(label) == normalizedSource,
        ),
      );
    }
    scored.sort((a, b) {
      final byConfidence = b.confidence.compareTo(a.confidence);
      if (byConfidence != 0) return byConfidence;
      return a.label.compareTo(b.label);
    });
    return scored.take(3).toList(growable: false);
  }

  String? _nullable(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  String _fullName(String firstName, String lastName) {
    return '$firstName $lastName'.trim();
  }

  String _firstText(Object? first, [Object? second, Object? third]) {
    final a = _text(first);
    if (a.isNotEmpty) return a;
    final b = _text(second);
    if (b.isNotEmpty) return b;
    return _text(third);
  }

  String _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? '' : text;
  }

  String _norm(String value) => SearchTextNormalizer.normalizeForSearch(value);

  List<String> _parseEquipmentCodes(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return const <String>[];
    final tokens = text
        .split(RegExp(r'[,\n;]+'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList(growable: false);
    final seen = <String>{};
    final normalizedUnique = <String>[];
    for (final token in tokens) {
      final key = _norm(token);
      if (key.isEmpty || seen.contains(key)) continue;
      seen.add(key);
      normalizedUnique.add(token);
    }
    return normalizedUnique;
  }

  Set<String> _identityCandidatesFromOwnerText(String ownerText) {
    final text = ownerText.trim();
    if (text.isEmpty) return const <String>{};
    final parsed = text
        .split(RegExp(r'\s+'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList(growable: false);
    if (parsed.isEmpty) return const <String>{};
    if (parsed.length == 1) {
      final single = UserIdentityNormalizer.identityKeyForPerson(
        parsed.first,
        '',
      );
      return single.isEmpty ? const <String>{} : <String>{single};
    }
    final candidates = <String>{
      UserIdentityNormalizer.identityKeyForPerson(
        parsed.first,
        parsed.sublist(1).join(' '),
      ),
      UserIdentityNormalizer.identityKeyForPerson(
        parsed.last,
        parsed.sublist(0, parsed.length - 1).join(' '),
      ),
    }..removeWhere((key) => key.isEmpty);
    return candidates;
  }

}
