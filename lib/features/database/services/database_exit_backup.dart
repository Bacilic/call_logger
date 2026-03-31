import '../../../core/database/database_helper.dart';
import '../models/database_backup_settings.dart';
import 'database_backup_service.dart';

/// Αθόρυβο backup κατά το κλείσιμο παραθύρου (Windows).
class DatabaseExitBackup {
  DatabaseExitBackup._();

  static Future<void> runIfEnabled() async {
    final raw = await DatabaseHelper.instance
        .getSetting(DatabaseBackupSettings.appSettingsKey);
    final settings = DatabaseBackupSettings.fromJsonString(raw);
    if (!settings.backupOnExit) return;
    if (!settings.usesCustomSchedule) return;
    await DatabaseBackupService.runBackup(
      settings,
      requireDestination: true,
    );
  }
}
