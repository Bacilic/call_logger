import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/database_backup_settings.dart';
import '../services/database_backup_service.dart';
import '../utils/backup_schedule_utils.dart';
import 'database_backup_settings_provider.dart';

/// Προγραμματιστής εβδομαδιαίου ωρολογίου (έλεγχος κάθε 1 λεπτό) + έλεγχος εκκίνησης.
final backupSchedulerProvider =
    NotifierProvider<BackupSchedulerNotifier, int>(BackupSchedulerNotifier.new);

class BackupSchedulerNotifier extends Notifier<int> {
  Timer? _timer;
  bool _runLock = false;

  @override
  int build() {
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
    });
    return 0;
  }

  /// Φόρτωση ρυθμίσεων, [checkStartupStatus], εκκίνηση περιοδικού ελέγχου.
  Future<void> checkStartupAndStart() async {
    await ref.read(databaseBackupSettingsProvider.notifier).load();
    final settings = ref.read(databaseBackupSettingsProvider);
    await checkStartupStatus(settings);
    startTimer();
  }

  void startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(_tick());
    });
  }

  Future<void> checkStartupStatus(DatabaseBackupSettings settings) async {
    if (!settings.backupOnExit || !settings.usesCustomSchedule) {
      return;
    }
    if (settings.destinationDirectory.trim().isEmpty) {
      return;
    }

    final now = DateTime.now();
    final deadline = BackupScheduleUtils.lastPassedScheduleInstant(
      now,
      settings.backupDays,
      settings.backupTime,
    );
    if (deadline == null) return;

    if (now.difference(deadline) > const Duration(days: 14)) {
      return;
    }

    final attempt = settings.lastBackupAttempt;
    if (attempt != null && !attempt.isBefore(deadline)) {
      return;
    }

    final notifier = ref.read(databaseBackupSettingsProvider.notifier);
    final current = ref.read(databaseBackupSettingsProvider);
    if (current.lastBackupStatus == BackupScheduleStatus.failed) {
      return;
    }

    await notifier.setLastBackupStatus(BackupScheduleStatus.missed);
    state = state + 1;
  }

  Future<void> _tick() async {
    if (_runLock) return;
    final settings = ref.read(databaseBackupSettingsProvider);
    if (!settings.backupOnExit) return;
    if (!settings.usesCustomSchedule) return;
    if (settings.destinationDirectory.trim().isEmpty) return;

    final now = DateTime.now();
    if (!BackupScheduleUtils.isScheduledWeekday(now, settings.backupDays)) {
      return;
    }
    if (!BackupScheduleUtils.hasReachedTimeToday(now, settings.backupTime)) {
      return;
    }

    final last = settings.lastBackupAttempt;
    if (last != null && BackupScheduleUtils.isSameLocalDate(last, now)) {
      return;
    }

    _runLock = true;
    try {
      final notifier = ref.read(databaseBackupSettingsProvider.notifier);
      final attemptAt = DateTime.now();
      await notifier.setLastBackupAttempt(attemptAt);

      final fresh = ref.read(databaseBackupSettingsProvider);
      final result = await DatabaseBackupFileOperation.run(fresh);

      await notifier.setLastBackupAttempt(DateTime.now());
      await notifier.setLastBackupStatus(
        result.success
            ? BackupScheduleStatus.success
            : BackupScheduleStatus.failed,
      );
      state = state + 1;
    } finally {
      _runLock = false;
    }
  }
}
