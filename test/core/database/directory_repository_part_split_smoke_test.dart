import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/directory_repository.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

/// Regression smoke test: μετά το part/part of split, η [DirectoryRepository]
/// εξακολουθεί να εκθέτει όλες τις δημόσιες μεθόδους από κάθε λειτουργική ομάδα.
void main() {
  group('DirectoryRepository part split — smoke', () {
    late DirectoryRepository repo;
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('dir_repo_split_smoke_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/split_smoke.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      repo = DirectoryRepository(db);
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    test('settings: getSetting / setSetting', () async {
      const key = 'smoke_test_setting_key';
      await repo.setSetting(key, 'alpha');
      expect(await repo.getSetting(key), 'alpha');
    });

    test('departments: getDepartments / getActiveDepartments', () async {
      final deptId = await db.insert('departments', {
        'name': 'Smoke Τμήμα',
        'name_key': SearchTextNormalizer.normalizeForSearch('Smoke Τμήμα'),
        'is_deleted': 0,
      });
      final all = await repo.getDepartments();
      final active = await repo.getActiveDepartments();
      expect(all.any((r) => r['id'] == deptId), isTrue);
      expect(active.any((r) => r['id'] == deptId), isTrue);
      expect(await repo.getDepartmentRowById(deptId), isNotNull);
    });

    test('users: getAllUsers / insertUser', () async {
      final userId = await repo.insertUser(
        firstName: 'Smoke',
        lastName: 'Χρήστης',
      );
      final users = await repo.getAllUsers();
      expect(users.any((u) => u['id'] == userId), isTrue);
    });

    test('equipment: getAllEquipment / getAllUserEquipmentLinks', () async {
      final eqId = await db.insert('equipment', {
        'code_equipment': 'SMOKE-PC-01',
        'is_deleted': 0,
      });
      final equipment = await repo.getAllEquipment();
      final links = await repo.getAllUserEquipmentLinks();
      expect(equipment.any((e) => e['id'] == eqId), isTrue);
      expect(links, isA<List<Map<String, dynamic>>>());
    });

    test('categories: getCategoryNames / getActiveCategoryRows', () async {
      await db.insert('categories', {
        'name': 'Smoke Κατηγορία',
        'is_deleted': 0,
      });
      final names = await repo.getCategoryNames();
      final rows = await repo.getActiveCategoryRows();
      expect(names, contains('Smoke Κατηγορία'));
      expect(rows.any((r) => (r['name'] as String?) == 'Smoke Κατηγορία'), isTrue);
    });

    test('building map: listBuildingMapFloors', () async {
      await repo.insertBuildingMapFloor(
        label: 'Όροφος Smoke',
        copiedImagePath: 'smoke/floor.png',
        rotationDegrees: 0,
      );
      final floors = await repo.listBuildingMapFloors();
      expect(floors.any((f) => f.label == 'Όροφος Smoke'), isTrue);
    });

    test('search: getNonUserPhonesCatalogRows / searchBuildingMapOmnisearch', () async {
      final catalog = await repo.getNonUserPhonesCatalogRows();
      expect(catalog, isA<List<Map<String, dynamic>>>());
      final hits = await repo.searchBuildingMapOmnisearch('smoke');
      expect(hits, isA<List<BuildingMapOmnisearchHit>>());
    });

    test('phones: phoneNumberExists / getDepartmentDirectPhonesMap', () async {
      await db.insert('phones', {'number': '2345999902', 'is_deleted': 0});
      expect(await repo.phoneNumberExists('2345999902'), isTrue);
      final map = await repo.getDepartmentDirectPhonesMap();
      expect(map, isA<Map<int, List<String>>>());
    });

    test('integrity: integrityUserLabel', () async {
      final label = await repo.integrityUserLabel(db, null);
      expect(label, '—');
    });
  });
}
