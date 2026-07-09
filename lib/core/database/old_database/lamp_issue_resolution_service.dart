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
      LampIssueType.setMasterSelfReference =>
        _duplicateAnalyzers.analyzeSetMasterSelfReferences(db),
      LampIssueType.setMasterCycle =>
        _duplicateAnalyzers.analyzeSetMasterCycles(db),
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
}
