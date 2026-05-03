import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../utils/search_text_normalizer.dart';
import '../../utils/user_identity_normalizer.dart';
import 'lamp_database_provider.dart';
import 'lamp_excel_parse_int.dart';
import 'old_database_schema.dart';

const String oldDataIssueEntityTypeEquipment = 'equipment';
const String oldDataIssueOriginIntegrityScan = 'integrity_scan';

/// Αποτέλεσμα αναζήτησης: εμφανιζόμενες γραμμές + συνολικός αριθμός ταιριασμάτων.
class OldEquipmentSearchResult {
  const OldEquipmentSearchResult({
    required this.rows,
    required this.totalCount,
  });

  final List<Map<String, Object?>> rows;
  final int totalCount;
}

enum OldEquipmentSectionType { equipment, model, contract, owner, department }

class OldEquipmentUpdateResult {
  const OldEquipmentUpdateResult({required this.success, this.message});

  final bool success;
  final String? message;
}

/// Αποτέλεσμα επαναδόμησης πίνακα `search_index` (Λάμπα).
class OldSearchIndexRebuildResult {
  const OldSearchIndexRebuildResult({
    required this.previousRowCount,
    required this.newRowCount,
  });

  final int previousRowCount;
  final int newRowCount;
}

class OldIntegrityScanResult {
  const OldIntegrityScanResult({
    required this.issues,
    this.steps = const <OldIntegrityScanStepState>[],
    this.cancelled = false,
    this.stoppedAfterError = false,
  });

  final List<Map<String, Object?>> issues;
  final List<OldIntegrityScanStepState> steps;
  final bool cancelled;
  final bool stoppedAfterError;

  int get totalCount => issues.length;
  int get totalSteps => steps.length;
  int get completedSteps =>
      steps.where((s) => s.status == OldIntegrityStepStatus.success).length;
  bool get isPartial => cancelled || stoppedAfterError;

  Map<String, int> get countByType {
    final map = <String, int>{};
    for (final issue in issues) {
      final type = issue['issue_type']?.toString() ?? 'unknown';
      map[type] = (map[type] ?? 0) + 1;
    }
    return map;
  }
}

enum OldIntegrityStepStatus { pending, running, success, error, cancelled }

enum OldIntegrityStepErrorDecision { continueScan, stopWithPartialReport }

class OldIntegrityCancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
  }
}

class OldIntegrityScanStepState {
  const OldIntegrityScanStepState({
    required this.id,
    required this.label,
    required this.index,
    required this.total,
    required this.weight,
    this.status = OldIntegrityStepStatus.pending,
    this.issuesFound = 0,
    this.elapsed = Duration.zero,
    this.errorMessage,
  });

  final String id;
  final String label;
  final int index;
  final int total;
  final int weight;
  final OldIntegrityStepStatus status;
  final int issuesFound;
  final Duration elapsed;
  final String? errorMessage;

  OldIntegrityScanStepState copyWith({
    OldIntegrityStepStatus? status,
    int? issuesFound,
    Duration? elapsed,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return OldIntegrityScanStepState(
      id: id,
      label: label,
      index: index,
      total: total,
      weight: weight,
      status: status ?? this.status,
      issuesFound: issuesFound ?? this.issuesFound,
      elapsed: elapsed ?? this.elapsed,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
    );
  }
}

class OldIntegrityScanProgress {
  const OldIntegrityScanProgress({
    required this.steps,
    required this.totalIssuesFound,
    required this.elapsed,
    required this.estimatedRemaining,
    this.cancelRequested = false,
  });

  final List<OldIntegrityScanStepState> steps;
  final int totalIssuesFound;
  final Duration elapsed;
  final Duration? estimatedRemaining;
  final bool cancelRequested;

  double get fraction {
    final totalWeight = steps.fold<int>(0, (sum, s) => sum + s.weight);
    if (totalWeight <= 0) return 0;
    var doneWeight = 0.0;
    for (final step in steps) {
      switch (step.status) {
        case OldIntegrityStepStatus.success:
        case OldIntegrityStepStatus.error:
        case OldIntegrityStepStatus.cancelled:
          doneWeight += step.weight;
          break;
        case OldIntegrityStepStatus.running:
          doneWeight += step.weight * 0.35;
          break;
        case OldIntegrityStepStatus.pending:
          break;
      }
    }
    return (doneWeight / totalWeight).clamp(0.0, 1.0);
  }

  int get completedSteps => steps
      .where(
        (s) =>
            s.status == OldIntegrityStepStatus.success ||
            s.status == OldIntegrityStepStatus.error ||
            s.status == OldIntegrityStepStatus.cancelled,
      )
      .length;
}

typedef OldIntegrityProgressCallback =
    void Function(OldIntegrityScanProgress progress);

typedef OldIntegrityStepErrorHandler =
    Future<OldIntegrityStepErrorDecision> Function(
      OldIntegrityScanStepState step,
      Object error,
      List<Map<String, Object?>> partialIssues,
    );

class OldEquipmentSearchFilters {
  const OldEquipmentSearchFilters({
    this.code,
    this.description,
    this.serialNo,
    this.assetNo,
    this.owner,
    this.office,
    this.phone,
    this.model,
    this.contract,
    this.state,
  });

  final String? code;
  final String? description;
  final String? serialNo;
  final String? assetNo;
  final String? owner;
  final String? office;
  final String? phone;
  final String? model;
  final String? contract;
  final String? state;
}

class OldEquipmentRepository {
  OldEquipmentRepository({LampDatabaseProvider? databaseProvider})
    : _databaseProvider = databaseProvider ?? LampDatabaseProvider.instance;

  final LampDatabaseProvider _databaseProvider;
  final Map<String, _SearchCacheEntry> _cacheByPath =
      <String, _SearchCacheEntry>{};

  /// Αύξηση όταν αλλάζει το SELECT / κανονικοποίηση ώστε να εκκαθαρίζεται η cache.
  static const int _searchCacheSchemaVersion = 4;

  static String _cacheKey(String databasePath) =>
      '${databasePath.trim()}#v$_searchCacheSchemaVersion';

  Future<void> preloadSearchCache(String databasePath) async {
    final path = databasePath.trim();
    if (path.isEmpty) return;
    final cache = await _buildCache(path);
    _cacheByPath[_cacheKey(path)] = cache;
  }

  Future<OldEquipmentSearchResult> searchByFields(
    String databasePath,
    OldEquipmentSearchFilters filters, {
    required int maxDisplay,
  }) async {
    final hasAnyField =
        _normalizeMaybe(filters.code) != null ||
        _normalizeMaybe(filters.description) != null ||
        _normalizeMaybe(filters.serialNo) != null ||
        _normalizeMaybe(filters.assetNo) != null ||
        _normalizeMaybe(filters.owner) != null ||
        _normalizeMaybe(filters.office) != null ||
        _normalizeMaybe(filters.phone) != null ||
        _normalizeMaybe(filters.model) != null ||
        _normalizeMaybe(filters.contract) != null ||
        _normalizeMaybe(filters.state) != null;
    if (!hasAnyField) {
      return const OldEquipmentSearchResult(
        rows: <Map<String, Object?>>[],
        totalCount: 0,
      );
    }
    final cap = maxDisplay.clamp(1, 1000000);
    final cache = await _ensureCache(databasePath);
    var totalCount = 0;
    final displayed = <Map<String, Object?>>[];
    for (final row in cache.rows) {
      if (!_matchesFieldFilters(row, filters)) continue;
      totalCount++;
      if (displayed.length < cap) {
        displayed.add(row.dto);
      }
    }
    return OldEquipmentSearchResult(rows: displayed, totalCount: totalCount);
  }

  Future<OldEquipmentSearchResult> globalSearch(
    String databasePath,
    String query, {
    required int maxDisplay,
  }) async {
    final normalizedQuery = _normalizeMaybe(query);
    if (normalizedQuery == null) {
      return const OldEquipmentSearchResult(
        rows: <Map<String, Object?>>[],
        totalCount: 0,
      );
    }
    final cap = maxDisplay.clamp(1, 1000000);
    final cache = await _ensureCache(databasePath);
    var totalCount = 0;
    final displayed = <Map<String, Object?>>[];
    for (final row in cache.rows) {
      if (!_containsAllTokens(row.normalizedText, normalizedQuery)) continue;
      totalCount++;
      if (displayed.length < cap) {
        displayed.add(row.dto);
      }
    }
    return OldEquipmentSearchResult(rows: displayed, totalCount: totalCount);
  }

