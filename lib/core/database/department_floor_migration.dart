import 'database_helper.dart';
import 'department_repository.dart';
import 'settings_repository.dart';

/// Εφάπαξ συμπλήρωση `floor_id` από `map_floor` (χωρίς αλλαγή `building`).
class DepartmentFloorMigrationRunner {
  DepartmentFloorMigrationRunner._();

  static const String _kSettingKey = 'department_floor_id_backfill_v1_done';

  static Future<void> runIfNeeded() async {
    final db = await DatabaseHelper.instance.database;
    final done = await SettingsRepository(db).getSetting(_kSettingKey);
    if (done == '1') return;
    await DepartmentRepository(db).backfillDepartmentFloorIdsFromMapFloor();
    await SettingsRepository(db).saveSetting(_kSettingKey, '1');
  }
}
