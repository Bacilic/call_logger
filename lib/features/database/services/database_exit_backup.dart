import '../../../core/database/database_helper.dart';
import '../../../core/database/directory_repository.dart';
import '../models/database_backup_settings.dart';
import 'database_backup_service.dart';

/// Αθόρυβο backup κατά το κλείσιμο παραθύρου (Windows).
class DatabaseExitBackup {
  DatabaseExitBackup._();

  static Future<void> runIfEnabled() async {
    final db = await DatabaseHelper.instance.database;
    final raw = await DirectoryRepository(db)
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
