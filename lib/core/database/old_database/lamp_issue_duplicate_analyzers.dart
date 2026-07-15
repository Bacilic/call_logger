import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'lamp_issue_resolution_models.dart';
import 'lamp_issue_resolution_support.dart';
import 'lamp_scientific_serial.dart';

class LampIssueDuplicateAnalyzers {
  LampIssueDuplicateAnalyzers(this._support);

  final LampIssueResolutionSupport _support;

  Future<List<LampIssueResolutionProposal>> analyzeDuplicateAssets(
    Database db,
  ) async {
    final labels = await _support.loadFkLabelMaps(db);
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
          labels: labels,
        ),
      );
    }
    return proposals;
  }

  Future<List<LampIssueResolutionProposal>> analyzeDuplicateModelSerial(
    Database db,
  ) async {
    final labels = await _support.loadFkLabelMaps(db);
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
          labels: labels,
        ),
      );
    }
    return proposals;
  }

  Future<List<LampIssueResolutionProposal>> analyzeScientificSerials(
    Database db,
  ) async {
    final labels = await _support.loadFkLabelMaps(db);
    final issues = await _support.openIssues(db, LampIssueType.scientificSerial);
    final proposals = <LampIssueResolutionProposal>[];
    for (final issue in issues) {
      final code = _support.toInt(issue['row_number']);
      final rawSerial = _support.text(issue['raw_value']);
      final issueId = _support.toInt(issue['id']);
      if (code == null || rawSerial == null || issueId == null) continue;
      if (!isScientificSerial(rawSerial)) continue;

      final rows = await db.query(
        'equipment',
        columns: LampIssueResolutionSupport.equipmentPreviewColumns,
        where: 'code = ?',
        whereArgs: <Object?>[code],
        limit: 1,
      );
      if (rows.isEmpty) continue;

      final cleanDigits = scientificSerialCleanDigits(rawSerial);
      final expectedLength = scientificSerialExpectedLength(rawSerial);
      final preview = _support.equipmentSummary(rows.first, labels: labels);
      final notes =
          'Σειριακός σε επιστημονική μορφή: $rawSerial\n$preview\n'
          'Ψηφία για αναζήτηση: $cleanDigits · πιθανό μήκος: $expectedLength ψηφία';

      proposals.add(
        LampIssueResolutionProposal(
          issueType: LampIssueType.scientificSerial,
          issueIds: [issueId],
          sheet: _support.text(issue['sheet']) ?? 'integrity_scan',
          row: code,
          column: 'serial_no',
          originalValue: rawSerial,
          proposedAction: LampIssueResolutionAction.manualReview,
          confidence: 55,
          notes: notes,
          metadata: <String, Object?>{
            'cleanDigits': cleanDigits,
            'expectedLength': expectedLength,
            'rawSerial': rawSerial,
            'rows': rows,
            'confidenceIsNominal': true,
          },
          options: <LampIssueResolutionOption>[
            LampIssueResolutionOption(
              id: 'scientific_serial_reassign_$code',
              label: 'Καταχώρηση νέου σειριακού',
              action: LampIssueResolutionAction.manualReview,
              requiresTextInput: true,
              inputLabel: 'Νέος σειριακός',
              metadata: <String, Object?>{
                'operation': 'reassign_scientific_serial',
                'targetCode': code,
                'cleanDigits': cleanDigits,
                'expectedLength': expectedLength,
                'rawSerial': rawSerial,
              },
            ),
          ],
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
    LampFkLabelMaps labels = LampFkLabelMaps.empty,
  }) {
    String codeWithDescription(Map<String, Object?> row) {
      final code = row['code'];
      final description = _support.text(row['description']);
      if (description != null) return '$code ($description)';
      return '$code';
    }

    final preview = rows
        .map((row) => _support.equipmentSummary(row, labels: labels))
        .join('\n');
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
      metadata: <String, Object?>{
        'rows': rows,
        'confidenceIsNominal': true,
        ...extraMetadata,
      },
      options: <LampIssueResolutionOption>[
        for (final row in rows)
          LampIssueResolutionOption(
            id: '${operationPrefix}_clear_keep_${row['code']}',
            label:
                'Κράτα ${codeWithDescription(row)} και καθάρισε την τιμή στις άλλες εγγραφές',
            action: LampIssueResolutionAction.autoFix,
            metadata: <String, Object?>{
              'operation': clearOperation,
              'duplicateActionKind': 'clear',
              'keepCode': _support.toInt(row['code']),
              'value': column == 'asset_no' ? originalValue : null,
              ...extraMetadata,
            },
          ),
        for (final row in rows)
          LampIssueResolutionOption(
            id: '${operationPrefix}_delete_keep_${row['code']}',
            label:
                'Κράτα ${codeWithDescription(row)} και διέγραψε τις άλλες εγγραφές',
            action: LampIssueResolutionAction.autoFix,
            metadata: <String, Object?>{
              'operation': deleteOperation,
              'duplicateActionKind': 'delete',
              'keepCode': _support.toInt(row['code']),
              'value': column == 'asset_no' ? originalValue : null,
              ...extraMetadata,
            },
          ),
        for (final row in rows)
          LampIssueResolutionOption(
            id: '${operationPrefix}_reassign_${row['code']}',
            label: 'Δώσε νέα τιμή στο ${codeWithDescription(row)}',
            action: LampIssueResolutionAction.autoFix,
            requiresTextInput: true,
            inputLabel: inputLabel,
            metadata: <String, Object?>{
              'operation': reassignOperation,
              'duplicateActionKind': 'reassign',
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
    final proposals = <LampIssueResolutionProposal>[];
    for (final issue in issues) {
      final code = _codeFromSetMasterIssue(issue);
      if (code == null) continue;
      proposals.add(
        LampIssueResolutionProposal(
          issueType: LampIssueType.setMasterSelfReference,
          issueIds: [_support.toInt(issue['id'])].whereType<int>().toList(),
          sheet: _support.text(issue['sheet']),
          row: code,
          column: 'set_master',
          originalValue: _support.text(issue['raw_value']),
          proposedAction: LampIssueResolutionAction.autoFix,
          proposedId: null,
          proposedMatch: 'δείκτης κύριου εξοπλισμού = κενό',
          confidence: 98,
          notes:
              'Η διόρθωση δεδομένων έχει ήδη εφαρμοστεί κατά το import. '
              'Η ενέργεια επιβεβαιώνει την κατάσταση και καθαρίζει το ιστορικό.',
          metadata: <String, Object?>{
            'operation': 'clear_set_master',
            'code': code,
          },
        ),
      );
    }
    return proposals;
  }

  int? _codeFromSetMasterIssue(Map<String, Object?> issue) {
    final fromRow = _support.toInt(issue['row_number']);
    if (fromRow != null) return fromRow;
    final message = _support.text(issue['message']);
    if (message == null) return null;
    final match = RegExp(r'code=(\d+)').firstMatch(message);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  /// Προτάσεις για set_master που δείχνει σε ανύπαρκτο εξοπλισμό (ΓΕΝ-1).
  ///
  /// Παράγει ανεπίλυτες προτάσεις με column `set_master`, ώστε ο οδηγός
  /// ανεπίλυτων να προσφέρει σύνδεση με υπαρκτό κωδικό (autocomplete) ή
  /// εκκαθάριση του δείκτη — και τα δύο υποστηρίζονται ήδη από τον applier.
  Future<List<LampIssueResolutionProposal>> analyzeSetMasterMissingTargets(
    Database db,
  ) async {
    final issues = await _support.openIssues(
      db,
      LampIssueType.setMasterMissingTarget,
    );
    final proposals = <LampIssueResolutionProposal>[];
    for (final issue in issues) {
      final code = _codeFromSetMasterIssue(issue);
      if (code == null) continue;
      final equipment = await _support.equipmentByCode(db, code);
      final missingTarget = _support.text(issue['raw_value']);
      proposals.add(
        LampIssueResolutionProposal(
          issueType: LampIssueType.setMasterMissingTarget,
          issueIds: [_support.toInt(issue['id'])].whereType<int>().toList(),
          sheet: _support.text(issue['sheet']),
          row: code,
          column: 'set_master',
          originalValue: missingTarget,
          proposedAction: LampIssueResolutionAction.unresolved,
          confidence: 0,
          notes:
              'Ο δείκτης κύριου εξοπλισμού δείχνει στον ανύπαρκτο κωδικό '
              '${missingTarget ?? '-'}. Συνδέστε τον με υπαρκτό εξοπλισμό '
              '(Εφαρμογή κωδικού) ή καθαρίστε τον δείκτη (Εκκαθάριση πεδίου).',
          metadata: <String, Object?>{
            'confidenceIsNominal': true,
            if (equipment != null) ...<String, Object?>{
              'rowContextCode': code,
              'rowContextDescription': _support.text(
                equipment['description'],
              ),
              'rowContextAssetNo': _support.text(equipment['asset_no']),
              'rowContextSerialNo': _support.text(equipment['serial_no']),
            },
          },
        ),
      );
    }
    return proposals;
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
