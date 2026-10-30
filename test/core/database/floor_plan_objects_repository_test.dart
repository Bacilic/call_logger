// Τα αντικείμενα του νέου χάρτη: η αναβάθμιση v71 που φτιάχνει τους πίνακές
// τους, τα είδη που ορίζει όποιος σχεδιάζει, και τα ίδια τα αντικείμενα.
//
//   flutter test test/core/database/floor_plan_objects_repository_test.dart

import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/database/floor_plan_objects_repository.dart';
import 'package:call_logger/core/database/floor_plan_repository.dart';
import 'package:call_logger/core/models/floor_plan_object.dart';
import 'package:call_logger/core/models/floor_plan_object_kind.dart';
import 'package:flutter/painting.dart' show Offset, Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  late Database db;
  late FloorPlanObjectsRepository repo;

  setUp(() async {
    initSqfliteFfiForTests();
    db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
    await migrateDatabaseToV69(db);
    // Η τρέχουσα μορφή: η διαγραφή ορόφου αγγίζει και τους πίνακες δικτύου.
    await migrateDatabaseToV74(db);
    repo = FloorPlanObjectsRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertObject({required int kindId, required int floorId}) =>
      db.insert('building_map_objects', {
        'kind_id': kindId,
        'floor_id': floorId,
        'x': 0,
        'y': 0,
      });

  Future<int> kindId(String name) async {
    final kinds = await repo.listKinds();
    return kinds.firstWhere((k) => k.kind.name == name).kind.id;
  }

  group('Αναβάθμιση v71', () {
    test('ξανατρέχει χωρίς να σβήσει όσα ορίστηκαν', () async {
      await repo.addKind(
        name: 'Εκτυπωτής',
        symbol: FloorPlanSymbol.printer,
        hasPorts: true,
      );
      await migrateDatabaseToV71(db);
      expect(await repo.listKinds(), hasLength(1));
    });

    test(
      'τηλέφωνο και εξοπλισμός παίρνουν μία θέση, ο υπάλληλος πολλές',
      () async {
        Future<void> place(String type, int floorId) =>
            db.insert('building_map_placements', {
              'entity_type': type,
              'entity_id': 7,
              'floor_id': floorId,
              'x': 0,
              'y': 0,
            });

        await place('user', 1);
        await place('user', 2);
        await place('phone', 1);
        await place('equipment', 1);

        await expectLater(place('phone', 2), throwsA(isA<DatabaseException>()));
        await expectLater(
          place('equipment', 2),
          throwsA(isA<DatabaseException>()),
        );
      },
    );

    test(
      'η διαγραφή ορόφου σβήνει και τα αντικείμενα και τις θέσεις του',
      () async {
        await insertObject(kindId: 1, floorId: 1);
        await insertObject(kindId: 1, floorId: 2);
        await db.insert('building_map_placements', {
          'entity_type': 'user',
          'entity_id': 3,
          'floor_id': 1,
          'x': 0,
          'y': 0,
        });

        await FloorPlanRepository(db).deleteFloorPlan(db, 1);

        final objects = await db.query('building_map_objects');
        expect([for (final r in objects) r['floor_id']], [2]);
        expect(await db.query('building_map_placements'), isEmpty);
      },
    );
  });

  group('Είδη αντικειμένων', () {
    test('η βάση ξεκινά χωρίς κανένα είδος', () async {
      expect(await repo.listKinds(), isEmpty);
    });

    test('νέο είδος γράφεται με σύμβολο και «έχει θύρες»', () async {
      final outcome = await repo.addKind(
        name: '  Εκτυπωτής ',
        symbol: FloorPlanSymbol.printer,
        hasPorts: true,
      );

      expect(outcome, FloorPlanKindSaveOutcome.saved);
      final kind = (await repo.listKinds()).single.kind;
      expect(kind.name, 'Εκτυπωτής');
      expect(kind.symbol, FloorPlanSymbol.printer);
      expect(kind.hasPorts, isTrue);
    });

    test(
      'ίδιο όνομα με άλλους τόνους ή κεφαλαία δεν γίνεται δεύτερο είδος',
      () async {
        await repo.addKind(
          name: 'Εκτυπωτής',
          symbol: FloorPlanSymbol.printer,
          hasPorts: false,
        );

        final outcome = await repo.addKind(
          name: 'ΕΚΤΥΠΩΤΗΣ',
          symbol: FloorPlanSymbol.furniture,
          hasPorts: false,
        );

        expect(outcome, FloorPlanKindSaveOutcome.nameTaken);
        expect(await repo.listKinds(), hasLength(1));
      },
    );

    test('μετονομασία: το ίδιο είδος κρατά το όνομά του, άλλο όχι', () async {
      await repo.addKind(
        name: 'Γραφείο',
        symbol: FloorPlanSymbol.furniture,
        hasPorts: false,
      );
      await repo.addKind(
        name: 'Ντουλάπα',
        symbol: FloorPlanSymbol.furniture,
        hasPorts: false,
      );
      final desk = await kindId('Γραφείο');

      expect(
        await repo.updateKind(
          id: desk,
          name: 'γραφείο',
          symbol: FloorPlanSymbol.furniture,
          hasPorts: false,
        ),
        FloorPlanKindSaveOutcome.saved,
      );
      expect(
        await repo.updateKind(
          id: desk,
          name: 'Ντουλάπα',
          symbol: FloorPlanSymbol.furniture,
          hasPorts: false,
        ),
        FloorPlanKindSaveOutcome.nameTaken,
      );
    });

    test('είδος που σβήστηκε στο μεταξύ δεν ξαναγράφεται σιωπηλά', () async {
      expect(
        await repo.updateKind(
          id: 99,
          name: 'Εκτυπωτής',
          symbol: FloorPlanSymbol.printer,
          hasPorts: false,
        ),
        FloorPlanKindSaveOutcome.missing,
      );
      expect(await repo.listKinds(), isEmpty);
    });

    test(
      'είδος με αντικείμενα δεν αφαιρείται, και λέει πόσα και πού',
      () async {
        await repo.addKind(
          name: 'Εκτυπωτής',
          symbol: FloorPlanSymbol.printer,
          hasPorts: false,
        );
        final id = await kindId('Εκτυπωτής');
        await insertObject(kindId: id, floorId: 1);
        await insertObject(kindId: id, floorId: 1);
        await insertObject(kindId: id, floorId: 3);

        final blocked = await repo.deleteKind(id);

        expect(blocked?.objectCount, 3);
        expect(blocked?.floorIds, {1, 3});
        expect(await repo.listKinds(), hasLength(1));
      },
    );

    test('είδος χωρίς αντικείμενα αφαιρείται', () async {
      await repo.addKind(
        name: 'Εκτυπωτής',
        symbol: FloorPlanSymbol.printer,
        hasPorts: false,
      );

      expect(await repo.deleteKind(await kindId('Εκτυπωτής')), isNull);
      expect(await repo.listKinds(), isEmpty);
    });

    test(
      'σύμβολο νεότερης έκδοσης διαβάζεται χωρίς να ρίξει τη λίστα',
      () async {
        await db.insert('building_map_object_kinds', {
          'name': 'Κάμερα',
          'name_key': 'καμερα',
          'symbol': 'camera',
        });

        final kind = (await repo.listKinds()).single.kind;
        expect(kind.name, 'Κάμερα');
        expect(kind.symbol, isNull);
      },
    );
  });

  group('Αντικείμενα', () {
    FloorPlanObject printer(int floorId, Offset at) => FloorPlanObject(
      id: 0,
      floorId: floorId,
      kindId: 1,
      center: at,
      name: 'ΕΚΤ-01',
      ip: '10.1.2.3',
    );

    test('γράφεται με θέση, μέγεθος και στοιχεία, και κάθε όροφος βλέπει τα '
        'δικά του', () async {
      await repo.insertObject(printer(1, const Offset(120, 80)));
      await repo.insertObject(
        FloorPlanObject(
          id: 0,
          floorId: 2,
          kindId: 2,
          center: Offset.zero,
          size: const Size(160, 80),
        ),
      );

      final first = (await repo.listObjects(1)).single;
      expect(first.center, const Offset(120, 80));
      expect(first.size, isNull);
      expect(first.name, 'ΕΚΤ-01');
      expect(first.ip, '10.1.2.3');
      expect((await repo.listObjects(2)).single.size, const Size(160, 80));
    });

    test('μετακίνηση και επαναφορά κρατούν το ίδιο id', () async {
      final id = await repo.insertObject(printer(1, Offset.zero));
      final stored = (await repo.listObjects(1)).single;

      await repo.restoreObjects([
        stored.copyWith(center: const Offset(50, 0), rotationDegrees: 90),
      ]);

      final moved = (await repo.listObjects(1)).single;
      expect(moved.id, id);
      expect(moved.center, const Offset(50, 0));
      expect(moved.rotationDegrees, 90);
    });

    test('ό,τι σβήστηκε επιστρέφει με τα στοιχεία του', () async {
      await repo.insertObject(printer(1, Offset.zero));
      final id = (await repo.listObjects(1)).single.id;

      final removed = await repo.deleteObjects({id});
      expect(await repo.listObjects(1), isEmpty);

      await repo.restoreObjects(removed);
      final back = (await repo.listObjects(1)).single;
      expect(back.id, id);
      expect(back.name, 'ΕΚΤ-01');
    });

    test('κάθε εγγραφή αλλάζει το αποτύπωμα του ορόφου — έτσι το βλέπουν οι '
        'άλλοι σταθμοί', () async {
      final plans = FloorPlanRepository(db);
      await repo.insertObject(printer(1, Offset.zero));
      final afterInsert = (await plans.floorStamps())[1];
      expect(afterInsert, isNotNull);

      await Future<void>.delayed(const Duration(milliseconds: 5));
      final id = (await repo.listObjects(1)).single.id;
      await repo.deleteObjects({id});

      expect((await plans.floorStamps())[1], isNot(afterInsert));
    });

    test('κενά στοιχεία γράφονται ως κενά, όχι ως κενό κείμενο', () {
      final object = printer(
        1,
        Offset.zero,
      ).withDetails(name: '  ', ip: ' 10.0.0.9 ');
      expect(object.name, isNull);
      expect(object.ip, '10.0.0.9');
    });
  });

  group('Πληροφορίες ανά είδος', () {
    test('το είδος θυμάται αν δείχνει πληροφορίες', () async {
      await repo.addKind(
        name: 'Γραφείο',
        symbol: FloorPlanSymbol.furniture,
        hasPorts: false,
        showInfo: false,
      );
      final desk = (await repo.listKinds()).single.kind;
      expect(desk.showInfo, isFalse);

      await repo.updateKind(
        id: desk.id,
        name: 'Γραφείο',
        symbol: FloorPlanSymbol.furniture,
        hasPorts: false,
        showInfo: true,
      );
      expect((await repo.listKinds()).single.kind.showInfo, isTrue);
    });

    test('αναβάθμιση v73: τα υπάρχοντα είδη συνεχίζουν να δείχνουν '
        'πληροφορίες', () async {
      final old = await openDatabase(
        inMemoryDatabasePath,
        singleInstance: false,
      );
      addTearDown(old.close);
      await old.execute('''
        CREATE TABLE building_map_object_kinds (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          name_key TEXT NOT NULL UNIQUE,
          symbol TEXT NOT NULL,
          has_ports INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await old.insert('building_map_object_kinds', {
        'name': 'Εκτυπωτής',
        'name_key': 'εκτυπωτησ',
        'symbol': 'printer',
      });

      await migrateDatabaseToV73(old);
      await migrateDatabaseToV73(old);

      final kinds = await FloorPlanObjectsRepository(old).kinds();
      expect(kinds.values.single.showInfo, isTrue);
    });
  });

  group('Δίκτυο (v74)', () {
    test('αναβάθμιση v74: τα υπάρχοντα αντικείμενα μένουν εκτός καμπίνας, '
        'και ξανατρέχει χωρίς παρενέργειες', () async {
      final old = await openDatabase(
        inMemoryDatabasePath,
        singleInstance: false,
      );
      addTearDown(old.close);
      await old.execute('''
        CREATE TABLE building_map_objects (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          floor_id INTEGER NOT NULL,
          kind_id INTEGER NOT NULL,
          x REAL NOT NULL,
          y REAL NOT NULL,
          width REAL,
          height REAL,
          rotation_degrees REAL NOT NULL DEFAULT 0,
          name TEXT,
          ip TEXT,
          lansweeper_name TEXT,
          notes TEXT,
          cabinet_id INTEGER
        )
      ''');
      await old.insert('building_map_objects', {
        'floor_id': 1,
        'kind_id': 1,
        'x': 10,
        'y': 20,
        'name': 'ΕΚΤ-01',
      });

      await migrateDatabaseToV74(old);
      await migrateDatabaseToV74(old);

      final object = (await FloorPlanObjectsRepository(old).listObjects(1))
          .single;
      expect(object.name, 'ΕΚΤ-01');
      expect((object.inCabinet, object.rackU), (false, null));
    });

    test('κάθε πλευρά θύρας δέχεται ένα μόνο καλώδιο', () async {
      await migrateDatabaseToV74(db);
      await db.insert('building_map_cable_ends', {
        'cable_id': 1,
        'port_id': 5,
        'side': 'back',
      });
      await db.insert('building_map_cable_ends', {
        'cable_id': 2,
        'port_id': 5,
        'side': 'front',
      });
      expect(
        () => db.insert('building_map_cable_ends', {
          'cable_id': 3,
          'port_id': 5,
          'side': 'back',
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('η θέση και το ύψος σε U γράφονται και διαβάζονται', () async {
      await migrateDatabaseToV74(db);
      final id = await repo.insertObject(
        const FloorPlanObject(
          id: 0,
          floorId: 1,
          kindId: 1,
          center: Offset.zero,
          cabinetId: 7,
          rackU: 40,
          rackUnits: 3,
        ),
      );
      final stored = (await repo.listObjects(1)).firstWhere((o) => o.id == id);
      expect((stored.cabinetId, stored.rackU, stored.heightU), (7, 40, 3));
    });

    test('διαγραφή καμπίνας παίρνει μαζί ό,τι έχει μέσα, και τα επιστρέφει '
        'για την αναίρεση', () async {
      await migrateDatabaseToV74(db);
      final cabinet = await insertObject(kindId: 1, floorId: 1);
      final inside = await db.insert('building_map_objects', {
        'kind_id': 2,
        'floor_id': 1,
        'x': 0,
        'y': 0,
        'cabinet_id': cabinet,
        'rack_u': 1,
      });
      final elsewhere = await insertObject(kindId: 2, floorId: 1);

      final removed = await repo.deleteObjects([cabinet]);

      expect(removed.map((o) => o.id), unorderedEquals([cabinet, inside]));
      expect((await repo.listObjects(1)).map((o) => o.id), [elsewhere]);
    });

    test('η διαγραφή ορόφου σβήνει τις θύρες και τα καλώδιά του, όχι των '
        'άλλων ορόφων', () async {
      await migrateDatabaseToV74(db);
      final here = await insertObject(kindId: 1, floorId: 1);
      final there = await insertObject(kindId: 1, floorId: 2);
      final portHere = await db.insert('building_map_ports', {
        'object_id': here,
        'number': 1,
      });
      final portThere = await db.insert('building_map_ports', {
        'object_id': there,
        'number': 1,
      });
      final across = await db.rawInsert(
        'INSERT INTO building_map_cables DEFAULT VALUES',
      );
      for (final port in [portHere, portThere]) {
        await db.insert('building_map_cable_ends', {
          'cable_id': across,
          'port_id': port,
        });
      }
      final otherPort = await db.insert('building_map_ports', {
        'object_id': there,
        'number': 2,
      });

      await FloorPlanRepository(db).deleteFloorPlan(db, 1);

      final ports = await db.query('building_map_ports');
      expect(
        ports.map((r) => r['id']),
        unorderedEquals([portThere, otherPort]),
      );
      expect(await db.query('building_map_cables'), isEmpty);
      expect(await db.query('building_map_cable_ends'), isEmpty);
    });
  });
}
