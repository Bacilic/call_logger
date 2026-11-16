// Ο νέος, σχεδιασμένος χάρτης: τι γράφεται στη βάση, και τι επιστρέφει με
// την αναίρεση. Και η αναβάθμιση v69 που φτιάχνει τους πίνακές του.
//
//   flutter test test/core/database/floor_plan_repository_test.dart

import 'dart:typed_data';

import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/database/floor_plan_repository.dart';
import 'package:call_logger/core/models/floor_plan_element.dart';
import 'package:call_logger/core/models/floor_plan_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  late Database db;
  late FloorPlanRepository repo;

  setUp(() async {
    initSqfliteFfiForTests();
    db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
    await migrateDatabaseToV69(db);
    await migrateDatabaseToV81(db);
    repo = FloorPlanRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  FloorPlanElement wall(int floorId, Offset a, Offset b) => FloorPlanElement(
    id: 0,
    floorId: floorId,
    kind: FloorPlanElementKind.wall,
    points: [a, b],
  );

  group('Αναβάθμιση v69', () {
    test('ξανατρέχει χωρίς να σβήσει όσα σχεδιάστηκαν', () async {
      await repo.insertElement(wall(1, Offset.zero, const Offset(100, 0)));
      await migrateDatabaseToV69(db);
      expect(await repo.listElements(1), hasLength(1));
    });
  });

  group('Αναβάθμιση v70', () {
    test('βάση με τον πίνακα της v69 αποκτά τη θέση του ονόματος χώρου, και '
        'οι χώροι της μένουν στο κέντρο', () async {
      final old = await openDatabase(
        inMemoryDatabasePath,
        singleInstance: false,
      );
      addTearDown(old.close);
      await old.execute('''
        CREATE TABLE building_map_plan_elements (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          floor_id INTEGER NOT NULL,
          kind TEXT NOT NULL,
          points_json TEXT NOT NULL,
          parent_id INTEGER,
          name TEXT,
          department_id INTEGER,
          font_size REAL,
          rotation_degrees REAL NOT NULL DEFAULT 0
        )
      ''');
      await old.insert('building_map_plan_elements', {
        'floor_id': 1,
        'kind': 'room',
        'points_json': '[[0,0],[400,0],[400,300]]',
        'name': 'Αποθήκη',
      });

      await migrateDatabaseToV70(old);
      await migrateDatabaseToV70(old);
      // Η ανάγνωση ζητά τις σημερινές στήλες του πίνακα.
      await migrateDatabaseToV77(old);

      final oldRepo = FloorPlanRepository(old);
      final room = (await oldRepo.listElements(1)).single;
      expect(room.labelOffset, isNull);
      await oldRepo.restoreElements([
        room.copyWith(labelOffset: const Offset(120, -80)),
      ]);
      expect(
        (await oldRepo.listElements(1)).single.labelOffset,
        const Offset(120, -80),
      );
    });
  });

  group('Στοιχεία σχεδίου', () {
    test('ο τοίχος γράφεται με τα σημεία του σε εκατοστά', () async {
      await repo.insertElement(
        wall(1, const Offset(10, 20), const Offset(430, 20)),
      );
      final stored = (await repo.listElements(1)).single;
      expect(stored.kind, FloorPlanElementKind.wall);
      expect(stored.points, [const Offset(10, 20), const Offset(430, 20)]);
    });

    test('κάθε όροφος βλέπει μόνο τα δικά του στοιχεία', () async {
      await repo.insertElement(wall(1, Offset.zero, const Offset(100, 0)));
      await repo.insertElement(wall(2, Offset.zero, const Offset(200, 0)));
      expect(await repo.listElements(1), hasLength(1));
      expect(await repo.listElements(2), hasLength(1));
    });

    test('η διαγραφή τοίχου παίρνει μαζί τα ανοίγματά του', () async {
      final wallId = await repo.insertElement(
        wall(1, Offset.zero, const Offset(500, 0)),
      );
      await repo.insertElement(
        FloorPlanElement(
          id: 0,
          floorId: 1,
          kind: FloorPlanElementKind.opening,
          points: const [Offset(100, 0), Offset(190, 0)],
          parentId: wallId,
        ),
      );

      final removed = await repo.deleteElements([wallId]);

      expect(removed, hasLength(2));
      expect(await repo.listElements(1), isEmpty);
    });

    test('ό,τι σβήστηκε επιστρέφει με τα ίδια id', () async {
      final wallId = await repo.insertElement(
        wall(1, Offset.zero, const Offset(500, 0)),
      );
      await repo.insertElement(
        FloorPlanElement(
          id: 0,
          floorId: 1,
          kind: FloorPlanElementKind.opening,
          points: const [Offset(100, 0), Offset(190, 0)],
          parentId: wallId,
        ),
      );
      final removed = await repo.deleteElements([wallId]);

      await repo.restoreElements(removed);

      final back = await repo.listElements(1);
      expect(back.map((e) => e.id), removed.map((e) => e.id));
      expect(
        back.firstWhere((e) => e.kind == FloorPlanElementKind.opening).parentId,
        wallId,
      );
    });

    test('σε ποιους ορόφους έχει χώρο ένα τμήμα', () async {
      FloorPlanElement room(int floorId, int departmentId) => FloorPlanElement(
        id: 0,
        floorId: floorId,
        kind: FloorPlanElementKind.room,
        points: const [Offset(0, 0), Offset(100, 0), Offset(100, 100)],
        departmentId: departmentId,
      );
      await repo.insertElement(room(1, 5));
      await repo.insertElement(room(1, 5));
      await repo.insertElement(room(3, 5));
      await repo.insertElement(room(2, 6));

      expect(await repo.floorsWithRoomOfDepartment(5), {1, 3});
      expect(await repo.floorsWithRoomOfDepartment(9), isEmpty);
    });

    test('είδος που δεν ξέρει αυτή η έκδοση αγνοείται, δεν ρίχνει', () async {
      await db.insert('building_map_plan_elements', {
        'floor_id': 1,
        'kind': 'object',
        'points_json': '[[0,0],[100,0],[100,100]]',
      });
      await repo.insertElement(wall(1, Offset.zero, const Offset(100, 0)));
      final listed = await repo.listElements(1);
      expect(listed.single.kind, FloorPlanElementKind.wall);
    });
  });

  group('Πατρόν', () {
    final image = Uint8List.fromList(List.generate(64, (i) => i));

    test('όροφος χωρίς εγγραφή: προεπιλογές, χωρίς πατρόν', () async {
      final state = await repo.readState(3);
      expect(state.hasPattern, isFalse);
      expect(state.patternCalibrated, isFalse);
      expect(state.isActive, isFalse);
    });

    test('φόρτωση, βαθμονόμηση και αφαίρεση κρατούν την κλίμακα', () async {
      await repo.setPattern(3, image, const FloorPlanState(floorId: 3));
      expect(await repo.readPatternImage(3), image);

      final loaded = await repo.readState(3);
      await repo.savePatternPlacement(
        loaded.copyWith(
          cmPerPixel: 2.5,
          patternCenter: const Offset(40, -60),
          patternRotationDegrees: 1.5,
          patternCalibrated: true,
        ),
      );
      await repo.clearPattern(3);

      final after = await repo.readState(3);
      expect(after.hasPattern, isFalse);
      expect(await repo.readPatternImage(3), isNull);
      expect(after.cmPerPixel, 2.5);
      expect(after.patternCalibrated, isTrue);
      expect(after.patternCenter, const Offset(40, -60));
    });

    // Η βάση περνά μέσα από όσα βρίσκονται πριν από τη στήλη που ζητήθηκε, και
    // κάθε αλλαγή ξαναδιαβάζει όλη τη γραμμή. Αν τα bytes της εικόνας ζουν σε
    // αυτή τη γραμμή, κάθε άνοιγμα ορόφου και κάθε αλλαγή στον χάρτη τα
    // κατεβάζει από το δίκτυο, όποιες στήλες κι αν ζητήσει ο κώδικας.
    test('η γραμμή κατάστασης δεν κρατά τα bytes της εικόνας', () async {
      await repo.setPattern(3, image, const FloorPlanState(floorId: 3));

      final row = (await db.query(
        'building_map_floor_state',
        where: 'floor_id = 3',
      )).single;

      expect(row.values.whereType<Uint8List>(), isEmpty);
      expect((await repo.readState(3)).hasPattern, isTrue);
    });

    test('νέα εικόνα αντικαθιστά την παλιά του ίδιου ορόφου', () async {
      final other = Uint8List.fromList(List.generate(64, (i) => 200 - i));
      await repo.setPattern(3, image, const FloorPlanState(floorId: 3));
      final before = (await repo.readState(3)).patternHash;

      await repo.setPattern(3, other, const FloorPlanState(floorId: 3));

      expect(await repo.readPatternImage(3), other);
      expect((await repo.readState(3)).patternHash, isNot(before));
      expect(await db.query('building_map_floor_patterns'), hasLength(1));
    });

    test('η αφαίρεση του πατρόν και η διαγραφή ορόφου σβήνουν την εικόνα, '
        'χωρίς να αγγίζουν άλλον όροφο', () async {
      await repo.setPattern(3, image, const FloorPlanState(floorId: 3));
      await repo.setPattern(4, image, const FloorPlanState(floorId: 4));
      await repo.setPattern(5, image, const FloorPlanState(floorId: 5));

      await repo.clearPattern(3);
      await repo.deleteFloorPlan(db, 4);

      final left = await db.query('building_map_floor_patterns');
      expect(left.map((r) => r['floor_id']), [5]);
    });
  });

  group('Αναβάθμιση v76', () {
    test('οι εικόνες μεταφέρονται αυτούσιες, οι ρυθμίσεις μένουν, η παλιά '
        'στήλη φεύγει, και ξανατρέχει χωρίς παρενέργειες', () async {
      final old = await openDatabase(
        inMemoryDatabasePath,
        singleInstance: false,
      );
      addTearDown(old.close);
      await old.execute('''
        CREATE TABLE building_map_floor_state (
          floor_id INTEGER PRIMARY KEY,
          is_active INTEGER NOT NULL DEFAULT 0,
          changed_at TEXT,
          pattern_image BLOB,
          pattern_hash TEXT,
          pattern_cm_per_px REAL NOT NULL DEFAULT 1,
          pattern_center_x REAL NOT NULL DEFAULT 0,
          pattern_center_y REAL NOT NULL DEFAULT 0,
          pattern_rotation_degrees REAL NOT NULL DEFAULT 0,
          pattern_opacity REAL NOT NULL DEFAULT 0.5,
          pattern_hidden INTEGER NOT NULL DEFAULT 0,
          pattern_calibrated INTEGER NOT NULL DEFAULT 0
        )
      ''');
      final image = Uint8List.fromList(List.generate(64, (i) => i));
      await old.insert('building_map_floor_state', {
        'floor_id': 1,
        'is_active': 1,
        'changed_at': '2026-11-04T10:00:00.000Z',
        'pattern_image': image,
        'pattern_hash': 'αποτύπωμα',
        'pattern_cm_per_px': 2.5,
        'pattern_opacity': 0.7,
        'pattern_calibrated': 1,
      });
      await old.insert('building_map_floor_state', {'floor_id': 2});

      await migrateDatabaseToV76(old);
      await migrateDatabaseToV76(old);

      final migrated = FloorPlanRepository(old);
      expect(await migrated.readPatternImage(1), image);
      expect(await migrated.readPatternImage(2), isNull);

      final state = await migrated.readState(1);
      expect(state.isActive, isTrue);
      expect(state.patternHash, 'αποτύπωμα');
      expect(state.cmPerPixel, 2.5);
      expect(state.patternOpacity, 0.7);
      expect(state.patternCalibrated, isTrue);
      expect((await migrated.readState(2)).hasPattern, isFalse);

      final columns = await old.rawQuery(
        'PRAGMA table_info(building_map_floor_state)',
      );
      expect(columns.map((c) => c['name']), isNot(contains('pattern_image')));
    });
  });

  group('Αναβάθμιση v77', () {
    test('τοίχος που σχεδιάστηκε πριν μένει με το συνηθισμένο πάχος, ο νέος '
        'κρατά το δικό του, και ξανατρέχει χωρίς παρενέργειες', () async {
      final old = await openDatabase(
        inMemoryDatabasePath,
        singleInstance: false,
      );
      addTearDown(old.close);
      await migrateDatabaseToV69(old);
      await migrateDatabaseToV76(old);
      await old.insert('building_map_plan_elements', {
        'floor_id': 1,
        'kind': 'wall',
        'points_json': '[[0,0],[400,0]]',
      });

      await migrateDatabaseToV77(old);
      await migrateDatabaseToV77(old);

      final migrated = FloorPlanRepository(old);
      final before = (await migrated.listElements(1)).single;
      expect(before.thicknessCm, isNull);
      expect(before.wallThicknessCm, kFloorPlanDefaultWallThicknessCm);

      await migrated.restoreElements([before.copyWith(thicknessCm: 45)]);
      expect((await migrated.listElements(1)).single.wallThicknessCm, 45);
    });
  });

  group('Ενεργοποίηση ορόφου', () {
    FloorPlanElement room(int floorId, int departmentId) => FloorPlanElement(
      id: 0,
      floorId: floorId,
      kind: FloorPlanElementKind.room,
      points: const [Offset(0, 0), Offset(100, 0), Offset(100, 100)],
      departmentId: departmentId,
    );

    test('ενεργός γίνεται μόνο ο όροφος που ενεργοποιήθηκε', () async {
      await repo.insertElement(wall(1, Offset.zero, const Offset(100, 0)));
      await repo.insertElement(wall(2, Offset.zero, const Offset(100, 0)));
      await repo.setActive(2);
      expect(await repo.activeFloorIds(), {2});
      expect((await repo.readState(2)).isActive, isTrue);
      expect((await repo.readState(1)).isActive, isFalse);
    });

    test('χώροι τμήματος: μετρούν μόνο οι ενεργοί όροφοι', () async {
      await repo.insertElement(room(1, 5));
      await repo.insertElement(room(2, 5));
      await repo.insertElement(room(2, 6));
      await repo.setActive(2);

      final found = await repo.activeFloorsWithRoomsOf({5, 6, 7});
      expect(found, {
        5: {2},
        6: {2},
      });
    });

    test('το αποτύπωμα αλλάζει με κάθε σχεδίαση — έτσι το βλέπουν οι άλλοι '
        'σταθμοί', () async {
      await repo.insertElement(wall(1, Offset.zero, const Offset(100, 0)));
      final before = await repo.floorStamps();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repo.insertElement(wall(1, Offset.zero, const Offset(0, 100)));
      expect(await repo.floorStamps(), isNot(before));
    });
  });
}
