import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/floor_plan_objects_repository.dart';
import 'package:call_logger/core/database/floor_plan_repository.dart';
import 'package:call_logger/core/database/omnisearch_service.dart';
import 'package:call_logger/core/models/floor_plan_element.dart';
import 'package:call_logger/core/models/floor_plan_object_kind.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

/// Κλείδωμα συμπεριφοράς omnisearch πριν από Φάση Γ.3α (OmnisearchService).
void main() {
  group('Omnisearch behavior — lock πριν εξαγωγή', () {
    late OmnisearchService repo;
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp(
        'omnisearch_service_test_',
      );
      await DatabaseHelper.bindTestDatabaseFile(
        '${dir.path}/omnisearch_service.db',
      );
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('building_map_placements');
      await db.delete('building_map_objects');
      await db.delete('building_map_object_kinds');
      await db.delete('building_map_plan_elements');
      await db.delete('building_map_floor_state');
      await db.delete('building_map_floors');
      await db.delete('department_phones');
      await db.delete('user_phones');
      await db.delete('phones');
      await db.delete('user_equipment');
      await db.delete('equipment');
      await db.delete('users');
      await db.delete('departments');
      repo = OmnisearchService(db);
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

    test(
      'department hit: kind, entityId, title, mapDisplayLabel, subtitle',
      () async {
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
      },
    );

    Future<void> drawRoom(int floorId, int departmentId) =>
        FloorPlanRepository(db).insertElement(
          FloorPlanElement(
            id: 0,
            floorId: floorId,
            kind: FloorPlanElementKind.room,
            points: const [Offset(0, 0), Offset(400, 0), Offset(400, 300)],
            departmentId: departmentId,
          ),
        );

    test('department: χώρος σε ενεργοποιημένο όροφο του νέου χάρτη = '
        'σχεδιασμένο', () async {
      final floorId = await insertFloor(label: 'Υπόγειο');
      final deptId = await insertDepartment(
        name: 'Ξυλουργοί',
        floorId: floorId,
      );
      await drawRoom(floorId, deptId);
      await FloorPlanRepository(db).setActive(floorId);

      final hit = (await repo.searchBuildingMapOmnisearch('ξυλουργ')).single;
      expect(hit.subtitle, 'Τμήμα • Υπόγειο');
    });

    test('department: χώρος σε όροφο που δεν ενεργοποιήθηκε ακόμη = χωρίς '
        'σχεδίαση', () async {
      final floorId = await insertFloor(label: 'Υπόγειο');
      final deptId = await insertDepartment(
        name: 'Ξυλουργοί',
        floorId: floorId,
      );
      await drawRoom(floorId, deptId);

      final hit = (await repo.searchBuildingMapOmnisearch('ξυλουργ')).single;
      expect(hit.subtitle, 'Τμήμα • Υπόγειο • χωρίς σχεδίαση');
    });

    test('department: mapDisplayLabel null όταν ίδιο με title', () async {
      await insertDepartment(name: 'Τμήμα Ίδιο', mapCustomName: 'Τμήμα Ίδιο');

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
      await db.insert('user_phones', {'user_id': userId, 'phone_id': phoneId});

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

    // Πραγματικό σενάριο 27/07: ο 3668 χωρίς απευθείας τμήμα έδειχνε σκέτο
    // «Εξοπλισμός» — το «ποιος και πού» έρχεται από την κάτοχο μέσω M2M.
    test('equipment χωρίς άμεσο τμήμα: κάτοχος + τμήμα κατόχου', () async {
      final deptId = await insertDepartment(name: 'Εφημερείο ΤΕΠ');
      final userId = await db.insert('users', {
        'first_name': 'Σοφία',
        'last_name': 'Κανέλου',
        'department_id': deptId,
        'is_deleted': 0,
      });
      final eqId = await db.insert('equipment', {
        'code_equipment': '3668',
        'is_deleted': 0,
      });
      await db.insert('user_equipment', {
        'user_id': userId,
        'equipment_id': eqId,
      });

      final hits = await repo.searchBuildingMapOmnisearch('3668');
      final hit = hits.singleWhere(
        (h) => h.kind == BuildingMapOmnisearchEntityKind.equipment,
      );
      expect(hit.subtitle, contains('Σοφία Κανέλου'));
      expect(hit.subtitle, contains('Εφημερείο ΤΕΠ'));
      expect(hit.departmentIds, [
        deptId,
      ], reason: 'Η μετάβαση στον χάρτη κληρονομεί το τμήμα της κατόχου');
    });

    test('equipment με άμεσο τμήμα: εμφανίζεται και ο κάτοχος', () async {
      final directDeptId = await insertDepartment(name: 'Αποθήκη Υλικού');
      final ownerDeptId = await insertDepartment(name: 'Πληροφορική');
      final userId = await db.insert('users', {
        'first_name': 'Βασίλης',
        'last_name': 'Δρόσος',
        'department_id': ownerDeptId,
        'is_deleted': 0,
      });
      final eqId = await db.insert('equipment', {
        'code_equipment': 'PC-5006',
        'department_id': directDeptId,
        'is_deleted': 0,
      });
      await db.insert('user_equipment', {
        'user_id': userId,
        'equipment_id': eqId,
      });

      final hits = await repo.searchBuildingMapOmnisearch('pc-5006');
      final hit = hits.single;
      expect(hit.subtitle, contains('Βασίλης Δρόσος'));
      expect(
        hit.subtitle,
        contains('Αποθήκη Υλικού'),
        reason: 'Το άμεσο τμήμα κερδίζει στην εμφάνιση',
      );
      expect(
        hit.departmentIds,
        containsAll([directDeptId, ownerDeptId]),
        reason: 'Η μετάβαση προσφέρει και τις δύο τοποθεσίες',
      );
    });

    test('equipment: διαγραμμένος κάτοχος δεν εμφανίζεται', () async {
      final deptId = await insertDepartment(name: 'Γραμματεία');
      final userId = await db.insert('users', {
        'first_name': 'Παλιός',
        'last_name': 'Κάτοχος',
        'department_id': deptId,
        'is_deleted': 1,
      });
      final eqId = await db.insert('equipment', {
        'code_equipment': 'EQ-ORPHAN',
        'is_deleted': 0,
      });
      await db.insert('user_equipment', {
        'user_id': userId,
        'equipment_id': eqId,
      });

      final hits = await repo.searchBuildingMapOmnisearch('eq-orphan');
      final hit = hits.single;
      expect(hit.subtitle ?? '', isNot(contains('Παλιός')));
      expect(hit.departmentIds, isEmpty);
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

    test('ranking: ακριβές πριν από prefix πριν από contains, μετά kind, μετά αλφαβητικά', () async {
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
      expect(
        await repo.searchBuildingMapOmnisearch('τμημα', limit: 0),
        isEmpty,
      );
    });

    test('limit περιορίζει αποτελέσματα', () async {
      await insertDepartment(name: 'Alpha Τμήμα');
      await insertDepartment(name: 'Beta Τμήμα');
      await insertDepartment(name: 'Gamma Τμήμα');

      final hits = await repo.searchBuildingMapOmnisearch('τμημα', limit: 2);
      expect(hits, hasLength(2));
    });

    // ── Νέος χάρτης: θέσεις και αντικείμενα ──────────────────────────────

    Future<int> activeFloor(String label) async {
      final id = await insertFloor(label: label);
      await FloorPlanRepository(db).setActive(id);
      return id;
    }

    Future<int> place(String type, int entityId, int floorId) =>
        db.insert('building_map_placements', {
          'entity_type': type,
          'entity_id': entityId,
          'floor_id': floorId,
          'x': 100.0,
          'y': 50.0,
        });

    /// Κάθε σημείο βρίσκεται στο «Γραφείο υλικού».
    ({int? departmentId, String? name})? Function(Offset) office(
      List<FloorPlanElement> _,
    ) =>
        (_) => (departmentId: null, name: 'Γραφείο υλικού');

    Future<int> user(String first, String last) => db.insert('users', {
      'first_name': first,
      'last_name': last,
      'is_deleted': 0,
    });

    test(
      'υπάλληλος σε δύο θέσεις = δύο αποτελέσματα, με όροφο και χώρο',
      () async {
        final ground = await activeFloor('Ισόγειο');
        final first = await activeFloor('1ος');
        final userId = await user('Γιώργος', 'Παπαδόπουλος');
        final a = await place('user', userId, ground);
        final b = await place('user', userId, first);

        final hits = await repo.searchBuildingMapOmnisearch(
          'παπαδοπ',
          roomLookup: office,
        );
        expect(hits, hasLength(2));
        expect({for (final h in hits) h.spot!.itemId}, {a, b});
        expect({for (final h in hits) h.spot!.floorId}, {ground, first});
        expect(hits.every((h) => h.spot!.isPlacement), isTrue);
        expect(hits.first.subtitle, contains('Γραφείο υλικού'));
        expect(hits.any((h) => h.unplaced), isFalse);
      },
    );

    test('«2345» βρίσκει το τηλέφωνο με τη θέση του, πρώτο', () async {
      final floor = await activeFloor('Ισόγειο');
      final phoneId = await db.insert('phones', {
        'number': '2345',
        'is_deleted': 0,
      });
      final userId = await user('Γιώργος', 'Παπαδόπουλος');
      await db.insert('user_phones', {'user_id': userId, 'phone_id': phoneId});
      final placementId = await place('phone', phoneId, floor);

      final hits = await repo.searchBuildingMapOmnisearch('2345');
      final first = hits.first;
      expect(first.kind, BuildingMapOmnisearchEntityKind.phone);
      expect(first.spot?.itemId, placementId);
      expect(first.spot?.floorId, floor);
    });

    test('εγγραφή χωρίς θέση: αχνή, «χωρίς θέση στον χάρτη», με τα τμήματά '
        'της για τη μετάβαση', () async {
      await activeFloor('Ισόγειο');
      final deptId = await insertDepartment(name: 'Υλικού');
      await db.insert('phones', {
        'number': '2345',
        'department_id': deptId,
        'is_deleted': 0,
      });

      final hit = (await repo.searchBuildingMapOmnisearch('2345')).single;
      expect(hit.unplaced, isTrue);
      expect(hit.spot, isNull);
      expect(hit.subtitle, contains('χωρίς θέση στον χάρτη'));
      expect(hit.departmentIds, [deptId]);
    });

    test('χωρίς κανέναν ενεργοποιημένο όροφο τίποτα δεν είναι αχνό', () async {
      await user('Γιώργος', 'Παπαδόπουλος');

      final hit = (await repo.searchBuildingMapOmnisearch('παπαδοπ')).single;
      expect(hit.unplaced, isFalse);
    });

    test('θέση σε όροφο που δεν ενεργοποιήθηκε δεν εμφανίζεται', () async {
      await activeFloor('Ισόγειο');
      final draft = await insertFloor(label: 'Υπόγειο');
      final userId = await user('Γιώργος', 'Παπαδόπουλος');
      await place('user', userId, draft);

      final hit = (await repo.searchBuildingMapOmnisearch('παπαδοπ')).single;
      expect(hit.spot, isNull);
      expect(hit.unplaced, isTrue);
    });

    test(
      'αντικείμενο χάρτη: βρίσκεται με την IP, όχι σε ανενεργό όροφο',
      () async {
        final floor = await activeFloor('Ισόγειο');
        final draft = await insertFloor(label: 'Υπόγειο');
        final objects = FloorPlanObjectsRepository(db);
        await objects.addKind(
          name: 'Εκτυπωτής',
          symbol: FloorPlanSymbol.printer,
          hasPorts: false,
        );
        final kindId = (await objects.kinds()).keys.single;
        final shown = await db.insert('building_map_objects', {
          'floor_id': floor,
          'kind_id': kindId,
          'x': 10.0,
          'y': 20.0,
          'ip': '10.1.2.33',
        });
        await db.insert('building_map_objects', {
          'floor_id': draft,
          'kind_id': kindId,
          'x': 10.0,
          'y': 20.0,
          'ip': '10.1.2.34',
        });

        final hit = (await repo.searchBuildingMapOmnisearch('10.1.2.3')).single;
        expect(hit.kind, BuildingMapOmnisearchEntityKind.mapObject);
        expect(hit.title, 'Εκτυπωτής');
        expect(hit.spot?.itemId, shown);
        expect(hit.spot?.isPlacement, isFalse);
      },
    );
  });
}
