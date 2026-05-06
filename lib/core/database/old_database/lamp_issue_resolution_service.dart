import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../utils/search_text_normalizer.dart';
import '../../utils/user_identity_normalizer.dart';
import 'lamp_database_provider.dart';
import 'old_database_schema.dart';
import 'resolution_log_entry.dart';

typedef ResolutionLogSink = void Function(ResolutionLogEntry entry);

enum LampIssueType {
  nonNumericFk('non_numeric_fk', 'Επίλυση · Μη αριθμητικό Κλειδί Αναφοράς'),
  unknownId('unknown_id', 'Επίλυση · Ασύμβατο Αναγνωριστικό'),
  duplicateAssetNo('duplicate_asset_no', 'Επίλυση · Διπλότυποι αριθμοί παγίου'),
  duplicateModelSerial(
    'duplicate_model_serial',
    'Επίλυση · Διπλότυποι συνδυασμοί μοντέλου / σειριακού',
  ),
  setMasterSelfReference(
    'set_master_self_reference',
    'Επίλυση · Κύριος εξοπλισμός που δείχνει στον ίδιο εξοπλισμό',
  ),
  setMasterCycle(
    'set_master_cycle',
    'Επίλυση · Κύκλοι ιεραρχίας Κύριου εξοπλισμού',
  );

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

extension LampIssueResolutionActionLabelsEl on LampIssueResolutionAction {
  /// Ετικέτα εμφάνισης (το [jsonValue] παραμένει για αποθήκευση / JSON).
  String get labelEl {
    switch (this) {
      case LampIssueResolutionAction.autoFix:
        return 'Αυτόματη διόρθωση';
      case LampIssueResolutionAction.createNew:
        return 'Νέα εγγραφή';
      case LampIssueResolutionAction.manualReview:
        return 'Χειροκίνητη επισκόπηση';
      case LampIssueResolutionAction.unresolved:
        return 'Ανεπίλυτο';
    }
  }
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

