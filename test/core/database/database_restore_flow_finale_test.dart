// Φινάλε επαναφοράς από .zip: η διαδρομή περνά από τον κοινό εκτελεστή εναλλαγής.
//
//   flutter test test/core/database/database_restore_flow_finale_test.dart

import 'package:call_logger/core/database/database_init_result.dart';
import 'package:call_logger/core/database/database_init_runner.dart';
import 'package:call_logger/features/database/services/database_backup_service.dart';
import 'package:call_logger/features/database/services/database_path_switch_runner.dart';
import 'package:call_logger/features/database/services/database_zip_pick_restore.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeHooks implements DatabasePathSwitchHooks {
  final List<String> calls = <String>[];
  int applyCallCount = 0;
  int reportCallCount = 0;
  String? appliedPath;
  DatabaseInitRunnerResult? reportedRunner;

  @override
  void declareSwitchBegin() => calls.add('declareSwitchBegin');

  @override
  void declareSwitchEnd() => calls.add('declareSwitchEnd');

  @override
  Future<void> showVerifyingIndicator() async {
    calls.add('showVerifyingIndicator');
  }

  @override
  Future<void> hideVerifyingIndicator() async {
    calls.add('hideVerifyingIndicator');
  }

  @override
  Future<void> reportVerificationFailure(
    DatabaseInitRunnerResult runner,
  ) async {
    calls.add('reportVerificationFailure');
    reportCallCount++;
    reportedRunner = runner;
  }

  @override
  Future<void> applySwitchToSession(String path) async {
    calls.add('applySwitchToSession');
    applyCallCount++;
    appliedPath = path;
  }
}

/// Ενορχήστρωση φινάλε όπως στο πάνελ ρυθμίσεων / οθόνη σφάλματος:
/// επαναφορά → (αν υπάρχει διαδρομή) → [runDatabasePathSwitch].
Future<bool> _orchestrateRestoreFinale({
  required Future<ZipPickRestoreResult> Function() restore,
  required DatabasePathSwitchHooks hooks,
  required DatabasePathVerifier verify,
}) async {
  final outcome = await restore();
  final path = outcome.databasePath;
  if (path == null) return false;
  return runDatabasePathSwitch(path: path, hooks: hooks, verify: verify);
}

void main() {
  const zipPath = r'E:\backups\call_logger.zip';
  const targetPath = r'C:\data\call_logger.db';
  const restoredPath = r'C:\data\call_logger.db';

  Future<void> closeOk() async {}

  test('επιτυχής επαναφορά: applySwitchToSession καλείται ακριβώς μία φορά '
      'με τη διαδρομή της επαναφερμένης βάσης', () async {
    final hooks = _FakeHooks();
    final runner = DatabaseInitRunnerResult(
      result: DatabaseInitResult.success(restoredPath),
      isLocalDevMode: false,
    );

    final ok = await _orchestrateRestoreFinale(
      restore: () => DatabaseZipPickRestore.restoreToTarget(
        zipPath,
        targetDatabasePath: targetPath,
        closeConnection: closeOk,
        runRestore:
            (
              path, {
              required String targetDatabasePath,
              String? databaseEntryName,
            }) async {
              expect(targetDatabasePath, targetPath);
              return const DatabaseRestoreResult(
                success: true,
                databasePath: restoredPath,
              );
            },
      ),
      hooks: hooks,
      verify: (_) async => (ok: true, runner: runner),
    );

    expect(ok, isTrue);
    expect(hooks.applyCallCount, 1);
    expect(hooks.appliedPath, restoredPath);
    expect(hooks.reportCallCount, 0);
  });

  test('αποτυχία επαναφοράς: applySwitchToSession δεν καλείται ποτέ', () async {
    final hooks = _FakeHooks();
    final runner = DatabaseInitRunnerResult(
      result: DatabaseInitResult.success(restoredPath),
      isLocalDevMode: false,
    );

    final ok = await _orchestrateRestoreFinale(
      restore: () => DatabaseZipPickRestore.restoreToTarget(
        zipPath,
        targetDatabasePath: targetPath,
        closeConnection: closeOk,
        runRestore:
            (
              path, {
              required String targetDatabasePath,
              String? databaseEntryName,
            }) async {
              return const DatabaseRestoreResult(
                success: false,
                message: 'Αποτυχία επαναφοράς από zip.',
              );
            },
      ),
      hooks: hooks,
      verify: (_) async => (ok: true, runner: runner),
    );

    expect(ok, isFalse);
    expect(hooks.applyCallCount, 0);
    expect(hooks.reportCallCount, 0);
    expect(hooks.calls, isEmpty);
  });
}
