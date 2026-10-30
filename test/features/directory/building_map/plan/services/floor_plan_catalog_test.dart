// Η μεταφορά τμήματος σε άλλον όροφο από τη σχεδίαση χώρου: ο Κατάλογος
// γράφει τον νέο όροφο, και το κουτάκι του παλιού χάρτη φεύγει μόνο όταν
// ήταν σε άλλον όροφο.
//
// Ο όροφος χάρτη (`map_floor`) ακολουθεί πάντα τον όροφο του Καταλόγου, όπως
// τον γράφει και η καρτέλα τμήματος. Αν μείνει κενός, η επόμενη αποθήκευση
// της καρτέλας βλέπει διαφορά και λέει ψευδώς «Κάποιος πρόλαβε».
//
//   flutter test test/features/directory/building_map/plan/services/floor_plan_catalog_test.dart

import 'dart:typed_data';

import 'package:call_logger/core/database/building_map_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/department_repository.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/directory/building_map/plan/services/floor_plan_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../../test_setup.dart';

void main() {
  late Database db;
  late DatabaseFloorPlanCatalog catalog;
  late int refreshes;
  late int ground;
  late int third;

  setUpAll(() async {
    await bindCallLoggerIsolatedTestDatabase();
    db = await DatabaseHelper.instance.database;
  });

  setUp(() async {
    await seedIsolatedTestDatabase();
    await db.delete('departments');
    await db.delete('building_map_floors');
    Future<int> floor(String label) =>
        db.insert('building_map_floors', {'label': label, 'image_path': ''});
    ground = await floor('Ισόγειο');
    third = await floor('3ος');
    refreshes = 0;
    catalog = DatabaseFloorPlanCatalog(
      departmentRepository: DepartmentRepository(db),
      buildingMapRepository: BuildingMapRepository(db),
      afterDepartmentChange: () async => refreshes++,
    );
  });

  tearDownAll(() async {
    await releaseCallLoggerTestDatabase();
  });

  Future<int> department(String name, {int? floorId, String? mapFloor}) =>
      db.insert('departments', {
        'name': name,
        'name_key': SearchTextNormalizer.normalizeForSearch(name),
        'is_deleted': 0,
        'floor_id': floorId,
        'map_floor': mapFloor,
        'map_x': 0.2,
        'map_y': 0.3,
        'map_width': 0.1,
        'map_height': 0.1,
      });

  Future<Map<String, Object?>> row(int id) async =>
      (await db.query('departments', where: 'id = ?', whereArgs: [id])).single;

  test(
    'μεταφορά από άλλον όροφο: νέος όροφος, το παλιό κουτάκι φεύγει',
    () async {
      final id = await department(
        'Ορθοπαιδική',
        floorId: third,
        mapFloor: '$third',
      );

      await catalog.moveDepartmentToFloor(id, ground);

      final after = await row(id);
      expect(after['floor_id'], ground);
      expect(after['map_floor'], '$ground');
      expect(after['map_width'], 0.0);
      expect(refreshes, 1);
    },
  );

  test('κουτάκι ήδη στον ίδιο όροφο: μένει όπως είναι', () async {
    final id = await department('Ακτινολογικό', mapFloor: '$ground');

    await catalog.moveDepartmentToFloor(id, ground);

    final after = await row(id);
    expect(after['floor_id'], ground);
    expect(after['map_floor'], '$ground');
    expect(after['map_width'], 0.1);
  });

  test('η λίστα τμημάτων αφήνει έξω τα διαγραμμένα', () async {
    await department('Καρδιολογική');
    await db.insert('departments', {
      'name': 'Παλιό τμήμα',
      'name_key': SearchTextNormalizer.normalizeForSearch('Παλιό τμήμα'),
      'is_deleted': 1,
    });
    final names = (await catalog.departments()).map((d) => d.name);
    expect(names, ['Καρδιολογική']);
  });

  test('απόσυρση παλιού χάρτη: σβήνουν τα κουτάκια του ορόφου και η εικόνα, '
      'ο όροφος του Καταλόγου μένει', () async {
    final here = await department(
      'Ορθοπαιδική',
      floorId: ground,
      mapFloor: '$ground',
    );
    final elsewhere = await department(
      'Καρδιολογική',
      floorId: third,
      mapFloor: '$third',
    );
    await BuildingMapRepository(db)
        .saveFloorImage(ground, Uint8List.fromList([1, 2, 3]));

    await catalog.retireOldMap(ground);

    final a = await row(here);
    expect(a['floor_id'], ground);
    expect(a['map_floor'], '$ground');
    expect(a['map_width'], 0.0);
    final b = await row(elsewhere);
    expect(b['map_floor'], '$third');
    expect(b['map_width'], 0.1);
    expect(await BuildingMapRepository(db).readFloorImage(ground), isNull);
  });
}
