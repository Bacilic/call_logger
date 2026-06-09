import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/database_integrity_finding.dart';
import '../models/database_integrity_report.dart';
import '../models/integrity_fix_models.dart';
import '../services/database_integrity_fix_service.dart';
import '../services/database_integrity_service.dart';

/// Κατάσταση ελέγχου ακεραιότητας βάσης.
sealed class DatabaseIntegrityState {
  const DatabaseIntegrityState();
}

final class DatabaseIntegrityIdle extends DatabaseIntegrityState {
  const DatabaseIntegrityIdle();
}

final class DatabaseIntegrityLoading extends DatabaseIntegrityState {
  const DatabaseIntegrityLoading({
    required this.currentStep,
    required this.totalSteps,
    required this.currentCheckName,
    required this.totalRowsChecked,
    this.tableScopeLabel,
  });

  final int currentStep;
  final int totalSteps;
  final String currentCheckName;
  final int totalRowsChecked;
  final String? tableScopeLabel;
}

final class DatabaseIntegritySuccess extends DatabaseIntegrityState {
  const DatabaseIntegritySuccess(this.report);
  final DatabaseIntegrityReport report;
}

final class DatabaseIntegrityError extends DatabaseIntegrityState {
  const DatabaseIntegrityError(this.message);
  final String message;
}

final databaseIntegrityServiceProvider = Provider<DatabaseIntegrityService>(
  (ref) => DatabaseIntegrityService(),
);

final databaseIntegrityFixServiceProvider = Provider<DatabaseIntegrityFixService>(
  (ref) => DatabaseIntegrityFixService(),
);

/// Κλειδιά ευρημάτων σε εξέλιξη επιδιόρθωσης (για disable κουμπιών UI).
class IntegrityFixingKeysNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};

  void setKeys(Set<String> keys) {
    state = keys;
  }
}

final integrityFixingKeysProvider =
    NotifierProvider<IntegrityFixingKeysNotifier, Set<String>>(
  IntegrityFixingKeysNotifier.new,
);

class DatabaseIntegrityNotifier extends Notifier<DatabaseIntegrityState> {
  @override
  DatabaseIntegrityState build() => const DatabaseIntegrityIdle();

  void _markFixing(String key, {required bool fixing}) {
    final next = Set<String>.from(ref.read(integrityFixingKeysProvider));
    if (fixing) {
      next.add(key);
    } else {
      next.remove(key);
    }
    ref.read(integrityFixingKeysProvider.notifier).setKeys(next);
  }

  void _markFixingAll(Iterable<String> keys, {required bool fixing}) {
    final next = Set<String>.from(ref.read(integrityFixingKeysProvider));
    if (fixing) {
      next.addAll(keys);
    } else {
      next.removeAll(keys);
    }
    ref.read(integrityFixingKeysProvider.notifier).setKeys(next);
  }

  Future<void> runCheck({bool force = false}) async {
    if (state is DatabaseIntegrityLoading && !force) return;

    state = const DatabaseIntegrityLoading(
      currentStep: 0,
      totalSteps: DatabaseIntegrityService.totalSteps,
      currentCheckName: 'Προετοιμασία…',
      totalRowsChecked: 0,
    );

    try {
      final service = ref.read(databaseIntegrityServiceProvider);
      final report = await service.runChecks(
        onProgress: (progress) {
          state = DatabaseIntegrityLoading(
            currentStep: progress.currentStep,
            totalSteps: progress.totalSteps,
            currentCheckName: progress.currentCheckName,
            totalRowsChecked: progress.totalRowsChecked,
            tableScopeLabel: progress.tableScopeLabel,
          );
        },
      );
      state = DatabaseIntegritySuccess(report);
    } catch (e) {
      state = DatabaseIntegrityError('$e');
    }
  }

  Future<IntegrityFixResult> applyFix(
    DatabaseIntegrityFinding finding,
    IntegrityFixDecision decision,
  ) async {
    _markFixing(finding.findingKey, fixing: true);

    try {
      final fixService = ref.read(databaseIntegrityFixServiceProvider);
      final result = await fixService.applyFix(finding, decision);
      if (result is IntegrityFixLockFailure) return result;
      if (result.success && state is DatabaseIntegritySuccess) {
        await _refreshAfterSingleFix(finding);
      }
      return result;
    } finally {
      _markFixing(finding.findingKey, fixing: false);
    }
  }

  Future<IntegrityBulkFixResult> applyBulkFix(
    IntegrityCheckType checkType,
    List<DatabaseIntegrityFinding> findings,
  ) async {
    _markFixingAll(findings.map((f) => f.findingKey), fixing: true);

    try {
      final fixService = ref.read(databaseIntegrityFixServiceProvider);
      final result = await fixService.applyBulkFix(findings);
      if (result.anySuccess && state is DatabaseIntegritySuccess) {
        final fixedKeys = <String>[];
        for (var i = 0; i < result.results.length; i++) {
          if (result.results[i].success) {
            fixedKeys.add(findings[i].findingKey);
          }
        }
        await _refreshAfterBulkFix(checkType, fixedKeys);
      }
      return result;
    } finally {
      _markFixingAll(findings.map((f) => f.findingKey), fixing: false);
    }
  }

  /// Μετά ατομική επιδιόρθωση: αφαιρεί μόνο το διορθωμένο εύρημα από τη λίστα.
  /// Δεν ξανατρέχει ολόκληρο τον έλεγχο τύπου — τα υπόλοιπα ομοειδή ευρήματα
  /// παραμένουν μέχρι ατομική ή μαζική επιδιόρθωση.
  Future<void> _refreshAfterSingleFix(DatabaseIntegrityFinding fixedFinding) async {
    if (state is! DatabaseIntegritySuccess) return;
    final current = state as DatabaseIntegritySuccess;

    final updatedFindings = current.report.findings
        .where((f) => f.findingKey != fixedFinding.findingKey)
        .toList();

    state = DatabaseIntegritySuccess(
      DatabaseIntegrityReport(
        findings: updatedFindings,
        checkedAt: DateTime.now(),
        schemaVersion: current.report.schemaVersion,
      ),
    );
  }

  /// Μετά μαζική επιδιόρθωση: επαναέλεγχος τύπου και ανανέωση ολόκληρης ομάδας.
  Future<void> _refreshAfterBulkFix(
    IntegrityCheckType checkType,
    List<String> removedFindingKeys,
  ) async {
    if (state is! DatabaseIntegritySuccess) return;
    final current = state as DatabaseIntegritySuccess;
    final service = ref.read(databaseIntegrityServiceProvider);

    var updatedFindings = List<DatabaseIntegrityFinding>.from(
      current.report.findings,
    );
    updatedFindings.removeWhere((f) => removedFindingKeys.contains(f.findingKey));

    final recheck = await service.runCheck(checkType);
    updatedFindings.removeWhere((f) => f.checkType == checkType);
    updatedFindings.addAll(recheck);

    state = DatabaseIntegritySuccess(
      DatabaseIntegrityReport(
        findings: updatedFindings,
        checkedAt: DateTime.now(),
        schemaVersion: current.report.schemaVersion,
      ),
    );
  }

  void reset() {
    state = const DatabaseIntegrityIdle();
    ref.read(integrityFixingKeysProvider.notifier).setKeys({});
  }
}

final databaseIntegrityProvider =
    NotifierProvider<DatabaseIntegrityNotifier, DatabaseIntegrityState>(
  DatabaseIntegrityNotifier.new,
);
