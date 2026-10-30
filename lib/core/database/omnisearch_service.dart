import 'dart:ui' show Offset;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/building_map_floor.dart';
import '../models/floor_plan_element.dart';
import '../models/floor_plan_placement.dart';
import '../utils/search_text_normalizer.dart';
import 'building_map_repository.dart';
import 'directory_support.dart';
import 'floor_plan_objects_repository.dart';
import 'floor_plan_placements_repository.dart';
import 'floor_plan_repository.dart';
import '../utils/display_text_sort.dart';

enum BuildingMapOmnisearchEntityKind {
  department,
  user,
  phone,
  equipment,

  /// Αντικείμενο του νέου χάρτη (εκτυπωτής, έπιπλο…).
  mapObject,
}

/// «Ποιος χώρος είναι εδώ;» για τα στοιχεία ενός ορόφου του νέου χάρτη: το
/// τμήμα του χώρου ή το ελεύθερο όνομά του. Η γεωμετρία ζει στον χάρτη, γι'
/// αυτό τη δίνει ο καλών.
typedef BuildingMapRoomLookup =
    ({int? departmentId, String? name})? Function(Offset world) Function(
      List<FloorPlanElement> elements,
    );

/// Πού βρίσκεται ένα αποτέλεσμα στον νέο χάρτη: όροφος, χώρος, σημείο, και
/// ποιο σύμβολο να φωτιστεί.
class BuildingMapOmnisearchSpot {
  const BuildingMapOmnisearchSpot({
    required this.floorId,
    required this.floorLabel,
    required this.center,
    required this.isPlacement,
    required this.itemId,
    this.roomName,
  });

  final int floorId;
  final String floorLabel;
  final Offset center;

  /// Θέση εγγραφής του Καταλόγου (`true`) ή αντικείμενο του χάρτη.
  final bool isPlacement;

  /// Το id της θέσης ή του αντικειμένου.
  final int itemId;

  /// Ο χώρος όπου βρίσκεται — όνομα ή τμήμα· `null` εκτός χώρου.
  final String? roomName;

  /// «Ισόγειο, Γραφείο υλικού».
  String get label => roomName == null ? floorLabel : '$floorLabel, $roomName';
}

class BuildingMapOmnisearchHit {
  const BuildingMapOmnisearchHit({
    required this.kind,
    required this.entityId,
    required this.title,
    required this.departmentIds,
    this.subtitle,
    this.mapDisplayLabel,
    this.spot,
    this.unplaced = false,
  });

  final BuildingMapOmnisearchEntityKind kind;
  final int entityId;
  final String title;
  final String? subtitle;

  /// Ετικέτα όπως εμφανίζεται στον χάρτη (αν διαφέρει από [title]).
  final String? mapDisplayLabel;
  final List<int> departmentIds;

  /// Η θέση στον νέο χάρτη· με αυτήν η μετάβαση πηγαίνει στο ίδιο το σύμβολο
  /// αντί για τον χώρο του τμήματος.
  final BuildingMapOmnisearchSpot? spot;

  /// Εγγραφή του Καταλόγου χωρίς θέση σε ενεργοποιημένο όροφο — φαίνεται
  /// αχνή, ώστε να μη μοιάζει ότι δεν υπάρχει.
  final bool unplaced;
}

/// Κάτοχος εξοπλισμού για τη γραμμή αποτελέσματος («ποιος και πού»).
class _OmnisearchEquipmentOwner {
  const _OmnisearchEquipmentOwner({
    required this.name,
    required this.departmentId,
    required this.departmentName,
  });

  final String name;
  final int? departmentId;
  final String departmentName;
}

/// Read-only αναζήτηση για τον χάρτη κτιρίου: Κατάλογος (τμήματα, υπάλληλοι,
/// τηλέφωνα, εξοπλισμός) και αντικείμενα του νέου χάρτη.
class OmnisearchService {
  OmnisearchService(this.db, [DirectorySupport? support])
    : _support = support ?? DirectorySupport(db),
      _buildingMap = BuildingMapRepository(db, support);

  final Database db;
  final DirectorySupport _support;
  final BuildingMapRepository _buildingMap;

