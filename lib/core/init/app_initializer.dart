import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/database/providers/backup_scheduler_provider.dart';
import '../../features/database/providers/database_backup_settings_provider.dart';
import '../database/database_init_progress_provider.dart';
import '../database/database_init_result.dart';
import '../database/database_init_runner.dart';
import '../database/database_path_resolution.dart';
import '../database/lock_diagnostic_service.dart';
import '../services/core_lexicon_service.dart';
import '../services/settings_service.dart';

/// Αποτέλεσμα αρχικοποίησης εφαρμογής (βάση δεδομένων + τρόπος λειτουργίας).
class AppInitResult {
  const AppInitResult({
    required this.result,
    required this.isLocalDevMode,
    this.spellCheckReady = false,
  });

  final DatabaseInitResult result;
  final bool isLocalDevMode;

  /// True αν φορτώθηκε λεξικό-πυρήνας από αποθηκευμένη διαδρομή.
  final bool spellCheckReady;

  bool get success => result.isSuccess;
  String? get message => result.message;
  String? get details => result.details;
  DatabaseStatus get dbStatus => result.status;
}

/// Αρχικοποίηση εφαρμογής: έλεγχος βάσης δεδομένων και υπολογισμός τρόπου λειτουργίας.
class AppInitializer {
  AppInitializer._();

  static Future<void> activateBackupSchedulingAfterDatabaseReady(
    Ref ref,
  ) async {
    await ref.read(databaseBackupSettingsProvider.notifier).load();
    await ref.read(backupSchedulerProvider.notifier).checkStartupAndStart();
  }

  static Future<AppInitResult> initialize({
    DatabaseInitProgressNotifier? progressNotifier,
  }) async {
    try {
      final runnerResult = await runDatabaseInitChecks(
        closeConnectionFirst: false,
        progressNotifier: progressNotifier,
      );
      var spellCheckReady = false;
      if (runnerResult.result.isSuccess) {
        try {
          spellCheckReady =
              await CoreLexiconService.instance.bootstrapFromSavedPath();
        } catch (_) {
          spellCheckReady = false;
        }
      }
      progressNotifier?.setStep(
        'Ολοκλήρωση εκκίνησης',
        clearSecondsRemaining: true,
      );
      return AppInitResult(
        result: runnerResult.result,
        isLocalDevMode: runnerResult.isLocalDevMode,
        spellCheckReady: spellCheckReady,
      );
    } catch (e, st) {
      var result = DatabaseInitResult.fromException(e, null, st);
      if (e is TimeoutException || e is DatabaseInitException) {
        try {
          progressNotifier?.setStep('Εντοπισμός διεργασίας');
          final configured = await SettingsService().getDatabasePath();
          final resolved = await resolveEffectiveDatabasePath(configured);
          final diagnostic = await const LockDiagnosticService()
              .detectLockingProcess(resolved.path);
          if (diagnostic.trim().isNotEmpty) {
            final details = result.details?.trim();
            final merged = (details == null || details.isEmpty)
                ? diagnostic
                : '$details\n\n--- Lock diagnostics ---\n$diagnostic';
            result = result.copyWith(details: merged);
            progressNotifier?.setDiagnostic(diagnostic);
          }
        } catch (_) {}
      }
      return AppInitResult(
        result: result,
        isLocalDevMode: false,
        spellCheckReady: false,
      );
    }
  }
}
