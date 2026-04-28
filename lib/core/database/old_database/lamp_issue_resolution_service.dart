import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../utils/search_text_normalizer.dart';
import 'lamp_database_provider.dart';

enum LampIssueType {
  nonNumericFk('non_numeric_fk', 'Επίλυση non-numeric FK'),
  unknownId('unknown_id', 'Επίλυση unknown ID'),
  duplicateAssetNo('duplicate_asset_no', 'Επίλυση διπλότυπων asset_no'),
  duplicateModelSerial(
    'duplicate_model_serial',
    'Επίλυση διπλοεγγραφών model/serial',
  ),
  ownerOfficeMismatch(
    'owner_office_mismatch',
    'Διόρθωση ασυμφωνίας ιδιοκτήτη-γραφείου',
  ),
  setMasterSelfReference(
    'set_master_self_reference',
    'Διόρθωση αυτοαναφορών set_master',
  ),
  setMasterCycle('set_master_cycle', 'Επίλυση κύκλων set_master');

  const LampIssueType(this.issueType, this.label);

  final String issueType;
  final String label;
}

enum LampIssueResolutionAction {
  autoFix('auto_fix'),
  manualReview('manual_review'),
  unresolved('unresolved'),
  createNew('create_new');

  const LampIssueResolutionAction(this.jsonValue);
  final String jsonValue;
}

class LampIssueResolutionOption {
  const LampIssueResolutionOption({
    required this.id,
    required this.label,
    required this.action,
    this.description,
    this.proposedId,
    this.proposedMatch,
    this.confidence,
    this.requiresTextInput = false,
    this.inputLabel,
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final String label;
  final LampIssueResolutionAction action;
  final String? description;
  final int? proposedId;
  final String? proposedMatch;
  final int? confidence;
  final bool requiresTextInput;
  final String? inputLabel;
  final Map<String, Object?> metadata;
}

class LampIssueResolutionProposal {
  const LampIssueResolutionProposal({
    required this.issueType,
    required this.issueIds,
    required this.sheet,
    required this.row,
    required this.column,
    required this.originalValue,
    required this.proposedAction,
    this.proposedId,
    this.proposedMatch,
    required this.confidence,
    this.options = const <LampIssueResolutionOption>[],
    required this.notes,
    this.metadata = const <String, Object?>{},
  });

  final LampIssueType issueType;
  final List<int> issueIds;
  final String? sheet;
  final int? row;
  final String? column;
  final String? originalValue;
  final LampIssueResolutionAction proposedAction;
  final int? proposedId;
  final String? proposedMatch;
  final int confidence;
  final List<LampIssueResolutionOption> options;
  final String notes;
  final Map<String, Object?> metadata;

  bool get canApplyAutomatically =>
      proposedAction == LampIssueResolutionAction.autoFix ||
      proposedAction == LampIssueResolutionAction.createNew;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'sheet': sheet,
      'row': row,
      'column': column,
      'original_value': originalValue,
      'proposed_action': proposedAction.jsonValue,
      'proposed_id': proposedId,
      'proposed_match': proposedMatch,
      'confidence': confidence,
      'options': <Map<String, Object?>>[
        for (final option in options)
          <String, Object?>{
            'id': option.id,
            'label': option.label,
            'proposed_id': option.proposedId,
            'proposed_match': option.proposedMatch,
          },
      ],
      'notes': notes,
    };
  }
}

class LampIssueResolutionDecision {
  const LampIssueResolutionDecision({
    required this.proposal,
    this.option,
    this.textInput,
  });

  final LampIssueResolutionProposal proposal;
  final LampIssueResolutionOption? option;
  final String? textInput;
}

class LampIssueResolutionApplyResult {
  const LampIssueResolutionApplyResult({
    required this.resolved,
    required this.manualApplied,
    required this.created,
    required this.unresolved,
    required this.errors,
  });

  final int resolved;
  final int manualApplied;
  final int created;
  final int unresolved;
  final List<String> errors;

  int get totalChanged => resolved + manualApplied + created;
}

class LampIssueResolutionService {
  LampIssueResolutionService({LampDatabaseProvider? databaseProvider})
    : _databaseProvider = databaseProvider ?? LampDatabaseProvider.instance;

  final LampDatabaseProvider _databaseProvider;

  Future<List<LampIssueResolutionProposal>> analyzeIssues({
    required String databasePath,
    required LampIssueType issueType,
  }) async {
    final db = await _databaseProvider.open(
      databasePath.trim(),
      mode: LampDatabaseMode.read,
    );
    return switch (issueType) {
      LampIssueType.nonNumericFk ||
      LampIssueType.unknownId => _analyzeFkIssues(db, issueType),
      LampIssueType.duplicateAssetNo => _analyzeDuplicateAssets(db),
      LampIssueType.duplicateModelSerial => _analyzeDuplicateModelSerial(db),
      LampIssueType.ownerOfficeMismatch => _analyzeOwnerOfficeMismatch(db),
      LampIssueType.setMasterSelfReference => _analyzeSetMasterSelfReferences(
        db,
      ),
      LampIssueType.setMasterCycle => _analyzeSetMasterCycles(db),
    };
  }

  Future<LampIssueResolutionApplyResult> applyDecisions({
    required String databasePath,
    required List<LampIssueResolutionDecision> decisions,
  }) async {
    final db = await _databaseProvider.open(
      databasePath.trim(),
      mode: LampDatabaseMode.write,
    );
    var resolved = 0;
    var manualApplied = 0;
    var created = 0;
    var unresolved = 0;
    final errors = <String>[];

    for (final decision in decisions) {
      try {
        final changed = await db.transaction<_AppliedDecision>((txn) async {
          return _applyDecision(txn, decision);
        });
        if (changed.created) {
          created++;
        } else if (decision.option != null) {
          manualApplied++;
        } else {
          resolved++;
        }
      } catch (e) {
        unresolved++;
        final p = decision.proposal;
        errors.add(
          '${p.issueType.issueType} row=${p.row ?? '-'} column=${p.column ?? '-'}: $e',
        );
      }
    }

    return LampIssueResolutionApplyResult(
      resolved: resolved,
      manualApplied: manualApplied,
      created: created,
      unresolved: unresolved,
      errors: errors,
    );
  }

