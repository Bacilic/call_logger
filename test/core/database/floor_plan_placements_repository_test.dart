// Οι θέσεις υπαλλήλων, τηλεφώνων και εξοπλισμού στον νέο χάρτη: τι γράφεται,
// τι φαίνεται όταν η εγγραφή του Καταλόγου διαγραφεί, και ο κατάλογος που
// δείχνει το πάνελ «Τοποθέτηση».
//
//   flutter test test/core/database/floor_plan_placements_repository_test.dart

import 'package:call_logger/core/database/database_foreign_keys.dart';
import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/database/floor_plan_placements_repository.dart';
import 'package:call_logger/core/database/floor_plan_repository.dart';
import 'package:call_logger/core/models/floor_plan_placement.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  late Database db;
  late FloorPlanPlacementsRepository repo;

  setUp(() async {
    initSqfliteFfiForTests();
    db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
    for (final table in [
      kCreateDepartmentsTable,
      kCreateUsersTable,
      kCreatePhonesTable,
      kCreateDepartmentPhonesTable,
      kCreateEquipmentTable,
      kCreateUserPhonesTable,
      kCreateUserEquipmentTable,
    ]) {
      await db.execute(table);
    }
    await migrateDatabaseToV69(db);
    await migrateDatabaseToV71(db);
    repo = FloorPlanPlacementsRepository(db);

    await db.insert('departments', {
      'id': 1,
      'name': 'Υλικού',
      'name_key': 'υλικου',
    });
    await db.insert('departments', {
      'id': 2,
      'name': 'Προμήθειες',
      'name_key': 'προμηθειες',
    });
    await db.insert('users', {
      'id': 10,
      'last_name': 'Παπαδόπουλος',
      'first_name': 'Γιώργος',
      'department_id': 1,
    });
    await db.insert('phones', {'id': 20, 'number': '2345'});
    await db.insert('department_phones', {'department_id': 1, 'phone_id': 20});
    await db.insert('department_phones', {'department_id': 2, 'phone_id': 20});
    await db.insert('equipment', {
      'id': 30,
      'code_equipment': 'PC-0412',
      'department_id': 2,
    });
  });

  tearDown(() async {
    await db.close();
  });

  FloorPlanPlacement place(
    FloorPlanPlacementType type,
    int entityId, {
    int floorId = 1,
    Offset at = Offset.zero,
  }) => FloorPlanPlacement(
    id: 0,
    type: type,
    entityId: entityId,
    floorId: floorId,
    center: at,
  );

  test('θέση γράφεται και κάθε όροφος βλέπει τις δικές του', () async {
    await repo.insertPlacement(
      place(FloorPlanPlacementType.user, 10, at: const Offset(50, 60)),
    );
    await repo.insertPlacement(
      place(FloorPlanPlacementType.phone, 20, floorId: 2),
    );

    final first = (await repo.listPlacements(1)).single;
    expect(first.type, FloorPlanPlacementType.user);
    expect(first.entityId, 10);
    expect(first.center, const Offset(50, 60));
    expect((await repo.listPlacements(2)).single.entityId, 20);
  });

  test('διαγραμμένος στον Κατάλογο φεύγει από τον χάρτη, και επιστρέφει με '
      'την επαναφορά του', () async {
    await repo.insertPlacement(place(FloorPlanPlacementType.user, 10));

    await db.update('users', {'is_deleted': 1}, where: 'id = 10');
    expect(await repo.listPlacements(1), isEmpty);
    expect(await repo.allPlacements(), isEmpty);

    await db.update('users', {'is_deleted': 0}, where: 'id = 10');
    expect(await repo.listPlacements(1), hasLength(1));
  });

  test('οι θέσεις μιας εγγραφής για τον μικρό χάρτη: μόνο σε ενεργοποιημένο '
      'όροφο, χωρίς τα διαγραμμένα', () async {
    await FloorPlanRepository(db).setActive(1);
    await repo.insertPlacement(place(FloorPlanPlacementType.user, 10));
    await repo.insertPlacement(
      place(FloorPlanPlacementType.user, 10, floorId: 2),
    );

    final active = await repo.activePlacementsOf(
      FloorPlanPlacementType.user,
      10,
    );
    expect(active.map((p) => p.floorId), [1]);

    await db.update('users', {'is_deleted': 1}, where: 'id = 10');
    expect(
      await repo.activePlacementsOf(FloorPlanPlacementType.user, 10),
      isEmpty,
    );
  });

  test('η μεταφορά σε άλλον όροφο κρατά το ίδιο id και αλλάζει το αποτύπωμα '
      'και των δύο ορόφων', () async {
    final plans = FloorPlanRepository(db);
    final id = await repo.insertPlacement(
      place(FloorPlanPlacementType.equipment, 30),
    );
    final stored = (await repo.listPlacements(1)).single;
    final before = await plans.floorStamps();
    await Future<void>.delayed(const Duration(milliseconds: 5));

    await repo.restorePlacements([
      stored.copyWith(floorId: 2, center: const Offset(10, 10)),
    ]);

    expect(await repo.listPlacements(1), isEmpty);
    expect((await repo.listPlacements(2)).single.id, id);
    final after = await plans.floorStamps();
    expect(after[1], isNot(before[1]));
    expect(after[2], isNotNull);
  });

  test('διαγραφή θέσης σβήνει μόνο από τον χάρτη και επιστρέφει με την '
      'αναίρεση', () async {
    final id = await repo.insertPlacement(
      place(FloorPlanPlacementType.user, 10),
    );

    final removed = await repo.deletePlacements({id});
    expect(await repo.listPlacements(1), isEmpty);
    expect(await db.query('users'), hasLength(1));

    await repo.restorePlacements(removed);
    expect((await repo.listPlacements(1)).single.id, id);
  });

  group('Κατάλογος για το πάνελ', () {
    test('ετικέτες: ονοματεπώνυμο, αριθμός, κωδικός', () async {
      final entries = await repo.catalogEntries();
      String labelOf(FloorPlanPlacementType t) =>
          entries.firstWhere((e) => e.type == t).label;

      expect(labelOf(FloorPlanPlacementType.user), 'Παπαδόπουλος Γιώργος');
      expect(labelOf(FloorPlanPlacementType.phone), '2345');
      expect(labelOf(FloorPlanPlacementType.equipment), 'PC-0412');
    });

    test('οι σχέσεις για την υπόδειξη: τηλέφωνα και εξοπλισμός του '
        'υπαλλήλου, ποιοι έχουν το τηλέφωνο, ποιος χρησιμοποιεί τον '
        'εξοπλισμό', () async {
      await db.insert('user_phones', {'user_id': 10, 'phone_id': 20});
      await db.insert('user_equipment', {'user_id': 10, 'equipment_id': 30});
      await db.update('equipment', {
        'lansweeper_asset_name': 'PC0412',
      }, where: 'id = 30');

      final entries = await repo.catalogEntries();
      FloorPlanCatalogEntry of(FloorPlanPlacementType t) =>
          entries.firstWhere((e) => e.type == t);

      expect(of(FloorPlanPlacementType.user).phones, ['2345']);
      expect(of(FloorPlanPlacementType.user).equipment, ['PC-0412']);
      expect(of(FloorPlanPlacementType.phone).holders, [
        'Παπαδόπουλος Γιώργος',
      ]);
      expect(of(FloorPlanPlacementType.equipment).holders, [
        'Παπαδόπουλος Γιώργος',
      ]);
      expect(of(FloorPlanPlacementType.equipment).lansweeperName, 'PC0412');
    });

    test('διαγραμμένος υπάλληλος δεν εμφανίζεται ως κάτοχος', () async {
      await db.insert('user_phones', {'user_id': 10, 'phone_id': 20});
      await db.update('users', {'is_deleted': 1}, where: 'id = 10');

      final phone = (await repo.catalogEntries()).firstWhere(
        (e) => e.type == FloorPlanPlacementType.phone,
      );
      expect(phone.holders, isEmpty);
    });

    test('το τηλέφωνο ανήκει σε όλα τα τμήματά του', () async {
      final phone = (await repo.catalogEntries()).firstWhere(
        (e) => e.type == FloorPlanPlacementType.phone,
      );
      expect(phone.departmentIds, {1, 2});
    });

    test('τα διαγραμμένα δεν εμφανίζονται', () async {
      await db.update('equipment', {'is_deleted': 1}, where: 'id = 30');
      final entries = await repo.catalogEntries();
      expect(
        entries.where((e) => e.type == FloorPlanPlacementType.equipment),
        isEmpty,
      );
    });
  });

  test('αναβάθμιση v72: πίνακας θέσεων της v71 αποκτά κλίση, και ό,τι '
      'υπήρχε μένει όρθιο', () async {
    final old = await openDatabase(inMemoryDatabasePath, singleInstance: false);
    addTearDown(old.close);
    await old.execute('''
      CREATE TABLE building_map_placements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_type TEXT NOT NULL,
        entity_id INTEGER NOT NULL,
        floor_id INTEGER NOT NULL,
        x REAL NOT NULL,
        y REAL NOT NULL
      )
    ''');
    await old.insert('building_map_placements', {
      'entity_type': 'user',
      'entity_id': 10,
      'floor_id': 1,
      'x': 0,
      'y': 0,
    });

    await migrateDatabaseToV72(old);
    await migrateDatabaseToV72(old);

    final row = (await old.query('building_map_placements')).single;
    expect(row['rotation_degrees'], 0);
  });

  test('η κλίση της θέσης γράφεται και διαβάζεται', () async {
    final id = await repo.insertPlacement(
      place(FloorPlanPlacementType.equipment, 30),
    );
    final stored = (await repo.listPlacements(1)).single;

    await repo.restorePlacements([stored.copyWith(rotationDegrees: 45)]);

    final turned = (await repo.listPlacements(1)).single;
    expect(turned.id, id);
    expect(turned.rotationDegrees, 45);
  });
}