  Future<List<Map<String, Object?>>> relatedEquipment(
    String databasePath,
    int code,
  ) async {
    final db = await _databaseProvider.open(databasePath);
    return db.rawQuery(
      '''
      SELECT code, description, serial_no, asset_no, state_name
      FROM equipment
      WHERE set_master = ? OR code = (
        SELECT set_master FROM equipment WHERE code = ?
      )
      ORDER BY code
      ''',
      <Object?>[code, code],
    );
  }

  Future<OldEquipmentUpdateResult> updateSection({
    required String databasePath,
    required int id,
    required OldEquipmentSectionType sectionType,
    required Map<String, Object?> updatedFields,
  }) async {
    final spec = _UpdateSectionSpec.forType(sectionType);
    final dbFields = <String, Object?>{};
    for (final entry in updatedFields.entries) {
      final column = spec.allowedColumnsByField[entry.key];
      if (column != null) {
        dbFields[column] = _normalizeForColumn(column, entry.value);
      }
    }
    if (dbFields.isEmpty) {
      return const OldEquipmentUpdateResult(
        success: false,
        message: 'Δεν υπάρχουν επιτρεπόμενα πεδία για αποθήκευση.',
      );
    }

    final path = databasePath.trim();
    try {
      final db = await _databaseProvider.open(
        path,
        mode: LampDatabaseMode.write,
      );
      await _ensureIntegrityArtifacts(db);
      final validationMessage = await _validateUpdate(
        db,
        id: id,
        spec: spec,
        dbFields: dbFields,
      );
      if (validationMessage != null) {
        return OldEquipmentUpdateResult(
          success: false,
          message: validationMessage,
        );
      }
      final updatedCount = await db.transaction<int>((txn) async {
        final updated = await txn.update(
          spec.table,
          dbFields,
          where: '${spec.idColumn} = ?',
          whereArgs: <Object?>[id],
        );
        return updated;
      });
      if (updatedCount == 0) {
        return const OldEquipmentUpdateResult(
          success: false,
          message: 'Δεν βρέθηκε εγγραφή για ενημέρωση.',
        );
      }
      _cacheByPath.remove(_cacheKey(path));
      return const OldEquipmentUpdateResult(success: true);
    } catch (e) {
      return OldEquipmentUpdateResult(
        success: false,
        message: _friendlySqlError(e),
      );
    }
  }

  Future<List<Map<String, Object?>>> dataIssues(
    String databasePath, {
    int limit = 10000,
  }) async {
    final db = await _databaseProvider.open(databasePath);
    return db.query('data_issues', orderBy: 'id DESC', limit: limit);
  }

  Future<int> dataIssueCount(String databasePath) async {
    final db = await _databaseProvider.open(databasePath);
    final rows = await db.rawQuery('SELECT COUNT(*) AS count FROM data_issues');
    return (rows.first['count'] as int?) ?? 0;
  }

  /// Διαγράφει όλες τις εγγραφές του πίνακα `data_issues`. Επιστρέφει το πλήθος διαγραφών.
  Future<int> deleteAllDataIssues(String databasePath) async {
    final path = databasePath.trim();
    if (path.isEmpty) {
      throw StateError('Κενή διαδρομή βάσης.');
    }
    try {
      final db = await _databaseProvider.open(
        path,
        mode: LampDatabaseMode.write,
      );
      return db.delete('data_issues');
    } catch (e) {
      throw Exception(_friendlySqlError(e));
    }
  }

  /// Πλήρης εκκαθάριση και επαναδόμηση του `search_index` από τον εξοπλισμό (ίδια λογική με την εσωτερική αναδόμηση).
  Future<OldSearchIndexRebuildResult> rebuildLampSearchIndex(
    String databasePath,
  ) async {
    final path = databasePath.trim();
    if (path.isEmpty) {
      throw StateError('Κενή διαδρομή βάσης.');
    }
    try {
      await _ensureSearchIndexTable(path);
      final db = await _databaseProvider.open(
        path,
        mode: LampDatabaseMode.write,
      );
      final before = await _countTable(db, 'search_index');
      await _applyLampSearchIndexRebuild(db);
      final after = await _countTable(db, 'search_index');
      _cacheByPath.remove(_cacheKey(path));
      return OldSearchIndexRebuildResult(
        previousRowCount: before,
        newRowCount: after,
      );
    } catch (e) {
      throw Exception(_friendlySqlError(e));
    }
  }

  Future<int> _countTable(Database db, String tableName) async {
    final q = await db.rawQuery('SELECT COUNT(*) AS c FROM $tableName');
    return (q.first['c'] as int?) ?? 0;
  }