  Future<List<Map<String, Object?>>> _openIssues(
    Database db,
    LampIssueType issueType,
  ) {
    return db.query(
      'data_issues',
      where: 'issue_type = ?',
      whereArgs: <Object?>[issueType.issueType],
      orderBy: 'id ASC',
    );
  }

  Future<List<LampIssueResolutionProposal>> _analyzeFkIssues(
    Database db,
    LampIssueType issueType,
  ) async {
    final issues = await _openIssues(db, issueType);
    final proposals = <LampIssueResolutionProposal>[];

    final offices = await _referenceRows(
      db,
      table: 'offices',
      idColumn: 'office',
      labelColumn: 'office_name',
    );
    final owners = await db.query(
      'owners',
      columns: <String>['owner', 'last_name', 'first_name'],
    );
    final contracts = await _referenceRows(
      db,
      table: 'contracts',
      idColumn: 'contract',
      labelColumn: 'contract_name',
    );
    final models = await _referenceRows(
      db,
      table: 'model',
      idColumn: 'model',
      labelColumn: 'model_name',
    );

    for (final issue in issues) {
      final base = _baseProposal(issueType, issue);
      final sheet = _text(issue['sheet']);
      final row = _toInt(issue['row_number']);
      final column = _text(issue['column_name'])?.toLowerCase();
      if (sheet != 'equipment' || row == null || column == null) {
        proposals.add(
          base(
            action: LampIssueResolutionAction.unresolved,
            confidence: 0,
            notes:
                'Το FK resolver εφαρμόζεται μόνο σε sheet=equipment με row_number.',
          ),
        );
        continue;
      }

      final equipment = await _equipmentByCode(db, row);
      if (equipment == null) {
        proposals.add(
          base(
            action: LampIssueResolutionAction.unresolved,
            confidence: 0,
            notes: 'Δεν βρέθηκε equipment με code=$row.',
          ),
        );
        continue;
      }

      final spec = _fkSpec(column);
      if (spec == null) {
        proposals.add(
          base(
            action: LampIssueResolutionAction.unresolved,
            confidence: 0,
            notes: 'Μη υποστηριζόμενη FK στήλη.',
          ),
        );
        continue;
      }

      final original = _originalText(
        equipment,
        spec.originalColumn,
        issue['raw_value'],
      );
      final normalized = _normalizeReferenceText(original);

      if (column == 'office') {
        proposals.add(
          _resolveNamedReference(
            issueType: issueType,
            issue: issue,
            original: original,
            normalized: normalized,
            references: offices,
            fkColumn: 'office',
            table: 'offices',
            idColumn: 'office',
            labelColumn: 'office_name',
            createLabel: 'office_name',
            exactAutoConfidence: 97,
            fuzzyAllowed: true,
          ),
        );
      } else if (column == 'owner') {
        proposals.add(
          _resolveOwner(
            issueType: issueType,
            issue: issue,
            original: original,
            normalized: normalized,
            owners: owners,
          ),
        );
      } else if (column == 'contract') {
        proposals.add(
          _resolveContract(
            issueType: issueType,
            issue: issue,
            original: original,
            normalized: normalized,
            references: contracts,
          ),
        );
      } else if (column == 'model') {
        proposals.add(
          _resolveNamedReference(
            issueType: issueType,
            issue: issue,
            original: original,
            normalized: normalized,
            references: models,
            fkColumn: 'model',
            table: 'model',
            idColumn: 'model',
            labelColumn: 'model_name',
            createLabel: 'model_name',
            exactAutoConfidence: 96,
            fuzzyAllowed: false,
          ),
        );
      }
    }

    return proposals;
  }

