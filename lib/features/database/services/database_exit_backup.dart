import '../../../core/database/database_helper.dart';
import '../../../core/database/directory_repository.dart';
import '../models/database_backup_settings.dart';
import '../utils/backup_schedule_status.dart';
import '../utils/backup_schedule_utils.dart';
import 'database_backup_audit.dart';
import 'database_backup_service.dart';

/// Fallback backup κατά το κλείσιμο παραθύρου (Windows) — μόνο σε προγραμματισμένη
/// ημέρα, μετά την ώρα και όταν δεν έχει ολοκληρωθεί επιτυχώς το σημερινό αντίγραφο.
class DatabaseExitBackup {
  DatabaseExitBackup._();

  static Future<void> runIfEnabled() async {
    final db = await DatabaseHelper.instance.database;
    final repo = DirectoryRepository(db);
    final raw = await repo.getSetting(DatabaseBackupSettings.appSettingsKey);
    final settings = DatabaseBackupSettings.fromJsonString(raw);
    if (!BackupScheduleStatusFormatter.shouldRunExitBackup(
      settings,
      DateTime.now(),
    )) {
      return;
    }

    final result = await DatabaseBackupService.runBackup(
      settings,
      requireDestination: true,
      auditTrigger: BackupAuditTrigger.onExit,
    );

    final updated = settings.copyWith(
      lastBackupAttempt: DateTime.now(),
      lastBackupStatus: result.success
          ? BackupScheduleStatus.success
          : (result.failureCode == DatabaseBackupFailureCode.folderMissing
              ? BackupScheduleStatus.folderMissing
              : BackupScheduleStatus.failed),
    );
    await repo.setSetting(
      DatabaseBackupSettings.appSettingsKey,
      updated.toJsonString(),
    );
  }
}