  int _omnisearchRank({required String query, required List<String> fields}) {
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

  /// Σχεδιασμένο = κουτάκι στον παλιό χάρτη ή χώρος σε ενεργοποιημένο όροφο
  /// του νέου ([drawnOnNewMap]).
  bool _isDepartmentMappedOnMap(
    Map<String, dynamic> row,
    Set<int> floorIds,
    Set<int> drawnOnNewMap,
  ) {
    if (drawnOnNewMap.contains(row['id'])) return true;
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
    Set<int> drawnOnNewMap,
  ) {
    final parts = <String>['Τμήμα'];
    final floorId = row['floor_id'] as int?;
    final floor = floorId != null ? floorById[floorId] : null;
    if (floor != null) {
      parts.add(_buildingMapFloorDisplayLabel(floor));
    }
    if (!_isDepartmentMappedOnMap(row, floorIds, drawnOnNewMap)) {
      parts.add('χωρίς σχεδίαση');
    }
    return parts.join(' • ');
  }

  String? _omnisearchUnmappedHintForDepartmentId(
    int departmentId,
    Map<int, Map<String, dynamic>> deptById,
    Map<int, BuildingMapFloor> floorById,
    Set<int> floorIds,
    Set<int> drawnOnNewMap,
  ) {
    final row = deptById[departmentId];
    if (row == null) return null;
    if (_isDepartmentMappedOnMap(row, floorIds, drawnOnNewMap)) return null;
    final floorId = row['floor_id'] as int?;
    final floor = floorId != null ? floorById[floorId] : null;
    if (floor != null) {
      return 'χωρίς σχεδίαση · ${_buildingMapFloorDisplayLabel(floor)}';
    }
    return 'χωρίς σχεδίαση';
  }

  /// Τμήματα, υπάλληλοι, τηλέφωνα, εξοπλισμός και αντικείμενα του νέου
  /// χάρτη. Υπάλληλος με δύο θέσεις δίνει δύο αποτελέσματα· όροφος που δεν
  /// ενεργοποιήθηκε δεν δίνει θέσεις. Με [roomLookup] κάθε θέση λέει και τον
  /// χώρο της.
  Future<List<BuildingMapOmnisearchHit>> searchBuildingMapOmnisearch(
    String query, {
    int limit = 50,
    BuildingMapRoomLookup? roomLookup,
  }) async {
    final normalized = SearchTextNormalizer.normalizeForSearch(query);
    if (normalized.isEmpty || limit <= 0) return const [];

    await _support.ensurePhonesDepartmentColumn(db);

    final floors = await _buildingMap.listBuildingMapFloors();
    final floorById = {for (final f in floors) f.id: f};
    final floorIds = floorById.keys.toSet();

    final deptRows = sortedForDisplay(
      await db.rawQuery('''
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
    '''),
      (r) => [r['name'] as String?],
    );
    final deptById = <int, Map<String, dynamic>>{
      for (final row in deptRows)
        if (row['id'] is int) row['id'] as int: row,
    };
    final plans = FloorPlanRepository(db);
    final drawnOnNewMap = (await plans.activeFloorsWithRoomsOf(
      deptById.keys.toSet(),
    )).keys.toSet();

    // Θέσεις και αντικείμενα μόνο σε ενεργοποιημένους ορόφους: πριν από την
    // ενεργοποίηση ο όροφος δεν έχει αντικείμενα για τους συναδέλφους.
    final activeFloors = (await plans.activeFloorIds()).intersection(floorIds);
    final placementsOf =
        <(FloorPlanPlacementType, int), List<FloorPlanPlacement>>{};
    for (final p in await FloorPlanPlacementsRepository(db).allPlacements()) {
      if (!activeFloors.contains(p.floorId)) continue;
      (placementsOf[(p.type, p.entityId)] ??= []).add(p);
    }
    final roomsByFloor =
        <int, ({int? departmentId, String? name})? Function(Offset)>{};
    Future<BuildingMapOmnisearchSpot> spotOf({
      required int floorId,
      required Offset center,
      required bool isPlacement,
      required int itemId,
    }) async {
      String? roomName;
      if (roomLookup != null) {
        final at = roomsByFloor[floorId] ??= roomLookup(
          await plans.listElements(floorId),
        );
        final room = at(center);
        final name = room?.name?.trim() ?? '';
        final departmentId = room?.departmentId;
        roomName = name.isNotEmpty
            ? name
            : departmentId == null
            ? null
            : (deptById[departmentId]?['name'] as String?)?.trim();
      }
      return BuildingMapOmnisearchSpot(
        floorId: floorId,
        floorLabel: _buildingMapFloorDisplayLabel(floorById[floorId]!),
        center: center,
        isPlacement: isPlacement,
        itemId: itemId,
        roomName: roomName,
      );
    }

    final userRows = sortedForDisplay(
      await db.rawQuery('''
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
    '''),
      (r) => [r['last_name'] as String?, r['first_name'] as String?],
    );

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

    final equipmentRows = sortedForDisplay(
      await db.rawQuery('''
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
    '''),
      (r) => [r['code_equipment'] as String?, r['type'] as String?],
    );

    // Κάτοχοι εξοπλισμού (M2M) με το τμήμα τους: «ποιος και πού» για τον χάρτη,
    // αφού ο εξοπλισμός συνήθως δένεται με τμήμα μέσω του κατόχου του.
    final equipmentOwnerRows = sortedForDisplay(
      await db.rawQuery('''
      SELECT
        ue.equipment_id AS equipment_id,
        u.first_name AS first_name,
        u.last_name AS last_name,
        u.department_id AS department_id,
        d.name AS department_name
      FROM user_equipment ue
      JOIN users u ON u.id = ue.user_id AND COALESCE(u.is_deleted, 0) = 0
      LEFT JOIN departments d
        ON d.id = u.department_id AND COALESCE(d.is_deleted, 0) = 0
    '''),
      (r) => [r['last_name'] as String?, r['first_name'] as String?],
    );

    final phoneRows = await db.rawQuery('''
      SELECT id, number FROM phones
      WHERE COALESCE(is_deleted, 0) = 0
      ORDER BY number ASC
    ''');
    final phoneDeptRows = await db.rawQuery('''
      SELECT p.id AS phone_id, p.department_id AS department_id
      FROM phones p
      WHERE p.department_id IS NOT NULL
      UNION
      SELECT dp.phone_id AS phone_id, dp.department_id AS department_id
      FROM department_phones dp
    ''');
    final phoneDepartmentIds = <int, Set<int>>{};
    for (final row in phoneDeptRows) {
      final pid = row['phone_id'] as int?;
      final did = row['department_id'] as int?;
      if (pid == null || did == null || !deptById.containsKey(did)) continue;
      phoneDepartmentIds.putIfAbsent(pid, () => <int>{}).add(did);
    }

    final userPhoneDepartmentIds = <int, Set<int>>{};
    for (final row in userPhoneDeptRows) {
      final uid = row['user_id'] as int?;
      final did = row['department_id'] as int?;
      if (uid == null || did == null) continue;
      userPhoneDepartmentIds.putIfAbsent(uid, () => <int>{}).add(did);
    }

    final ownersByEquipmentId = <int, List<_OmnisearchEquipmentOwner>>{};
    for (final row in equipmentOwnerRows) {
      final eid = row['equipment_id'] as int?;
      if (eid == null) continue;
      final name =
          '${(row['first_name'] as String?)?.trim() ?? ''} '
                  '${(row['last_name'] as String?)?.trim() ?? ''}'
              .trim();
      ownersByEquipmentId
          .putIfAbsent(eid, () => [])
          .add(
            _OmnisearchEquipmentOwner(
              name: name,
              departmentId: row['department_id'] as int?,
              departmentName: (row['department_name'] as String?)?.trim() ?? '',
            ),
          );
    }

    final hits =
        <
          (
            int rank,
            int kindOrder,
            String sortKey,
            BuildingMapOmnisearchHit hit,
          )
        >[];

    /// Μία γραμμή για κάθε θέση της εγγραφής στον χάρτη· χωρίς θέση, η
    /// γραμμή του Καταλόγου — αχνή, όταν υπάρχει έστω ένας νέος όροφος.
    Future<void> addPlaced({
      required FloorPlanPlacementType type,
      required int rank,
      required int kindOrder,
      required BuildingMapOmnisearchHit hit,
    }) async {
      final placements = placementsOf[(type, hit.entityId)] ?? const [];
      final sortKey = hit.title.toLowerCase();
      if (placements.isEmpty) {
        final unplaced = activeFloors.isNotEmpty;
        hits.add((
          rank,
          kindOrder,
          sortKey,
          !unplaced
              ? hit
              : BuildingMapOmnisearchHit(
                  kind: hit.kind,
                  entityId: hit.entityId,
                  title: hit.title,
                  subtitle: [
                    ?hit.subtitle,
                    'χωρίς θέση στον χάρτη',
                  ].join(' • '),
                  departmentIds: hit.departmentIds,
                  unplaced: true,
                ),
        ));
        return;
      }
      for (final p in placements) {
        final spot = await spotOf(
          floorId: p.floorId,
          center: p.center,
          isPlacement: true,
          itemId: p.id,
        );
        hits.add((
          rank,
          kindOrder,
          '$sortKey ${spot.label.toLowerCase()}',
          BuildingMapOmnisearchHit(
            kind: hit.kind,
            entityId: hit.entityId,
            title: hit.title,
            subtitle: [spot.label, ?hit.subtitle].join(' • '),
            departmentIds: hit.departmentIds,
            spot: spot,
          ),
        ));
      }
    }

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
          subtitle: _omnisearchDepartmentSubtitle(
            row,
            floorById,
            floorIds,
            drawnOnNewMap,
          ),
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
      if (!SearchTextNormalizer.matchesNormalizedQuery(
        searchableText,
        normalized,
      )) {
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
          drawnOnNewMap,
        );
        if (hint != null) subtitleParts.add(hint);
      }
      final rank = _omnisearchRank(
        query: normalized,
        fields: [title, deptName, phonesCsv],
      );
      await addPlaced(
        type: FloorPlanPlacementType.user,
        rank: rank,
        kindOrder: 2,
        hit: BuildingMapOmnisearchHit(
          kind: BuildingMapOmnisearchEntityKind.user,
          entityId: id,
          title: title,
          subtitle: subtitleParts.isEmpty ? null : subtitleParts.join(' • '),
          departmentIds: departmentIds.toList()..sort(),
        ),
      );
    }

