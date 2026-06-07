import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/database_helper.dart';
import '../models/database_backup_settings.dart';
import '../services/database_backup_audit.dart';
import '../services/database_backup_service.dart';
import '../utils/backup_destination_folder_validator.dart';
import '../utils/backup_schedule_status.dart';
import '../utils/backup_schedule_utils.dart';
import 'database_backup_settings_provider.dart';

/// Προγραμματιστής εβδομαδιαίου ωρολογίου (έλεγχος κάθε 1 λεπτό) + έλεγχος εκκίνησης.
final backupSchedulerProvider =
    NotifierProvider<BackupSchedulerNotifier, int>(BackupSchedulerNotifier.new);

class BackupSchedulerNotifier extends Notifier<int> {
  Timer? _timer;
  bool _runLock = false;
  String? _skipAuditLoggedKey;

  /// True όσο τρέχει προγραμματισμένο αντίγραφο ασφαλείας.
  bool get isBackupJobRunning => _runLock;

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
    var settings = ref.read(databaseBackupSettingsProvider);
    await checkStartupStatus(settings);
    settings = ref.read(databaseBackupSettingsProvider);
    await checkDestinationFolderStatus(settings);
    startTimer();
  }

  void startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(_tick());
    });
  }

  static bool _isAtScheduledWindow(
    DatabaseBackupSettings settings,
    DateTime now,
  ) =>
      settings.usesCustomSchedule &&
      BackupScheduleUtils.isScheduledWeekday(now, settings.backupDays) &&
      BackupScheduleUtils.hasReachedTimeToday(now, settings.backupTime);

  void _maybeLogScheduledSkip(
    DatabaseBackupSettings settings,
    String skipReason,
  ) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final key = '$today:$skipReason';
    if (_skipAuditLoggedKey == key) return;
    _skipAuditLoggedKey = key;
    unawaited(
      DatabaseBackupAudit.logScheduledSkip(
        skipReason: skipReason,
        destination: settings.destinationDirectory.trim(),
        scheduledTime: settings.backupTime,
      ),
    );
  }

  Future<void> checkStartupStatus(DatabaseBackupSettings settings) async {
    final now = DateTime.now();
    final notifier = ref.read(databaseBackupSettingsProvider.notifier);

    if (BackupScheduleStatusFormatter.isScheduleSatisfiedForToday(settings, now)) {
      if (BackupScheduleStatus.normalize(settings.lastBackupStatus) ==
          BackupScheduleStatus.missed) {
        await notifier.setLastBackupStatus(BackupScheduleStatus.none);
        state = state + 1;
      }
      return;
    }

    if (!BackupScheduleStatusFormatter.shouldMarkScheduleMissed(settings, now)) {
      if (BackupScheduleStatus.normalize(settings.lastBackupStatus) ==
          BackupScheduleStatus.missed) {
        await notifier.setLastBackupStatus(BackupScheduleStatus.none);
        state = state + 1;
      }
      return;
    }

    final deadline = BackupScheduleUtils.lastPassedScheduleInstant(
      now,
      settings.backupDays,
      settings.backupTime,
    );
    if (deadline == null) return;

    await notifier.setLastBackupStatus(BackupScheduleStatus.missed);
    await DatabaseBackupAudit.logScheduledMissed(
      missedDeadline: deadline,
      destination: settings.destinationDirectory.trim(),
      scheduledTime: settings.backupTime,
    );
    state = state + 1;
  }

  /// Αναβάθμιση failed/missed σε folder_missing όταν λείπει ο φάκελος· καθάρισμα όταν επανέρχεται.
  Future<void> checkDestinationFolderStatus(
    DatabaseBackupSettings settings,
  ) async {
    if (!settings.backupOnExit) return;
    final dest = settings.destinationDirectory.trim();
    if (dest.isEmpty) return;

    final db = await DatabaseHelper.instance.database;
    final baseName = p.basenameWithoutExtension(db.path);
    final content =
        await BackupDestinationFolderValidator.inspectDestinationContent(
      destinationDirectory: dest,
      dbBaseName: baseName,
    );

    final notifier = ref.read(databaseBackupSettingsProvider.notifier);
    final st = BackupScheduleStatus.normalize(settings.lastBackupStatus);

    if (content.kind == BackupDestinationContentKind.folderMissing) {
      if (st == BackupScheduleStatus.failed ||
          st == BackupScheduleStatus.missed) {
        await notifier.setLastBackupStatus(BackupScheduleStatus.folderMissing);
        state = state + 1;
      }
      return;
    }

    if (st == BackupScheduleStatus.folderMissing) {
      await notifier.setLastBackupStatus(BackupScheduleStatus.none);
      state = state + 1;
    }
  }

  Future<void> _tick() async {
    final settings = ref.read(databaseBackupSettingsProvider);
    final now = DateTime.now();
    final atWindow = _isAtScheduledWindow(settings, now);

    if (_runLock) {
      if (atWindow) {
        _maybeLogScheduledSkip(settings, BackupAuditSkipReason.jobRunning);
      }
      return;
    }

    if (!settings.backupOnExit) {
      if (atWindow) {
        _maybeLogScheduledSkip(settings, BackupAuditSkipReason.backupDisabled);
      }
      return;
    }
    if (!settings.usesCustomSchedule) {
      if (atWindow) {
        _maybeLogScheduledSkip(settings, BackupAuditSkipReason.noSchedule);
      }
      return;
    }
    if (settings.destinationDirectory.trim().isEmpty) {
      if (atWindow) {
        _maybeLogScheduledSkip(settings, BackupAuditSkipReason.noDestination);
      }
      return;
    }

    if (!BackupScheduleUtils.isScheduledWeekday(now, settings.backupDays)) {
      return;
    }
    if (!BackupScheduleUtils.hasReachedTimeToday(now, settings.backupTime)) {
      return;
    }

    final last = settings.lastBackupAttempt;
    if (last != null && BackupScheduleUtils.isSameLocalDate(last, now)) {
      _maybeLogScheduledSkip(settings, BackupAuditSkipReason.alreadyRanToday);
      return;
    }

    _runLock = true;
    try {
      final notifier = ref.read(databaseBackupSettingsProvider.notifier);
      final attemptAt = DateTime.now();
      await notifier.setLastBackupAttempt(attemptAt);

      final fresh = ref.read(databaseBackupSettingsProvider);
      final result = await DatabaseBackupFileOperation.run(
        fresh,
        auditTrigger: BackupAuditTrigger.scheduled,
      );

      await notifier.setLastBackupAttempt(DateTime.now());
      await notifier.setLastBackupStatus(
        result.success
            ? BackupScheduleStatus.success
            : (result.failureCode == DatabaseBackupFailureCode.folderMissing
                ? BackupScheduleStatus.folderMissing
                : BackupScheduleStatus.failed),
      );
      state = state + 1;
    } finally {
      _runLock = false;
    }
  }
}