  LampIssueResolutionProposal _resolveNamedReference({
    required LampIssueType issueType,
    required Map<String, Object?> issue,
    required String original,
    required String normalized,
    required List<_ReferenceRow> references,
    required String fkColumn,
    required String table,
    required String idColumn,
    required String labelColumn,
    required String createLabel,
    required int exactAutoConfidence,
    required bool fuzzyAllowed,
  }) {
    final base = _baseProposal(issueType, issue, originalOverride: original);
    final exact = references
        .where((r) => r.normalized == normalized && normalized.isNotEmpty)
        .toList();
    final metadata = <String, Object?>{
      'operation': 'update_equipment_fk',
      'fkColumn': fkColumn,
      'referenceTable': table,
      'idColumn': idColumn,
      'labelColumn': labelColumn,
      'createLabel': createLabel,
    };
    if (exact.length == 1) {
      final match = exact.single;
      return base(
        action: LampIssueResolutionAction.autoFix,
        proposedId: match.id,
        proposedMatch: match.label,
        confidence: exactAutoConfidence,
        notes: 'Ακριβής κανονικοποιημένη αντιστοίχιση.',
        metadata: <String, Object?>{...metadata, 'proposedId': match.id},
      );
    }
    if (exact.length > 1) {
      return base(
        action: LampIssueResolutionAction.manualReview,
        confidence: 55,
        notes: 'Πολλαπλές ακριβείς αντιστοιχίσεις.',
        options: [
          for (final match in exact)
            LampIssueResolutionOption(
              id: 'fk_${match.id}',
              label: '${match.id} · ${match.label}',
              action: LampIssueResolutionAction.autoFix,
              proposedId: match.id,
              proposedMatch: match.label,
              metadata: <String, Object?>{...metadata, 'proposedId': match.id},
            ),
        ],
      );
    }

    if (fuzzyAllowed && normalized.isNotEmpty) {
      final candidates = <_FuzzyReferenceMatch>[];
      for (final ref in references) {
        if (ref.normalized.isEmpty) continue;
        final contains =
            ref.normalized.contains(normalized) ||
            normalized.contains(ref.normalized);
        final distance = _levenshtein(normalized, ref.normalized);
        if (contains || distance < 3) {
          candidates.add(
            _FuzzyReferenceMatch(
              ref,
              contains ? 72 : (100 - (distance * 20)).clamp(20, 95),
              distance,
            ),
          );
        }
      }
      candidates.sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        return byScore != 0 ? byScore : a.distance.compareTo(b.distance);
      });
      if (candidates.isNotEmpty) {
        return base(
          action: LampIssueResolutionAction.manualReview,
          proposedId: candidates.first.reference.id,
          proposedMatch: candidates.first.reference.label,
          confidence: candidates.first.score,
          notes: 'Ασαφής αντιστοίχιση με κοντινό όνομα.',
          options: [
            for (final candidate in candidates.take(5))
              LampIssueResolutionOption(
                id: 'fk_${candidate.reference.id}',
                label:
                    '${candidate.reference.id} · ${candidate.reference.label}',
                description: 'Απόσταση: ${candidate.distance}',
                action: LampIssueResolutionAction.autoFix,
                proposedId: candidate.reference.id,
                proposedMatch: candidate.reference.label,
                metadata: <String, Object?>{
                  ...metadata,
                  'proposedId': candidate.reference.id,
                },
              ),
          ],
        );
      }
    }

    return base(
      action: LampIssueResolutionAction.createNew,
      proposedMatch: '$createLabel=$original',
      confidence: original.isEmpty ? 20 : 80,
      notes: 'Δεν βρέθηκε αντιστοίχιση· προτείνεται δημιουργία νέας εγγραφής.',
      metadata: <String, Object?>{...metadata, 'createValue': original},
    );
  }

  LampIssueResolutionProposal _resolveOwner({
    required LampIssueType issueType,
    required Map<String, Object?> issue,
    required String original,
    required String normalized,
    required List<Map<String, Object?>> owners,
  }) {
    final base = _baseProposal(issueType, issue, originalOverride: original);
    final raw = _text(issue['raw_value']) ?? '';
    if (issueType == LampIssueType.unknownId &&
        int.tryParse(raw.trim()) != null) {
      return base(
        action: LampIssueResolutionAction.unresolved,
        confidence: 20,
        notes:
            'Αριθμητικό owner ID που δεν υπάρχει· παραμένει για χειροκίνητη απόφαση.',
      );
    }

    final parts = normalized.split(' ').where((p) => p.isNotEmpty).toList();
    final metadata = <String, Object?>{
      'operation': 'update_equipment_fk',
      'fkColumn': 'owner',
      'referenceTable': 'owners',
      'idColumn': 'owner',
      'labelColumn': 'last_name',
      'createLabel': 'last_name',
    };

    if (parts.length == 1) {
      final matches = owners.where((owner) {
        return _normalizeReferenceText(_text(owner['last_name']) ?? '') ==
            parts.single;
      }).toList();
      if (matches.isEmpty) {
        return base(
          action: LampIssueResolutionAction.createNew,
          proposedMatch: 'owner(last_name=$original, first_name=null)',
          confidence: 70,
          notes:
              'Μονολεκτικό owner χωρίς αντιστοίχιση· προτείνεται νέος owner.',
          metadata: <String, Object?>{
            ...metadata,
            'createValue': original,
            'createOwnerLastName': original,
          },
        );
      }
      return base(
        action: LampIssueResolutionAction.manualReview,
        proposedId: matches.length == 1 ? _toInt(matches.first['owner']) : null,
        proposedMatch: matches.length == 1 ? _ownerLabel(matches.first) : null,
        confidence: matches.length == 1 ? 76 : 52,
        notes: 'Μονολεκτικό owner ως επώνυμο· απαιτείται επιβεβαίωση.',
        options: [
          for (final match in matches)
            LampIssueResolutionOption(
              id: 'owner_${match['owner']}',
              label: '${match['owner']} · ${_ownerLabel(match)}',
              action: LampIssueResolutionAction.autoFix,
              proposedId: _toInt(match['owner']),
              proposedMatch: _ownerLabel(match),
              metadata: <String, Object?>{
                ...metadata,
                'proposedId': _toInt(match['owner']),
              },
            ),
        ],
      );
    }

    if (parts.length == 2) {
      return base(
        action: LampIssueResolutionAction.manualReview,
        confidence: 45,
        notes: 'Διμερές owner· απαιτείται επιλογή ονόματος/επωνύμου.',
        options: <LampIssueResolutionOption>[
          _createOwnerOption(
            id: 'owner_create_${parts[0]}_${parts[1]}',
            lastName: parts[0],
            firstName: parts[1],
            originalLabel: original,
          ),
          _createOwnerOption(
            id: 'owner_create_${parts[1]}_${parts[0]}',
            lastName: parts[1],
            firstName: parts[0],
            originalLabel: original,
          ),
        ],
      );
    }

    return base(
      action: LampIssueResolutionAction.manualReview,
      confidence: 30,
      notes: 'Σύνθετη ή ασυνήθιστη τιμή owner· απαιτείται απόφαση.',
      options: <LampIssueResolutionOption>[
        _createOwnerOption(
          id: 'owner_create_full',
          lastName: original,
          firstName: null,
          originalLabel: original,
        ),
        LampIssueResolutionOption(
          id: 'owner_null_keep_note',
          label: 'Αποσύνδεση κατόχου και διατήρηση κειμένου στο original_text',
          action: LampIssueResolutionAction.autoFix,
          metadata: <String, Object?>{
            'operation': 'update_equipment_fk',
            'fkColumn': 'owner',
            'proposedId': null,
          },
        ),
        LampIssueResolutionOption(
          id: 'owner_null_clear_original',
          label: 'Αποσύνδεση κατόχου και εκκαθάριση owner_original_text',
          action: LampIssueResolutionAction.autoFix,
          metadata: <String, Object?>{
            'operation': 'update_equipment_owner_null_clear_original',
          },
        ),
      ],
    );
  }

  LampIssueResolutionOption _createOwnerOption({
    required String id,
    required String lastName,
    required String? firstName,
    required String originalLabel,
  }) {
    return LampIssueResolutionOption(
      id: id,
      label: firstName == null
          ? 'Νέος owner: last_name=$lastName'
          : 'Νέος owner: last_name=$lastName, first_name=$firstName',
      action: LampIssueResolutionAction.createNew,
      proposedMatch: originalLabel,
      metadata: <String, Object?>{
        'operation': 'create_owner_and_update_equipment',
        'createOwnerLastName': lastName,
        'createOwnerFirstName': firstName,
      },
    );
  }

  LampIssueResolutionProposal _resolveContract({
    required LampIssueType issueType,
    required Map<String, Object?> issue,
    required String original,
    required String normalized,
    required List<_ReferenceRow> references,
  }) {
    final raw = _text(issue['raw_value']) ?? '';
    final rawId = int.tryParse(raw.trim());
    final base = _baseProposal(issueType, issue, originalOverride: original);
    if (issueType == LampIssueType.unknownId && rawId != null) {
      final idMatch = references.where((r) => r.id == rawId).toList();
      if (idMatch.isNotEmpty) {
        final match = idMatch.single;
        return base(
          action: LampIssueResolutionAction.autoFix,
          proposedId: match.id,
          proposedMatch: match.label,
          confidence: 90,
          notes: 'Το numeric ID υπάρχει πλέον στον πίνακα contracts.',
          metadata: <String, Object?>{
            'operation': 'update_equipment_fk',
            'fkColumn': 'contract',
            'proposedId': match.id,
          },
        );
      }
      final inName = references
          .where((r) => r.label.contains(rawId.toString()))
          .toList();
      if (inName.isNotEmpty) {
        return base(
          action: LampIssueResolutionAction.manualReview,
          confidence: 58,
          notes:
              'Το ID δεν υπάρχει, αλλά ο αριθμός εμφανίζεται σε contract_name.',
          options: [
            for (final match in inName.take(10))
              LampIssueResolutionOption(
                id: 'contract_${match.id}',
                label: '${match.id} · ${match.label}',
                action: LampIssueResolutionAction.autoFix,
                proposedId: match.id,
                proposedMatch: match.label,
                metadata: <String, Object?>{
                  'operation': 'update_equipment_fk',
                  'fkColumn': 'contract',
                  'proposedId': match.id,
                },
              ),
          ],
        );
      }
      return base(
        action: LampIssueResolutionAction.unresolved,
        confidence: 15,
        notes:
            'Αριθμητικό unknown_id χωρίς αντιστοίχιση σε ID ή contract_name.',
      );
    }

    return _resolveNamedReference(
      issueType: issueType,
      issue: issue,
      original: original,
      normalized: normalized,
      references: references,
      fkColumn: 'contract',
      table: 'contracts',
      idColumn: 'contract',
      labelColumn: 'contract_name',
      createLabel: 'contract_name',
      exactAutoConfidence: 96,
      fuzzyAllowed: false,
    );
  }

  Future<List<LampIssueResolutionProposal>> _analyzeDuplicateAssets(
    Database db,
  ) async {
    final issues = await _openIssues(db, LampIssueType.duplicateAssetNo);
    final byAsset = <String, List<int>>{};
    for (final issue in issues) {
      final raw = _text(issue['raw_value']);
      final id = _toInt(issue['id']);
      if (raw != null && id != null) {
        byAsset.putIfAbsent(raw, () => <int>[]).add(id);
      }
    }

    final proposals = <LampIssueResolutionProposal>[];
    for (final entry in byAsset.entries) {
      final rows = await db.query(
        'equipment',
        columns: _equipmentPreviewColumns,
        where: 'asset_no = ?',
        whereArgs: <Object?>[entry.key],
        orderBy: 'code ASC',
      );
      if (rows.length < 2) continue;
      proposals.add(
        _duplicateProposal(
          issueType: LampIssueType.duplicateAssetNo,
          issueIds: entry.value,
          column: 'asset_no',
          originalValue: entry.key,
          rows: rows,
          operationPrefix: 'duplicate_asset',
          clearOperation: 'clear_duplicate_asset_others',
          deleteOperation: 'delete_duplicate_asset_others',
          reassignOperation: 'reassign_asset',
          inputLabel: 'Νέο asset_no',
        ),
      );
    }
    return proposals;
  }

  Future<List<LampIssueResolutionProposal>> _analyzeDuplicateModelSerial(
    Database db,
  ) async {
    final issues = await _openIssues(db, LampIssueType.duplicateModelSerial);
    final issueIdsBySerial = <String, List<int>>{};
    for (final issue in issues) {
      final raw = _text(issue['raw_value']);
      final id = _toInt(issue['id']);
      if (raw != null && id != null) {
        issueIdsBySerial.putIfAbsent(raw, () => <int>[]).add(id);
      }
    }

    final duplicateGroups = await db.rawQuery('''
      SELECT model, serial_no
      FROM equipment
      WHERE model IS NOT NULL AND serial_no IS NOT NULL AND TRIM(serial_no) <> ''
      GROUP BY model, serial_no
      HAVING COUNT(*) > 1
      ORDER BY model, serial_no
      ''');
    final proposals = <LampIssueResolutionProposal>[];
    for (final group in duplicateGroups) {
      final model = _toInt(group['model']);
      final serial = _text(group['serial_no']);
      if (model == null || serial == null) continue;
      final rows = await db.query(
        'equipment',
        columns: _equipmentPreviewColumns,
        where: 'model = ? AND serial_no = ?',
        whereArgs: <Object?>[model, serial],
        orderBy: 'code ASC',
      );
      proposals.add(
        _duplicateProposal(
          issueType: LampIssueType.duplicateModelSerial,
          issueIds: issueIdsBySerial[serial] ?? const <int>[],
          column: 'serial_no',
          originalValue: '$model / $serial',
          rows: rows,
          operationPrefix: 'duplicate_model_serial',
          clearOperation: 'clear_duplicate_serial_others',
          deleteOperation: 'delete_duplicate_serial_others',
          reassignOperation: 'reassign_serial',
          inputLabel: 'Νέο serial_no',
          extraMetadata: <String, Object?>{'model': model, 'serialNo': serial},
        ),
      );
    }
    return proposals;
  }

  LampIssueResolutionProposal _duplicateProposal({
    required LampIssueType issueType,
    required List<int> issueIds,
    required String column,
    required String originalValue,
    required List<Map<String, Object?>> rows,
    required String operationPrefix,
    required String clearOperation,
    required String deleteOperation,
    required String reassignOperation,
    required String inputLabel,
    Map<String, Object?> extraMetadata = const <String, Object?>{},
  }) {
    final preview = rows.map(_equipmentSummary).join('\n');
    return LampIssueResolutionProposal(
      issueType: issueType,
      issueIds: issueIds,
      sheet: 'integrity_scan',
      row: _toInt(rows.first['code']),
      column: column,
      originalValue: originalValue,
      proposedAction: LampIssueResolutionAction.manualReview,
      confidence: 45,
      notes: 'Ομάδα διπλότυπων (${rows.length} εγγραφές):\n$preview',
      metadata: <String, Object?>{'rows': rows, ...extraMetadata},
      options: <LampIssueResolutionOption>[
        for (final row in rows)
          LampIssueResolutionOption(
            id: '${operationPrefix}_clear_keep_${row['code']}',
            label:
                'Κράτα code ${row['code']} και καθάρισε την τιμή στις άλλες εγγραφές',
            action: LampIssueResolutionAction.autoFix,
            metadata: <String, Object?>{
              'operation': clearOperation,
              'keepCode': _toInt(row['code']),
              'value': column == 'asset_no' ? originalValue : null,
              ...extraMetadata,
            },
          ),
        for (final row in rows)
          LampIssueResolutionOption(
            id: '${operationPrefix}_delete_keep_${row['code']}',
            label: 'Κράτα code ${row['code']} και διέγραψε τις άλλες εγγραφές',
            action: LampIssueResolutionAction.autoFix,
            metadata: <String, Object?>{
              'operation': deleteOperation,
              'keepCode': _toInt(row['code']),
              'value': column == 'asset_no' ? originalValue : null,
              ...extraMetadata,
            },
          ),
        for (final row in rows)
          LampIssueResolutionOption(
            id: '${operationPrefix}_reassign_${row['code']}',
            label: 'Δώσε νέα τιμή στο code ${row['code']}',
            action: LampIssueResolutionAction.autoFix,
            requiresTextInput: true,
            inputLabel: inputLabel,
            metadata: <String, Object?>{
              'operation': reassignOperation,
              'targetCode': _toInt(row['code']),
            },
          ),
      ],
    );
  }

  Future<List<LampIssueResolutionProposal>> _analyzeOwnerOfficeMismatch(
    Database db,
  ) async {
    final issues = await _openIssues(db, LampIssueType.ownerOfficeMismatch);
    final proposals = <LampIssueResolutionProposal>[];
    for (final issue in issues) {
      final code = _toInt(issue['row_number']);
      if (code == null) continue;
      final rows = await db.rawQuery(
        '''
        SELECT e.code, e.description, e.office, e.owner,
               eo.office_name AS equipment_office_name,
               o.office AS owner_office,
               o.last_name, o.first_name,
               oo.office_name AS owner_office_name
        FROM equipment e
        JOIN owners o ON o.owner = e.owner
        LEFT JOIN offices eo ON eo.office = e.office
        LEFT JOIN offices oo ON oo.office = o.office
        WHERE e.code = ?
        LIMIT 1
        ''',
        <Object?>[code],
      );
      if (rows.isEmpty) continue;
      final row = rows.first;
      final equipmentOffice = _toInt(row['office']);
      final ownerOffice = _toInt(row['owner_office']);
      if (ownerOffice == equipmentOffice) continue;
      final owner = _toInt(row['owner']);
      final sameOfficeOwners = equipmentOffice == null
          ? const <Map<String, Object?>>[]
          : await db.query(
              'owners',
              columns: <String>['owner', 'last_name', 'first_name'],
              where: 'office = ?',
              whereArgs: <Object?>[equipmentOffice],
              orderBy: 'last_name, first_name',
              limit: 12,
            );
      proposals.add(
        LampIssueResolutionProposal(
          issueType: LampIssueType.ownerOfficeMismatch,
          issueIds: [_toInt(issue['id'])].whereType<int>().toList(),
          sheet: _text(issue['sheet']),
          row: code,
          column: 'office',
          originalValue: _text(issue['raw_value']),
          proposedAction: LampIssueResolutionAction.manualReview,
          proposedId: ownerOffice,
          proposedMatch: _text(row['owner_office_name']),
          confidence: 75,
          notes:
              'equipment.office=$equipmentOffice (${_text(row['equipment_office_name']) ?? '-'}) · '
              'owner=$owner (${_ownerLabel(row)}) · owner.office=$ownerOffice (${_text(row['owner_office_name']) ?? '-'})',
          metadata: <String, Object?>{'code': code, 'owner': owner},
          options: <LampIssueResolutionOption>[
            LampIssueResolutionOption(
              id: 'move_equipment_office_$code',
              label:
                  'Μεταφορά equipment.office στο γραφείο του owner ($ownerOffice)',
              action: LampIssueResolutionAction.autoFix,
              proposedId: ownerOffice,
              proposedMatch: _text(row['owner_office_name']),
              metadata: <String, Object?>{
                'operation': 'update_equipment_office',
                'code': code,
                'office': ownerOffice,
              },
            ),
            for (final candidate in sameOfficeOwners)
              LampIssueResolutionOption(
                id: 'change_owner_${candidate['owner']}_$code',
                label:
                    'Αλλαγή κατόχου σε ${candidate['owner']} · ${_ownerLabel(candidate)}',
                action: LampIssueResolutionAction.autoFix,
                proposedId: _toInt(candidate['owner']),
                proposedMatch: _ownerLabel(candidate),
                metadata: <String, Object?>{
                  'operation': 'change_equipment_owner',
                  'code': code,
                  'owner': _toInt(candidate['owner']),
                },
              ),
            if (owner != null)
              LampIssueResolutionOption(
                id: 'fix_owner_office_${owner}_$code',
                label: 'Διόρθωση owners.office ώστε να γίνει $equipmentOffice',
                action: LampIssueResolutionAction.autoFix,
                proposedId: equipmentOffice,
                metadata: <String, Object?>{
                  'operation': 'fix_owner_office',
                  'owner': owner,
                  'office': equipmentOffice,
                },
              ),
          ],
        ),
      );
    }
    return proposals;
  }

  Future<List<LampIssueResolutionProposal>> _analyzeSetMasterSelfReferences(
    Database db,
  ) async {
    final issues = await _openIssues(db, LampIssueType.setMasterSelfReference);
    return <LampIssueResolutionProposal>[
      for (final issue in issues)
        if (_toInt(issue['row_number']) != null)
          LampIssueResolutionProposal(
            issueType: LampIssueType.setMasterSelfReference,
            issueIds: [_toInt(issue['id'])].whereType<int>().toList(),
            sheet: _text(issue['sheet']),
            row: _toInt(issue['row_number']),
            column: 'set_master',
            originalValue: _text(issue['raw_value']),
            proposedAction: LampIssueResolutionAction.autoFix,
            proposedId: null,
            proposedMatch: 'set_master=NULL',
            confidence: 98,
            notes: 'Ασφαλής εκκαθάριση αυτοαναφοράς set_master.',
            metadata: <String, Object?>{
              'operation': 'clear_set_master',
              'code': _toInt(issue['row_number']),
            },
          ),
    ];
  }

  Future<List<LampIssueResolutionProposal>> _analyzeSetMasterCycles(
    Database db,
  ) async {
    final issues = await _openIssues(db, LampIssueType.setMasterCycle);
    final issueIdsByRoot = <int, List<int>>{};
    for (final issue in issues) {
      final root = _toInt(issue['row_number']);
      final id = _toInt(issue['id']);
      if (root != null && id != null) {
        issueIdsByRoot.putIfAbsent(root, () => <int>[]).add(id);
      }
    }
    final rows = await db.query(
      'equipment',
      columns: <String>['code', 'set_master', 'description'],
      where: 'set_master IS NOT NULL AND set_master <> code',
    );
    final masterByCode = <int, int>{};
    final descriptionByCode = <int, String>{};
    for (final row in rows) {
      final code = _toInt(row['code']);
      final master = _toInt(row['set_master']);
      if (code != null && master != null) {
        masterByCode[code] = master;
        descriptionByCode[code] = _text(row['description']) ?? '';
      }
    }

    final proposals = <LampIssueResolutionProposal>[];
    final emittedCycles = <String>{};
    for (final root in issueIdsByRoot.keys) {
      final cycle = _cycleForRoot(root, masterByCode);
      if (cycle.isEmpty) continue;
      final key = (cycle.toList()..sort()).join('>');
      if (!emittedCycles.add(key)) continue;
      proposals.add(
        LampIssueResolutionProposal(
          issueType: LampIssueType.setMasterCycle,
          issueIds: [for (final code in cycle) ...?issueIdsByRoot[code]],
          sheet: 'integrity_scan',
          row: root,
          column: 'set_master',
          originalValue: cycle.join(' -> '),
          proposedAction: LampIssueResolutionAction.manualReview,
          confidence: 65,
          notes: 'Κύκλος: ${cycle.join(' -> ')} -> ${cycle.first}',
          metadata: <String, Object?>{'cycle': cycle},
          options: <LampIssueResolutionOption>[
            for (final code in cycle)
              LampIssueResolutionOption(
                id: 'break_cycle_$code',
                label:
                    'Σπάσιμο στο code $code (${descriptionByCode[code] ?? ''})',
                description: 'Θέτει set_master=NULL για το code $code.',
                action: LampIssueResolutionAction.autoFix,
                metadata: <String, Object?>{
                  'operation': 'clear_set_master',
                  'code': code,
                },
              ),
          ],
        ),
      );
    }
    return proposals;
  }

  Future<_AppliedDecision> _applyDecision(
    Transaction txn,
    LampIssueResolutionDecision decision,
  ) async {
    final proposal = decision.proposal;
    final option = decision.option;
    final metadata = option?.metadata ?? proposal.metadata;
    final operation = metadata['operation']?.toString();
    var created = false;

    if (proposal.proposedAction == LampIssueResolutionAction.createNew &&
        option == null) {
      await _createReferenceAndUpdateEquipment(txn, proposal);
      created = true;
      await _deleteIssues(txn, proposal.issueIds);
      return _AppliedDecision(created: created);
    }

    switch (operation) {
      case 'update_equipment_fk':
        final code = proposal.row;
        final fkColumn = metadata['fkColumn']?.toString();
        final proposedId = metadata['proposedId'] as int?;
        if (code == null || fkColumn == null) {
          throw StateError('Λείπουν στοιχεία FK update.');
        }
        await txn.update(
          'equipment',
          <String, Object?>{fkColumn: proposedId},
          where: 'code = ?',
          whereArgs: <Object?>[code],
        );
      case 'create_owner_and_update_equipment':
        final code = proposal.row;
        if (code == null) throw StateError('Λείπει code equipment.');
        final ownerId = await _nextId(txn, 'owners', 'owner');
        await txn.insert('owners', <String, Object?>{
          'owner': ownerId,
          'last_name': metadata['createOwnerLastName'],
          'first_name': metadata['createOwnerFirstName'],
        });
        await txn.update(
          'equipment',
          <String, Object?>{'owner': ownerId},
          where: 'code = ?',
          whereArgs: <Object?>[code],
        );
        created = true;
      case 'update_equipment_owner_null_clear_original':
        final code = proposal.row;
        if (code == null) throw StateError('Λείπει code equipment.');
        await txn.update(
          'equipment',
          <String, Object?>{'owner': null, 'owner_original_text': null},
          where: 'code = ?',
          whereArgs: <Object?>[code],
        );
      case 'update_equipment_office':
        await txn.update(
          'equipment',
          <String, Object?>{'office': metadata['office']},
          where: 'code = ?',
          whereArgs: <Object?>[metadata['code']],
        );
      case 'change_equipment_owner':
        await txn.update(
          'equipment',
          <String, Object?>{'owner': metadata['owner']},
          where: 'code = ?',
          whereArgs: <Object?>[metadata['code']],
        );
      case 'fix_owner_office':
        await txn.update(
          'owners',
          <String, Object?>{'office': metadata['office']},
          where: 'owner = ?',
          whereArgs: <Object?>[metadata['owner']],
        );
      case 'clear_set_master':
        final code = metadata['code'];
        await txn.update(
          'equipment',
          <String, Object?>{'set_master': null},
          where: 'code = ?',
          whereArgs: <Object?>[code],
        );
        await txn.delete(
          'data_issues',
          where: 'issue_type = ? AND row_number = ? AND column_name = ?',
          whereArgs: <Object?>['set_master_cycle', code, 'set_master'],
        );
      case 'clear_duplicate_asset_others':
        await txn.update(
          'equipment',
          <String, Object?>{'asset_no': null},
          where: 'asset_no = ? AND code <> ?',
          whereArgs: <Object?>[metadata['value'], metadata['keepCode']],
        );
      case 'delete_duplicate_asset_others':
        await _deleteDuplicateEquipmentOthers(
          txn,
          keepCode: metadata['keepCode'] as int?,
          where: 'asset_no = ? AND code <> ?',
          whereArgs: <Object?>[metadata['value'], metadata['keepCode']],
        );
      case 'reassign_asset':
        final value = decision.textInput?.trim();
        if (value == null || value.isEmpty) {
          throw StateError('Δεν δόθηκε νέο asset_no.');
        }
        await txn.update(
          'equipment',
          <String, Object?>{'asset_no': value},
          where: 'code = ?',
          whereArgs: <Object?>[metadata['targetCode']],
        );
      case 'clear_duplicate_serial_others':
        await txn.update(
          'equipment',
          <String, Object?>{'serial_no': null},
          where: 'model = ? AND serial_no = ? AND code <> ?',
          whereArgs: <Object?>[
            metadata['model'],
            metadata['serialNo'],
            metadata['keepCode'],
          ],
        );
      case 'delete_duplicate_serial_others':
        await _deleteDuplicateEquipmentOthers(
          txn,
          keepCode: metadata['keepCode'] as int?,
          where: 'model = ? AND serial_no = ? AND code <> ?',
          whereArgs: <Object?>[
            metadata['model'],
            metadata['serialNo'],
            metadata['keepCode'],
          ],
        );
      case 'reassign_serial':
        final value = decision.textInput?.trim();
        if (value == null || value.isEmpty) {
          throw StateError('Δεν δόθηκε νέο serial_no.');
        }
        await txn.update(
          'equipment',
          <String, Object?>{'serial_no': value},
          where: 'code = ?',
          whereArgs: <Object?>[metadata['targetCode']],
        );
      default:
        if (proposal.proposedAction == LampIssueResolutionAction.autoFix) {
          final fkColumn = proposal.metadata['fkColumn']?.toString();
          if (fkColumn != null && proposal.row != null) {
            await txn.update(
              'equipment',
              <String, Object?>{fkColumn: proposal.proposedId},
              where: 'code = ?',
              whereArgs: <Object?>[proposal.row],
            );
          } else {
            throw StateError(
              'Δεν υπάρχει εφαρμόσιμη ενέργεια για την πρόταση.',
            );
          }
        } else {
          throw StateError('Δεν υπάρχει εφαρμόσιμη ενέργεια για την πρόταση.');
        }
    }

    await _deleteIssues(txn, proposal.issueIds);
    return _AppliedDecision(created: created);
  }

  Future<void> _createReferenceAndUpdateEquipment(
    Transaction txn,
    LampIssueResolutionProposal proposal,
  ) async {
    final metadata = proposal.metadata;
    final table = metadata['referenceTable']?.toString();
    final idColumn = metadata['idColumn']?.toString();
    final labelColumn = metadata['labelColumn']?.toString();
    final fkColumn = metadata['fkColumn']?.toString();
    final code = proposal.row;
    final createValue = metadata['createValue'];
    if (table == null ||
        idColumn == null ||
        labelColumn == null ||
        fkColumn == null ||
        code == null) {
      throw StateError('Λείπουν στοιχεία για create_new.');
    }
    final id = await _nextId(txn, table, idColumn);
    await txn.insert(table, <String, Object?>{
      idColumn: id,
      labelColumn: createValue,
    });
    await txn.update(
      'equipment',
      <String, Object?>{fkColumn: id},
      where: 'code = ?',
      whereArgs: <Object?>[code],
    );
  }

  Future<void> _deleteDuplicateEquipmentOthers(
    Transaction txn, {
    required int? keepCode,
    required String where,
    required List<Object?> whereArgs,
  }) async {
    if (keepCode == null) throw StateError('Λείπει κύρια εγγραφή.');
    final rows = await txn.query(
      'equipment',
      columns: <String>['code'],
      where: where,
      whereArgs: whereArgs,
    );
    for (final row in rows) {
      final code = _toInt(row['code']);
      if (code == null) continue;
      await txn.update(
        'equipment',
        <String, Object?>{'set_master': keepCode},
        where: 'set_master = ?',
        whereArgs: <Object?>[code],
      );
      await txn.delete(
        'equipment',
        where: 'code = ?',
        whereArgs: <Object?>[code],
      );
    }
  }

  Future<void> _deleteIssues(Transaction txn, List<int> ids) async {
    if (ids.isEmpty) return;
    final placeholders = List<String>.filled(ids.length, '?').join(',');
    await txn.delete(
      'data_issues',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  Future<int> _nextId(
    DatabaseExecutor db,
    String table,
    String idColumn,
  ) async {
    final rows = await db.rawQuery(
      'SELECT COALESCE(MAX($idColumn), 0) + 1 AS next_id FROM $table',
    );
    return _toInt(rows.first['next_id']) ?? 1;
  }

  Future<Map<String, Object?>?> _equipmentByCode(Database db, int code) async {
    final rows = await db.query(
      'equipment',
      where: 'code = ?',
      whereArgs: <Object?>[code],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<_ReferenceRow>> _referenceRows(
    Database db, {
    required String table,
    required String idColumn,
    required String labelColumn,
  }) async {
    final rows = await db.query(
      table,
      columns: <String>[idColumn, labelColumn],
      orderBy: labelColumn,
    );
    return <_ReferenceRow>[
      for (final row in rows)
        if (_toInt(row[idColumn]) != null)
          _ReferenceRow(
            id: _toInt(row[idColumn])!,
            label: _text(row[labelColumn]) ?? '',
            normalized: _normalizeReferenceText(_text(row[labelColumn]) ?? ''),
          ),
    ];
  }

  _FkSpec? _fkSpec(String column) {
    return switch (column) {
      'office' => const _FkSpec('office', 'office_original_text'),
      'owner' => const _FkSpec('owner', 'owner_original_text'),
      'contract' => const _FkSpec('contract', 'contract_original_text'),
      'model' => const _FkSpec('model', 'model_original_text'),
      _ => null,
    };
  }

  LampIssueResolutionProposal Function({
    required LampIssueResolutionAction action,
    int? proposedId,
    String? proposedMatch,
    required int confidence,
    List<LampIssueResolutionOption> options,
    required String notes,
    Map<String, Object?> metadata,
  })
  _baseProposal(
    LampIssueType issueType,
    Map<String, Object?> issue, {
    String? originalOverride,
  }) {
    return ({
      required LampIssueResolutionAction action,
      int? proposedId,
      String? proposedMatch,
      required int confidence,
      List<LampIssueResolutionOption> options =
          const <LampIssueResolutionOption>[],
      required String notes,
      Map<String, Object?> metadata = const <String, Object?>{},
    }) {
      return LampIssueResolutionProposal(
        issueType: issueType,
        issueIds: [_toInt(issue['id'])].whereType<int>().toList(),
        sheet: _text(issue['sheet']),
        row: _toInt(issue['row_number']),
        column: _text(issue['column_name']),
        originalValue: originalOverride ?? _text(issue['raw_value']),
        proposedAction: action,
        proposedId: proposedId,
        proposedMatch: proposedMatch,
        confidence: confidence,
        options: options,
        notes: notes,
        metadata: metadata,
      );
    };
  }

  List<int> _cycleForRoot(int root, Map<int, int> masterByCode) {
    final path = <int>[];
    final indexByCode = <int, int>{};
    var current = root;
    while (true) {
      final existing = indexByCode[current];
      if (existing != null) return path.sublist(existing);
      final next = masterByCode[current];
      if (next == null || next == current) return const <int>[];
      indexByCode[current] = path.length;
      path.add(current);
      current = next;
    }
  }

  String _originalText(
    Map<String, Object?> equipment,
    String originalColumn,
    Object? rawValue,
  ) {
    final fromOriginal = _text(equipment[originalColumn]);
    if (fromOriginal != null && fromOriginal.trim().isNotEmpty) {
      return fromOriginal.trim();
    }
    return _text(rawValue)?.trim() ?? '';
  }

  String _normalizeReferenceText(String value) {
    return SearchTextNormalizer.normalizeForSearch(
      value.replaceAll(RegExp(r'[-/()\\]+'), ' '),
    );
  }

  int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.length < b.length) {
      final tmp = a;
      a = b;
      b = tmp;
    }
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 0; i < a.length; i++) {
      final current = <int>[i + 1];
      for (var j = 0; j < b.length; j++) {
        final insert = current[j] + 1;
        final delete = previous[j + 1] + 1;
        final substitute = previous[j] + (a[i] == b[j] ? 0 : 1);
        current.add(
          [insert, delete, substitute].reduce((x, y) => x < y ? x : y),
        );
      }
      previous = current;
    }
    return previous.last;
  }

  String _ownerLabel(Map<String, Object?> owner) {
    final lastName = _text(owner['last_name']) ?? '';
    final firstName = _text(owner['first_name']) ?? '';
    return '$lastName $firstName'.trim();
  }

  String _equipmentSummary(Map<String, Object?> row) {
    return 'code=${row['code']} · ${_text(row['description']) ?? '-'} · '
        'model=${row['model'] ?? '-'} · serial=${row['serial_no'] ?? '-'} · '
        'office=${row['office'] ?? '-'} · owner=${row['owner'] ?? '-'}';
  }

  String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  int? _toInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }

  static const List<String> _equipmentPreviewColumns = <String>[
    'code',
    'description',
    'model',
    'serial_no',
    'asset_no',
    'office',
    'owner',
    'set_master',
  ];
}

class _ReferenceRow {
  const _ReferenceRow({
    required this.id,
    required this.label,
    required this.normalized,
  });

  final int id;
  final String label;
  final String normalized;
}

class _FuzzyReferenceMatch {
  const _FuzzyReferenceMatch(this.reference, this.score, this.distance);

  final _ReferenceRow reference;
  final int score;
  final int distance;
}

class _FkSpec {
  const _FkSpec(this.fkColumn, this.originalColumn);

  final String fkColumn;
  final String originalColumn;
}

class _AppliedDecision {
  const _AppliedDecision({required this.created});

  final bool created;
}