    // Τηλέφωνα: μόνο με τον αριθμό· «2345» πρέπει να βρίσκει το τηλέφωνο,
    // όχι κάθε τηλέφωνο ενός τμήματος.
    for (final row in phoneRows) {
      final id = row['id'] as int?;
      final number = (row['number'] as String?)?.trim() ?? '';
      if (id == null || number.isEmpty) continue;
      if (!SearchTextNormalizer.matchesNormalizedQuery(number, normalized)) {
        continue;
      }
      final departmentIds = (phoneDepartmentIds[id] ?? const <int>{}).toList()
        ..sort();
      final deptNames = [
        for (final d in departmentIds)
          if ((deptById[d]?['name'] as String?)?.trim() case final n?
              when n.isNotEmpty)
            n,
      ];
      await addPlaced(
        type: FloorPlanPlacementType.phone,
        rank: _omnisearchRank(query: normalized, fields: [number]),
        kindOrder: 1,
        hit: BuildingMapOmnisearchHit(
          kind: BuildingMapOmnisearchEntityKind.phone,
          entityId: id,
          title: number,
          subtitle: deptNames.isEmpty ? null : deptNames.join(', '),
          departmentIds: departmentIds,
        ),
      );
    }

    for (final row in equipmentRows) {
      final id = row['id'] as int?;
      if (id == null) continue;
      final code = (row['code_equipment'] as String?)?.trim() ?? '';
      final type = (row['type'] as String?)?.trim() ?? '';
      final notes = (row['notes'] as String?)?.trim() ?? '';
      final deptName = (row['department_name'] as String?)?.trim() ?? '';
      final searchableText = '$code $type $notes $deptName'.trim();
      if (!SearchTextNormalizer.matchesNormalizedQuery(
        searchableText,
        normalized,
      )) {
        continue;
      }
      final title = code.isNotEmpty
          ? code
          : (type.isNotEmpty ? type : '(Χωρίς κωδικό)');
      final owners = ownersByEquipmentId[id] ?? const [];
      final ownerNames = [
        for (final o in owners)
          if (o.name.isNotEmpty) o.name,
      ];
      // «Ποιος και πού»: κάτοχος + τμήμα. Χωρίς απευθείας τμήμα, το τμήμα
      // (και η μετάβαση στον χάρτη) προκύπτει από τους κατόχους.
      final ownerDeptNames = <String>{
        for (final o in owners)
          if (o.departmentName.isNotEmpty) o.departmentName,
      };
      final deptDisplay = deptName.isNotEmpty
          ? deptName
          : ownerDeptNames.join(' / ');
      final subtitleParts = <String>[];
      if (type.isNotEmpty && type != title) subtitleParts.add(type);
      if (ownerNames.isNotEmpty) subtitleParts.add(ownerNames.join(', '));
      if (deptDisplay.isNotEmpty) subtitleParts.add(deptDisplay);
      final equipmentDepartmentId = row['department_id'] as int?;
      final departmentIds = <int>{
        ?equipmentDepartmentId,
        for (final o in owners) ?o.departmentId,
      }.toList()..sort();
      if (departmentIds.length == 1 && departmentIds.first > 0) {
        final hint = _omnisearchUnmappedHintForDepartmentId(
          departmentIds.first,
          deptById,
          floorById,
          floorIds,
          drawnOnNewMap,
        );
        if (hint != null) subtitleParts.add(hint);
      }
      final rank = _omnisearchRank(
        query: normalized,
        fields: [title, type, notes, deptName],
      );
      await addPlaced(
        type: FloorPlanPlacementType.equipment,
        rank: rank,
        kindOrder: 3,
        hit: BuildingMapOmnisearchHit(
          kind: BuildingMapOmnisearchEntityKind.equipment,
          entityId: id,
          title: title,
          subtitle: subtitleParts.isEmpty ? null : subtitleParts.join(' • '),
          departmentIds: departmentIds,
        ),
      );
    }