  /// Κοινή βαθμολόγηση ομοιότητας που επαναχρησιμοποιείται σε flows migration.
  int similarityConfidenceScore(String source, String candidate) {
    final a = _normalizeReferenceText(source);
    final b = _normalizeReferenceText(candidate);
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 100;
    if (a.contains(b) || b.contains(a)) return 72;
    final distance = _levenshtein(a, b);
    return (100 - (distance * 20)).clamp(20, 95);
  }

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
      LampIssueType.setMasterSelfReference => _analyzeSetMasterSelfReferences(
        db,
      ),
      LampIssueType.setMasterCycle => _analyzeSetMasterCycles(db),
    };
  }

  Future<LampIssueResolutionApplyResult> applyDecisions({
    required String databasePath,
    required List<LampIssueResolutionDecision> decisions,
    ResolutionLogSink? onLog,
    ResolutionCancelToken? cancelToken,
  }) async {
    void emit(ResolutionLogEntry entry) => onLog?.call(entry);

    emit(
      ResolutionLogEntry.info(
        'Έναρξη εφαρμογής ${decisions.length} αποφάσεων επίλυσης.',
      ),
    );
    final db = await _databaseProvider.open(
      databasePath.trim(),
      mode: LampDatabaseMode.write,
    );
    await _ensureIntegrityArtifacts(db);
    var resolved = 0;
    var manualApplied = 0;
    var created = 0;
    var unresolved = 0;
    final errors = <String>[];

    for (final decision in decisions) {
      if (cancelToken?.isCancelled == true) {
        emit(
          ResolutionLogEntry.warning(
            'Η διαδικασία ακυρώθηκε πριν την επόμενη απόφαση.',
          ),
        );
        break;
      }
      try {
        final changed = await db.transaction<_AppliedDecision>((txn) async {
          return _applyDecision(txn, decision, emit: emit);
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
        final errorMessage =
            '${p.issueType.issueType} γραμμή=${p.row ?? '-'} '
            'στήλη=${p.column ?? '-'}: $e';
        emit(
          ResolutionLogEntry.error(
            'Σφάλμα κατά την εφαρμογή απόφασης: $errorMessage',
          ),
        );
        errors.add(errorMessage);
      }
    }

    emit(
      ResolutionLogEntry.success(
        'Ολοκληρώθηκε η εφαρμογή αποφάσεων: '
        'auto=$resolved, manual=$manualApplied, νέες=$created, '
        'ανεπίλυτες=$unresolved.',
      ),
    );

    return LampIssueResolutionApplyResult(
      resolved: resolved,
      manualApplied: manualApplied,
      created: created,
      unresolved: unresolved,
      errors: errors,
    );
  }

  Future<void> _ensureIntegrityArtifacts(Database db) async {
    for (final statement in oldDatabaseIntegrityStatements) {
      try {
        await db.execute(statement);
      } catch (_) {
        // Συνεχίζουμε: σε legacy βάσεις κάποια integrity artifacts μπορεί
        // να αποτύχουν, αλλά το κρίσιμο cleanup (π.χ. DROP legacy trigger)
        // πρέπει να έχει ευκαιρία να εφαρμοστεί.
      }
    }
  }

  /// Μία απόφαση σε μία συναλλαγή — ίδια διαδρομή με [applyDecisions] (logs, `_applyDecision`).
  Future<LampIssueResolutionApplyResult> applySingleDecision({
    required String databasePath,
    required LampIssueResolutionDecision decision,
    ResolutionLogSink? onLog,
    ResolutionCancelToken? cancelToken,
  }) {
    return applyDecisions(
      databasePath: databasePath,
      decisions: <LampIssueResolutionDecision>[decision],
      onLog: onLog,
      cancelToken: cancelToken,
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
      columns: <String>['owner', 'last_name', 'first_name', 'office'],
    );
    final contracts = await _referenceRows(
      db,
      table: 'contracts',
      idColumn: 'contract',
      labelColumn: 'contract_name',
    );
    final contractDetailsRows = await db.query(
      'contracts',
      columns: <String>[
        'contract',
        'contract_name',
        'supplier_name',
        'category_name',
      ],
    );
    final contractDetailsById = <int, _ContractDetailRow>{
      for (final row in contractDetailsRows)
        if (_toInt(row['contract']) != null)
          _toInt(row['contract'])!: _ContractDetailRow(
            id: _toInt(row['contract'])!,
            contractName: _text(row['contract_name']) ?? '',
            supplierName: _text(row['supplier_name']),
            categoryName: _text(row['category_name']),
          ),
    };
    final models = await _referenceRows(
      db,
      table: 'model',
      idColumn: 'model',
      labelColumn: 'model_name',
    );
    final officeDetailRows = await db.query(
      'offices',
      columns: <String>[
        'office',
        'office_name',
        'department_name',
        'organization_name',
      ],
    );
    final officeDetailsById = <int, _OfficeDetailRow>{
      for (final row in officeDetailRows)
        if (_toInt(row['office']) != null)
          _toInt(row['office'])!: _OfficeDetailRow(
            id: _toInt(row['office'])!,
            officeName: _text(row['office_name']),
            departmentName: _text(row['department_name']),
            organizationName: _text(row['organization_name']),
          ),
    };
    final modelDetailRows = await db.query(
      'model',
      columns: <String>[
        'model',
        'model_name',
        'manufacturer_name',
        'category_name',
        'subcategory_name',
      ],
    );
    final modelDetailsById = <int, _ModelDetailRow>{
      for (final row in modelDetailRows)
        if (_toInt(row['model']) != null)
          _toInt(row['model'])!: _ModelDetailRow(
            id: _toInt(row['model'])!,
            modelName: _text(row['model_name']),
            manufacturerName: _text(row['manufacturer_name']),
            categoryName: _text(row['category_name']),
            subcategoryName: _text(row['subcategory_name']),
          ),
    };
    final equipmentStatsRows = await db.query(
      'equipment',
      columns: <String>['model', 'contract', 'owner', 'office'],
    );
    final usageByColumn = _buildFkUsageByColumn(equipmentStatsRows);
    final officeLabelById = <int, String>{
      for (final row in offices)
        row.id: _officeDisplayLabel(
          officeDetailsById[row.id] ??
              _OfficeDetailRow(id: row.id, officeName: row.label),
        ),
    };
    final ownerLabelById = <int, String>{
      for (final row in owners)
        if (_toInt(row['owner']) != null)
          _toInt(row['owner'])!: _ownerLabel(row),
    };
    final modelLabelById = <int, String>{
      for (final row in models)
        row.id: _modelDisplayLabel(
          modelDetailsById[row.id] ??
              _ModelDetailRow(id: row.id, modelName: row.label),
        ),
    };
    final contractLabelById = <int, String>{
      for (final row in contracts)
        row.id: _contractDisplayLabel(
          contractDetailsById[row.id] ??
              _ContractDetailRow(id: row.id, contractName: row.label),
        ),
    };

    for (final issue in issues) {
      final base = _baseProposal(issueType, issue);
      final entityType = _issueEntityType(issue);
      final origin = _issueOrigin(issue);
      final rowRaw = issue['row_number'];
      final row = _toInt(rowRaw);
      final columnRaw = _text(issue['column_name']);
      final column = columnRaw?.toLowerCase();
      if (entityType != 'equipment' || row == null || column == null) {
        final reasons = <String>[
          if (entityType != 'equipment')
            'Το `entity_type` δεν είναι `equipment` '
                '(τρέχουσα τιμή: `${entityType ?? '(κενό)'}`).',
          if (row == null)
            'Το `row_number` λείπει ή δεν είναι έγκυρος ακέραιος '
                '(τρέχουσα τιμή: `${_text(rowRaw) ?? '(κενό)'}`).',
          if (column == null)
            'Η στήλη αναφοράς `column` λείπει ή είναι κενή '
                '(τρέχουσα τιμή: `${columnRaw ?? '(κενό)'}`).',
        ];
        final details = reasons.join(' ');
        proposals.add(
          base(
            action: LampIssueResolutionAction.unresolved,
            confidence: 0,
            notes: 'Αποτυχία επιλεξιμότητας για επίλυση FK. $details',
            metadata: <String, Object?>{
              'diagnosticType': 'fk_resolution_eligibility',
              'diagnosticEntityType': entityType ?? '(κενό)',
              'diagnosticOrigin': origin ?? '(κενό)',
              'diagnosticSheet': _text(issue['sheet']) ?? '(κενό)',
              'diagnosticRowNumberRaw': rowRaw?.toString() ?? '(κενό)',
              'diagnosticColumn': columnRaw ?? '(κενό)',
              'diagnosticReasons': reasons,
            },
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
            notes: 'Δεν βρέθηκε εξοπλισμός με κωδικό $row.',
          ),
        );
        continue;
      }

      final spec = _fkSpec(column);
      if (spec == null) {
        final reasons = <String>[
          'Η στήλη αναφοράς `column` δεν υποστηρίζεται για επίλυση FK '
              '(τρέχουσα τιμή: `${columnRaw ?? '(κενό)'}`, υποστηριζόμενες: office, owner, contract, model).',
        ];
        proposals.add(
          base(
            action: LampIssueResolutionAction.unresolved,
            confidence: 0,
            notes:
                'Αποτυχία επιλεξιμότητας για επίλυση FK. ${reasons.join(' ')}',
            metadata: <String, Object?>{
              'diagnosticType': 'fk_resolution_unsupported_column',
              'diagnosticEntityType': entityType ?? '(κενό)',
              'diagnosticOrigin': origin ?? '(κενό)',
              'diagnosticSheet': _text(issue['sheet']) ?? '(κενό)',
              'diagnosticRowNumberRaw': rowRaw?.toString() ?? '(κενό)',
              'diagnosticColumn': columnRaw ?? '(κενό)',
              'diagnosticReasons': reasons,
            },
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
      LampIssueResolutionProposal withEquipmentContext(
        LampIssueResolutionProposal proposal,
      ) {
        return _appendEquipmentContextMetadata(
          proposal,
          equipment: equipment,
          officeLabelById: officeLabelById,
          ownerLabelById: ownerLabelById,
          modelLabelById: modelLabelById,
          contractLabelById: contractLabelById,
        );
      }

      if (issueType == LampIssueType.unknownId) {
        final unknownProposal = _resolveUnknownIdReference(
          issue: issue,
          equipment: equipment,
          column: column,
          original: original,
          offices: offices,
          owners: owners,
          contracts: contracts,
          contractDetailsById: contractDetailsById,
          models: models,
          usageByColumn: usageByColumn,
          equipmentStatsRows: equipmentStatsRows,
        );
        proposals.add(withEquipmentContext(unknownProposal));
        continue;
      }

      if (column == 'office') {
        proposals.add(
          withEquipmentContext(
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
          ),
        );
      } else if (column == 'owner') {
        proposals.add(
          withEquipmentContext(
            _resolveOwner(
              issueType: issueType,
              issue: issue,
              original: original,
              normalized: normalized,
              owners: owners,
            ),
          ),
        );
      } else if (column == 'contract') {
        proposals.add(
          withEquipmentContext(
            _resolveContract(
              issueType: issueType,
              issue: issue,
              original: original,
              normalized: normalized,
              references: contracts,
            ),
          ),
        );
      } else if (column == 'model') {
        proposals.add(
          withEquipmentContext(
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

  LampIssueResolutionProposal _appendEquipmentContextMetadata(
    LampIssueResolutionProposal proposal, {
    required Map<String, Object?> equipment,
    required Map<int, String> officeLabelById,
    required Map<int, String> ownerLabelById,
    required Map<int, String> modelLabelById,
    required Map<int, String> contractLabelById,
  }) {
    final code = _toInt(equipment['code']);
    final description = _text(equipment['description']) ?? '';
    final assetNo = _text(equipment['asset_no']);
    final serialNo = _text(equipment['serial_no']);
    final stateName = _text(equipment['state_name']);
    final officeId = _toInt(equipment['office']);
    final ownerId = _toInt(equipment['owner']);
    final modelId = _toInt(equipment['model']);
    final contractId = _toInt(equipment['contract']);
    final contextMetadata = <String, Object?>{
      'rowContextCode': code,
      'rowContextDescription': description,
      'rowContextAssetNo': assetNo,
      'rowContextSerialNo': serialNo,
      'rowContextStateName': stateName,
      'rowContextOfficeId': officeId,
      'rowContextOfficeLabel': officeId == null
          ? null
          : officeLabelById[officeId],
      'rowContextOwnerId': ownerId,
      'rowContextOwnerLabel': ownerId == null ? null : ownerLabelById[ownerId],
      'rowContextModelId': modelId,
      'rowContextModelLabel': modelId == null ? null : modelLabelById[modelId],
      'rowContextContractId': contractId,
      'rowContextContractLabel': contractId == null
          ? null
          : contractLabelById[contractId],
    };
    return LampIssueResolutionProposal(
      issueType: proposal.issueType,
      issueIds: proposal.issueIds,
      sheet: proposal.sheet,
      row: proposal.row,
      column: proposal.column,
      originalValue: proposal.originalValue,
      proposedAction: proposal.proposedAction,
      proposedId: proposal.proposedId,
      proposedMatch: proposal.proposedMatch,
      confidence: proposal.confidence,
      options: proposal.options,
      notes: proposal.notes,
      metadata: <String, Object?>{...proposal.metadata, ...contextMetadata},
    );
  }

  LampIssueResolutionProposal _resolveUnknownIdReference({
    required Map<String, Object?> issue,
    required Map<String, Object?> equipment,
    required String column,
    required String original,
    required List<_ReferenceRow> offices,
    required List<Map<String, Object?>> owners,
    required List<_ReferenceRow> contracts,
    required Map<int, _ContractDetailRow> contractDetailsById,
    required List<_ReferenceRow> models,
    required Map<String, Map<int, int>> usageByColumn,
    required List<Map<String, Object?>> equipmentStatsRows,
  }) {
    final base = _baseProposal(
      LampIssueType.unknownId,
      issue,
      originalOverride: original,
    );
    final issueRaw = (_text(issue['raw_value']) ?? '').trim();
    final issueRawId = int.tryParse(issueRaw);
    if (issueRawId == null) {
      return base(
        action: LampIssueResolutionAction.unresolved,
        confidence: 0,
        notes:
            'Το άγνωστο αναγνωριστικό δεν είναι έγκυρος αριθμός για στοχευμένη επανασύνδεση.',
      );
    }

    final equipmentOffice = _toInt(equipment['office']);
    final equipmentOwner = _toInt(equipment['owner']);
    final equipmentModel = _toInt(equipment['model']);
    final equipmentContract = _toInt(equipment['contract']);
    final ownerOfficeById = <int, int?>{
      for (final owner in owners)
        if (_toInt(owner['owner']) != null)
          _toInt(owner['owner'])!: _toInt(owner['office']),
    };
    final rowsByColumn = <String, List<_ReferenceRow>>{
      'office': offices,
      'contract': contracts,
      'model': models,
      'owner': <_ReferenceRow>[
        for (final owner in owners)
          if (_toInt(owner['owner']) != null)
            _ReferenceRow(
              id: _toInt(owner['owner'])!,
              label: _ownerLabel(owner),
              normalized: _normalizeReferenceText(_ownerLabel(owner)),
            ),
      ],
    };
    final references = rowsByColumn[column] ?? const <_ReferenceRow>[];
    if (references.isEmpty) {
      return base(
        action: LampIssueResolutionAction.unresolved,
        confidence: 0,
        notes:
            'Δεν υπάρχουν διαθέσιμες εγγραφές αναφοράς για επανασύνδεση του πεδίου `$column`.',
      );
    }

    final currentUsage = usageByColumn[column] ?? const <int, int>{};
    final candidates = <_UnknownIdCandidate>[];
    for (final ref in references) {
      final reasons = <String>[];
      var score = (currentUsage[ref.id] ?? 0).clamp(0, 30).toInt();
      switch (column) {
        case 'owner':
          final ownerOffice = ownerOfficeById[ref.id];
          if (equipmentOffice != null &&
              ownerOffice != null &&
              ownerOffice == equipmentOffice) {
            score += 60;
            reasons.add(
              'Ίδιο γραφείο με τον εξοπλισμό (${equipmentOffice.toString()}).',
            );
          }
          if (equipmentModel != null &&
              _coUsageCount(
                    equipmentStatsRows,
                    primaryColumn: 'model',
                    primaryId: equipmentModel,
                    targetColumn: 'owner',
                    targetId: ref.id,
                  ) >
                  0) {
            score += 20;
            reasons.add(
              'Ο ιδιοκτήτης εμφανίζεται σε εξοπλισμό του ίδιου μοντέλου.',
            );
          }
          break;
        case 'contract':
          if (equipmentModel != null &&
              _coUsageCount(
                    equipmentStatsRows,
                    primaryColumn: 'model',
                    primaryId: equipmentModel,
                    targetColumn: 'contract',
                    targetId: ref.id,
                  ) >
                  0) {
            score += 55;
            reasons.add(
              'Το συμβόλαιο χρησιμοποιείται σε εξοπλισμό του ίδιου μοντέλου.',
            );
          }
          if (equipmentOffice != null &&
              _coUsageCount(
                    equipmentStatsRows,
                    primaryColumn: 'office',
                    primaryId: equipmentOffice,
                    targetColumn: 'contract',
                    targetId: ref.id,
                  ) >
                  0) {
            score += 25;
            reasons.add(
              'Το συμβόλαιο χρησιμοποιείται στο ίδιο γραφείο εξοπλισμού.',
            );
          }
          break;
        case 'office':
          final ownerOffice = equipmentOwner == null
              ? null
              : ownerOfficeById[equipmentOwner];
          if (ownerOffice != null && ownerOffice == ref.id) {
            score += 60;
            reasons.add(
              'Ταιριάζει με το γραφείο του τρέχοντος ιδιοκτήτη εξοπλισμού.',
            );
          }
          if (equipmentContract != null &&
              _coUsageCount(
                    equipmentStatsRows,
                    primaryColumn: 'contract',
                    primaryId: equipmentContract,
                    targetColumn: 'office',
                    targetId: ref.id,
                  ) >
                  0) {
            score += 20;
            reasons.add(
              'Το γραφείο εμφανίζεται με ίδιο συμβόλαιο σε άλλες εγγραφές.',
            );
          }
          break;
        case 'model':
          if (equipmentContract != null &&
              _coUsageCount(
                    equipmentStatsRows,
                    primaryColumn: 'contract',
                    primaryId: equipmentContract,
                    targetColumn: 'model',
                    targetId: ref.id,
                  ) >
                  0) {
            score += 55;
            reasons.add(
              'Το μοντέλο χρησιμοποιείται σε εξοπλισμό του ίδιου συμβολαίου.',
            );
          }
          if (equipmentOffice != null &&
              _coUsageCount(
                    equipmentStatsRows,
                    primaryColumn: 'office',
                    primaryId: equipmentOffice,
                    targetColumn: 'model',
                    targetId: ref.id,
                  ) >
                  0) {
            score += 20;
            reasons.add(
              'Το μοντέλο χρησιμοποιείται στο ίδιο γραφείο εξοπλισμού.',
            );
          }
          break;
      }

      if (column == 'contract') {
        final details = contractDetailsById[ref.id];
        if (details != null &&
            (details.contractName.contains(issueRaw) ||
                (details.supplierName?.contains(issueRaw) ?? false) ||
                (details.categoryName?.contains(issueRaw) ?? false))) {
          score += 15;
          reasons.add(
            'Ο αριθμός εμφανίζεται σε όνομα/κατηγορία/προμηθευτή συμβολαίου.',
          );
        }
      }

      final finalLabel = column == 'contract'
          ? _contractDisplayLabel(
              contractDetailsById[ref.id] ??
                  _ContractDetailRow(id: ref.id, contractName: ref.label),
            )
          : ref.label;
      candidates.add(
        _UnknownIdCandidate(
          id: ref.id,
          label: finalLabel,
          score: score,
          reasons: reasons,
        ),
      );
    }

    candidates.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.id.compareTo(b.id);
    });
    final top = candidates.take(8).toList();
    final options = <LampIssueResolutionOption>[
      for (final candidate in top)
        LampIssueResolutionOption(
          id: 'unknown_${column}_${candidate.id}',
          label: '${candidate.id} · ${candidate.label}',
          description: candidate.reasons.isEmpty
              ? 'Χωρίς ισχυρή συσχέτιση· επιλέξτε μόνο με επιχειρησιακή επιβεβαίωση.'
              : candidate.reasons.join(' '),
          action: LampIssueResolutionAction.autoFix,
          proposedId: candidate.id,
          proposedMatch: candidate.label,
          metadata: <String, Object?>{
            'operation': 'update_equipment_fk',
            'fkColumn': column,
            'proposedId': candidate.id,
          },
        ),
    ];
    if (options.isEmpty) {
      return base(
        action: LampIssueResolutionAction.unresolved,
        confidence: 0,
        notes:
            'Δεν βρέθηκαν υποψήφιες επανασυνδέσεις για το άγνωστο αναγνωριστικό $issueRawId στο πεδίο `$column`.',
      );
    }
    final first = top.first;
    return base(
      action: LampIssueResolutionAction.manualReview,
      proposedId: first.id,
      proposedMatch: first.label,
      confidence: first.score.clamp(15, 95),
      notes:
          'Ασύμβατο αναγνωριστικό `$issueRawId` στο πεδίο `$column`. Προτείνονται μόνο επιλογές επανασύνδεσης και απαιτείται χειροκίνητη επιβεβαίωση.',
      metadata: <String, Object?>{
        'unknownId': issueRawId,
        'unknownColumn': column,
      },
      options: options,
    );
  }

  Map<String, Map<int, int>> _buildFkUsageByColumn(
    List<Map<String, Object?>> equipmentRows,
  ) {
    final usage = <String, Map<int, int>>{
      'owner': <int, int>{},
      'contract': <int, int>{},
      'office': <int, int>{},
      'model': <int, int>{},
    };
    for (final row in equipmentRows) {
      for (final column in usage.keys) {
        final id = _toInt(row[column]);
        if (id == null) continue;
        final map = usage[column]!;
        map[id] = (map[id] ?? 0) + 1;
      }
    }
    return usage;
  }

  int _coUsageCount(
    List<Map<String, Object?>> equipmentRows, {
    required String primaryColumn,
    required int primaryId,
    required String targetColumn,
    required int targetId,
  }) {
    var count = 0;
    for (final row in equipmentRows) {
      if (_toInt(row[primaryColumn]) != primaryId) continue;
      if (_toInt(row[targetColumn]) != targetId) continue;
      count++;
    }
    return count;
  }

  String _contractDisplayLabel(_ContractDetailRow details) {
    final parts = <String>[
      details.contractName,
      if (details.supplierName != null && details.supplierName!.isNotEmpty)
        'προμηθευτής=${details.supplierName}',
      if (details.categoryName != null && details.categoryName!.isNotEmpty)
        'κατηγορία=${details.categoryName}',
    ];
    return parts.where((p) => p.trim().isNotEmpty).join(' · ');
  }

  String _officeDisplayLabel(_OfficeDetailRow details) {
    final preferred = _firstInformativeText(
      details.departmentName,
      details.officeName,
      details.organizationName,
    );
    if (preferred != null) return preferred;
    return details.officeName ??
        details.departmentName ??
        details.organizationName ??
        '';
  }

  String _modelDisplayLabel(_ModelDetailRow details) {
    final baseName = _firstInformativeText(
      details.modelName,
      details.subcategoryName,
      details.categoryName,
    );
    final manufacturer = details.manufacturerName?.trim();
    final parts = <String>[
      ?baseName,
      if (manufacturer != null && manufacturer.isNotEmpty)
        'κατασκευαστής=$manufacturer',
    ];
    if (parts.isEmpty) {
      return details.modelName ??
          details.subcategoryName ??
          details.categoryName ??
          '';
    }
    return parts.join(' · ');
  }

  String? _firstInformativeText(String? a, String? b, String? c) {
    final candidates = <String?>[a, b, c];
    for (final candidate in candidates) {
      final text = candidate?.trim();
      if (text == null || text.isEmpty) continue;
      if (_looksNumericOnly(text)) continue;
      return text;
    }
    return null;
  }

  bool _looksNumericOnly(String value) {
    return RegExp(r'^[0-9\-\s]+$').hasMatch(value.trim());
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
            'Αριθμητικό αναγνωριστικό κατόχου που δεν υπάρχει· παραμένει για χειροκίνητη απόφαση.',
      );
    }

    final normalizedParts = normalized
        .split(' ')
        .where((p) => p.isNotEmpty)
        .toList();
    final originalParts = _ownerOriginalParts(original);
    final metadata = <String, Object?>{
      'operation': 'update_equipment_fk',
      'fkColumn': 'owner',
      'referenceTable': 'owners',
      'idColumn': 'owner',
      'labelColumn': 'last_name',
      'createLabel': 'last_name',
    };

    if (normalizedParts.length == 1) {
      final matches = owners.where((owner) {
        return _normalizeReferenceText(_text(owner['last_name']) ?? '') ==
            normalizedParts.single;
      }).toList();
      final preferredLastName = originalParts.isNotEmpty
          ? originalParts.single
          : original;
      if (matches.isEmpty) {
        return base(
          action: LampIssueResolutionAction.createNew,
          proposedMatch:
              'υπάλληλος (επώνυμο=$preferredLastName, μικρό όνομα=κενό)',
          confidence: 70,
          notes:
              'Μονολεκτικός υπάλληλος χωρίς αντιστοίχιση· προτείνεται νέος υπάλληλος.',
          metadata: <String, Object?>{
            ...metadata,
            'createValue': original,
            'createOwnerLastName': preferredLastName,
          },
        );
      }
      return base(
        action: LampIssueResolutionAction.manualReview,
        proposedId: matches.length == 1 ? _toInt(matches.first['owner']) : null,
        proposedMatch: matches.length == 1 ? _ownerLabel(matches.first) : null,
        confidence: matches.length == 1 ? 76 : 52,
        notes: 'Μονολεκτικός υπάλληλος ως επώνυμο· απαιτείται επιβεβαίωση.',
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

    if (originalParts.length == 2) {
      final candidatePairs = <({String lastName, String firstName})>[
        (lastName: originalParts[0], firstName: originalParts[1]),
        if (originalParts[0] != originalParts[1])
          (lastName: originalParts[1], firstName: originalParts[0]),
      ];
      final seenOwnerIds = <int>{};
      final linkExistingOptions = <LampIssueResolutionOption>[];
      for (final pair in candidatePairs) {
        final identityKey = UserIdentityNormalizer.identityKeyForPerson(
          pair.firstName,
          pair.lastName,
        );
        if (identityKey.isEmpty) continue;
        for (final owner in owners) {
          final ownerId = _toInt(owner['owner']);
          if (ownerId == null || seenOwnerIds.contains(ownerId)) continue;
          final ownerIdentityKey = _ownerIdentityKeyFromRow(owner);
          if (ownerIdentityKey != identityKey) continue;
          seenOwnerIds.add(ownerId);
          linkExistingOptions.add(
            LampIssueResolutionOption(
              id: 'owner_link_$ownerId',
              label: 'Σύνδεση με υπάρχον: $ownerId · ${_ownerLabel(owner)}',
              action: LampIssueResolutionAction.autoFix,
              proposedId: ownerId,
              proposedMatch: _ownerLabel(owner),
              metadata: <String, Object?>{...metadata, 'proposedId': ownerId},
            ),
          );
        }
      }
      final createOwnerOptions = <LampIssueResolutionOption>[
        for (final pair in candidatePairs)
          _createOwnerOption(
            id: 'owner_create_${pair.lastName}_${pair.firstName}',
            lastName: pair.lastName,
            firstName: pair.firstName,
            originalLabel: original,
          ),
      ];
      final manualEditOption = LampIssueResolutionOption(
        id: 'owner_manual_edit',
        label: 'Τροποποίηση',
        description:
            'Χειροκίνητη διόρθωση ονόματος (μορφή: επώνυμο, μικρό όνομα).',
        action: LampIssueResolutionAction.createNew,
        requiresTextInput: true,
        inputLabel: 'Επώνυμο, μικρό όνομα',
        metadata: <String, Object?>{
          'operation': 'create_owner_and_update_equipment',
          'allowManualNameInput': true,
          'createOwnerLastName': originalParts[0],
          'createOwnerFirstName': originalParts[1],
        },
      );
      final allOptions = <LampIssueResolutionOption>[
        ...linkExistingOptions,
        ...createOwnerOptions,
        manualEditOption,
      ];
      final singleLink = linkExistingOptions.length == 1
          ? linkExistingOptions.single
          : null;
      return base(
        action: LampIssueResolutionAction.manualReview,
        proposedId: singleLink?.proposedId,
        proposedMatch: singleLink?.proposedMatch,
        confidence: linkExistingOptions.isNotEmpty ? 86 : 45,
        notes: linkExistingOptions.isNotEmpty
            ? 'Διμερής τιμή υπαλλήλου· βρέθηκε ισοδύναμο ονοματεπώνυμο σε υπάρχοντα υπάλληλο.'
            : 'Διμερής τιμή υπαλλήλου· απαιτείται επιλογή μικρού ονόματος/επωνύμου.',
        options: allOptions,
      );
    }

    return base(
      action: LampIssueResolutionAction.manualReview,
      confidence: 30,
      notes: 'Σύνθετη ή ασυνήθιστη τιμή υπαλλήλου· απαιτείται απόφαση.',
      options: <LampIssueResolutionOption>[
        _createOwnerOption(
          id: 'owner_create_full',
          lastName: original,
          firstName: null,
          originalLabel: original,
        ),
        LampIssueResolutionOption(
          id: 'owner_null_keep_note',
          label:
              'Αποσύνδεση υπαλλήλου και διατήρηση κειμένου στο original_text',
          action: LampIssueResolutionAction.autoFix,
          metadata: <String, Object?>{
            'operation': 'update_equipment_fk',
            'fkColumn': 'owner',
            'proposedId': null,
          },
        ),
        LampIssueResolutionOption(
          id: 'owner_null_clear_original',
          label: 'Αποσύνδεση υπαλλήλου και εκκαθάριση owner_original_text',
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
          ? 'Νέος υπάλληλος: επώνυμο=$lastName'
          : 'Νέος υπάλληλος: επώνυμο=$lastName, μικρό όνομα=$firstName',
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
            'Αριθμητικό ασύμβατο αναγνωριστικό χωρίς αντιστοίχιση σε αναγνωριστικό '
            'ή όνομα συμβολαίου.',
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
            proposedMatch: 'δείκτης κύριου εξοπλισμού = κενό',
            confidence: 98,
            notes: 'Ασφαλής εκκαθάριση αυτοαναφοράς κύριου εξοπλισμού.',
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
                    'Σπάσιμο στον κωδικό $code (${descriptionByCode[code] ?? ''})',
                description:
                    'Θέτει κενό τον δείκτη κύριου εξοπλισμού για κωδικό $code.',
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
    LampIssueResolutionDecision decision, {
    required ResolutionLogSink emit,
  }) async {
    final proposal = decision.proposal;
    final option = decision.option;
    final metadata = option?.metadata ?? proposal.metadata;
    final operation = metadata['operation']?.toString();
    var created = false;

    if (proposal.proposedAction == LampIssueResolutionAction.createNew &&
        option == null) {
      await _createReferenceAndUpdateEquipment(txn, proposal, emit: emit);
      created = true;
      await _deleteIssues(txn, proposal.issueIds, emit: emit);
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
        final fkSpec = _fkSpec(fkColumn);
        if (fkColumn == 'owner' && proposedId != null) {
          await _updateEquipmentOwner(
            txn,
            code: code,
            ownerId: proposedId,
            clearOriginalText: true,
            emit: emit,
          );
        } else {
          final values = <String, Object?>{fkColumn: proposedId};
          if (fkSpec != null && proposedId != null) {
            values[fkSpec.originalColumn] = null;
          }
          await txn.update(
            'equipment',
            values,
            where: 'code = ?',
            whereArgs: <Object?>[code],
          );
          emit(
            ResolutionLogEntry.success(
              'Ενημερώθηκε η στήλη $fkColumn του εξοπλισμού $code σε $proposedId.',
            ),
          );
        }
      case 'create_owner_and_update_equipment':
        final code = proposal.row;
        if (code == null) throw StateError('Λείπει κωδικός εξοπλισμού.');
        var lastName = _text(metadata['createOwnerLastName']);
        var firstName = _text(metadata['createOwnerFirstName']);
        final allowsManualNameInput = metadata['allowManualNameInput'] == true;
        if (allowsManualNameInput) {
          final parsed = _parseOwnerNameInput(decision.textInput);
          if (parsed == null) {
            throw StateError(
              'Η "Τροποποίηση" απαιτεί μορφή: επώνυμο, μικρό όνομα.',
            );
          }
          lastName = parsed.lastName;
          firstName = parsed.firstName;
        }
        final equipmentOfficeRows = await txn.query(
          'equipment',
          columns: <String>['office'],
          where: 'code = ?',
          whereArgs: <Object?>[code],
          limit: 1,
        );
        final equipmentOffice = equipmentOfficeRows.isEmpty
            ? null
            : _toInt(equipmentOfficeRows.first['office']);

        var ownerId = await _existingOwnerIdByIdentity(
          txn,
          lastName: lastName,
          firstName: firstName,
        );
        if (ownerId != null) {
          emit(
            ResolutionLogEntry.success(
              'Βρέθηκε ισοδύναμος υπάρχων υπάλληλος: id=$ownerId. '
              'Θα γίνει σύνδεση χωρίς νέα δημιουργία.',
            ),
          );
        } else {
          ownerId = await _nextId(txn, 'owners', 'owner');
          await txn.insert('owners', <String, Object?>{
            'owner': ownerId,
            'last_name': lastName,
            'first_name': firstName,
            'office': equipmentOffice,
          });
          emit(
            ResolutionLogEntry.success(
              'Δημιουργήθηκε νέος υπάλληλος: id=$ownerId, '
              'επώνυμο=${lastName ?? '(κενό)'}, '
              'μικρό όνομα=${firstName ?? '(χωρίς μικρό όνομα)'}, '
              'γραφείο=${equipmentOffice ?? '(κενό)'}.',
            ),
          );
          created = true;
        }
        await _updateEquipmentOwner(
          txn,
          code: code,
          ownerId: ownerId,
          emit: emit,
        );
      case 'update_equipment_owner_null_clear_original':
        final code = proposal.row;
        if (code == null) throw StateError('Λείπει κωδικός εξοπλισμού.');
        await txn.update(
          'equipment',
          <String, Object?>{'owner': null, 'owner_original_text': null},
          where: 'code = ?',
          whereArgs: <Object?>[code],
        );
        emit(
          ResolutionLogEntry.success(
            'Αποσυνδέθηκε ο υπάλληλος και εκκαθαρίστηκε το αρχικό κείμενο για τον εξοπλισμό $code.',
          ),
        );
      case 'clear_set_master':
        final code = metadata['code'];
        await txn.update(
          'equipment',
          <String, Object?>{'set_master': null},
          where: 'code = ?',
          whereArgs: <Object?>[code],
        );
        emit(
          ResolutionLogEntry.success(
            'Εκκαθαρίστηκε ο δείκτης κύριου εξοπλισμού για τον κωδικό $code.',
          ),
        );
        await txn.delete(
          'data_issues',
          where: 'issue_type = ? AND row_number = ? AND column_name = ?',
          whereArgs: <Object?>['set_master_cycle', code, 'set_master'],
        );
        emit(
          ResolutionLogEntry.success(
            'Αφαιρέθηκε η εγγραφή κύκλου κύριου εξοπλισμού για τον κωδικό $code.',
          ),
        );
      case 'clear_duplicate_asset_others':
        await txn.update(
          'equipment',
          <String, Object?>{'asset_no': null},
          where: 'asset_no = ? AND code <> ?',
          whereArgs: <Object?>[metadata['value'], metadata['keepCode']],
        );
        emit(
          ResolutionLogEntry.success(
            'Εκκαθαρίστηκαν διπλότυποι αριθμοί παγίου ${metadata['value']} εκτός από τον εξοπλισμό ${metadata['keepCode']}.',
          ),
        );
      case 'delete_duplicate_asset_others':
        await _deleteDuplicateEquipmentOthers(
          txn,
          keepCode: metadata['keepCode'] as int?,
          where: 'asset_no = ? AND code <> ?',
          whereArgs: <Object?>[metadata['value'], metadata['keepCode']],
          emit: emit,
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
        emit(
          ResolutionLogEntry.success(
            'Ενημερώθηκε ο αριθμός παγίου του εξοπλισμού ${metadata['targetCode']} σε $value.',
          ),
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
        emit(
          ResolutionLogEntry.success(
            'Εκκαθαρίστηκαν διπλότυπα serial_no ${metadata['serialNo']} για μοντέλο ${metadata['model']} εκτός από τον εξοπλισμό ${metadata['keepCode']}.',
          ),
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
          emit: emit,
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
        emit(
          ResolutionLogEntry.success(
            'Ενημερώθηκε το serial_no του εξοπλισμού ${metadata['targetCode']} σε $value.',
          ),
        );
      default:
        if (proposal.proposedAction == LampIssueResolutionAction.autoFix) {
          final fkColumn = proposal.metadata['fkColumn']?.toString();
          if (fkColumn != null && proposal.row != null) {
            final rowCode = proposal.row!;
            final pid = proposal.proposedId;
            final fallbackFkSpec = _fkSpec(fkColumn);
            if (fkColumn == 'owner' && pid != null) {
              await _updateEquipmentOwner(
                txn,
                code: rowCode,
                ownerId: pid,
                clearOriginalText: true,
                emit: emit,
              );
            } else {
              final values = <String, Object?>{fkColumn: pid};
              if (fallbackFkSpec != null && pid != null) {
                values[fallbackFkSpec.originalColumn] = null;
              }
              await txn.update(
                'equipment',
                values,
                where: 'code = ?',
                whereArgs: <Object?>[rowCode],
              );
              emit(
                ResolutionLogEntry.success(
                  'Ενημερώθηκε η στήλη $fkColumn του εξοπλισμού $rowCode σε $pid.',
                ),
              );
            }
          } else {
            throw StateError(
              'Δεν υπάρχει εφαρμόσιμη ενέργεια για την πρόταση.',
            );
          }
        } else {
          throw StateError('Δεν υπάρχει εφαρμόσιμη ενέργεια για την πρόταση.');
        }
    }

    await _deleteIssues(txn, proposal.issueIds, emit: emit);
    return _AppliedDecision(created: created);
  }

  Future<void> _createReferenceAndUpdateEquipment(
    Transaction txn,
    LampIssueResolutionProposal proposal, {
    required ResolutionLogSink emit,
  }) async {
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
    emit(
      ResolutionLogEntry.success(
        'Δημιουργήθηκε νέα εγγραφή στον πίνακα $table: '
        '$idColumn=$id, $labelColumn=${createValue ?? '(κενό)'}.',
      ),
    );
    await txn.update(
      'equipment',
      <String, Object?>{
        fkColumn: id,
        if (_fkSpec(fkColumn) != null) _fkSpec(fkColumn)!.originalColumn: null,
      },
      where: 'code = ?',
      whereArgs: <Object?>[code],
    );
    emit(
      ResolutionLogEntry.success(
        'Ενημερώθηκε η στήλη $fkColumn του εξοπλισμού $code σε $id.',
      ),
    );
  }

  Future<void> _deleteDuplicateEquipmentOthers(
    Transaction txn, {
    required int? keepCode,
    required String where,
    required List<Object?> whereArgs,
    required ResolutionLogSink emit,
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
      emit(
        ResolutionLogEntry.success(
          'Μεταφέρθηκαν οι παιδικές εγγραφές του εξοπλισμού $code στον κύριο εξοπλισμό $keepCode.',
        ),
      );
      await txn.delete(
        'equipment',
        where: 'code = ?',
        whereArgs: <Object?>[code],
      );
      emit(
        ResolutionLogEntry.success(
          'Διαγράφηκε διπλότυπη εγγραφή εξοπλισμού με κωδικό $code.',
        ),
      );
    }
  }

  Future<void> _deleteIssues(
    Transaction txn,
    List<int> ids, {
    required ResolutionLogSink emit,
  }) async {
    if (ids.isEmpty) return;
    final placeholders = List<String>.filled(ids.length, '?').join(',');
    await txn.delete(
      'data_issues',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
    emit(
      ResolutionLogEntry.success(
        'Αφαιρέθηκαν ${ids.length} εγγραφές από τον πίνακα data_issues.',
      ),
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

  String _ownerIdentityKeyFromRow(Map<String, Object?> owner) {
    return UserIdentityNormalizer.identityKeyForPerson(
      _text(owner['first_name']),
      _text(owner['last_name']),
    );
  }

  List<String> _ownerOriginalParts(String original) {
    final cleaned = original.replaceAll(RegExp(r'[-/()\\]+'), ' ').trim();
    if (cleaned.isEmpty) return const <String>[];
    return cleaned
        .split(RegExp(r'\s+'))
        .where((part) => part.trim().isNotEmpty)
        .toList();
  }

  Future<void> _updateEquipmentOwner(
    Transaction txn, {
    required int code,
    required int ownerId,
    bool clearOriginalText = false,
    required ResolutionLogSink emit,
  }) async {
    final values = <String, Object?>{
      'owner': ownerId,
      if (clearOriginalText) 'owner_original_text': null,
    };
    await txn.update(
      'equipment',
      values,
      where: 'code = ?',
      whereArgs: <Object?>[code],
    );
    emit(
      ResolutionLogEntry.success(
        'Ενημερώθηκε ο υπάλληλος του εξοπλισμού $code σε $ownerId.',
      ),
    );
  }

  Future<int?> _existingOwnerIdByIdentity(
    DatabaseExecutor db, {
    required String? lastName,
    required String? firstName,
  }) async {
    final target = UserIdentityNormalizer.identityKeyForPerson(
      firstName,
      lastName,
    );
    if (target.isEmpty) return null;
    final rows = await db.query(
      'owners',
      columns: <String>['owner', 'last_name', 'first_name'],
    );
    for (final row in rows) {
      final ownerId = _toInt(row['owner']);
      if (ownerId == null) continue;
      if (_ownerIdentityKeyFromRow(row) == target) return ownerId;
    }
    return null;
  }

  ({String lastName, String firstName})? _parseOwnerNameInput(String? raw) {
    final input = raw?.trim() ?? '';
    if (input.isEmpty) return null;
    final commaParts = input
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (commaParts.length >= 2) {
      final lastName = commaParts.first;
      final firstName = commaParts.sublist(1).join(' ').trim();
      if (lastName.isEmpty || firstName.isEmpty) return null;
      return (lastName: lastName, firstName: firstName);
    }

    final wsParts = input
        .split(RegExp(r'\s+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (wsParts.length < 2) return null;
    final lastName = wsParts.first;
    final firstName = wsParts.sublist(1).join(' ').trim();
    if (lastName.isEmpty || firstName.isEmpty) return null;
    return (lastName: lastName, firstName: firstName);
  }

  String _equipmentSummary(Map<String, Object?> row) {
    return 'κωδικός=${row['code']} · ${_text(row['description']) ?? '-'} · '
        'μοντέλο=${row['model'] ?? '-'} · σειριακός=${row['serial_no'] ?? '-'} · '
        'γραφείο=${row['office'] ?? '-'} · υπάλληλος=${row['owner'] ?? '-'}';
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

  String? _issueEntityType(Map<String, Object?> issue) {
    final explicit = _text(issue['entity_type'])?.toLowerCase();
    if (explicit != null) return explicit;
    final legacySheet = _text(issue['sheet'])?.toLowerCase();
    if (legacySheet == 'integrity_scan') {
      return 'equipment';
    }
    return legacySheet;
  }

  String? _issueOrigin(Map<String, Object?> issue) {
    final explicit = _text(issue['origin'])?.toLowerCase();
    if (explicit != null) return explicit;
    final legacySheet = _text(issue['sheet'])?.toLowerCase();
    if (legacySheet == 'integrity_scan') {
      return 'integrity_scan';
    }
    return 'manual';
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

class _ContractDetailRow {
  const _ContractDetailRow({
    required this.id,
    required this.contractName,
    this.supplierName,
    this.categoryName,
  });

  final int id;
  final String contractName;
  final String? supplierName;
  final String? categoryName;
}

class _OfficeDetailRow {
  const _OfficeDetailRow({
    required this.id,
    this.officeName,
    this.departmentName,
    this.organizationName,
  });

  final int id;
  final String? officeName;
  final String? departmentName;
  final String? organizationName;
}

class _ModelDetailRow {
  const _ModelDetailRow({
    required this.id,
    this.modelName,
    this.manufacturerName,
    this.categoryName,
    this.subcategoryName,
  });

  final int id;
  final String? modelName;
  final String? manufacturerName;
  final String? categoryName;
  final String? subcategoryName;
}

class _UnknownIdCandidate {
  const _UnknownIdCandidate({
    required this.id,
    required this.label,
    required this.score,
    required this.reasons,
  });

  final int id;
  final String label;
  final int score;
  final List<String> reasons;
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
