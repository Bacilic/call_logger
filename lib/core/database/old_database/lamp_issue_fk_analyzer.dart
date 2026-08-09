import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../utils/user_identity_normalizer.dart';
import 'lamp_data_issue_type_labels.dart';
import 'lamp_issue_matching_engine.dart';
import 'lamp_issue_resolution_models.dart';
import 'lamp_issue_resolution_support.dart';
import 'lamp_owner_name_similarity.dart';
import 'lamp_place_suggestion.dart';
import 'lamp_reference_labels.dart';
import 'lamp_reference_name_match.dart';

class LampIssueFkAnalyzer {
  LampIssueFkAnalyzer(this._matching, this._support);

  final LampIssueMatchingEngine _matching;
  final LampIssueResolutionSupport _support;

  Future<List<LampIssueResolutionProposal>> analyzeFkIssues(
    Database db,
    LampIssueType issueType,
  ) async {
    final issues = await _support.openIssues(db, issueType);
    final proposals = <LampIssueResolutionProposal>[];

    final offices = await _support.referenceRows(
      db,
      table: 'offices',
      idColumn: 'office',
      labelColumn: 'office_name',
    );
    final owners = await db.query(
      'owners',
      columns: <String>['owner', 'last_name', 'first_name', 'office'],
    );
    final contracts = await _support.referenceRows(
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
        if (_support.toInt(row['contract']) != null)
          _support.toInt(row['contract'])!: _ContractDetailRow(
            id: _support.toInt(row['contract'])!,
            contractName: _support.text(row['contract_name']) ?? '',
            supplierName: _support.text(row['supplier_name']),
            categoryName: _support.text(row['category_name']),
          ),
    };
    final models = await _support.referenceRows(
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
        if (_support.toInt(row['office']) != null)
          _support.toInt(row['office'])!: _OfficeDetailRow(
            id: _support.toInt(row['office'])!,
            officeName: _support.text(row['office_name']),
            departmentName: _support.text(row['department_name']),
            organizationName: _support.text(row['organization_name']),
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
        if (_support.toInt(row['model']) != null)
          _support.toInt(row['model'])!: _ModelDetailRow(
            id: _support.toInt(row['model'])!,
            modelName: _support.text(row['model_name']),
            manufacturerName: _support.text(row['manufacturer_name']),
            categoryName: _support.text(row['category_name']),
            subcategoryName: _support.text(row['subcategory_name']),
          ),
    };
    final equipmentStatsRows = await db.query(
      'equipment',
      columns: <String>['model', 'contract', 'owner', 'office'],
    );
    final usageByColumn = _buildFkUsageByColumn(equipmentStatsRows);

    /// Οντότητες που δεν τις χρησιμοποιεί κανένας εξοπλισμός.
    ///
    /// Στη λίστα υποψηφίων σημαίνονται με σπασμένο σύνδεσμο: συνήθως
    /// απορρίπτονται, και η ένδειξη γλιτώνει τον χρήστη από το να το
    /// ανακαλύψει αφού διαλέξει.
    Set<int> unlinkedIdsFor(String column) {
      final usage = usageByColumn[column] ?? const <int, int>{};
      final all = switch (column) {
        'owner' => owners.map((row) => _support.toInt(row['owner'])),
        'office' => offices.map((row) => row.id),
        _ => const Iterable<int?>.empty(),
      };
      return <int>{
        for (final id in all)
          if (id != null && (usage[id] ?? 0) == 0) id,
      };
    }

    final officeLabelById = <int, String>{
      for (final row in offices)
        row.id: _officeDisplayLabel(
          officeDetailsById[row.id] ??
              _OfficeDetailRow(id: row.id, officeName: row.label),
        ),
    };
    // Το γραφείο μπαίνει δίπλα στο όνομα: όταν δύο υποψήφιοι λέγονται
    // «Παπαβασιλείου», είναι συχνά το μόνο κριτήριο επιλογής.
    final ownerLabelById = <int, String>{
      for (final row in owners)
        if (_support.toInt(row['owner']) != null)
          _support.toInt(row['owner'])!: lampOwnerDisplayLabel(
            lastName: _support.text(row['last_name']),
            firstName: _support.text(row['first_name']),
            officeName:
                officeDetailsById[_support.toInt(row['office'])]?.officeName,
            departmentName: officeDetailsById[_support.toInt(row['office'])]
                ?.departmentName,
          ),
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
      final base = _support.baseProposal(issueType, issue);
      final entityType = _support.issueEntityType(issue);
      final origin = _support.issueOrigin(issue);
      final rowRaw = issue['row_number'];
      final row = _support.toInt(rowRaw);
      final columnRaw = _support.text(issue['column_name']);
      final column = columnRaw?.toLowerCase();
      if (entityType != 'equipment' || row == null || column == null) {
        final reasons = <String>[
          if (entityType != 'equipment')
            'Το `entity_type` δεν είναι `equipment` '
                '(τρέχουσα τιμή: `${entityType ?? '(κενό)'}`).',
          if (row == null)
            'Το `row_number` λείπει ή δεν είναι έγκυρος ακέραιος '
                '(τρέχουσα τιμή: `${_support.text(rowRaw) ?? '(κενό)'}`).',
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
              'diagnosticSheet': _support.text(issue['sheet']) ?? '(κενό)',
              'diagnosticRowNumberRaw': rowRaw?.toString() ?? '(κενό)',
              'diagnosticColumn': columnRaw ?? '(κενό)',
              'diagnosticReasons': reasons,
            },
          ),
        );
        continue;
      }

      final equipment = await _support.equipmentByCode(db, row);
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

      final spec = _support.fkSpec(column);
      if (spec == null) {
        final reasons = <String>[
          'Η στήλη αναφοράς `column` δεν υποστηρίζεται για επίλυση FK '
              '(τρέχουσα τιμή: `${columnRaw ?? '(κενό)'}`, υποστηριζόμενες: '
              '${lampDataIssueColumnDisplayLabel('office')}, '
              '${lampDataIssueColumnDisplayLabel('owner')}, '
              '${lampDataIssueColumnDisplayLabel('contract')}, '
              '${lampDataIssueColumnDisplayLabel('model')}).',
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
              'diagnosticSheet': _support.text(issue['sheet']) ?? '(κενό)',
              'diagnosticRowNumberRaw': rowRaw?.toString() ?? '(κενό)',
              'diagnosticColumn': columnRaw ?? '(κενό)',
              'diagnosticReasons': reasons,
            },
          ),
        );
        continue;
      }

      final original = _support.originalText(
        equipment,
        spec.originalColumn,
        issue['raw_value'],
      );
      final normalized = _matching.normalizeReferenceText(original);
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

      // Το FK λύθηκε ήδη — σε προηγούμενη συνεδρία ή σε άλλο βήμα. Το πρόβλημα
      // είναι φάντασμα και δεν αξίζει ερώτηση: κλείνει μόνο του στην αυτόματη
      // παρτίδα, με γραμμή στο ημερολόγιο ώστε να φαίνεται τι έγινε.
      final resolvedFkId = _support.toInt(equipment[column]);
      if (resolvedFkId != null &&
          _fkTargetIds(
            column,
            offices: offices,
            owners: owners,
            contracts: contracts,
            models: models,
          ).contains(resolvedFkId)) {
        proposals.add(
          withEquipmentContext(
            base(
              action: LampIssueResolutionAction.autoFix,
              proposedId: resolvedFkId,
              confidence: 100,
              notes:
                  'Το πεδίο δείχνει ήδη σε έγκυρη εγγραφή ($resolvedFkId)· '
                  'το πρόβλημα έχει λυθεί και κλείνει.',
              metadata: <String, Object?>{
                'operation': 'close_resolved_fk_issue',
                'fkColumn': column,
              },
            ),
          ),
        );
        continue;
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
              detailedLabelById: officeLabelById,
              unlinkedReferenceIds: unlinkedIdsFor('office'),
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
              ownerLabelById: ownerLabelById,
              unlinkedOwnerIds: unlinkedIdsFor('owner'),
              ownerEquipmentCounts:
                  usageByColumn['owner'] ?? const <int, int>{},
              // Η τιμή του υπαλλήλου είναι συχνά τμήμα ή γραφείο· χρειάζονται
              // τα πραγματικά γραφεία και το πεδίο γραφείου του εξοπλισμού
              // για να δοθεί ο λόγος, χωρίς να αλλάξει τίποτα εκεί.
              placeRows: <LampPlaceRow>[
                for (final detail in officeDetailsById.values)
                  (
                    id: detail.id,
                    officeName: detail.officeName,
                    departmentName: detail.departmentName,
                  ),
              ],
              linkedOfficeId: _support.toInt(equipment['office']),
              officeRawValue: _support.text(equipment['office_original_text']),
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
              detailedLabelById: contractLabelById,
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
              detailedLabelById: modelLabelById,
            ),
          ),
        );
      }
    }

    return proposals;
  }

  String _referenceValueDisplayLabel({
    required String rawValue,
    int? id,
    Map<int, String>? detailedLabelById,
  }) {
    final trimmed = rawValue.trim();
    final parsedId = id ?? int.tryParse(trimmed);
    final detailed = parsedId != null && detailedLabelById != null
        ? detailedLabelById[parsedId]?.trim()
        : null;
    if (parsedId != null && detailed != null && detailed.isNotEmpty) {
      return '$parsedId · $detailed';
    }
    if (parsedId != null &&
        trimmed.isNotEmpty &&
        trimmed != parsedId.toString()) {
      return '$parsedId · $trimmed';
    }
    if (parsedId != null) return parsedId.toString();
    return trimmed.isEmpty ? '-' : trimmed;
  }

  Map<String, Object?> _referenceDisplayMetadata({
    required String original,
    int? proposedId,
    String? proposedMatch,
    Map<int, String>? detailedLabelById,
    required Map<String, Object?> base,
  }) {
    return <String, Object?>{
      ...base,
      'originalDisplayLabel': _referenceValueDisplayLabel(
        rawValue: original,
        detailedLabelById: detailedLabelById,
      ),
      if (proposedId != null ||
          (proposedMatch != null && proposedMatch.trim().isNotEmpty))
        'proposedDisplayLabel': _referenceValueDisplayLabel(
          rawValue: proposedMatch ?? '',
          id: proposedId,
          detailedLabelById: detailedLabelById,
        ),
    };
  }

  String _referenceOptionDisplayLabel(
    ReferenceRow match, {
    Map<int, String>? detailedLabelById,
  }) {
    final detailed = detailedLabelById?[match.id]?.trim();
    final name = (detailed != null && detailed.isNotEmpty)
        ? detailed
        : match.label.trim();
    if (name.isEmpty) return '${match.id}';
    return '${match.id} · $name';
  }

  LampIssueResolutionProposal _resolveNamedReference({
    required LampIssueType issueType,
    required Map<String, Object?> issue,
    required String original,
    required String normalized,
    required List<ReferenceRow> references,
    required String fkColumn,
    required String table,
    required String idColumn,
    required String labelColumn,
    required String createLabel,
    required int exactAutoConfidence,
    required bool fuzzyAllowed,
    Map<int, String>? detailedLabelById,
    Set<int> unlinkedReferenceIds = const <int>{},
  }) {
    final base = _support.baseProposal(
      issueType,
      issue,
      originalOverride: original,
    );
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
        metadata: _referenceDisplayMetadata(
          original: original,
          detailedLabelById: detailedLabelById,
          base: metadata,
        ),
        options: [
          for (final match in exact)
            LampIssueResolutionOption(
              id: 'fk_${match.id}',
              label: _referenceOptionDisplayLabel(
                match,
                detailedLabelById: detailedLabelById,
              ),
              description: 'Ακριβής αντιστοίχιση',
              action: LampIssueResolutionAction.autoFix,
              proposedId: match.id,
              proposedMatch: match.label,
              metadata: <String, Object?>{...metadata, 'proposedId': match.id},
            ),
        ],
      );
    }

    if (fuzzyAllowed && normalized.isNotEmpty) {
      final candidates = <FuzzyReferenceMatch>[];
      for (final ref in references) {
        if (ref.normalized.isEmpty) continue;
        final contains =
            ref.normalized.contains(normalized) ||
            normalized.contains(ref.normalized);
        final distance = _matching.levenshtein(normalized, ref.normalized);
        if (contains || distance < 3) {
          candidates.add(
            FuzzyReferenceMatch(
              ref,
              contains
                  ? _matching.substringContainmentScore()
                  : (100 - (distance * 20)).clamp(20, 95),
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
        final top = candidates.first;
        return base(
          action: LampIssueResolutionAction.manualReview,
          proposedId: top.reference.id,
          proposedMatch: top.reference.label,
          confidence: top.score,
          notes: 'Ασαφής αντιστοίχιση με κοντινό όνομα.',
          metadata: _referenceDisplayMetadata(
            original: original,
            proposedId: top.reference.id,
            proposedMatch: top.reference.label,
            detailedLabelById: detailedLabelById,
            base: metadata,
          ),
          options: [
            for (final candidate in candidates.take(5))
              LampIssueResolutionOption(
                id: 'fk_${candidate.reference.id}',
                label: _referenceOptionDisplayLabel(
                  candidate.reference,
                  detailedLabelById: detailedLabelById,
                ),
                // Μόνο η ομοιότητα: η απόσταση Levenshtein είναι εσωτερικό
                // μέγεθος του αλγορίθμου και λέει την ίδια πληροφορία σε
                // μορφή που δεν βοηθά ανθρώπινη απόφαση.
                description: 'Ομοιότητα: ${candidate.score}%',
                action: LampIssueResolutionAction.autoFix,
                proposedId: candidate.reference.id,
                proposedMatch: candidate.reference.label,
                metadata: <String, Object?>{
                  ...metadata,
                  'proposedId': candidate.reference.id,
                  if (unlinkedReferenceIds.contains(candidate.reference.id))
                    kLampOptionUnlinkedFlag: true,
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
    final code = _support.toInt(equipment['code']);
    final description = _support.text(equipment['description']) ?? '';
    final assetNo = _support.text(equipment['asset_no']);
    final serialNo = _support.text(equipment['serial_no']);
    final stateName = _support.text(equipment['state_name']);
    final officeId = _support.toInt(equipment['office']);
    final ownerId = _support.toInt(equipment['owner']);
    final modelId = _support.toInt(equipment['model']);
    final contractId = _support.toInt(equipment['contract']);
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
    required List<ReferenceRow> offices,
    required List<Map<String, Object?>> owners,
    required List<ReferenceRow> contracts,
    required Map<int, _ContractDetailRow> contractDetailsById,
    required List<ReferenceRow> models,
    required Map<String, Map<int, int>> usageByColumn,
    required List<Map<String, Object?>> equipmentStatsRows,
  }) {
    final base = _support.baseProposal(
      LampIssueType.unknownId,
      issue,
      originalOverride: original,
    );
    final issueRaw = (_support.text(issue['raw_value']) ?? '').trim();
    final issueRawId = int.tryParse(issueRaw);
    if (issueRawId == null) {
      return base(
        action: LampIssueResolutionAction.unresolved,
        confidence: 0,
        notes:
            'Το άγνωστο αναγνωριστικό δεν είναι έγκυρος αριθμός για στοχευμένη επανασύνδεση.',
      );
    }

    final equipmentOffice = _support.toInt(equipment['office']);
    final equipmentOwner = _support.toInt(equipment['owner']);
    final equipmentModel = _support.toInt(equipment['model']);
    final equipmentContract = _support.toInt(equipment['contract']);
    final ownerOfficeById = <int, int?>{
      for (final owner in owners)
        if (_support.toInt(owner['owner']) != null)
          _support.toInt(owner['owner'])!: _support.toInt(owner['office']),
    };
    final rowsByColumn = <String, List<ReferenceRow>>{
      'office': offices,
      'contract': contracts,
      'model': models,
      'owner': <ReferenceRow>[
        for (final owner in owners)
          if (_support.toInt(owner['owner']) != null)
            ReferenceRow(
              id: _support.toInt(owner['owner'])!,
              label: _support.ownerLabel(owner),
              normalized: _matching.normalizeReferenceText(
                _support.ownerLabel(owner),
              ),
            ),
      ],
    };
    final references = rowsByColumn[column] ?? const <ReferenceRow>[];
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

      // Η τιμή μπορεί να είναι το ΟΝΟΜΑ της εγγραφής και όχι αναγνωριστικό:
      // «30236» είναι η σύμβαση 231 «30236 18/12/2024». Ένδειξη πολύ
      // ισχυρότερη από τα συμφραζόμενα, γι' αυτό βαραίνει περισσότερο απ'
      // όλες τις άλλες μαζί.
      final nameMatch = lampReferenceNameMatch(
        rawValue: issueRaw,
        name: ref.label,
      );
      if (nameMatch != null) {
        score += nameMatch.score;
        reasons.add(nameMatch.reason);
      }

      if (column == 'contract' && nameMatch == null) {
        final details = contractDetailsById[ref.id];
        if (details != null &&
            ((details.supplierName?.contains(issueRaw) ?? false) ||
                (details.categoryName?.contains(issueRaw) ?? false))) {
          score += 15;
          reasons.add(
            'Ο αριθμός εμφανίζεται στην κατηγορία ή τον προμηθευτή του '
            'συμβολαίου.',
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
          nameMatch: nameMatch,
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
      // Όταν η σύμβαση όντως δεν υπάρχει — τιμή που ήρθε από το Excel και
      // δεν αντιστοιχεί σε τίποτα — ο χρήστης πρέπει να μπορεί να τη
      // δημιουργήσει εδώ, με προμηθευτή από τους ήδη καταχωρημένους.
      if (column == 'contract')
        LampIssueResolutionOption(
          id: 'contract_create',
          label: 'Δημιουργία σύμβασης «$issueRaw»',
          description:
              'Νέα εγγραφή με προμηθευτή και κατηγορία από τη βάση· '
              'ο εξοπλισμός συνδέεται μαζί της.',
          action: LampIssueResolutionAction.createNew,
          requiresContractInput: true,
          metadata: <String, Object?>{
            'operation': 'create_contract_and_update_equipment',
            'createContractName': issueRaw,
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
      notes: first.nameMatch != null
          // Η τιμή δεν ήταν αναγνωριστικό αλλά όνομα· ο χρήστης πρέπει να το
          // δει, γιατί αλλιώς θα δημιουργήσει διπλοεγγραφή.
          ? 'Η τιμή `$issueRawId` δεν είναι αναγνωριστικό αλλά ταιριάζει με '
                'το όνομα υπάρχουσας εγγραφής στο πεδίο `$column`.'
          : 'Ασύμβατο αναγνωριστικό `$issueRawId` στο πεδίο `$column`. Προτείνονται μόνο επιλογές επανασύνδεσης και απαιτείται χειροκίνητη επιβεβαίωση.',
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
        final id = _support.toInt(row[column]);
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
      if (_support.toInt(row[primaryColumn]) != primaryId) continue;
      if (_support.toInt(row[targetColumn]) != targetId) continue;
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

  String _officeDisplayLabel(_OfficeDetailRow details) => lampOfficeDisplayLabel(
    officeName: details.officeName,
    departmentName: details.departmentName,
    organizationName: details.organizationName,
  );

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

  String? _firstInformativeText(String? a, String? b, String? c) =>
      lampFirstInformativeText(a, b, c);

  LampIssueResolutionProposal _resolveOwner({
    required LampIssueType issueType,
    required Map<String, Object?> issue,
    required String original,
    required String normalized,
    required List<Map<String, Object?>> owners,
    required Map<int, String> ownerLabelById,
    required Set<int> unlinkedOwnerIds,
    Map<int, int> ownerEquipmentCounts = const <int, int>{},
    Iterable<LampPlaceRow> placeRows = const <LampPlaceRow>[],
    int? linkedOfficeId,
    String? officeRawValue,
  }) {
    // Το πεδίο υπαλλήλου κρατά συχνά χώρο: «Γιατροί Μαιευτικής», «ΞΕΝΩΝΑΣ».
    // Η πρόταση είναι μόνο ένδειξη — δίνει σημείο εκκίνησης, δεν συμπληρώνει.
    final placeSuggestion = lampPlaceSuggestion(
      rawValue: original,
      places: placeRows,
    );

    /// Ορισμός τοποθέτησης: δύο συνδεδεμένα πεδία, γραφείο και υπάλληλος.
    ///
    /// Υπάρχει σε κάθε μορφή τιμής, ακόμη και όταν βρέθηκε υποψήφιος
    /// υπάλληλος: χωρίς αυτό, όταν ο υποψήφιος είναι λάθος δεν υπάρχει
    /// διέξοδος πέρα από την παράλειψη.
    LampIssueResolutionOption placementOption() => LampIssueResolutionOption(
      id: 'owner_set_placement',
      label: 'Ορισμός γραφείου και υπαλλήλου',
      description: placeSuggestion.sentence,
      action: LampIssueResolutionAction.manualReview,
      requiresPlacementInput: true,
      metadata: <String, Object?>{
        'operation': 'set_equipment_placement',
        'currentOfficeId': ?linkedOfficeId,
        if (placeSuggestion.matches.isNotEmpty)
          'suggestedOfficeId': placeSuggestion.matches.first.id,
      },
    );

    /// Ετικέτα υποψηφίου: όνομα **και γραφείο**, γιατί όταν δύο υποψήφιοι
    /// λέγονται «Παπαβασιλείου» το γραφείο είναι το μόνο κριτήριο επιλογής.
    String labelFor(Map<String, Object?> owner) {
      final id = _support.toInt(owner['owner']);
      return ownerLabelById[id] ?? _support.ownerLabel(owner);
    }

    /// «21 εξοπλισμοί» — το κριτήριο που ξεχωρίζει τον υπαρκτό υπάλληλο από
    /// τη σκουπιδο-εγγραφή. Στους μηδενικούς μιλάει ήδη το σπασμένο
    /// εικονίδιο, οπότε το «0 εξοπλισμοί» θα ήταν πλεονασμός.
    String? equipmentCountText(int? ownerId) {
      final count = ownerId == null ? 0 : (ownerEquipmentCounts[ownerId] ?? 0);
      if (count <= 0) return null;
      return count == 1 ? '1 εξοπλισμός' : '$count εξοπλισμοί';
    }

    Map<String, Object?> optionMetadata(
      Map<String, Object?> base,
      int? ownerId,
    ) {
      if (ownerId == null || !unlinkedOwnerIds.contains(ownerId)) return base;
      return <String, Object?>{...base, kLampOptionUnlinkedFlag: true};
    }

    final base = _support.baseProposal(
      issueType,
      issue,
      originalOverride: original,
    );
    final raw = _support.text(issue['raw_value']) ?? '';
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
    final originalParts = _support.ownerOriginalParts(original);
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
        return _matching.normalizeReferenceText(
              _support.text(owner['last_name']) ?? '',
            ) ==
            normalizedParts.single;
      }).toList();

      // Εφεδρική ανάγνωση: κάποιος έγραψε σκέτο το ΜΙΚΡΟ όνομα. Το «Θάνια»
      // έβγαζε πρόταση για νέο υπάλληλο ενώ υπάρχει η «Αναγνωστοπούλου
      // Θάνια» με 4 εξοπλισμούς. Μπαίνει μετά τα επώνυμα, γιατί μονολεκτική
      // τιμή σε πεδίο υπαλλήλου είναι πρώτα επώνυμο.
      final firstNameMatches =
          owners.where((owner) {
            final ownerId = _support.toInt(owner['owner']);
            if (ownerId == null) return false;
            if (matches.any((m) => _support.toInt(m['owner']) == ownerId)) {
              return false;
            }
            return _matching.normalizeReferenceText(
                  _support.text(owner['first_name']) ?? '',
                ) ==
                normalizedParts.single;
          }).toList()
          // Περισσότεροι εξοπλισμοί πρώτα: σε κοινά μικρά ονόματα οι
          // υποψήφιοι πληθαίνουν και ο υπαρκτός πρέπει να φαίνεται αμέσως.
          ..sort((a, b) {
            final aCount =
                ownerEquipmentCounts[_support.toInt(a['owner'])] ?? 0;
            final bCount =
                ownerEquipmentCounts[_support.toInt(b['owner'])] ?? 0;
            return bCount.compareTo(aCount);
          });
      // Πέρα από αυτό το πλήθος η λίστα παύει να είναι επιλογή και γίνεται
      // κατάλογος· ίδιο όριο με την ασαφή αντιστοίχιση των άλλων πεδίων.
      final nameFallbackMatches = firstNameMatches.take(5).toList();

      final preferredLastName = originalParts.isNotEmpty
          ? originalParts.single
          : original;
      if (matches.isEmpty && nameFallbackMatches.isEmpty) {
        final looksLikePlace = !placeSuggestion.isEmpty;
        return base(
          action: LampIssueResolutionAction.manualReview,
          confidence: looksLikePlace ? 74 : 70,
          notes: looksLikePlace
              ? 'Μονολεκτική τιμή που ταιριάζει με χώρο· απαιτείται επιβεβαίωση.'
              : 'Μονολεκτικός υπάλληλος χωρίς αντιστοίχιση· απαιτείται απόφαση.',
          options: <LampIssueResolutionOption>[
            if (looksLikePlace) placementOption(),
            _createOwnerOption(
              id: 'owner_create_single',
              lastName: preferredLastName,
              firstName: null,
              originalLabel: original,
            ),
            if (!looksLikePlace) placementOption(),
            _clearOriginalOption(),
          ],
        );
      }
      LampIssueResolutionOption linkOption(
        Map<String, Object?> match, {
        required bool asFirstName,
      }) {
        final ownerId = _support.toInt(match['owner']);
        final count = equipmentCountText(ownerId);
        return LampIssueResolutionOption(
          id: asFirstName ? 'owner_first_$ownerId' : 'owner_$ownerId',
          label: '$ownerId · ${labelFor(match)}',
          description: <String>[
            if (asFirstName) 'ταιριάζει ως μικρό όνομα',
            ?count,
          ].join(' · '),
          action: LampIssueResolutionAction.autoFix,
          proposedId: ownerId,
          proposedMatch: _support.ownerLabel(match),
          metadata: optionMetadata(<String, Object?>{
            ...metadata,
            'proposedId': ownerId,
          }, ownerId),
        );
      }

      return base(
        action: LampIssueResolutionAction.manualReview,
        proposedId: matches.length == 1
            ? _support.toInt(matches.first['owner'])
            : null,
        proposedMatch: matches.length == 1 ? labelFor(matches.first) : null,
        confidence: matches.length == 1 ? 76 : 52,
        notes: matches.isEmpty
            ? 'Μονολεκτική τιμή που ταιριάζει ως μικρό όνομα υπάρχοντος υπαλλήλου· απαιτείται επιβεβαίωση.'
            : 'Μονολεκτικός υπάλληλος ως επώνυμο· απαιτείται επιβεβαίωση.',
        options: [
          for (final match in matches) linkOption(match, asFirstName: false),
          for (final match in nameFallbackMatches)
            linkOption(match, asFirstName: true),
          // Χωρίς αυτή την επιλογή η λίστα υποψηφίων γίνεται παγίδα: όποιος
          // έχει όντως νέο υπάλληλο με το ίδιο όνομα δεν έχει τρόπο να το πει.
          _createOwnerOption(
            id: 'owner_create_single',
            lastName: preferredLastName,
            firstName: null,
            originalLabel: original,
          ),
          placementOption(),
          _clearOriginalOption(),
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
          final ownerId = _support.toInt(owner['owner']);
          if (ownerId == null || seenOwnerIds.contains(ownerId)) continue;
          final ownerIdentityKey = _support.ownerIdentityKeyFromRow(owner);
          if (ownerIdentityKey != identityKey) continue;
          seenOwnerIds.add(ownerId);
          linkExistingOptions.add(
            LampIssueResolutionOption(
              id: 'owner_link_$ownerId',
              label: 'Σύνδεση με υπάρχον: $ownerId · ${labelFor(owner)}',
              description: equipmentCountText(ownerId),
              action: LampIssueResolutionAction.autoFix,
              proposedId: ownerId,
              proposedMatch: _support.ownerLabel(owner),
              metadata: optionMetadata(<String, Object?>{
                ...metadata,
                'proposedId': ownerId,
              }, ownerId),
            ),
          );
        }
      }

      // Ο ίδιος άνθρωπος γραμμένος αλλιώς: «Μαλατέστα Καλλή» στο ωμό κείμενο,
      // «Μαλατέστα Καλή» στη βάση. Χωρίς αυτό το πέρασμα ο οδηγός πρότεινε
      // μόνο δημιουργία νέου — διπλοεγγραφή δίπλα σε μία με 21 εξοπλισμούς.
      final nearOptions = <({int distance, LampIssueResolutionOption option})>[];
      for (final pair in candidatePairs) {
        for (final owner in owners) {
          final ownerId = _support.toInt(owner['owner']);
          if (ownerId == null || seenOwnerIds.contains(ownerId)) continue;
          final deviation = lampOwnerNameDeviation(
            candidateLastName: pair.lastName,
            candidateFirstName: pair.firstName,
            ownerLastName: _support.text(owner['last_name']),
            ownerFirstName: _support.text(owner['first_name']),
          );
          if (deviation == null || deviation.isExact) continue;
          seenOwnerIds.add(ownerId);
          final count = equipmentCountText(ownerId);
          nearOptions.add((
            distance: deviation.totalDistance,
            option: LampIssueResolutionOption(
              id: 'owner_near_$ownerId',
              label: 'Σύνδεση με υπάρχον: $ownerId · ${labelFor(owner)}',
              description: <String>[
                deviation.description,
                ?count,
              ].join(' · '),
              action: LampIssueResolutionAction.autoFix,
              proposedId: ownerId,
              proposedMatch: _support.ownerLabel(owner),
              metadata: optionMetadata(<String, Object?>{
                ...metadata,
                'proposedId': ownerId,
              }, ownerId),
            ),
          ));
        }
      }
      // Λιγότερη απόκλιση πρώτα· σε ισοπαλία προηγείται ο υπάλληλος με τους
      // περισσότερους εξοπλισμούς, γιατί είναι ο πιθανότερα υπαρκτός.
      nearOptions.sort((a, b) {
        final byDistance = a.distance.compareTo(b.distance);
        if (byDistance != 0) return byDistance;
        final aCount = ownerEquipmentCounts[a.option.proposedId] ?? 0;
        final bCount = ownerEquipmentCounts[b.option.proposedId] ?? 0;
        return bCount.compareTo(aCount);
      });

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
      final nearLinkOptions = <LampIssueResolutionOption>[
        for (final entry in nearOptions) entry.option,
      ];
      final hasName =
          linkExistingOptions.isNotEmpty || nearLinkOptions.isNotEmpty;
      final looksLikePlace = !placeSuggestion.isEmpty && !hasName;
      final allOptions = <LampIssueResolutionOption>[
        // «Γιατροί Μαιευτικής» δεν είναι ονοματεπώνυμο· όταν δεν βρέθηκε
        // κανένα πρόσωπο, η σωστή απάντηση μπαίνει πρώτη ώστε να μη
        // διαβαστούν πρώτα οι δύο λάθος «Νέος υπάλληλος».
        if (looksLikePlace) placementOption(),
        ...linkExistingOptions,
        ...nearLinkOptions,
        ...createOwnerOptions,
        manualEditOption,
        if (!looksLikePlace) placementOption(),
        _clearOriginalOption(),
      ];
      final singleLink = linkExistingOptions.length == 1
          ? linkExistingOptions.single
          : (linkExistingOptions.isEmpty && nearLinkOptions.length == 1
                ? nearLinkOptions.single
                : null);
      // Ο κοντινός υποψήφιος παίρνει χαμηλότερη βεβαιότητα από τον ισοδύναμο:
      // είναι πολύ πιθανός, αλλά η απόφαση μένει στον άνθρωπο.
      final confidence = switch ((linkExistingOptions.isNotEmpty, hasName)) {
        _ when looksLikePlace => 74,
        (true, _) => 86,
        (false, true) => 72,
        (false, false) => 45,
      };
      return base(
        action: LampIssueResolutionAction.manualReview,
        proposedId: singleLink?.proposedId,
        proposedMatch: singleLink?.proposedMatch,
        confidence: confidence,
        notes: switch ((linkExistingOptions.isNotEmpty, hasName)) {
          _ when looksLikePlace =>
            'Διμερής τιμή που ταιριάζει με χώρο, όχι με πρόσωπο· απαιτείται επιβεβαίωση.',
          (true, _) =>
            'Διμερής τιμή υπαλλήλου· βρέθηκε ισοδύναμο ονοματεπώνυμο σε υπάρχοντα υπάλληλο.',
          (false, true) =>
            'Διμερής τιμή υπαλλήλου· βρέθηκε υπάρχων υπάλληλος με σχεδόν ίδιο όνομα.',
          (false, false) =>
            'Διμερής τιμή υπαλλήλου· απαιτείται επιλογή μικρού ονόματος/επωνύμου.',
        },
        options: allOptions,
      );
    }

    final looksLikePlace = !placeSuggestion.isEmpty;
    return base(
      action: LampIssueResolutionAction.manualReview,
      confidence: looksLikePlace ? 74 : 30,
      notes: looksLikePlace
          ? 'Σύνθετη τιμή που ταιριάζει με χώρο, όχι με πρόσωπο· απαιτείται επιβεβαίωση.'
          : 'Σύνθετη ή ασυνήθιστη τιμή υπαλλήλου· απαιτείται απόφαση.',
      options: <LampIssueResolutionOption>[
        if (looksLikePlace) placementOption(),
        _createOwnerOption(
          id: 'owner_create_full',
          lastName: original,
          firstName: null,
          originalLabel: original,
        ),
        if (!looksLikePlace) placementOption(),
        _clearOriginalOption(),
      ],
    );
  }

  /// Τα υπαρκτά αναγνωριστικά του πίνακα στον οποίο δείχνει μια στήλη FK.
  Set<int> _fkTargetIds(
    String column, {
    required List<ReferenceRow> offices,
    required List<Map<String, Object?>> owners,
    required List<ReferenceRow> contracts,
    required List<ReferenceRow> models,
  }) {
    return switch (column) {
      'office' => <int>{for (final row in offices) row.id},
      'contract' => <int>{for (final row in contracts) row.id},
      'model' => <int>{for (final row in models) row.id},
      'owner' => <int>{for (final row in owners) ?_support.toInt(row['owner'])},
      _ => const <int>{},
    };
  }

  /// Η διέξοδος για σκέτα σκουπίδια: ούτε πρόσωπο ούτε χώρος, απλώς θόρυβος
  /// που δεν αξίζει να μείνει γραμμένος δίπλα στον εξοπλισμό.
  LampIssueResolutionOption _clearOriginalOption() {
    return const LampIssueResolutionOption(
      id: 'owner_null_clear_original',
      label: 'Αποσύνδεση υπαλλήλου και εκκαθάριση του αρχικού κειμένου',
      action: LampIssueResolutionAction.autoFix,
      metadata: <String, Object?>{
        'operation': 'update_equipment_owner_null_clear_original',
      },
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
    required List<ReferenceRow> references,
    Map<int, String>? detailedLabelById,
  }) {
    final raw = _support.text(issue['raw_value']) ?? '';
    final rawId = int.tryParse(raw.trim());
    final base = _support.baseProposal(
      issueType,
      issue,
      originalOverride: original,
    );
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
        final first = inName.first;
        return base(
          action: LampIssueResolutionAction.manualReview,
          proposedId: first.id,
          proposedMatch: first.label,
          confidence: 58,
          notes:
              'Το ID δεν υπάρχει, αλλά ο αριθμός εμφανίζεται σε contract_name.',
          metadata: _referenceDisplayMetadata(
            original: original,
            proposedId: first.id,
            proposedMatch: first.label,
            detailedLabelById: detailedLabelById,
            base: <String, Object?>{
              'operation': 'update_equipment_fk',
              'fkColumn': 'contract',
            },
          ),
          options: [
            for (final match in inName.take(10))
              LampIssueResolutionOption(
                id: 'contract_${match.id}',
                label: _referenceOptionDisplayLabel(
                  match,
                  detailedLabelById: detailedLabelById,
                ),
                description: 'Ακριβής αντιστοίχιση',
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
      detailedLabelById: detailedLabelById,
    );
  }
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
    this.nameMatch,
  });

  final int id;
  final String label;
  final int score;
  final List<String> reasons;

  /// Πόσο δυνατά ταιριάζει η ωμή τιμή με το όνομα της εγγραφής, αν ταιριάζει.
  final LampNameMatchStrength? nameMatch;
}
