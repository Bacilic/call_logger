import '../../../core/database/database_helper.dart';
import '../../../core/database/audit_service.dart';

/// Πηγή εκτέλεσης αντιγράφου ασφαλείας (για audit).
enum BackupAuditTrigger {
  manual,
  scheduled,
  onExit,
  maintenance,
  scheduledRetry,
}

/// Αποτέλεσμα προσπάθειας αντιγράφου (για audit).
enum BackupAuditOutcome { success, failed, skipped }

/// Κωδικοί παράλειψης οφειλόμενου αυτόματου αντιγράφου.
abstract final class BackupAuditSkipReason {
  static const noDestination = 'no_destination';
  static const backupDisabled = 'backup_disabled';
  static const jobRunning = 'job_running';
  static const databaseSwitchInProgress = 'database_switch_in_progress';
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
    BackupAuditSkipReason.noDestination =>
      'Παραλείφθηκε οφειλόμενο αντίγραφο: δεν έχει οριστεί φάκελος προορισμού.',
    BackupAuditSkipReason.backupDisabled =>
      'Παραλείφθηκε οφειλόμενο αντίγραφο: τα αυτόματα αντίγραφα είναι απενεργοποιημένα.',
    BackupAuditSkipReason.jobRunning =>
      'Παραλείφθηκε οφειλόμενο αντίγραφο: άλλη εργασία αντιγράφου σε εξέλιξη.',
    _ => 'Παραλείφθηκε οφειλόμενο αντίγραφο.',
  };

  static String _actionFor(BackupAuditOutcome outcome) => switch (outcome) {
    BackupAuditOutcome.success => 'ΑΝΤΙΓΡΑΦΟ ΑΣΦΑΛΕΙΑΣ ΕΠΙΤΥΧΙΑ',
    BackupAuditOutcome.failed => 'ΑΝΤΙΓΡΑΦΟ ΑΣΦΑΛΕΙΑΣ ΑΠΟΤΥΧΙΑ',
    BackupAuditOutcome.skipped => 'ΑΝΤΙΓΡΑΦΟ ΑΣΦΑΛΕΙΑΣ ΠΑΡΑΛΕΙΦΘΗΚΕ',
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
          : (skipReason != null ? skipReasonMessageEl(skipReason) : null);
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
  }) => log(
    trigger: trigger,
    outcome: success ? BackupAuditOutcome.success : BackupAuditOutcome.failed,
    details: message,
    destination: destination,
    outputPath: outputPath,
  );

  static Future<void> logScheduledSkip({
    required String skipReason,
    String? destination,
    Map<String, dynamic>? extra,
  }) => log(
    trigger: BackupAuditTrigger.scheduled,
    outcome: BackupAuditOutcome.skipped,
    skipReason: skipReason,
    destination: destination,
    extra: extra,
  );
}
