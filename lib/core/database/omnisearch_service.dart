import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/building_map_floor.dart';
import '../utils/search_text_normalizer.dart';
import 'building_map_repository.dart';
import 'directory_support.dart';

enum BuildingMapOmnisearchEntityKind { department, user, equipment }

class BuildingMapOmnisearchHit {
  const BuildingMapOmnisearchHit({
    required this.kind,
    required this.entityId,
    required this.title,
    required this.departmentIds,
    this.subtitle,
    this.mapDisplayLabel,
  });

  final BuildingMapOmnisearchEntityKind kind;
  final int entityId;
  final String title;
  final String? subtitle;
  /// Ετικέτα όπως εμφανίζεται στον χάρτη (αν διαφέρει από [title]).
  final String? mapDisplayLabel;
  final List<int> departmentIds;
}

/// Read-only αναζήτηση καταλόγου για τον χάρτη κτιρίου (τμήματα, χρήστες, εξοπλισμός).
class OmnisearchService {
  OmnisearchService(this.db, this._support)
      : _buildingMap = BuildingMapRepository(db, _support);

  final Database db;
  final DirectorySupport _support;
  final BuildingMapRepository _buildingMap;

  int _omnisearchRank({
    required String query,
    required List<String> fields,
  }) {
    var best = 3;
    for (final raw in fields) {
      final value = SearchTextNormalizer.normalizeForSearch(raw);
      if (value.isEmpty) continue;
      if (value == query) return 0;
      if (value.startsWith(query) && best > 1) {
        best = 1;
        continue;
      }
      if (value.contains(query) && best > 2) {
        best = 2;
      }
    }
    return best;
  }

  String _omnisearchMapDisplayLabelFlat(String? mapCustomName) {
    final custom = mapCustomName?.trim() ?? '';
    if (custom.isEmpty) return '';
    return custom.replaceAll(RegExp(r'\s+'), ' ');
  }

  String _buildingMapFloorDisplayLabel(BuildingMapFloor f) {
    final g = f.floorGroup?.trim();
    return (g != null && g.isNotEmpty) ? '$g · ${f.label}' : f.label;
  }

  bool _isDepartmentMappedOnMap(
    Map<String, dynamic> row,
    Set<int> floorIds,
  ) {
    final w = (row['map_width'] as num?)?.toDouble() ?? 0;
    final h = (row['map_height'] as num?)?.toDouble() ?? 0;
    if (w <= 0 || h <= 0) return false;
    if (row['map_x'] == null || row['map_y'] == null) return false;
    final mapFloorRaw = row['map_floor'];
    final int? mf = mapFloorRaw is int
        ? mapFloorRaw
        : int.tryParse(mapFloorRaw?.toString().trim() ?? '');
    return mf != null && floorIds.contains(mf);
  }

  String? _omnisearchDepartmentMapDisplayLabel(
    String departmentName,
    String? mapCustomName,
  ) {
    final flat = _omnisearchMapDisplayLabelFlat(mapCustomName);
    if (flat.isEmpty) return null;
    if (flat == departmentName.trim()) return null;
    return flat;
  }

  String _omnisearchDepartmentSubtitle(
    Map<String, dynamic> row,
    Map<int, BuildingMapFloor> floorById,
    Set<int> floorIds,
  ) {
    final parts = <String>['Τμήμα'];
    final floorId = row['floor_id'] as int?;
    final floor = floorId != null ? floorById[floorId] : null;
    if (floor != null) {
      parts.add(_buildingMapFloorDisplayLabel(floor));
    }
    if (!_isDepartmentMappedOnMap(row, floorIds)) {
      parts.add('χωρίς σχεδίαση');
    }
    return parts.join(' • ');
  }

  String? _omnisearchUnmappedHintForDepartmentId(
    int departmentId,
    Map<int, Map<String, dynamic>> deptById,
    Map<int, BuildingMapFloor> floorById,
    Set<int> floorIds,
  ) {
    final row = deptById[departmentId];
    if (row == null) return null;
    if (_isDepartmentMappedOnMap(row, floorIds)) return null;
    final floorId = row['floor_id'] as int?;
    final floor = floorId != null ? floorById[floorId] : null;
    if (floor != null) {
      return 'χωρίς σχεδίαση · ${_buildingMapFloorDisplayLabel(floor)}';
    }
    return 'χωρίς σχεδίαση';
  }

