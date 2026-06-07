import '../../../core/database/database_helper.dart';
import '../../../core/services/audit_service.dart';

/// Πηγή εκτέλεσης αντιγράφου ασφαλείας (για audit).
enum BackupAuditTrigger {
  manual,
  scheduled,
  onExit,
  maintenance,
  scheduledRetry,
}

/// Αποτέλεσμα προσπάθειας αντιγράφου (για audit).
enum BackupAuditOutcome {
  success,
  failed,
  skipped,
  missed,
}

/// Κωδικοί παράλειψης προγραμματισμένου αντιγράφου.
abstract final class BackupAuditSkipReason {
  static const alreadyRanToday = 'already_ran_today';
  static const noDestination = 'no_destination';
  static const backupDisabled = 'backup_disabled';
  static const noSchedule = 'no_schedule';
  static const jobRunning = 'job_running';
  static const appNotRunning = 'app_not_running';
}

/// Καταγραφή ενεργειών αντιγράφου ασφαλείας στο `audit_log`.
class DatabaseBackupAudit {
  DatabaseBackupAudit._();

  static String triggerLabelEl(BackupAuditTrigger trigger) => switch (trigger) {
        BackupAuditTrigger.manual => 'χειροκίνητο',
        BackupAuditTrigger.scheduled => 'προγραμματισμένο',
        BackupAuditTrigger.onExit => 'κατά το κλείσιμο',
        BackupAuditTrigger.maintenance => 'πριν από συντήρηση',
        BackupAuditTrigger.scheduledRetry => 'επανάληψη προγράμματος',
      };

  static String skipReasonMessageEl(String reason) => switch (reason) {
        BackupAuditSkipReason.alreadyRanToday =>
          'Παραλείφθηκε προγραμματισμένο αντίγραφο: είχε ήδη εκτελεστεί αυτόματο αντίγραφο σήμερα.',
        BackupAuditSkipReason.noDestination =>
          'Παραλείφθηκε προγραμματισμένο αντίγραφο: δεν έχει οριστεί φάκελος προορισμού.',
        BackupAuditSkipReason.backupDisabled =>
          'Παραλείφθηκε προγραμματισμένο αντίγραφο: τα αυτόματα αντίγραφα είναι απενεργοποιημένα.',
        BackupAuditSkipReason.noSchedule =>
          'Παραλείφθηκε προγραμματισμένο αντίγραφο: δεν έχει οριστεί πρόγραμμα ημερών και ώρας.',
        BackupAuditSkipReason.jobRunning =>
          'Παραλείφθηκε προγραμματισμένο αντίγραφο: άλλη εργασία αντιγράφου σε εξέλιξη.',
        BackupAuditSkipReason.appNotRunning =>
          'Χάθηκε προγραμματισμένο αντίγραφο: η εφαρμογή δεν ήταν ανοιχτή στη σχετική ημέρα και ώρα ή δεν ολοκληρώθηκε εγκαίρως.',
        _ => 'Παραλείφθηκε προγραμματισμένο αντίγραφο.',
      };

  static String _actionFor(BackupAuditOutcome outcome) => switch (outcome) {
        BackupAuditOutcome.success => 'ΑΝΤΙΓΡΑΦΟ ΑΣΦΑΛΕΙΑΣ ΕΠΙΤΥΧΙΑ',
        BackupAuditOutcome.failed => 'ΑΝΤΙΓΡΑΦΟ ΑΣΦΑΛΕΙΑΣ ΑΠΟΤΥΧΙΑ',
        BackupAuditOutcome.skipped => 'ΑΝΤΙΓΡΑΦΟ ΑΣΦΑΛΕΙΑΣ ΠΑΡΑΛΕΙΦΘΗΚΕ',
        BackupAuditOutcome.missed => 'ΑΝΤΙΓΡΑΦΟ ΑΣΦΑΛΕΙΑΣ ΧΑΘΗΚΕ',
      };

  static Future<void> log({
    required BackupAuditTrigger trigger,
    required BackupAuditOutcome outcome,
    String? details,
    String? destination,
    String? outputPath,
    String? skipReason,
    Map<String, dynamic>? extra,
  }) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final user = await AuditService.performingUser(db);
      final resolvedDetails = details?.trim().isNotEmpty == true
          ? details!.trim()
          : (skipReason != null
              ? skipReasonMessageEl(skipReason)
              : null);
      final newValues = <String, dynamic>{
        'trigger': trigger.name,
        'trigger_el': triggerLabelEl(trigger),
        'outcome': outcome.name,
        if (destination != null && destination.trim().isNotEmpty)
          'destination': destination.trim(),
        if (outputPath != null && outputPath.trim().isNotEmpty)
          'output_path': outputPath.trim(),
        if (skipReason != null && skipReason.trim().isNotEmpty)
          'skip_reason': skipReason.trim(),
        ...?extra,
      };
      await AuditService.log(
        db,
        action: _actionFor(outcome),
        userPerforming: user,
        entityType: AuditEntityTypes.backup,
        details: resolvedDetails,
        newValues: newValues,
      );
    } catch (_) {}
  }

  static Future<void> logRunResult({
    required BackupAuditTrigger trigger,
    required bool success,
    String? message,
    String? destination,
    String? outputPath,
  }) =>
      log(
        trigger: trigger,
        outcome: success ? BackupAuditOutcome.success : BackupAuditOutcome.failed,
        details: message,
        destination: destination,
        outputPath: outputPath,
      );

  static Future<void> logScheduledSkip({
    required String skipReason,
    String? destination,
    String? scheduledTime,
    Map<String, dynamic>? extra,
  }) =>
      log(
        trigger: BackupAuditTrigger.scheduled,
        outcome: BackupAuditOutcome.skipped,
        skipReason: skipReason,
        destination: destination,
        extra: {
          if (scheduledTime != null && scheduledTime.trim().isNotEmpty)
            'scheduled_time': scheduledTime.trim(),
          ...?extra,
        },
      );

  static Future<void> logScheduledMissed({
    required DateTime missedDeadline,
    String? destination,
    String? scheduledTime,
  }) =>
      log(
        trigger: BackupAuditTrigger.scheduled,
        outcome: BackupAuditOutcome.missed,
        skipReason: BackupAuditSkipReason.appNotRunning,
        destination: destination,
        extra: {
          'missed_deadline': missedDeadline.toIso8601String(),
          if (scheduledTime != null && scheduledTime.trim().isNotEmpty)
            'scheduled_time': scheduledTime.trim(),
        },
      );
}
