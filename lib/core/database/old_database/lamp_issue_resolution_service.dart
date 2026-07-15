import '../../utils/search_text_normalizer.dart';
import 'lamp_database_provider.dart';
import 'lamp_issue_decision_applier.dart';
import 'lamp_issue_duplicate_analyzers.dart';
import 'lamp_issue_fk_analyzer.dart';
import 'lamp_issue_matching_engine.dart';
import 'lamp_issue_resolution_models.dart';
import 'lamp_issue_resolution_support.dart';
import 'resolution_log_entry.dart';

export 'lamp_issue_resolution_models.dart';

class LampIssueResolutionService {
  LampIssueResolutionService({LampDatabaseProvider? databaseProvider})
    : _databaseProvider = databaseProvider ?? LampDatabaseProvider.instance {
    final matching = LampIssueMatchingEngine();
    _matching = matching;
    _support = LampIssueResolutionSupport(matching);
    _fkAnalyzer = LampIssueFkAnalyzer(matching, _support);
    _duplicateAnalyzers = LampIssueDuplicateAnalyzers(_support);
    _applier = LampIssueDecisionApplier(_databaseProvider, matching, _support);
  }

  final LampDatabaseProvider _databaseProvider;
  late final LampIssueMatchingEngine _matching;
  late final LampIssueResolutionSupport _support;
  late final LampIssueFkAnalyzer _fkAnalyzer;
  late final LampIssueDuplicateAnalyzers _duplicateAnalyzers;
  late final LampIssueDecisionApplier _applier;

  /// Confidence για ταύτιση «το ένα περιέχει το άλλο» (substring containment).
  static const int substringContainmentConfidence =
      LampIssueMatchingEngine.substringContainmentConfidence;

