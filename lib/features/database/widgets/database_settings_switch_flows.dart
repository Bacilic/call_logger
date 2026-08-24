import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/database/database_init_runner.dart';
import '../../../core/database/database_restore_flow.dart';
import '../../../core/init/database_switch_completion.dart';
import '../../../core/init/database_switch_guard.dart';
import '../../../core/providers/active_critical_operations_provider.dart';
import '../../../core/services/settings_service.dart';
import '../providers/database_backup_settings_provider.dart';
import '../services/database_path_switch_runner.dart';
import '../services/restore_plan.dart';
import 'database_check_failed_dialog.dart';

/// Οι ροές εναλλαγής βάσης και επαναφοράς από zip, κοινές στις καρτέλες
/// «Βάση» και «Επαναφορά» του διαλόγου ρυθμίσεων.
///
/// Πριν από την καρτελοποίηση ζούσαν σε ένα ενιαίο πάνελ· δύο καρτέλες τις
/// χρειάζονται και οι δύο (η «Βάση» επαναφέρει όταν ο επιλογέας διαλέξει
/// αρχείο zip), οπότε η υλοποίηση των [DatabasePathSwitchHooks] μένει σε ένα
/// σημείο αντί να αντιγραφεί.
mixin DatabaseSettingsSwitchFlows<T extends ConsumerStatefulWidget>
    on ConsumerState<T>
    implements DatabasePathSwitchHooks {
  /// Ειδοποίηση του κελύφους μετά από επιτυχή αλλαγή/δημιουργία βάσης.
  Future<void> Function()? get onDatabaseLifecycleChanged;

  /// Ενημέρωση της οθόνης της καρτέλας μετά από επιτυχή εναλλαγή — π.χ.
  /// ξαναφόρτωμα της λίστας διαδρομών. Προεπιλογή: τίποτα.
  Future<void> refreshAfterDatabaseSwitch(String activePath) async {}

  /// Αλλαγή στη διαδρομή βάσης που επέλεξε ο χρήστης (επιλογέας ή πρόσφατη).
  Future<void> switchToPickedDatabasePath(String newPath) async {
    final trimmed = newPath.trim();
    if (trimmed.isEmpty || !mounted) return;
    if (!await ensureDatabaseSwitchAllowed(context, ref)) return;
    if (!mounted) return;

    await runDatabasePathSwitch(path: trimmed, hooks: this);
  }

  Future<void> restoreFromBackupZip({String? preselectedZipPath}) async {
    await runGuardedDatabaseSwitch(context, ref, () async {
      if (!mounted) return;
      // Υπόδειξη φακέλου: η αποθηκευμένη τιμή των ρυθμίσεων αντιγράφων — ό,τι
      // έχει περάσει από επικύρωση, όχι μισογραμμένο κείμενο πεδίου.
      final backupFolder = ref
          .read(databaseBackupSettingsProvider)
          .destinationDirectory
          .trim();
      final currentDbPath = (await SettingsService().getDatabasePath()).trim();
      if (!mounted) return;
      final defaultTarget = currentDbPath.isNotEmpty
          ? currentDbPath
          : AppConfig.defaultDbPath;
      final result = await runRestoreFromBackupZipFlow(
        context: context,
        backupFolderHint: backupFolder.isNotEmpty ? backupFolder : null,
        currentDatabasePath: defaultTarget,
        preselectedZipPath: preselectedZipPath,
        initialDestination: RestoreDestinationChoice.currentDatabase,
      );
      if (!mounted || !result.isSuccess) return;
      final toOpen = result.pathToOpen?.trim();
      if (toOpen != null && toOpen.isNotEmpty) {
        await runDatabasePathSwitch(path: toOpen, hooks: this);
      }
    });
  }

  @override
  Future<void> showVerifyingIndicator() async {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              height: 48,
              width: 48,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(width: 24),
            Expanded(
              child: Text(
                'Έλεγχος βάσης δεδομένων…',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Future<void> hideVerifyingIndicator() async {
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _applySwitchAfterSchemaRecovery() async {
    if (!mounted) return;
    final activePath = await SettingsService().getDatabasePath();
    if (!mounted) return;
    await applySwitchToSession(activePath);
  }

  @override
  Future<void> reportVerificationFailure(
    DatabaseInitRunnerResult runner,
  ) async {
    if (!mounted) return;
    final recovered = await showDatabaseCheckFailedDialog(
      context: context,
      result: runner.result,
      onSuccess: _applySwitchAfterSchemaRecovery,
    );
    if (recovered && mounted) {
      // Η διαδρομή μπορεί να είναι αντίγραφο (αναβαθμισμένο ή υποβαθμισμένο)
      // — ανανέωση ετικετών.
      final activePath = await SettingsService().getDatabasePath();
      if (!mounted) return;
      await refreshAfterDatabaseSwitch(activePath);
    }
  }

  @override
  Future<void> applySwitchToSession(String path) async {
    if (!mounted) return;
    await completeDatabaseSwitch(
      ref: ref,
      path: path,
      hooks: DatabaseSwitchCompletionHooks(
        onSessionStateUpdated: (switchedPath) async {
          if (!mounted) return;
          await refreshAfterDatabaseSwitch(switchedPath);
        },
        onLifecycleChanged: () async {
          await onDatabaseLifecycleChanged?.call();
        },
      ),
    );
  }

  @override
  void declareSwitchBegin() {
    ref
        .read(activeCriticalOperationsProvider.notifier)
        .begin(CriticalOperation.databaseSwitch);
  }

  @override
  void declareSwitchEnd() {
    ref
        .read(activeCriticalOperationsProvider.notifier)
        .end(CriticalOperation.databaseSwitch);
  }
}