  Future<List<BuildingMapOmnisearchHit>> searchBuildingMapOmnisearch(
    String query, {
    int limit = 50,
  }) async {
    final normalized = SearchTextNormalizer.normalizeForSearch(query);
    if (normalized.isEmpty || limit <= 0) return const [];

    await _support.ensurePhonesDepartmentColumn(db);

    final floors = await _buildingMap.listBuildingMapFloors();
    final floorById = {for (final f in floors) f.id: f};
    final floorIds = floorById.keys.toSet();

    final deptRows = await db.rawQuery('''
      SELECT
        id,
        name,
        map_custom_name,
        floor_id,
        map_floor,
        map_x,
        map_y,
        map_width,
        map_height
      FROM departments
      WHERE ${DirectorySupport.notDeletedClause}
      ORDER BY name COLLATE NOCASE ASC
    ''');
    final deptById = <int, Map<String, dynamic>>{
      for (final row in deptRows)
        if (row['id'] is int) row['id'] as int: row,
    };

    final userRows = await db.rawQuery('''
      SELECT
        u.id AS id,
        u.first_name AS first_name,
        u.last_name AS last_name,
        u.department_id AS department_id,
        d.name AS department_name,
        GROUP_CONCAT(DISTINCT p.number) AS phones_csv
      FROM users u
      LEFT JOIN departments d ON d.id = u.department_id
      LEFT JOIN user_phones up ON up.user_id = u.id
      LEFT JOIN phones p ON p.id = up.phone_id
      WHERE COALESCE(u.is_deleted, 0) = 0
      GROUP BY u.id, u.first_name, u.last_name, u.department_id, d.name
      ORDER BY u.last_name COLLATE NOCASE ASC, u.first_name COLLATE NOCASE ASC
    ''');

    final userPhoneDeptRows = await db.rawQuery('''
      WITH phone_dept AS (
        SELECT p.id AS phone_id, p.department_id AS department_id
        FROM phones p
        WHERE p.department_id IS NOT NULL
        UNION
        SELECT dp.phone_id AS phone_id, dp.department_id AS department_id
        FROM department_phones dp
      )
      SELECT DISTINCT
        up.user_id AS user_id,
        pd.department_id AS department_id
      FROM user_phones up
      JOIN phone_dept pd ON pd.phone_id = up.phone_id
      JOIN departments d ON d.id = pd.department_id
      WHERE COALESCE(d.is_deleted, 0) = 0
      ORDER BY up.user_id ASC, pd.department_id ASC
    ''');

    final equipmentRows = await db.rawQuery('''
      SELECT
        e.id AS id,
        e.code_equipment AS code_equipment,
        e.type AS type,
        e.notes AS notes,
        e.department_id AS department_id,
        d.name AS department_name
      FROM equipment e
      LEFT JOIN departments d ON d.id = e.department_id
      WHERE COALESCE(e.is_deleted, 0) = 0
      ORDER BY e.code_equipment COLLATE NOCASE ASC, e.type COLLATE NOCASE ASC
    ''');

    final userPhoneDepartmentIds = <int, Set<int>>{};
    for (final row in userPhoneDeptRows) {
      final uid = row['user_id'] as int?;
      final did = row['department_id'] as int?;
      if (uid == null || did == null) continue;
      userPhoneDepartmentIds.putIfAbsent(uid, () => <int>{}).add(did);
    }

    final hits = <(int rank, int kindOrder, String sortKey, BuildingMapOmnisearchHit hit)>[];

    for (final row in deptRows) {
      final id = row['id'] as int?;
      final name = (row['name'] as String?)?.trim() ?? '';
      final customName = (row['map_custom_name'] as String?)?.trim() ?? '';
      if (id == null || name.isEmpty) continue;

      if (!SearchTextNormalizer.matchesNormalizedQuery(name, normalized)) {
        continue;
      }

      final mapDisplayLabel = _omnisearchDepartmentMapDisplayLabel(
        name,
        customName.isEmpty ? null : customName,
      );

      final rank = _omnisearchRank(query: normalized, fields: [name]);
      hits.add((
        rank,
        0,
        name.toLowerCase(),
        BuildingMapOmnisearchHit(
          kind: BuildingMapOmnisearchEntityKind.department,
          entityId: id,
          title: name,
          subtitle: _omnisearchDepartmentSubtitle(row, floorById, floorIds),
          mapDisplayLabel: mapDisplayLabel,
          departmentIds: [id],
        ),
      ));
    }

    for (final row in userRows) {
      final id = row['id'] as int?;
      if (id == null) continue;
      final first = (row['first_name'] as String?)?.trim() ?? '';
      final last = (row['last_name'] as String?)?.trim() ?? '';
      final fullName = '$first $last'.trim();
      final phonesCsv = (row['phones_csv'] as String?)?.trim() ?? '';
      final deptName = (row['department_name'] as String?)?.trim() ?? '';
      final searchableText = '$fullName $phonesCsv $deptName'.trim();
      if (!SearchTextNormalizer.matchesNormalizedQuery(searchableText, normalized)) {
        continue;
      }
      final departmentIds = <int>{};
      final userDepartmentId = row['department_id'] as int?;
      if (userDepartmentId != null) {
        departmentIds.add(userDepartmentId);
      }
      departmentIds.addAll(userPhoneDepartmentIds[id] ?? const <int>{});
      final title = fullName.isEmpty ? '(Χωρίς όνομα)' : fullName;
      final subtitleParts = <String>[];
      if (deptName.isNotEmpty) subtitleParts.add(deptName);
      if (phonesCsv.isNotEmpty) subtitleParts.add(phonesCsv);
      if (departmentIds.length == 1) {
        final hint = _omnisearchUnmappedHintForDepartmentId(
          departmentIds.first,
          deptById,
          floorById,
          floorIds,
        );
        if (hint != null) subtitleParts.add(hint);
      }
      final rank = _omnisearchRank(
        query: normalized,
        fields: [title, deptName, phonesCsv],
      );
      hits.add((
        rank,
        1,
        title.toLowerCase(),
        BuildingMapOmnisearchHit(
          kind: BuildingMapOmnisearchEntityKind.user,
          entityId: id,
          title: title,
          subtitle: subtitleParts.isEmpty ? null : subtitleParts.join(' • '),
          departmentIds: departmentIds.toList()..sort(),
        ),
      ));
    }

    for (final row in equipmentRows) {
      final id = row['id'] as int?;
      if (id == null) continue;
      final code = (row['code_equipment'] as String?)?.trim() ?? '';
      final type = (row['type'] as String?)?.trim() ?? '';
      final notes = (row['notes'] as String?)?.trim() ?? '';
      final deptName = (row['department_name'] as String?)?.trim() ?? '';
      final searchableText = '$code $type $notes $deptName'.trim();
      if (!SearchTextNormalizer.matchesNormalizedQuery(searchableText, normalized)) {
        continue;
      }
      final title = code.isNotEmpty
          ? code
          : (type.isNotEmpty ? type : '(Χωρίς κωδικό)');
      final subtitleParts = <String>[];
      if (type.isNotEmpty && type != title) subtitleParts.add(type);
      if (deptName.isNotEmpty) subtitleParts.add(deptName);
      final equipmentDepartmentId = row['department_id'] as int?;
      final departmentIds = <int>[
        ?equipmentDepartmentId,
      ];
      if (departmentIds.length == 1 && departmentIds.first > 0) {
        final hint = _omnisearchUnmappedHintForDepartmentId(
          departmentIds.first,
          deptById,
          floorById,
          floorIds,
        );
        if (hint != null) subtitleParts.add(hint);
      }
      final rank = _omnisearchRank(
        query: normalized,
        fields: [title, type, notes, deptName],
      );
      hits.add((
        rank,
        2,
        title.toLowerCase(),
        BuildingMapOmnisearchHit(
          kind: BuildingMapOmnisearchEntityKind.equipment,
          entityId: id,
          title: title,
          subtitle: subtitleParts.isEmpty ? null : subtitleParts.join(' • '),
          departmentIds: departmentIds,
        ),
      ));
    }

    hits.sort((a, b) {
      final byRank = a.$1.compareTo(b.$1);
      if (byRank != 0) return byRank;
      final byKind = a.$2.compareTo(b.$2);
      if (byKind != 0) return byKind;
      return a.$3.compareTo(b.$3);
    });

    return hits.take(limit).map((row) => row.$4).toList(growable: false);
  }
}
