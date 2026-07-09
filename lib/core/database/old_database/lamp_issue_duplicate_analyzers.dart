import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'lamp_issue_resolution_models.dart';
import 'lamp_issue_resolution_support.dart';

class LampIssueDuplicateAnalyzers {
  LampIssueDuplicateAnalyzers(this._support);

  final LampIssueResolutionSupport _support;

  Future<List<LampIssueResolutionProposal>> analyzeDuplicateAssets(
    Database db,
  ) async {
    final issues = await _support.openIssues(db, LampIssueType.duplicateAssetNo);
    final byAsset = <String, List<int>>{};
    for (final issue in issues) {
      final raw = _support.text(issue['raw_value']);
      final id = _support.toInt(issue['id']);
      if (raw != null && id != null) {
        byAsset.putIfAbsent(raw, () => <int>[]).add(id);
      }
    }

    final proposals = <LampIssueResolutionProposal>[];
    for (final entry in byAsset.entries) {
      final rows = await db.query(
        'equipment',
        columns: LampIssueResolutionSupport.equipmentPreviewColumns,
        where: 'asset_no = ?',
        whereArgs: <Object?>[entry.key],
        orderBy: 'code ASC',
      );
      if (rows.length < 2) continue;
      proposals.add(
        duplicateProposal(
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

  Future<List<LampIssueResolutionProposal>> analyzeDuplicateModelSerial(
    Database db,
  ) async {
    final issues = await _support.openIssues(db, LampIssueType.duplicateModelSerial);
    final issueIdsBySerial = <String, List<int>>{};
    for (final issue in issues) {
      final raw = _support.text(issue['raw_value']);
      final id = _support.toInt(issue['id']);
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
      final model = _support.toInt(group['model']);
      final serial = _support.text(group['serial_no']);
      if (model == null || serial == null) continue;
      final rows = await db.query(
        'equipment',
        columns: LampIssueResolutionSupport.equipmentPreviewColumns,
        where: 'model = ? AND serial_no = ?',
        whereArgs: <Object?>[model, serial],
        orderBy: 'code ASC',
      );
      proposals.add(
        duplicateProposal(
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

  LampIssueResolutionProposal duplicateProposal({
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
    final preview = rows.map(_support.equipmentSummary).join('\n');
    return LampIssueResolutionProposal(
      issueType: issueType,
      issueIds: issueIds,
      sheet: 'integrity_scan',
      row: _support.toInt(rows.first['code']),
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
              'keepCode': _support.toInt(row['code']),
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
              'keepCode': _support.toInt(row['code']),
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
              'targetCode': _support.toInt(row['code']),
            },
          ),
      ],
    );
  }

  Future<List<LampIssueResolutionProposal>> analyzeSetMasterSelfReferences(
    Database db,
  ) async {
    final issues = await _support.openIssues(
      db,
      LampIssueType.setMasterSelfReference,
    );
    return <LampIssueResolutionProposal>[
      for (final issue in issues)
        if (_support.toInt(issue['row_number']) != null)
          LampIssueResolutionProposal(
            issueType: LampIssueType.setMasterSelfReference,
            issueIds: [_support.toInt(issue['id'])].whereType<int>().toList(),
            sheet: _support.text(issue['sheet']),
            row: _support.toInt(issue['row_number']),
            column: 'set_master',
            originalValue: _support.text(issue['raw_value']),
            proposedAction: LampIssueResolutionAction.autoFix,
            proposedId: null,
            proposedMatch: 'δείκτης κύριου εξοπλισμού = κενό',
            confidence: 98,
            notes: 'Ασφαλής εκκαθάριση αυτοαναφοράς κύριου εξοπλισμού.',
            metadata: <String, Object?>{
              'operation': 'clear_set_master',
              'code': _support.toInt(issue['row_number']),
            },
          ),
    ];
  }

  Future<List<LampIssueResolutionProposal>> analyzeSetMasterCycles(
    Database db,
  ) async {
    final issues = await _support.openIssues(db, LampIssueType.setMasterCycle);
    final issueIdsByRoot = <int, List<int>>{};
    for (final issue in issues) {
      final root = _support.toInt(issue['row_number']);
      final id = _support.toInt(issue['id']);
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
      final code = _support.toInt(row['code']);
      final master = _support.toInt(row['set_master']);
      if (code != null && master != null) {
        masterByCode[code] = master;
        descriptionByCode[code] = _support.text(row['description']) ?? '';
      }
    }

    final proposals = <LampIssueResolutionProposal>[];
    final emittedCycles = <String>{};
    for (final root in issueIdsByRoot.keys) {
      final cycle = _support.cycleForRoot(root, masterByCode);
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
}
