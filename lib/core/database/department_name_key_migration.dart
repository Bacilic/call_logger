import 'database_helper.dart';
import 'department_repository.dart';
import 'settings_repository.dart';

/// Εφάπαξ επαναϋπολογισμός `departments.name_key` με τον κανόνα τελικού σίγματος (ς/σ).
class DepartmentNameKeyMigrationRunner {
  DepartmentNameKeyMigrationRunner._();

  static const String _kSettingKey =
      'department_name_key_final_sigma_backfill_v1_done';

  static Future<void> runIfNeeded() async {
    final db = await DatabaseHelper.instance.database;
    final done = await SettingsRepository(db).getSetting(_kSettingKey);
    if (done == '1') return;
    await DepartmentRepository(db).backfillAllDepartmentNameKeys();
    await SettingsRepository(db).saveSetting(_kSettingKey, '1');
  }
}