  /// Κοινή βαθμολόγηση ομοιότητας που επαναχρησιμοποιείται σε flows migration.
  int similarityConfidenceScore(
    String source,
    String candidate, {
    String? sourceDepartment,
    String? candidateDepartment,
  }) {
    return _matching.similarityConfidenceScore(
      source,
      candidate,
      sourceDepartment: sourceDepartment,
      candidateDepartment: candidateDepartment,
    );
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
      LampIssueType.unknownId => _fkAnalyzer.analyzeFkIssues(db, issueType),
      LampIssueType.duplicateAssetNo =>
        _duplicateAnalyzers.analyzeDuplicateAssets(db),
      LampIssueType.duplicateModelSerial =>
        _duplicateAnalyzers.analyzeDuplicateModelSerial(db),
      LampIssueType.scientificSerial =>
        _duplicateAnalyzers.analyzeScientificSerials(db),
      LampIssueType.setMasterSelfReference =>
        _duplicateAnalyzers.analyzeSetMasterSelfReferences(db),
      LampIssueType.setMasterCycle =>
        _duplicateAnalyzers.analyzeSetMasterCycles(db),
      LampIssueType.setMasterMissingTarget =>
        _duplicateAnalyzers.analyzeSetMasterMissingTargets(db),
    };
  }

  Future<LampIssueResolutionApplyResult> applyDecisions({
    required String databasePath,
    required List<LampIssueResolutionDecision> decisions,
    ResolutionLogSink? onLog,
    ResolutionCancelToken? cancelToken,
    void Function(LampIssueResolutionDecision decision)? onDecisionApplied,
  }) {
    return _applier.applyDecisions(
      databasePath: databasePath,
      decisions: decisions,
      onLog: onLog,
      cancelToken: cancelToken,
      onDecisionApplied: onDecisionApplied,
    );
  }

  /// Μία απόφαση σε μία συναλλαγή — ίδια διαδρομή με [applyDecisions].
  Future<LampIssueResolutionApplyResult> applySingleDecision({
    required String databasePath,
    required LampIssueResolutionDecision decision,
    ResolutionLogSink? onLog,
    ResolutionCancelToken? cancelToken,
    void Function(LampIssueResolutionDecision decision)? onDecisionApplied,
  }) {
    return _applier.applySingleDecision(
      databasePath: databasePath,
      decision: decision,
      onLog: onLog,
      cancelToken: cancelToken,
      onDecisionApplied: onDecisionApplied,
    );
  }

  /// Ετικέτα οντότητας-στόχου για χειροκίνητη «Διόρθωση με κωδικό».
  Future<String?> lookupManualFkTargetLabel({
    required String databasePath,
    required String column,
    required int targetId,
  }) async {
    final spec = ManualFkTargetSpec.forColumn(column);
    if (spec == null) return null;
    final db = await _databaseProvider.open(databasePath.trim());
    if (column.trim().toLowerCase() == 'owner') {
      final rows = await db.query(
        'owners',
        where: 'owner = ?',
        whereArgs: <Object?>[targetId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return _support.ownerLabel(rows.first);
    }
    final rows = await db.query(
      spec.table,
      columns: <String>[spec.labelColumn],
      where: '${spec.idColumn} = ?',
      whereArgs: <Object?>[targetId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _support.text(rows.first[spec.labelColumn]);
  }

  /// Αναζήτηση ονόματος ή κωδικού για autocomplete «Διόρθωση με κωδικό».
  Future<List<LampEntityCodeSuggestion>> searchManualFkTargets({
    required String databasePath,
    required String column,
    required String query,
    int limit = 10,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const <LampEntityCodeSuggestion>[];
    if (ManualFkTargetSpec.forColumn(column) == null) {
      return const <LampEntityCodeSuggestion>[];
    }

    final normalizedQuery = SearchTextNormalizer.normalizeForSearch(trimmed);
    final compactQuery = trimmed.replaceAll(RegExp(r'\s+'), '');
    final db = await _databaseProvider.open(databasePath.trim());
    final matches = <LampEntityCodeSuggestion>[];

    bool matchesEntry(int code, String label) {
      if (compactQuery.isNotEmpty && code.toString().contains(compactQuery)) {
        return true;
      }
      return SearchTextNormalizer.matchesNormalizedQuery(label, normalizedQuery);
    }

    void addIfMatch(int? code, String label) {
      if (code == null || label.trim().isEmpty) return;
      if (!matchesEntry(code, label)) return;
      matches.add(LampEntityCodeSuggestion(code: code, label: label.trim()));
    }

    switch (column.trim().toLowerCase()) {
      case 'owner':
        final rows = await db.query(
          'owners',
          orderBy: 'last_name ASC, first_name ASC',
        );
        for (final row in rows) {
          addIfMatch(_support.toInt(row['owner']), _support.ownerLabel(row));
          if (matches.length >= limit) break;
        }
      case 'office':
        final rows = await db.query(
          'offices',
          orderBy: 'office_name ASC',
        );
        for (final row in rows) {
          final officeName = _support.text(row['office_name']) ?? '';
          final departmentName = _support.text(row['department_name']) ?? '';
          final label = departmentName.isNotEmpty
              ? '$officeName · $departmentName'
              : officeName;
          addIfMatch(_support.toInt(row['office']), label);
          if (matches.length >= limit) break;
        }
      case 'model':
        final rows = await db.query(
          'model',
          orderBy: 'model_name ASC',
        );
        for (final row in rows) {
          addIfMatch(
            _support.toInt(row['model']),
            _support.text(row['model_name']) ?? '',
          );
          if (matches.length >= limit) break;
        }
      case 'contract':
        final rows = await db.query(
          'contracts',
          orderBy: 'contract_name ASC',
        );
        for (final row in rows) {
          addIfMatch(
            _support.toInt(row['contract']),
            _support.text(row['contract_name']) ?? '',
          );
          if (matches.length >= limit) break;
        }
      case 'set_master':
        final rows = await db.query(
          'equipment',
          columns: <String>['code', 'description'],
          orderBy: 'description ASC',
        );
        for (final row in rows) {
          final code = _support.toInt(row['code']);
          final description = _support.text(row['description']) ?? '';
          final label = description.isNotEmpty
              ? description
              : 'Εξοπλισμός $code';
          addIfMatch(code, label);
          if (matches.length >= limit) break;
        }
      default:
        return const <LampEntityCodeSuggestion>[];
    }

    return matches.take(limit).toList();
  }
}
