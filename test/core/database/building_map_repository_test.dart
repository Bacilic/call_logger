import 'dart:io';

import 'package:call_logger/core/database/building_map_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/department_repository.dart';
import 'package:call_logger/core/database/directory_support.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

/// Κλείδωμα συμπεριφοράς χάρτη κτιρίου πριν από Φάση Γ.1β (BuildingMapRepository).
void main() {
  group('BuildingMapRepository behavior — lock πριν εξαγωγή', () {
    late BuildingMapRepository repo;
    late DepartmentRepository departments;
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir =
          await Directory.systemTemp.createTemp('building_map_repo_test_');
      await DatabaseHelper.bindTestDatabaseFile(
        '${dir.path}/building_map_repo.db',
      );
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('departments');
      await db.delete('building_map_floors');
      departments = DepartmentRepository(db);
      repo = BuildingMapRepository(db, DirectorySupport(db));
      repo.bindUpdateDepartment(
        (deptId, fields) async {
          await departments.updateDepartment(deptId, fields);
        },
      );
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    test('listBuildingMapFloors: σωστή σειρά και πεδία', () async {
      await db.insert('building_map_floors', {
        'sort_order': 2,
        'label': 'Δεύτερος',
        'image_path': 'b.png',
        'rotation_degrees': 90.0,
      });
      await db.insert('building_map_floors', {
        'sort_order': 1,
        'label': 'Πρώτος',
        'floor_group': 'Κτίριο Α',
        'image_path': 'a.png',
        'rotation_degrees': 0.0,
      });

      final floors = await repo.listBuildingMapFloors();
      expect(floors, hasLength(2));
      expect(floors[0].label, 'Πρώτος');
      expect(floors[0].floorGroup, 'Κτίριο Α');
      expect(floors[0].sortOrder, 1);
      expect(floors[0].imagePath, 'a.png');
      expect(floors[0].rotationDegrees, 0.0);
      expect(floors[1].label, 'Δεύτερος');
      expect(floors[1].sortOrder, 2);
      expect(floors[1].rotationDegrees, 90.0);
    });

    test('insertBuildingMapFloor / updateBuildingMapFloor', () async {
      final id = await repo.insertBuildingMapFloor(
        label: 'Νέος Όροφος',
        floorGroup: '  Ομάδα  ',
        copiedImagePath: 'floors/new.png',
        rotationDegrees: 45.0,
      );
      expect(id, greaterThan(0));

      var floors = await repo.listBuildingMapFloors();
      expect(floors.single.label, 'Νέος Όροφος');
      expect(floors.single.floorGroup, '  Ομάδα  ');
      expect(floors.single.rotationDegrees, 45.0);

      await repo.updateBuildingMapFloor(
        id,
        label: 'Ενημερωμένος',
        floorGroup: '',
        rotationDegrees: 180.0,
        imagePath: 'floors/updated.png',
      );

      floors = await repo.listBuildingMapFloors();
      expect(floors.single.label, 'Ενημερωμένος');
      expect(floors.single.floorGroup, isNull);
      expect(floors.single.rotationDegrees, 180.0);
      expect(floors.single.imagePath, 'floors/updated.png');
    });

    test('countDepartmentsReferencingMapFloor: σωστό πλήθος', () async {
      final floorId = await db.insert('building_map_floors', {
        'sort_order': 0,
        'label': 'Όροφος Αναφοράς',
        'image_path': 'f.png',
        'rotation_degrees': 0.0,
      });
      final idStr = floorId.toString();

      await db.insert('departments', {
        'name': 'Τμήμα Στον Χάρτη',
        'name_key': SearchTextNormalizer.normalizeForSearch('Τμήμα Στον Χάρτη'),
        'is_deleted': 0,
        'map_floor': idStr,
      });
      await db.insert('departments', {
        'name': 'Τμήμα Διαγραμμένο',
        'name_key':
            SearchTextNormalizer.normalizeForSearch('Τμήμα Διαγραμμένο'),
        'is_deleted': 1,
        'map_floor': idStr,
      });
      await db.insert('departments', {
        'name': 'Τμήμα Χωρίς Χάρτη',
        'name_key':
            SearchTextNormalizer.normalizeForSearch('Τμήμα Χωρίς Χάρτη'),
        'is_deleted': 0,
        'map_floor': null,
      });

      expect(
        await repo.countDepartmentsReferencingMapFloor(floorId),
        1,
      );
    });

    test(
      'deleteBuildingMapFloorClearingDepartmentMaps: διαγραφή floor + καθαρισμός placement',
      () async {
        final floorId = await db.insert('building_map_floors', {
          'sort_order': 0,
          'label': 'Προς Διαγραφή',
          'image_path': 'del.png',
          'rotation_degrees': 0.0,
        });
        final idStr = floorId.toString();

        final deptId = await db.insert('departments', {
          'name': 'Τμήμα Με Χάρτη',
          'name_key':
              SearchTextNormalizer.normalizeForSearch('Τμήμα Με Χάρτη'),
          'is_deleted': 0,
          'map_floor': idStr,
          'floor_id': 99,
          'map_x': 10.0,
          'map_y': 20.0,
          'map_width': 100.0,
          'map_height': 50.0,
          'map_rotation': 15.0,
          'map_label_offset_x': 1.0,
          'map_label_offset_y': 2.0,
          'map_anchor_offset_x': 3.0,
          'map_anchor_offset_y': 4.0,
          'map_custom_name': 'Ετικέτα',
          'map_label_font_scale': 1.2,
          'map_label_width': 80.0,
          'map_label_height': 30.0,
          'map_hidden': 1,
          'color': '#FF0000',
        });

        await repo.deleteBuildingMapFloorClearingDepartmentMaps(floorId);

        expect(
          await db.query('building_map_floors', where: 'id = ?', whereArgs: [floorId]),
          isEmpty,
        );

        final dept = (await db.query(
          'departments',
          where: 'id = ?',
          whereArgs: [deptId],
        ))
            .single;

        expect(dept['map_floor'], isNull);
        expect(dept['floor_id'], isNull);
        expect(dept['map_x'], 0.0);
        expect(dept['map_y'], 0.0);
        expect(dept['map_width'], 0.0);
        expect(dept['map_height'], 0.0);
        expect(dept['map_rotation'], 0.0);
        expect(dept['map_label_offset_x'], isNull);
        expect(dept['map_label_offset_y'], isNull);
        expect(dept['map_anchor_offset_x'], isNull);
        expect(dept['map_anchor_offset_y'], isNull);
        expect(dept['map_custom_name'], isNull);
        expect(dept['map_label_font_scale'], isNull);
        expect(dept['map_label_width'], isNull);
        expect(dept['map_label_height'], isNull);
        // Η υπάρχουσα λογική δεν αγγίζει map_hidden / color στο delete floor.
        expect(dept['map_hidden'], 1);
        expect(dept['color'], '#FF0000');
      },
    );

    test(
      'static clearedBuildingMapPlacementColumns / buildingMapPlacementColumnNames',
      () async {
        final defaults = BuildingMapRepository.clearedBuildingMapPlacementColumns();
        expect(defaults['map_floor'], isNull);
        expect(defaults['map_x'], 0.0);
        expect(defaults['map_y'], 0.0);
        expect(defaults['map_width'], 0.0);
        expect(defaults['map_height'], 0.0);
        expect(defaults['map_rotation'], 0.0);
        expect(defaults['map_hidden'], 0);
        expect(defaults.containsKey('floor_id'), isFalse);
        expect(defaults.containsKey('color'), isFalse);

        final withExtras =
            BuildingMapRepository.clearedBuildingMapPlacementColumns(
          clearFloorId: true,
          clearDepartmentHex: true,
        );
        expect(withExtras['floor_id'], isNull);
        expect(withExtras['color'], isNull);
        expect(withExtras['map_hidden'], 0);

        final names = BuildingMapRepository.buildingMapPlacementColumnNames.toList();
        expect(names, containsAll([
          'map_floor',
          'map_x',
          'map_y',
          'map_width',
          'map_height',
          'map_rotation',
          'map_hidden',
        ]));
        expect(names, hasLength(defaults.keys.length));
      },
    );
  });
}