    final objectsRepo = FloorPlanObjectsRepository(db);
    final objects = await objectsRepo.searchableObjects(activeFloors);
    final kinds = objects.isEmpty ? const {} : await objectsRepo.kinds();
    // Ό,τι είναι σε καμπίνα δεν ζωγραφίζεται στον χάρτη· η μετάβαση πηγαίνει
    // στην καμπίνα του.
    final cabinets = await objectsRepo.objectsById({
      for (final o in objects) ?o.cabinetId,
    });
    for (final object in objects) {
      final name = object.name?.trim() ?? '';
      final ip = object.ip?.trim() ?? '';
      final lansweeper = object.lansweeperName?.trim() ?? '';
      if (!SearchTextNormalizer.matchesNormalizedQuery(
        '$name $ip $lansweeper',
        normalized,
      )) {
        continue;
      }
      final kindName = kinds[object.kindId]?.name.trim() ?? '';
      final title = name.isNotEmpty
          ? name
          : (kindName.isNotEmpty ? kindName : 'Αντικείμενο');
      final cabinet = cabinets[object.cabinetId];
      final spot = await spotOf(
        floorId: (cabinet ?? object).floorId,
        center: (cabinet ?? object).center,
        isPlacement: false,
        itemId: (cabinet ?? object).id,
      );
      final cabinetName = cabinet?.name?.trim() ?? '';
      hits.add((
        _omnisearchRank(query: normalized, fields: [name, ip, lansweeper]),
        4,
        '${title.toLowerCase()} ${spot.label.toLowerCase()}',
        BuildingMapOmnisearchHit(
          kind: BuildingMapOmnisearchEntityKind.mapObject,
          entityId: object.id,
          title: title,
          subtitle: [
            if (kindName.isNotEmpty && kindName != title) kindName,
            if (ip.isNotEmpty) ip,
            if (cabinet != null)
              cabinetName.isEmpty ? 'σε καμπίνα' : 'στην καμπίνα $cabinetName',
            spot.label,
          ].join(' • '),
          departmentIds: const [],
          spot: spot,
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
