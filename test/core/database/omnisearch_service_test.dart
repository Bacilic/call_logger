import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/directory_repository.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

/// Κλείδωμα συμπεριφοράς omnisearch πριν από Φάση Γ.3α (OmnisearchService).
void main() {
  group('Omnisearch behavior — lock πριν εξαγωγή', () {
    late DirectoryRepository repo;
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir =
          await Directory.systemTemp.createTemp('omnisearch_service_test_');
      await DatabaseHelper.bindTestDatabaseFile(
        '${dir.path}/omnisearch_service.db',
      );
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('building_map_floors');
      await db.delete('department_phones');
      await db.delete('user_phones');
      await db.delete('phones');
      await db.delete('equipment');
      await db.delete('users');
      await db.delete('departments');
      repo = DirectoryRepository(db);
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Future<int> insertFloor({
      required String label,
      String? floorGroup,
      int sortOrder = 0,
    }) async {
      return db.insert('building_map_floors', {
        'sort_order': sortOrder,
        'label': label,
        'floor_group': floorGroup,
        'image_path': 'floor.png',
        'rotation_degrees': 0.0,
      });
    }

    Future<int> insertDepartment({
      required String name,
      int isDeleted = 0,
      int? floorId,
      String? mapCustomName,
      String? mapFloor,
      double? mapX,
      double? mapY,
      double? mapWidth,
      double? mapHeight,
    }) async {
      return db.insert('departments', {
        'name': name,
        'name_key': SearchTextNormalizer.normalizeForSearch(name),
        'is_deleted': isDeleted,
        'floor_id': ?floorId,
        'map_custom_name': ?mapCustomName,
        'map_floor': ?mapFloor,
        'map_x': mapX ?? 0.0,
        'map_y': mapY ?? 0.0,
        'map_width': mapWidth ?? 0.0,
        'map_height': mapHeight ?? 0.0,
      });
    }

    test('department hit: kind, entityId, title, mapDisplayLabel, subtitle', () async {
      final floorId = await insertFloor(
        label: 'Όροφος 1',
        floorGroup: 'Κτίριο Α',
      );
      final deptId = await insertDepartment(
        name: 'Τμήμα IT',
        floorId: floorId,
        mapCustomName: '  Τμήμα   Πληροφορικής  ',
      );

      final hits = await repo.searchBuildingMapOmnisearch('it');
      expect(hits, hasLength(1));
      final hit = hits.single;
      expect(hit.kind, BuildingMapOmnisearchEntityKind.department);
      expect(hit.entityId, deptId);
      expect(hit.title, 'Τμήμα IT');
      expect(hit.mapDisplayLabel, 'Τμήμα Πληροφορικής');
      expect(hit.departmentIds, [deptId]);
      expect(hit.subtitle, 'Τμήμα • Κτίριο Α · Όροφος 1 • χωρίς σχεδίαση');
    });

    test('department: mapDisplayLabel null όταν ίδιο με title', () async {
      await insertDepartment(
        name: 'Τμήμα Ίδιο',
        mapCustomName: 'Τμήμα Ίδιο',
      );

      final hits = await repo.searchBuildingMapOmnisearch('ιδιο');
      expect(hits, hasLength(1));
      expect(hits.single.mapDisplayLabel, isNull);
    });

    test('department: διαγραμμένο τμήμα δεν εμφανίζεται', () async {
      await insertDepartment(name: 'Διαγραμμένο Τμήμα', isDeleted: 1);
      await insertDepartment(name: 'Ενεργό Τμήμα');

      final hits = await repo.searchBuildingMapOmnisearch('τμημα');
      expect(hits.map((h) => h.title), ['Ενεργό Τμήμα']);
    });

    test('user hit: kind, entityId, title, departmentIds, subtitle', () async {
      final deptId = await insertDepartment(name: 'Τμήμα Χρηστών');
      final userId = await db.insert('users', {
        'first_name': 'Γιάννης',
        'last_name': 'Παπαδόπουλος',
        'department_id': deptId,
        'is_deleted': 0,
      });
      final phoneId = await db.insert('phones', {
        'number': '2100',
        'is_deleted': 0,
      });
      await db.insert('user_phones', {
        'user_id': userId,
        'phone_id': phoneId,
      });

      final hits = await repo.searchBuildingMapOmnisearch('παπα');
      expect(hits, hasLength(1));
      final hit = hits.single;
      expect(hit.kind, BuildingMapOmnisearchEntityKind.user);
      expect(hit.entityId, userId);
      expect(hit.title, 'Γιάννης Παπαδόπουλος');
      expect(hit.departmentIds, [deptId]);
      expect(hit.subtitle, contains('Τμήμα Χρηστών'));
      expect(hit.subtitle, contains('2100'));
    });

    test('user: διαγραμμένος χρήστης δεν εμφανίζεται', () async {
      await db.insert('users', {
        'first_name': 'Διαγραμμένος',
        'last_name': 'Χρήστης',
        'is_deleted': 1,
      });
      await db.insert('users', {
        'first_name': 'Ενεργός',
        'last_name': 'Χρήστης',
        'is_deleted': 0,
      });

      final hits = await repo.searchBuildingMapOmnisearch('χρηστης');
      expect(hits, hasLength(1));
      expect(hits.single.title, 'Ενεργός Χρήστης');
    });

    test('equipment hit: kind, entityId, title, departmentIds', () async {
      final deptId = await insertDepartment(name: 'Τμήμα Εξοπλισμού');
      final eqId = await db.insert('equipment', {
        'code_equipment': 'PC-OMNI-01',
        'type': 'Desktop',
        'notes': 'γραφείο 3',
        'department_id': deptId,
        'is_deleted': 0,
      });

      final hits = await repo.searchBuildingMapOmnisearch('pc-omni');
      expect(hits, hasLength(1));
      final hit = hits.single;
      expect(hit.kind, BuildingMapOmnisearchEntityKind.equipment);
      expect(hit.entityId, eqId);
      expect(hit.title, 'PC-OMNI-01');
      expect(hit.departmentIds, [deptId]);
      expect(hit.subtitle, contains('Desktop'));
      expect(hit.subtitle, contains('Τμήμα Εξοπλισμού'));
    });

    test('equipment: διαγραμμένος εξοπλισμός δεν εμφανίζεται', () async {
      await db.insert('equipment', {
        'code_equipment': 'DEL-EQ',
        'is_deleted': 1,
      });
      await db.insert('equipment', {
        'code_equipment': 'ACT-EQ',
        'is_deleted': 0,
      });

      final hits = await repo.searchBuildingMapOmnisearch('eq');
      expect(hits.map((h) => h.title), ['ACT-EQ']);
    });

    test('ranking: ακριβές πριν από prefix πριν από contains, μετά kind, μετά αλφαβητικά',
        () async {
      await insertDepartment(name: 'Alpine Dept');
      final userId = await db.insert('users', {
        'first_name': 'Alphonse',
        'last_name': 'User',
        'is_deleted': 0,
      });
      await db.insert('equipment', {
        'code_equipment': 'EQ-ALP',
        'notes': 'contains alpine keyword',
        'is_deleted': 0,
      });
      final exactDeptId = await insertDepartment(name: 'Alp');

      final hits = await repo.searchBuildingMapOmnisearch('alp');
      expect(hits.length, greaterThanOrEqualTo(3));

      final exactIdx = hits.indexWhere(
        (h) =>
            h.kind == BuildingMapOmnisearchEntityKind.department &&
            h.entityId == exactDeptId,
      );
      final prefixIdx = hits.indexWhere(
        (h) =>
            h.kind == BuildingMapOmnisearchEntityKind.user &&
            h.entityId == userId,
      );
      final containsIdx = hits.indexWhere(
        (h) => h.kind == BuildingMapOmnisearchEntityKind.equipment,
      );

      expect(exactIdx, lessThan(prefixIdx));
      expect(prefixIdx, lessThan(containsIdx));
    });

    test('κενό query ή limit<=0 επιστρέφει κενή λίστα', () async {
      await insertDepartment(name: 'Τμήμα');
      expect(await repo.searchBuildingMapOmnisearch(''), isEmpty);
      expect(await repo.searchBuildingMapOmnisearch('   '), isEmpty);
      expect(await repo.searchBuildingMapOmnisearch('τμημα', limit: 0), isEmpty);
    });

    test('limit περιορίζει αποτελέσματα', () async {
      await insertDepartment(name: 'Alpha Τμήμα');
      await insertDepartment(name: 'Beta Τμήμα');
      await insertDepartment(name: 'Gamma Τμήμα');

      final hits = await repo.searchBuildingMapOmnisearch('τμημα', limit: 2);
      expect(hits, hasLength(2));
    });
  });
}
