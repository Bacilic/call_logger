import 'database_helper.dart';
import 'directory_repository.dart';

/// Εφάπαξ συμπλήρωση `floor_id` από `map_floor` (χωρίς αλλαγή `building`).
class DepartmentFloorMigrationRunner {
  DepartmentFloorMigrationRunner._();

  static const String _kSettingKey = 'department_floor_id_backfill_v1_done';

  static Future<void> runIfNeeded() async {
    final db = await DatabaseHelper.instance.database;
    final repo = DirectoryRepository(db);
    final done = await repo.getSetting(_kSettingKey);
    if (done == '1') return;
    await repo.backfillDepartmentFloorIdsFromMapFloor();
    await repo.setSetting(_kSettingKey, '1');
  }
}