  Future<void> _applyLampSearchIndexRebuild(Database db) async {
    final rows = await _loadSourceRows(db);
    await db.transaction((txn) async {
      await txn.delete('search_index');
      final batch = txn.batch();
      for (final row in rows) {
        final sourceId = _toInt(row['_source_id']) ?? 0;
        final normalizedText = _buildNormalizedSearchText(row);
        batch.insert(
          'search_index',
          <String, Object?>{
            'source_table': 'equipment',
            'source_id': sourceId,
            'normalized_text': normalizedText,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<OldIntegrityScanResult> scanIntegrityIssues(
    String databasePath, {
    OldIntegrityProgressCallback? onProgress,
    OldIntegrityCancellationToken? cancellationToken,
    OldIntegrityStepErrorHandler? onStepError,
    Map<String, Duration> historicalStepDurations = const <String, Duration>{},
  }) async {
    final db = await _databaseProvider.open(
      databasePath.trim(),
      mode: LampDatabaseMode.read,
    );
    final createdAt = DateTime.now().toIso8601String();
    final startedAt = DateTime.now();
    final findings = <Map<String, Object?>>[];
    final token = cancellationToken ?? OldIntegrityCancellationToken();
    final existingFkFingerprints = await _loadExistingFkIssueFingerprints(db);
    final specs = _integrityScanStepSpecs(existingFkFingerprints);
    var steps = <OldIntegrityScanStepState>[
      for (var i = 0; i < specs.length; i++)
        OldIntegrityScanStepState(
          id: specs[i].id,
          label: specs[i].label,
          index: i + 1,
          total: specs.length,
          weight: specs[i].weight,
        ),
    ];

    OldIntegrityScanProgress progress() {
      return OldIntegrityScanProgress(
        steps: List<OldIntegrityScanStepState>.unmodifiable(steps),
        totalIssuesFound: findings.length,
        elapsed: DateTime.now().difference(startedAt),
        estimatedRemaining: _estimateIntegrityRemaining(
          steps,
          startedAt,
          historicalStepDurations,
        ),
        cancelRequested: token.isCancelled,
      );
    }

    void emit() => onProgress?.call(progress());

    List<OldIntegrityScanStepState> replaceStep(
      int index,
      OldIntegrityScanStepState Function(OldIntegrityScanStepState step) update,
    ) {
      return <OldIntegrityScanStepState>[
        for (var i = 0; i < steps.length; i++)
          i == index ? update(steps[i]) : steps[i],
      ];
    }

    OldIntegrityScanResult result({
      bool cancelled = false,
      bool stoppedAfterError = false,
    }) {
      return OldIntegrityScanResult(
        issues: findings,
        steps: List<OldIntegrityScanStepState>.unmodifiable(steps),
        cancelled: cancelled,
        stoppedAfterError: stoppedAfterError,
      );
    }

    emit();
    for (var i = 0; i < specs.length; i++) {
      if (token.isCancelled) {
        steps = _markRemainingIntegrityStepsCancelled(steps, fromIndex: i);
        emit();
        return result(cancelled: true);
      }

      final spec = specs[i];
      final stepStartedAt = DateTime.now();
      steps = replaceStep(
        i,
        (s) => s.copyWith(
          status: OldIntegrityStepStatus.running,
          clearErrorMessage: true,
        ),
      );
      emit();

      try {
        final stepIssues = await spec.runner(db, createdAt, token);
        findings.addAll(stepIssues);
        steps = replaceStep(
          i,
          (s) => s.copyWith(
            status: OldIntegrityStepStatus.success,
            issuesFound: stepIssues.length,
            elapsed: DateTime.now().difference(stepStartedAt),
            clearErrorMessage: true,
          ),
        );
        emit();
      } catch (error) {
        if (token.isCancelled) {
          steps = replaceStep(
            i,
            (s) => s.copyWith(
              status: OldIntegrityStepStatus.cancelled,
              elapsed: DateTime.now().difference(stepStartedAt),
            ),
          );
          steps = _markRemainingIntegrityStepsCancelled(
            steps,
            fromIndex: i + 1,
          );
          emit();
          return result(cancelled: true);
        }

        steps = replaceStep(
          i,
          (s) => s.copyWith(
            status: OldIntegrityStepStatus.error,
            elapsed: DateTime.now().difference(stepStartedAt),
            errorMessage: error.toString(),
          ),
        );
        emit();

        final decision =
            await onStepError?.call(steps[i], error, findings) ??
            OldIntegrityStepErrorDecision.stopWithPartialReport;
        if (decision == OldIntegrityStepErrorDecision.stopWithPartialReport) {
          steps = _markRemainingIntegrityStepsCancelled(
            steps,
            fromIndex: i + 1,
          );
          emit();
          return result(stoppedAfterError: true);
        }
      }
    }

    return result();
  }

  List<_IntegrityScanStepSpec> _integrityScanStepSpecs(
    Set<String> existingFkFingerprints,
  ) {
    return <_IntegrityScanStepSpec>[
      _IntegrityScanStepSpec(
        id: 'import_parity_fk_raw',
        label:
            'Έλεγχος μη αριθμητικών / ασύμβατων κλειδιών (ίδιο με εισαγωγή Excel)',
        weight: 2,
        runner: (db, createdAt, token) => _scanImportParityForeignKeys(
          db,
          createdAt,
          token,
          existingFkFingerprints,
        ),
      ),
      _IntegrityScanStepSpec(
        id: 'duplicate_asset_no',
        label: 'Έλεγχος διπλότυπων αριθμών παγίου',
        weight: 1,
        runner: _scanDuplicateAssets,
      ),
      _IntegrityScanStepSpec(
        id: 'duplicate_model_serial',
        label: 'Έλεγχος διπλότυπων συνδυασμών μοντέλου / σειριακού',
        weight: 1,
        runner: _scanDuplicateModelSerial,
      ),
      _IntegrityScanStepSpec(
        id: 'set_master_self_reference',
        label:
            'Έλεγχος κύριου εξοπλισμού που δείχνει στον ίδιο εξοπλισμό',
        weight: 1,
        runner: _scanSelfMaster,
      ),
      _IntegrityScanStepSpec(
        id: 'set_master_missing_target',
        label: 'Έλεγχος κύριου εξοπλισμού χωρίς υπαρκτό στόχο',
        weight: 1,
        runner: _scanMissingMaster,
      ),
      _IntegrityScanStepSpec(
        id: 'set_master_cycle',
        label: 'Έλεγχος κύκλων ιεραρχίας κύριου εξοπλισμού',
        weight: 4,
        runner: _scanSetMasterCycles,
      ),
    ];
  }

  Duration? _estimateIntegrityRemaining(
    List<OldIntegrityScanStepState> steps,
    DateTime startedAt,
    Map<String, Duration> historicalStepDurations,
  ) {
    final completedWeight = steps
        .where(
          (s) =>
              s.status == OldIntegrityStepStatus.success ||
              s.status == OldIntegrityStepStatus.error ||
              s.status == OldIntegrityStepStatus.cancelled,
        )
        .fold<int>(0, (sum, s) => sum + s.weight);
    final remainingWeight = steps
        .where(
          (s) =>
              s.status == OldIntegrityStepStatus.pending ||
              s.status == OldIntegrityStepStatus.running,
        )
        .fold<int>(0, (sum, s) => sum + s.weight);
    if (remainingWeight <= 0) return null;
    final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
    final msPerWeight = completedWeight > 0 && elapsedMs > 0
        ? elapsedMs / completedWeight
        : null;
    var remainingMs = 0;
    var hasHistoricalEstimate = false;
    for (final step in steps) {
      if (step.status != OldIntegrityStepStatus.pending &&
          step.status != OldIntegrityStepStatus.running) {
        continue;
      }
      final historical = historicalStepDurations[step.id];
      if (historical != null && historical.inMilliseconds > 0) {
        remainingMs += historical.inMilliseconds;
        hasHistoricalEstimate = true;
      } else if (msPerWeight != null) {
        remainingMs += (msPerWeight * step.weight).round();
      }
    }
    if (remainingMs <= 0 || (!hasHistoricalEstimate && msPerWeight == null)) {
      return null;
    }
    return Duration(milliseconds: remainingMs);
  }

  List<OldIntegrityScanStepState> _markRemainingIntegrityStepsCancelled(
    List<OldIntegrityScanStepState> steps, {
    required int fromIndex,
  }) {
    return <OldIntegrityScanStepState>[
      for (var i = 0; i < steps.length; i++)
        i >= fromIndex && steps[i].status == OldIntegrityStepStatus.pending
            ? steps[i].copyWith(status: OldIntegrityStepStatus.cancelled)
            : steps[i],
    ];
  }

  Future<Set<String>> _loadExistingFkIssueFingerprints(Database db) async {
    final rows = await db.query(
      'data_issues',
      columns: <String>['issue_type', 'column_name', 'raw_value'],
      where: 'issue_type IN (?, ?)',
      whereArgs: <Object?>['non_numeric_fk', 'unknown_id'],
    );
    return <String>{
      for (final r in rows)
        _fkIssueFingerprint(
          r['issue_type'] as String? ?? '',
          r['column_name'] as String? ?? '',
          r['raw_value'] as String?,
        ),
    };
  }

  String _fkIssueFingerprint(
    String issueType,
    String columnName,
    String? rawValue,
  ) {
    final t = issueType.trim();
    final c = columnName.trim();
    final r = (rawValue ?? '').trim();
    return '$t|$c|$r';
  }

  String _fkIssueRowKey(
    String issueType,
    String? columnName,
    String? rawValue,
    int? rowNumber,
  ) {
    return '${issueType.trim()}|${(columnName ?? '').trim()}|'
        '${(rawValue ?? '').trim()}|${rowNumber ?? 'null'}';
  }

  Future<Set<int>> _integerPrimaryKeys(
    Database db,
    String table,
    String column,
  ) async {
    final rows = await db.query(table, columns: <String>[column]);
    final result = <int>{};
    for (final r in rows) {
      final v = _toInt(r[column]);
      if (v != null) result.add(v);
    }
    return result;
  }

  /// Ίδια λογική με [OldExcelImporter] για FK από κείμενο στήλης / *_original_text.
  Future<List<Map<String, Object?>>> _scanImportParityForeignKeys(
    Database db,
    String createdAt,
    OldIntegrityCancellationToken token,
    Set<String> existingFkFingerprints,
  ) async {
    final out = <Map<String, Object?>>[];
    final seenRowKeys = <String>{};

    void addIfNew({
      required String issueType,
      required String message,
      required int? rowNumber,
      required String? columnName,
      required String? rawValue,
    }) {
      final fpTriple = _fkIssueFingerprint(
        issueType,
        columnName ?? '',
        rawValue,
      );
      if (existingFkFingerprints.contains(fpTriple)) return;
      final rowKey = _fkIssueRowKey(
        issueType,
        columnName,
        rawValue,
        rowNumber,
      );
      if (seenRowKeys.contains(rowKey)) return;
      seenRowKeys.add(rowKey);
      out.add(
        _scanIssue(
          issueType: issueType,
          message: message,
          rowNumber: rowNumber,
          columnName: columnName,
          rawValue: rawValue,
          createdAt: createdAt,
        ),
      );
    }

    final officeIds = await _integerPrimaryKeys(db, 'offices', 'office');
    if (token.isCancelled) throw const _OldIntegrityScanCancelled();
    final modelIds = await _integerPrimaryKeys(db, 'model', 'model');
    if (token.isCancelled) throw const _OldIntegrityScanCancelled();
    final contractIds = await _integerPrimaryKeys(db, 'contracts', 'contract');
    if (token.isCancelled) throw const _OldIntegrityScanCancelled();
    final ownerIds = await _integerPrimaryKeys(db, 'owners', 'owner');
    if (token.isCancelled) throw const _OldIntegrityScanCancelled();
    final equipmentCodes = await _integerPrimaryKeys(db, 'equipment', 'code');
    if (token.isCancelled) throw const _OldIntegrityScanCancelled();

    final ownerRows = await db.query('owners');
    if (token.isCancelled) throw const _OldIntegrityScanCancelled();
    for (final row in ownerRows) {
      final raw = row['office_original_text']?.toString();
      final hasRaw = raw != null && raw.trim().isNotEmpty;
      if (!hasRaw) continue;
      final parsed = lampParseExcelInt(raw);
      if (parsed != null && officeIds.contains(parsed)) continue;
      final ownerId = _toInt(row['owner']);
      addIfNew(
        issueType: parsed == null ? 'non_numeric_fk' : 'unknown_id',
        message: 'Η τιμή δεν αντιστοιχεί σε έγκυρο ID για office.',
        rowNumber: ownerId,
        columnName: 'office',
        rawValue: raw,
      );
    }

    final equipmentRows = await db.query('equipment');
    if (token.isCancelled) throw const _OldIntegrityScanCancelled();
    var equipmentIndex = 0;
    for (final row in equipmentRows) {
      equipmentIndex++;
      if (equipmentIndex % 200 == 0) {
        if (token.isCancelled) throw const _OldIntegrityScanCancelled();
        await Future<void>.delayed(Duration.zero);
      }

      final code = _toInt(row['code']);

      final fkSpecs = <(String, Set<int>)>[
        ('model', modelIds),
        ('contract', contractIds),
        ('owner', ownerIds),
        ('office', officeIds),
      ];
      for (final (col, valid) in fkSpecs) {
        final rawCol = '${col}_original_text';
        final raw = row[rawCol]?.toString();
        final hasRaw = raw != null && raw.trim().isNotEmpty;
        if (!hasRaw) continue;
        final parsed = lampParseExcelInt(raw);
        if (parsed != null && valid.contains(parsed)) continue;
        addIfNew(
          issueType: parsed == null ? 'non_numeric_fk' : 'unknown_id',
          message: 'Η τιμή δεν αντιστοιχεί σε έγκυρο ID για $col.',
          rowNumber: code,
          columnName: col,
          rawValue: raw,
        );
      }

      final smRaw = row['set_master_original_text']?.toString();
      final smHasRaw = smRaw != null && smRaw.trim().isNotEmpty;
      if (!smHasRaw) continue;
      final smParsed = lampParseExcelInt(smRaw);
      if (smParsed != null && equipmentCodes.contains(smParsed)) continue;
      addIfNew(
        issueType: smParsed == null ? 'non_numeric_fk' : 'unknown_id',
        message: 'Το set_master δεν αντιστοιχεί σε έγκυρο code εξοπλισμού.',
        rowNumber: code,
        columnName: 'set_master',
        rawValue: smRaw,
      );
    }

    return out;
  }

  Future<List<Map<String, Object?>>> _scanDuplicateAssets(
    Database db,
    String createdAt,
    OldIntegrityCancellationToken token,
  ) async {
    final rows = await db.rawQuery('''
      SELECT asset_no, COUNT(*) AS cnt
      FROM equipment
      WHERE asset_no IS NOT NULL AND TRIM(asset_no) <> ''
      GROUP BY asset_no
      HAVING COUNT(*) > 1
      ''');
    if (token.isCancelled) throw const _OldIntegrityScanCancelled();
    return <Map<String, Object?>>[
      for (final row in rows)
        _scanIssue(
          issueType: 'duplicate_asset_no',
          message:
              'Διπλότυπος αριθμός παγίου: ${row['asset_no']} (${row['cnt']} εγγραφές).',
          columnName: 'asset_no',
          rawValue: row['asset_no'],
          createdAt: createdAt,
        ),
    ];
  }

  Future<List<Map<String, Object?>>> _scanDuplicateModelSerial(
    Database db,
    String createdAt,
    OldIntegrityCancellationToken token,
  ) async {
    final rows = await db.rawQuery('''
      SELECT model, serial_no, COUNT(*) AS cnt
      FROM equipment
      WHERE model IS NOT NULL AND serial_no IS NOT NULL AND TRIM(serial_no) <> ''
      GROUP BY model, serial_no
      HAVING COUNT(*) > 1
      ''');
    if (token.isCancelled) throw const _OldIntegrityScanCancelled();
    return <Map<String, Object?>>[
      for (final row in rows)
        _scanIssue(
          issueType: 'duplicate_model_serial',
          message:
              'Διπλότυπο (model, serial_no): (${row['model']}, ${row['serial_no']}) σε ${row['cnt']} εγγραφές.',
          columnName: 'serial_no',
          rawValue: row['serial_no'],
          createdAt: createdAt,
        ),
    ];
  }

  Future<List<Map<String, Object?>>> _scanSelfMaster(
    Database db,
    String createdAt,
    OldIntegrityCancellationToken token,
  ) async {
    final rows = await db.rawQuery(
      'SELECT code FROM equipment WHERE set_master IS NOT NULL AND set_master = code',
    );
    if (token.isCancelled) throw const _OldIntegrityScanCancelled();
    return <Map<String, Object?>>[
      for (final row in rows)
        _scanIssue(
          issueType: 'set_master_self_reference',
          message:
              'Το set_master δείχνει στον ίδιο εξοπλισμό (code=${row['code']}).',
          rowNumber: _toInt(row['code']),
          columnName: 'set_master',
          rawValue: row['code'],
          createdAt: createdAt,
        ),
    ];
  }

  Future<List<Map<String, Object?>>> _scanMissingMaster(
    Database db,
    String createdAt,
    OldIntegrityCancellationToken token,
  ) async {
    final rows = await db.rawQuery('''
      SELECT e.code, e.set_master
      FROM equipment e
      LEFT JOIN equipment m ON m.code = e.set_master
      WHERE e.set_master IS NOT NULL AND m.code IS NULL
      ''');
    if (token.isCancelled) throw const _OldIntegrityScanCancelled();
    return <Map<String, Object?>>[
      for (final row in rows)
        _scanIssue(
          issueType: 'set_master_missing_target',
          message:
              'Το set_master δεν αντιστοιχεί σε υπαρκτό εξοπλισμό για code=${row['code']}.',
          rowNumber: _toInt(row['code']),
          columnName: 'set_master',
          rawValue: row['set_master'],
          createdAt: createdAt,
        ),
    ];
  }

  Future<List<Map<String, Object?>>> _scanSetMasterCycles(
    Database db,
    String createdAt,
    OldIntegrityCancellationToken token,
  ) async {
    final rows = await db.rawQuery('''
      SELECT code, set_master
      FROM equipment
      WHERE set_master IS NOT NULL
      ''');
    final masterByCode = <int, int>{};
    for (final row in rows) {
      final code = _toInt(row['code']);
      final master = _toInt(row['set_master']);
      if (code != null && master != null) masterByCode[code] = master;
    }

    final cycleRoots = <int>{};
    var visitedNodes = 0;
    for (final root in masterByCode.keys) {
      if (token.isCancelled) throw const _OldIntegrityScanCancelled();
      final seen = <int>{};
      var current = root;
      while (true) {
        visitedNodes++;
        if (visitedNodes % 100 == 0) {
          if (token.isCancelled) throw const _OldIntegrityScanCancelled();
          await Future<void>.delayed(Duration.zero);
        }
        if (!seen.add(current)) break;
        final next = masterByCode[current];
        if (next == null) break;
        if (next == root) {
          cycleRoots.add(root);
          break;
        }
        current = next;
      }
    }

    return <Map<String, Object?>>[
      for (final root in cycleRoots)
        _scanIssue(
          issueType: 'set_master_cycle',
          message:
              'Εντοπίστηκε κύκλος ιεραρχίας set_master που περιλαμβάνει code=$root.',
          rowNumber: root,
          columnName: 'set_master',
          rawValue: root,
          createdAt: createdAt,
        ),
    ];
  }

  /// Κλειδί σταθερό ανά «ίδιο» πρόβλημα (χωρίς `id` / `created_at`).
  /// Δεν περιλαμβάνει το `message` ώστε αλλαγές διατύπωσης να μην
  /// επανεισάγουν το ίδιο επιχειρησιακό εύρημα ως «νέο».
  String _dataIssueIdentityKey(Map<String, Object?> issue) {
    String normText(Object? o) {
      if (o == null) return '';
      return o.toString().trim();
    }

    String normRowNum(Object? o) {
      if (o == null) return '';
      if (o is int) return o.toString();
      if (o is num) return o.truncate().toString();
      final s = o.toString().trim();
      final i = int.tryParse(s);
      return i != null ? i.toString() : s;
    }

    final typRaw = normText(issue['issue_type']);
    final typ = typRaw.isEmpty ? oldDataIssueOriginIntegrityScan : typRaw;
    final entityType = _resolveDataIssueEntityType(issue, normText);
    final origin = _resolveDataIssueOrigin(issue, normText);
    final col = normText(issue['column_name']);
    final raw = normText(issue['raw_value']);
    final rn = normRowNum(issue['row_number']);
    return '$typ|$entityType|$origin|$rn|$col|$raw';
  }

  Future<Set<String>> _loadDataIssueIdentityKeys(DatabaseExecutor db) async {
    final columns = await _dataIssueColumnNames(db);
    final hasEntityType = columns.contains('entity_type');
    final hasOrigin = columns.contains('origin');
    final rows = await db.query(
      'data_issues',
      columns: <String>[
        'sheet',
        if (hasEntityType) 'entity_type',
        if (hasOrigin) 'origin',
        'row_number',
        'column_name',
        'raw_value',
        'issue_type',
        'message',
      ],
    );
    return <String>{for (final r in rows) _dataIssueIdentityKey(r)};
  }

  Future<int> insertDataIssues(
    String databasePath,
    List<Map<String, Object?>> issues,
  ) async {
    if (issues.isEmpty) return 0;
    final path = databasePath.trim();
    final db = await _databaseProvider.open(
      path,
      mode: LampDatabaseMode.write,
    );
    await _ensureDataIssueModelColumns(db);
    var inserted = 0;
    await db.transaction((txn) async {
      final columns = await _dataIssueColumnNames(txn);
      final hasEntityType = columns.contains('entity_type');
      final hasOrigin = columns.contains('origin');
      final existing = await _loadDataIssueIdentityKeys(txn);
      for (final issue in issues) {
        final key = _dataIssueIdentityKey(issue);
        if (existing.contains(key)) continue;
        final row = <String, Object?>{
          'sheet': issue['sheet'],
          if (hasEntityType)
            'entity_type': _resolveDataIssueEntityType(issue, _normalizeText) ??
                oldDataIssueEntityTypeEquipment,
          if (hasOrigin)
            'origin': _resolveDataIssueOrigin(issue, _normalizeText) ??
                oldDataIssueOriginIntegrityScan,
          'row_number': issue['row_number'],
          'column_name': issue['column_name'],
          'raw_value': issue['raw_value'],
          'issue_type': issue['issue_type'] ?? oldDataIssueOriginIntegrityScan,
          'message': issue['message'],
          'created_at': issue['created_at'] ?? DateTime.now().toIso8601String(),
        };
        await txn.insert('data_issues', <String, Object?>{
          ...row,
        });
        existing.add(key);
        inserted++;
      }
    });
    return inserted;
  }

  /// Ευρήματα ελέγχου που **δεν** έχουν ήδη ίδιο κλειδί με εγγραφή στο `data_issues`.
  Future<List<Map<String, Object?>>> filterToNewDataIssuesOnly(
    String databasePath,
    List<Map<String, Object?>> candidateIssues,
  ) async {
    if (candidateIssues.isEmpty) {
      return const <Map<String, Object?>>[];
    }
    final path = databasePath.trim();
    final db = await _databaseProvider.open(
      path,
      mode: LampDatabaseMode.read,
    );
    final existing = await _loadDataIssueIdentityKeys(db);
    return <Map<String, Object?>>[
      for (final issue in candidateIssues)
        if (!existing.contains(_dataIssueIdentityKey(issue))) issue,
    ];
  }

  Future<void> _ensureIntegrityArtifacts(Database db) async {
    for (final statement in oldDatabaseIntegrityStatements) {
      try {
        await db.execute(statement);
      } catch (_) {
        // Legacy βάσεις με διπλότυπα παραμένουν επεξεργάσιμες· οι ίδιοι
        // έλεγχοι εκτελούνται παρακάτω στο application layer με φιλικά μηνύματα.
      }
    }
  }

  Future<String?> _validateUpdate(
    Database db, {
    required int id,
    required _UpdateSectionSpec spec,
    required Map<String, Object?> dbFields,
  }) async {
    final currentRows = await db.query(
      spec.table,
      where: '${spec.idColumn} = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (currentRows.isEmpty) return 'Δεν βρέθηκε εγγραφή για ενημέρωση.';
    final merged = <String, Object?>{...currentRows.first, ...dbFields};

    return switch (spec.table) {
      'equipment' => _validateEquipmentUpdate(db, id, merged),
      'owners' => _validateOwnerUpdate(
        db,
        id: id,
        merged: merged,
        changedFields: dbFields,
      ),
      _ => _validatePrimaryKeyAvailability(db, spec, id, merged[spec.idColumn]),
    };
  }

  Future<String?> _validateEquipmentUpdate(
    Database db,
    int oldCode,
    Map<String, Object?> row,
  ) async {
    final code = _toInt(row['code']);
    if (code == null) return 'Ο κωδικός εξοπλισμού είναι υποχρεωτικός.';

    final pkMessage = await _validatePrimaryKeyAvailability(
      db,
      const _UpdateSectionSpec(
        table: 'equipment',
        idColumn: 'code',
        allowedColumnsByField: <String, String>{},
      ),
      oldCode,
      code,
    );
    if (pkMessage != null) return pkMessage;

    final assetNo = _normalizeText(row['asset_no']);
    if (assetNo != null) {
      final duplicates = await db.query(
        'equipment',
        columns: <String>['code'],
        where: 'asset_no = ? AND code <> ?',
        whereArgs: <Object?>[assetNo, oldCode],
        limit: 1,
      );
      if (duplicates.isNotEmpty) {
        return 'Ο αριθμός παγίου χρησιμοποιείται ήδη σε άλλο εξοπλισμό.';
      }
    }

    final model = _toInt(row['model']);
    if (model != null && !await _recordExists(db, 'model', 'model', model)) {
      return 'Το μοντέλο δεν υπάρχει στον πίνακα μοντέλων.';
    }
    final contract = _toInt(row['contract']);
    if (contract != null &&
        !await _recordExists(db, 'contracts', 'contract', contract)) {
      return 'Η σύμβαση δεν υπάρχει στον πίνακα συμβάσεων.';
    }
    final office = _toInt(row['office']);
    if (office != null &&
        !await _recordExists(db, 'offices', 'office', office)) {
      return 'Το γραφείο εξοπλισμού δεν υπάρχει.';
    }
    final serialNo = _normalizeText(row['serial_no']);
    if (model != null && serialNo != null) {
      final duplicates = await db.query(
        'equipment',
        columns: <String>['code'],
        where: 'model = ? AND serial_no = ? AND code <> ?',
        whereArgs: <Object?>[model, serialNo, oldCode],
        limit: 1,
      );
      if (duplicates.isNotEmpty) {
        return 'Υπάρχει ήδη εξοπλισμός με το ίδιο μοντέλο και σειριακό αριθμό.';
      }
    }

    final owner = _toInt(row['owner']);
    if (owner != null) {
      final ownerRows = await db.query(
        'owners',
        columns: <String>['office'],
        where: 'owner = ?',
        whereArgs: <Object?>[owner],
        limit: 1,
      );
      if (ownerRows.isEmpty) {
        return 'Ο κάτοχος δεν υπάρχει στον πίνακα ιδιοκτητών.';
      }
    }

    final setMaster = _toInt(row['set_master']);
    if (setMaster != null) {
      if (setMaster == code) {
        return 'Το set_master δεν μπορεί να δείχνει στον ίδιο εξοπλισμό.';
      }
      final masterRows = await db.query(
        'equipment',
        columns: <String>['code'],
        where: 'code = ?',
        whereArgs: <Object?>[setMaster],
        limit: 1,
      );
      if (masterRows.isEmpty) {
        return 'Το set_master δεν αντιστοιχεί σε υπαρκτό εξοπλισμό.';
      }
      if (await _wouldCreateSetMasterCycle(
        db,
        code: code,
        setMaster: setMaster,
      )) {
        return 'Η ιεραρχία set_master δημιουργεί κύκλο.';
      }
    }

    return null;
  }

  Future<String?> _validateOwnerUpdate(
    Database db, {
    required int id,
    required Map<String, Object?> merged,
    required Map<String, Object?> changedFields,
  }) async {
    final owner = _toInt(merged['owner']);
    if (owner == null) return 'Ο κωδικός ιδιοκτήτη είναι υποχρεωτικός.';
    final pkMessage = await _validatePrimaryKeyAvailability(
      db,
      const _UpdateSectionSpec(
        table: 'owners',
        idColumn: 'owner',
        allowedColumnsByField: <String, String>{},
      ),
      id,
      owner,
    );
    if (pkMessage != null) return pkMessage;

    if (changedFields.containsKey('first_name') ||
        changedFields.containsKey('last_name')) {
      final targetIdentityKey = UserIdentityNormalizer.identityKeyForPerson(
        _normalizeText(merged['first_name']),
        _normalizeText(merged['last_name']),
      );
      if (targetIdentityKey.isNotEmpty) {
        final rows = await db.query(
          'owners',
          columns: <String>['owner', 'last_name', 'first_name'],
          where: 'owner <> ?',
          whereArgs: <Object?>[id],
        );
        for (final row in rows) {
          final rowKey = UserIdentityNormalizer.identityKeyForPerson(
            _normalizeText(row['first_name']),
            _normalizeText(row['last_name']),
          );
          if (rowKey == targetIdentityKey) {
            return 'Υπάρχει ήδη υπάλληλος με ισοδύναμο ονοματεπώνυμο.';
          }
        }
      }
    }

    if (!changedFields.containsKey('office')) return null;
    final newOffice = _toInt(merged['office']);
    if (newOffice != null) {
      final officeRows = await db.query(
        'offices',
        columns: <String>['office'],
        where: 'office = ?',
        whereArgs: <Object?>[newOffice],
        limit: 1,
      );
      if (officeRows.isEmpty) return 'Το νέο γραφείο ιδιοκτήτη δεν υπάρχει.';
    }

    return null;
  }

  Future<String?> _validatePrimaryKeyAvailability(
    Database db,
    _UpdateSectionSpec spec,
    int oldId,
    Object? newValue,
  ) async {
    final newId = _toInt(newValue);
    if (newId == null) return 'Το πρωτεύον κλειδί είναι υποχρεωτικό.';
    if (newId == oldId) return null;
    final existing = await db.query(
      spec.table,
      columns: <String>[spec.idColumn],
      where: '${spec.idColumn} = ?',
      whereArgs: <Object?>[newId],
      limit: 1,
    );
    return existing.isEmpty
        ? null
        : 'Το νέο πρωτεύον κλειδί χρησιμοποιείται ήδη.';
  }

  Future<bool> _recordExists(
    DatabaseExecutor db,
    String table,
    String column,
    int value,
  ) async {
    final rows = await db.query(
      table,
      columns: <String>[column],
      where: '$column = ?',
      whereArgs: <Object?>[value],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<bool> _wouldCreateSetMasterCycle(
    Database db, {
    required int code,
    required int setMaster,
  }) async {
    final rows = await db.rawQuery(
      '''
      WITH RECURSIVE chain(code) AS (
        SELECT ?
        UNION ALL
        SELECT e.set_master
        FROM equipment e
        JOIN chain ON e.code = chain.code
        WHERE e.set_master IS NOT NULL
      )
      SELECT 1 AS found FROM chain WHERE code = ? LIMIT 1
      ''',
      <Object?>[setMaster, code],
    );
    return rows.isNotEmpty;
  }

  Future<_SearchCacheEntry> _ensureCache(String databasePath) async {
    final path = databasePath.trim();
    final key = _cacheKey(path);
    final existing = _cacheByPath[key];
    if (existing != null) return existing;
    final cache = await _buildCache(path);
    _cacheByPath[key] = cache;
    return cache;
  }

  Future<_SearchCacheEntry> _buildCache(String databasePath) async {
    await _ensureSearchIndexTable(databasePath);
    await _rebuildSearchIndex(databasePath);
    final db = await _databaseProvider.open(databasePath);
    final rows = await _loadSourceRows(db);
    final indexedRows = rows.map(_mapToIndexedRow).toList(growable: false);
    return _SearchCacheEntry(rows: indexedRows);
  }

  Future<void> _ensureSearchIndexTable(String databasePath) async {
    try {
      final db = await _databaseProvider.open(
        databasePath,
        mode: LampDatabaseMode.write,
      );
      await db.execute('''
        CREATE TABLE IF NOT EXISTS search_index (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          source_table TEXT NOT NULL,
          source_id INTEGER NOT NULL,
          normalized_text TEXT NOT NULL,
          UNIQUE(source_table, source_id)
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_search_index_source ON search_index(source_table, source_id)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_search_index_normalized ON search_index(normalized_text)',
      );
    } catch (_) {
      // Αν η βάση είναι μόνο-ανάγνωση, συνεχίζουμε με in-memory cache χωρίς persisted index.
    }
  }

  Future<void> _rebuildSearchIndex(String databasePath) async {
    try {
      final db = await _databaseProvider.open(
        databasePath,
        mode: LampDatabaseMode.write,
      );
      await _applyLampSearchIndexRebuild(db);
    } catch (_) {
      // persisted search_index είναι βελτιστοποίηση. Η κύρια λειτουργία
      // συνεχίζει μέσω in-memory κανονικοποιημένου cache.
    }
  }

  Future<List<Map<String, Object?>>> _loadSourceRows(Database db) {
    return db.rawQuery('''
      SELECT
        e.rowid AS _source_id,
        e.code,
        e.description,
        e.model AS model_id,
        e.model_original_text,
        e.serial_no,
        e.asset_no,
        e.state AS state_id,
        e.state_name,
        e.state_original_text,
        e.set_master,
        e.set_master_original_text,
        e.contract AS contract_id,
        e.contract_original_text,
        e.maintenance_contract,
        e.receiving_date,
        e.end_of_guarantee_date,
        e.cost,
        e.owner AS owner_id,
        e.owner_original_text,
        e.office AS office_id,
        e.office_original_text,
        e.attributes AS equipment_attributes,
        e.comments AS equipment_comments,
        m.model_name,
        m.category_code,
        m.category_code_original_text,
        m.category_name,
        m.subcategory_code,
        m.subcategory_code_original_text,
        m.subcategory_name,
        m.manufacturer,
        m.manufacturer_original_text,
        m.manufacturer_name,
        m.manufacturer_code,
        m.attributes AS model_attributes,
        m.consumables,
        m.network_connectivity,
        c.contract_name,
        c.category AS contract_category,
        c.category_original_text AS contract_category_original_text,
        c.supplier_name,
        c.supplier AS supplier_id,
        c.supplier_original_text,
        c.category_name AS contract_category_name,
        c.start_date AS contract_start_date,
        c.end_date AS contract_end_date,
        c.comments AS contract_comments,
        c.award AS contract_award,
        c.declaration AS contract_declaration,
        c.cost AS contract_cost,
        c.committee AS contract_committee,
        o.owner,
        o.last_name,
        o.first_name,
        o.office AS owner_office,
        o.office_original_text AS owner_office_original_text,
        o.e_mail AS owner_email,
        o.phones AS owner_phones,
        f.office AS office,
        f.office_name,
        f.organization,
        f.organization_name,
        f.department,
        f.e_mail AS office_email,
        f.department_name,
        f.responsible,
        f.responsible_original_text,
        f.phones AS office_phones,
        f.building,
        f.level
      FROM equipment e
      LEFT JOIN model m ON m.model = e.model
      LEFT JOIN contracts c ON c.contract = e.contract
      LEFT JOIN owners o ON o.owner = e.owner
      LEFT JOIN offices f ON f.office = e.office
      ORDER BY e.code
      ''');
  }

  _IndexedEquipmentRow _mapToIndexedRow(Map<String, Object?> row) {
    final dto = Map<String, Object?>.from(row)..remove('_source_id');
    return _IndexedEquipmentRow(
      sourceId: _toInt(row['_source_id']) ?? 0,
      normalizedText: _buildNormalizedSearchText(row),
      dto: dto,
    );
  }

  String _buildNormalizedSearchText(Map<String, Object?> row) {
    final parts = <String>[
      _toText(row['code']),
      _toText(row['description']),
      _toText(row['model_id']),
      _toText(row['model_original_text']),
      _toText(row['serial_no']),
      _toText(row['asset_no']),
      _toText(row['state_id']),
      _toText(row['state_name']),
      _toText(row['state_original_text']),
      _toText(row['set_master_original_text']),
      _toText(row['owner_original_text']),
      _toText(row['office_original_text']),
      _toText(row['contract_original_text']),
      _toText(row['contract_id']),
      _toText(row['owner_id']),
      _toText(row['office_id']),
      _toText(row['maintenance_contract']),
      _toText(row['receiving_date']),
      _toText(row['end_of_guarantee_date']),
      _toText(row['cost']),
      _toText(row['equipment_attributes']),
      _toText(row['equipment_comments']),
      _toText(row['model_name']),
      _toText(row['category_code']),
      _toText(row['category_code_original_text']),
      _toText(row['category_name']),
      _toText(row['subcategory_code']),
      _toText(row['subcategory_code_original_text']),
      _toText(row['subcategory_name']),
      _toText(row['manufacturer']),
      _toText(row['manufacturer_original_text']),
      _toText(row['manufacturer_name']),
      _toText(row['manufacturer_code']),
      _toText(row['model_attributes']),
      _toText(row['consumables']),
      _toText(row['network_connectivity']),
      _toText(row['contract_name']),
      _toText(row['contract_category']),
      _toText(row['contract_category_original_text']),
      _toText(row['supplier_name']),
      _toText(row['supplier_id']),
      _toText(row['supplier_original_text']),
      _toText(row['contract_category_name']),
      _toText(row['contract_start_date']),
      _toText(row['contract_end_date']),
      _toText(row['contract_comments']),
      _toText(row['contract_award']),
      _toText(row['contract_declaration']),
      _toText(row['contract_cost']),
      _toText(row['contract_committee']),
      _toText(row['last_name']),
      _toText(row['first_name']),
      _toText(row['owner_office']),
      _toText(row['owner_office_original_text']),
      _toText(row['owner_email']),
      _toText(row['owner_phones']),
      _toText(row['office_name']),
      _toText(row['organization']),
      _toText(row['organization_name']),
      _toText(row['office_email']),
      _toText(row['department']),
      _toText(row['department_name']),
      _toText(row['responsible']),
      _toText(row['responsible_original_text']),
      _toText(row['office_phones']),
      _toText(row['building']),
      _toText(row['level']),
    ];
    return SearchTextNormalizer.normalizeForSearch(parts.join(' '));
  }

  bool _matchesFieldFilters(
    _IndexedEquipmentRow row,
    OldEquipmentSearchFilters filters,
  ) {
    final dto = row.dto;
    return _matchesField(_fieldTextForCode(dto), filters.code) &&
        _matchesField(_fieldTextForDescription(dto), filters.description) &&
        _matchesField(_fieldTextForSerialNo(dto), filters.serialNo) &&
        _matchesField(_fieldTextForAssetNo(dto), filters.assetNo) &&
        _matchesField(_fieldTextForOwner(dto), filters.owner) &&
        _matchesField(_fieldTextForOffice(dto), filters.office) &&
        _matchesField(_fieldTextForPhone(dto), filters.phone) &&
        _matchesField(_fieldTextForModel(dto), filters.model) &&
        _matchesField(_fieldTextForContract(dto), filters.contract) &&
        _matchesField(_fieldTextForState(dto), filters.state);
  }

  bool _matchesField(String fieldText, String? queryRaw) {
    final q = _normalizeMaybe(queryRaw);
    if (q == null) return true;
    return _containsAllTokens(
      SearchTextNormalizer.normalizeForSearch(fieldText),
      q,
    );
  }

  String _fieldTextForCode(Map<String, Object?> row) => _toText(row['code']);
  String _fieldTextForDescription(Map<String, Object?> row) =>
      '${_toText(row['description'])} ${_toText(row['equipment_attributes'])} ${_toText(row['equipment_comments'])}';
  String _fieldTextForSerialNo(Map<String, Object?> row) =>
      _toText(row['serial_no']);
  String _fieldTextForAssetNo(Map<String, Object?> row) =>
      _toText(row['asset_no']);
  String _fieldTextForState(Map<String, Object?> row) =>
      '${_toText(row['state_name'])} ${_toText(row['state_original_text'])}';
  String _fieldTextForModel(Map<String, Object?> row) =>
      '${_toText(row['model_name'])} ${_toText(row['model_original_text'])} '
      '${_toText(row['category_name'])} ${_toText(row['subcategory_name'])} '
      '${_toText(row['manufacturer_name'])} ${_toText(row['consumables'])}';
  String _fieldTextForContract(Map<String, Object?> row) =>
      '${_toText(row['contract_name'])} ${_toText(row['contract_original_text'])} '
      '${_toText(row['supplier_name'])} ${_toText(row['contract_category_name'])} '
      '${_toText(row['contract_comments'])} ${_toText(row['contract_award'])} '
      '${_toText(row['contract_declaration'])}';
  String _fieldTextForOwner(Map<String, Object?> row) =>
      '${_toText(row['last_name'])} ${_toText(row['first_name'])} ${_toText(row['owner_original_text'])} ${_toText(row['owner_phones'])} ${_toText(row['owner_email'])}';
  String _fieldTextForOffice(Map<String, Object?> row) =>
      '${_toText(row['office_name'])} ${_toText(row['organization_name'])} '
      '${_toText(row['office_email'])} ${_toText(row['department_name'])} '
      '${_toText(row['office_original_text'])} ${_toText(row['office_phones'])}';
  String _fieldTextForPhone(Map<String, Object?> row) =>
      '${_toText(row['owner_phones'])} ${_toText(row['office_phones'])}';

  bool _containsAllTokens(String normalizedText, String normalizedQuery) {
    final tokens = normalizedQuery.split(' ').where((t) => t.isNotEmpty);
    for (final token in tokens) {
      if (!normalizedText.contains(token)) return false;
    }
    return true;
  }

  Map<String, Object?> _scanIssue({
    required String issueType,
    required String message,
    required String createdAt,
    String entityType = oldDataIssueEntityTypeEquipment,
    String origin = oldDataIssueOriginIntegrityScan,
    int? rowNumber,
    String? columnName,
    Object? rawValue,
  }) {
    return <String, Object?>{
      // Διατηρείται για legacy συμβατότητα/προβολές, αλλά η λογική επίλυσης
      // βασίζεται πλέον στα `entity_type` + `origin`.
      'sheet': entityType,
      'entity_type': entityType,
      'origin': origin,
      'row_number': rowNumber,
      'column_name': columnName,
      'raw_value': rawValue?.toString(),
      'issue_type': issueType,
      'message': message,
      'created_at': createdAt,
    };
  }

  Object? _normalizeForColumn(String column, Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    if (_integerColumns.contains(column)) return int.tryParse(text) ?? value;
    if (column == 'serial_no' || column == 'asset_no') return text;
    return value is String ? text : value;
  }

  String? _normalizeText(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  String? _normalizeMaybe(String? value) {
    final t = value?.trim() ?? '';
    if (t.isEmpty) return null;
    final n = SearchTextNormalizer.normalizeForSearch(t);
    return n.isEmpty ? null : n;
  }

  String _toText(Object? value) => value?.toString() ?? '';
  int? _toInt(Object? value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '');

  String? _resolveDataIssueEntityType(
    Map<String, Object?> issue,
    String? Function(Object?) normalizeText,
  ) {
    final explicit = normalizeText(issue['entity_type']);
    if (explicit != null && explicit.trim().isNotEmpty) return explicit;
    final legacySheet = normalizeText(issue['sheet'])?.toLowerCase();
    if (legacySheet == 'equipment') return oldDataIssueEntityTypeEquipment;
    if (legacySheet == oldDataIssueOriginIntegrityScan) {
      // Legacy records έγραφαν το origin στο `sheet`.
      return oldDataIssueEntityTypeEquipment;
    }
    return legacySheet;
  }

  String? _resolveDataIssueOrigin(
    Map<String, Object?> issue,
    String? Function(Object?) normalizeText,
  ) {
    final explicit = normalizeText(issue['origin']);
    if (explicit != null && explicit.trim().isNotEmpty) return explicit;
    final legacySheet = normalizeText(issue['sheet'])?.toLowerCase();
    if (legacySheet == oldDataIssueOriginIntegrityScan) {
      return oldDataIssueOriginIntegrityScan;
    }
    return 'manual';
  }

  Future<Set<String>> _dataIssueColumnNames(DatabaseExecutor db) async {
    final rows = await db.rawQuery("PRAGMA table_info('data_issues')");
    return <String>{
      for (final row in rows)
        if ((row['name']?.toString().trim().isNotEmpty ?? false))
          row['name'].toString(),
    };
  }

  Future<void> _ensureDataIssueModelColumns(Database db) async {
    final columns = await _dataIssueColumnNames(db);
    if (!columns.contains('entity_type')) {
      await db.execute("ALTER TABLE data_issues ADD COLUMN entity_type TEXT");
    }
    if (!columns.contains('origin')) {
      await db.execute("ALTER TABLE data_issues ADD COLUMN origin TEXT");
    }
    await db.execute(
      "UPDATE data_issues SET entity_type = COALESCE(entity_type, CASE "
      "WHEN lower(trim(COALESCE(sheet,''))) IN ('equipment','integrity_scan') THEN 'equipment' "
      "WHEN trim(COALESCE(sheet,'')) = '' THEN 'equipment' ELSE sheet END)",
    );
    await db.execute(
      "UPDATE data_issues SET origin = COALESCE(origin, CASE "
      "WHEN lower(trim(COALESCE(sheet,''))) = 'integrity_scan' THEN 'integrity_scan' "
      "ELSE 'manual' END)",
    );
  }

  String _friendlySqlError(Object error) {
    final message = error.toString();
    final lower = message.toLowerCase();
    if (lower.contains('database is locked')) {
      return 'Η βάση είναι προσωρινά κλειδωμένη από άλλη διεργασία. Δοκιμάστε ξανά σε λίγο.';
    }
    if (lower.contains('unique') || lower.contains('constraint failed')) {
      if (lower.contains('asset_no')) {
        return 'Ο αριθμός παγίου πρέπει να είναι μοναδικός.';
      }
      if (lower.contains('serial_no')) {
        return 'Ο συνδυασμός μοντέλου και σειριακού αριθμού υπάρχει ήδη.';
      }
      if (lower.contains('ux_owners_identity_key_clean') ||
          (lower.contains('owners') &&
              lower.contains('last_name') &&
              lower.contains('first_name'))) {
        return 'Υπάρχει ήδη υπάλληλος με ισοδύναμο ονοματεπώνυμο.';
      }
      return 'Η αποθήκευση παραβιάζει κανόνα μοναδικότητας ή ακεραιότητας.';
    }
    if (lower.contains('foreign key')) {
      return 'Η αποθήκευση παραβιάζει σχέση με άλλο πίνακα. Ελέγξτε κωδικούς γραφείου, κατόχου, μοντέλου ή σύμβασης.';
    }
    if (lower.contains('readonly') || lower.contains('read-only')) {
      return 'Η βάση είναι μόνο για ανάγνωση. Ελέγξτε δικαιώματα αρχείου.';
    }
    return 'Η αποθήκευση απέτυχε: $message';
  }

  static const Set<String> _integerColumns = <String>{
    'code',
    'model',
    'category_code',
    'subcategory_code',
    'manufacturer',
    'state',
    'set_master',
    'contract',
    'owner',
    'office',
    'organization',
    'department',
    'responsible',
    'level',
    'supplier',
    'category',
    'network_connectivity',
  };
}

typedef _IntegrityScanRunner =
    Future<List<Map<String, Object?>>> Function(
      Database db,
      String createdAt,
      OldIntegrityCancellationToken token,
    );

class _IntegrityScanStepSpec {
  const _IntegrityScanStepSpec({
    required this.id,
    required this.label,
    required this.weight,
    required this.runner,
  });

  final String id;
  final String label;
  final int weight;
  final _IntegrityScanRunner runner;
}

class _OldIntegrityScanCancelled implements Exception {
  const _OldIntegrityScanCancelled();
}

class _SearchCacheEntry {
  _SearchCacheEntry({required this.rows});
  final List<_IndexedEquipmentRow> rows;
}

class _IndexedEquipmentRow {
  _IndexedEquipmentRow({
    required this.sourceId,
    required this.normalizedText,
    required this.dto,
  });

  final int sourceId;
  final String normalizedText;
  final Map<String, Object?> dto;
}

class _UpdateSectionSpec {
  const _UpdateSectionSpec({
    required this.table,
    required this.idColumn,
    required this.allowedColumnsByField,
  });

  final String table;
  final String idColumn;
  final Map<String, String> allowedColumnsByField;

  static _UpdateSectionSpec forType(OldEquipmentSectionType type) {
    return switch (type) {
      OldEquipmentSectionType.equipment => const _UpdateSectionSpec(
        table: 'equipment',
        idColumn: 'code',
        allowedColumnsByField: <String, String>{
          'code': 'code',
          'description': 'description',
          'model_id': 'model',
          'model_original_text': 'model_original_text',
          'serial_no': 'serial_no',
          'asset_no': 'asset_no',
          'state_id': 'state',
          'state_original_text': 'state_original_text',
          'state_name': 'state_name',
          'set_master': 'set_master',
          'set_master_original_text': 'set_master_original_text',
          'contract_id': 'contract',
          'contract_original_text': 'contract_original_text',
          'maintenance_contract': 'maintenance_contract',
          'receiving_date': 'receiving_date',
          'end_of_guarantee_date': 'end_of_guarantee_date',
          'cost': 'cost',
          'owner_id': 'owner',
          'owner_original_text': 'owner_original_text',
          'office_id': 'office',
          'office_original_text': 'office_original_text',
          'equipment_attributes': 'attributes',
          'equipment_comments': 'comments',
        },
      ),
      OldEquipmentSectionType.model => const _UpdateSectionSpec(
        table: 'model',
        idColumn: 'model',
        allowedColumnsByField: <String, String>{
          'model_id': 'model',
          'model_name': 'model_name',
          'category_code': 'category_code',
          'category_code_original_text': 'category_code_original_text',
          'category_name': 'category_name',
          'subcategory_code': 'subcategory_code',
          'subcategory_code_original_text': 'subcategory_code_original_text',
          'subcategory_name': 'subcategory_name',
          'manufacturer': 'manufacturer',
          'manufacturer_original_text': 'manufacturer_original_text',
          'manufacturer_name': 'manufacturer_name',
          'manufacturer_code': 'manufacturer_code',
          'model_attributes': 'attributes',
          'consumables': 'consumables',
          'network_connectivity': 'network_connectivity',
        },
      ),
      OldEquipmentSectionType.contract => const _UpdateSectionSpec(
        table: 'contracts',
        idColumn: 'contract',
        allowedColumnsByField: <String, String>{
          'contract_id': 'contract',
          'contract_name': 'contract_name',
          'contract_category': 'category',
          'contract_category_original_text': 'category_original_text',
          'contract_category_name': 'category_name',
          'supplier_id': 'supplier',
          'supplier_original_text': 'supplier_original_text',
          'supplier_name': 'supplier_name',
          'contract_start_date': 'start_date',
          'contract_end_date': 'end_date',
          'contract_declaration': 'declaration',
          'contract_award': 'award',
          'contract_cost': 'cost',
          'contract_committee': 'committee',
          'contract_comments': 'comments',
        },
      ),
      OldEquipmentSectionType.owner => const _UpdateSectionSpec(
        table: 'owners',
        idColumn: 'owner',
        allowedColumnsByField: <String, String>{
          'owner_id': 'owner',
          'last_name': 'last_name',
          'first_name': 'first_name',
          'owner_office': 'office',
          'owner_office_original_text': 'office_original_text',
          'owner_email': 'e_mail',
          'owner_phones': 'phones',
        },
      ),
      OldEquipmentSectionType.department => const _UpdateSectionSpec(
        table: 'offices',
        idColumn: 'office',
        allowedColumnsByField: <String, String>{
          'office_id': 'office',
          'office_name': 'office_name',
          'organization': 'organization',
          'organization_name': 'organization_name',
          'department': 'department',
          'department_name': 'department_name',
          'responsible': 'responsible',
          'responsible_original_text': 'responsible_original_text',
          'office_email': 'e_mail',
          'office_phones': 'phones',
          'building': 'building',
          'level': 'level',
        },
      ),
    };
  }
}
