part of 'directory_repository.dart';

mixin DirectoryRepositorySettingsSearch on DirectoryRepositoryBase {
  Future<String?> getSetting(String key, {DatabaseExecutor? executor}) =>
      _support.getSetting(key, executor: executor);

  Future<void> setSetting(String key, String value) async {
    await db.insert('app_settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<BuildingMapOmnisearchHit>> searchBuildingMapOmnisearch(
    String query, {
    int limit = 50,
  }) =>
      _omnisearch.searchBuildingMapOmnisearch(query, limit: limit);

  /// Μία γραμμή `departments` για άνοιγμα φόρμας τμήματος (ή null).
  Future<List<Map<String, dynamic>>> getNonUserPhonesCatalogRows() async {
    await _support.ensurePhonesDepartmentColumn(db);
    await _support.ensurePhonesIsDeletedColumn(db);
    return db.rawQuery('''
WITH phone_dept AS (
  SELECT p.id AS phone_id, p.department_id AS dept_id
  FROM phones p
  WHERE p.department_id IS NOT NULL
    AND COALESCE(p.is_deleted, 0) = 0
  UNION
  SELECT dp.phone_id AS phone_id, dp.department_id AS dept_id
  FROM department_phones dp
  JOIN phones p ON p.id = dp.phone_id
  WHERE COALESCE(p.is_deleted, 0) = 0
)
SELECT
  p.id AS phone_id,
  p.number AS number,
  GROUP_CONCAT(DISTINCT d.name) AS dept_names,
  MIN(d.id) AS primary_department_id
FROM phones p
LEFT JOIN phone_dept pd ON pd.phone_id = p.id
LEFT JOIN departments d ON d.id = pd.dept_id AND COALESCE(d.is_deleted, 0) = 0
WHERE COALESCE(p.is_deleted, 0) = 0
  AND NOT EXISTS (SELECT 1 FROM user_phones up WHERE up.phone_id = p.id)
GROUP BY p.id, p.number
ORDER BY p.number COLLATE NOCASE ASC
''');
  }

}
