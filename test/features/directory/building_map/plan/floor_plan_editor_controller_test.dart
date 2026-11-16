// Η αναίρεση στη σχεδίαση γράφει κι αυτή αμέσως στη βάση: ό,τι αναιρείται
// φεύγει από τη βάση, ό,τι επαναλαμβάνεται ξαναγράφεται. Το ίδιο και για τα
// αντικείμενα του χάρτη, μόνα τους ή μαζί με το σχέδιο.
//
//   flutter test test/features/directory/building_map/plan/floor_plan_editor_controller_test.dart

import 'dart:convert';
import 'dart:typed_data';

import 'package:call_logger/features/directory/building_map/plan/services/floor_plan_pattern_cache.dart';
import 'package:call_logger/features/directory/building_map/plan/services/floor_plan_tool_preference.dart';
import 'package:call_logger/core/database/database_foreign_keys.dart';
import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/database/floor_plan_objects_repository.dart';
import 'package:call_logger/core/database/floor_plan_placements_repository.dart';
import 'package:call_logger/core/database/floor_plan_ports_repository.dart';
import 'package:call_logger/core/database/floor_plan_repository.dart';
import 'package:call_logger/core/models/floor_plan_element.dart';
import 'package:call_logger/core/models/floor_plan_object.dart';
import 'package:call_logger/core/models/floor_plan_object_kind.dart';
import 'package:call_logger/core/models/floor_plan_placement.dart';
import 'package:call_logger/core/models/floor_plan_port.dart';
import 'package:flutter/painting.dart' show Size;
import 'package:call_logger/features/directory/building_map/plan/floor_plan_cabinet.dart';
import 'package:call_logger/features/directory/building_map/plan/floor_plan_editor_controller.dart';
import 'package:call_logger/features/directory/building_map/plan/floor_plan_ports.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../test_setup.dart';

void main() {
  late Database db;
  late FloorPlanRepository repo;
  late FloorPlanEditorController controller;
  late List<String> errors;

  setUp(() async {
    initSqfliteFfiForTests();
    db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
    await migrateDatabaseToV69(db);
    await migrateDatabaseToV81(db);
    // Ο πίνακας των ορόφων υπάρχει πάντα στην πραγματική βάση (v20)· εδώ
    // χρειάζεται για το «πού βρίσκεται» των γραμμένων ονομάτων θυρών.
    await db.execute(
      'CREATE TABLE IF NOT EXISTS building_map_floors ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'sort_order INTEGER NOT NULL DEFAULT 0, label TEXT NOT NULL, '
      'floor_group TEXT, image_path TEXT NOT NULL, '
      'rotation_degrees REAL NOT NULL DEFAULT 0)',
    );
    repo = FloorPlanRepository(db);
    errors = [];
    controller = FloorPlanEditorController(
      floorId: 1,
      repository: repo,
      onError: errors.add,
    );
    await controller.load();
  });

  tearDown(() async {
    controller.dispose();
    await db.close();
  });

  Future<int> stored(FloorPlanElementKind kind) async =>
      (await repo.listElements(1)).where((e) => e.kind == kind).length;

  test('κάθε τοίχος γράφεται αμέσως', () async {
    await controller.addWall(Offset.zero, const Offset(400, 0));
    await controller.addWall(const Offset(400, 0), const Offset(400, 300));
    expect(await stored(FloorPlanElementKind.wall), 2);
    expect(errors, isEmpty);
  });

  test('αναίρεση σβήνει από τη βάση, επανάληψη ξαναγράφει', () async {
    await controller.addWall(Offset.zero, const Offset(400, 0));
    await controller.undo();
    expect(await stored(FloorPlanElementKind.wall), 0);
    await controller.redo();
    expect(await stored(FloorPlanElementKind.wall), 1);
  });

  test(
    'διαγραφή τοίχου με άνοιγμα: η αναίρεση φέρνει πίσω και τα δύο',
    () async {
      await controller.addWall(Offset.zero, const Offset(500, 0));
      final wallId = controller.wallSegments.single.id!;
      await controller.addOpening(wallId, 100, 190);

      controller.setTool(FloorPlanTool.select);
      controller.select(wallId);
      await controller.deleteSelected();
      expect(await repo.listElements(1), isEmpty);

      await controller.undo();
      expect(await stored(FloorPlanElementKind.wall), 1);
      expect(await stored(FloorPlanElementKind.opening), 1);
      expect(controller.openingsByWall[wallId], hasLength(1));

      await controller.redo();
      expect(await repo.listElements(1), isEmpty);
    },
  );

  test(
    'αλλαγή χώρου σε άλλο τμήμα: η αναίρεση επαναφέρει το προηγούμενο',
    () async {
      await controller.addRoom(const [
        Offset(0, 0),
        Offset(400, 0),
        Offset(400, 300),
      ], name: 'Διάδρομος');
      final id = controller.rooms.single.id;

      await controller.renameRoom(id, departmentId: 7);
      var stored = (await repo.listElements(1)).single;
      expect(stored.departmentId, 7);
      expect(stored.name, isNull);

      await controller.undo();
      stored = (await repo.listElements(1)).single;
      expect(stored.name, 'Διάδρομος');
      expect(stored.departmentId, isNull);

      await controller.redo();
      expect((await repo.listElements(1)).single.departmentId, 7);
    },
  );

  test('μετακίνηση πολλών μαζί: μία εγγραφή, μία αναίρεση', () async {
    await controller.addWall(Offset.zero, const Offset(400, 0));
    await controller.addText(const Offset(100, 100), 'Αποθήκη', 40);
    controller.setTool(FloorPlanTool.select);
    controller.selectMany({for (final e in controller.elements) e.id});

    controller.previewMove(const Offset(50, 20));
    // Όσο σύρεται, τίποτα δεν γράφεται.
    expect((await repo.listElements(1)).first.points.first, Offset.zero);
    await controller.commitPreview();

    final moved = await repo.listElements(1);
    expect(moved[0].points.first, const Offset(50, 20));
    expect(moved[1].points.first, const Offset(150, 120));

    await controller.undo();
    final back = await repo.listElements(1);
    expect(back[0].points.first, Offset.zero);
    expect(back[1].points.first, const Offset(100, 100));
  });

  test(
    'επικόλληση τοίχου με πόρτα: η νέα πόρτα ανήκει στον νέο τοίχο',
    () async {
      await controller.addWall(Offset.zero, const Offset(500, 0));
      final wallId = controller.wallSegments.single.id!;
      await controller.addOpening(wallId, 100, 190);
      controller.setTool(FloorPlanTool.select);
      controller.select(wallId);

      controller.copySelected();
      await controller.paste();

      final stored = await repo.listElements(1);
      final walls = stored.where((e) => e.kind == FloorPlanElementKind.wall);
      final doors = stored.where((e) => e.kind == FloorPlanElementKind.opening);
      expect(walls, hasLength(2));
      expect(
        doors.map((d) => d.parentId).toSet(),
        walls.map((w) => w.id).toSet(),
      );
      // Η επικόλληση γίνεται η νέα επιλογή.
      expect(controller.selectedIds, {walls.last.id});
    },
  );

  test('αποκοπή: φεύγει από τη βάση και επικολλάται ξανά', () async {
    await controller.addText(const Offset(10, 10), 'Α', 40);
    controller.setTool(FloorPlanTool.select);
    controller.select(controller.texts.single.id);

    await controller.cutSelected();
    expect(await repo.listElements(1), isEmpty);
    await controller.paste();
    expect((await repo.listElements(1)).single.name, 'Α');
  });

  test('κλειδωμένο σχέδιο: τίποτα δεν επιλέγεται', () async {
    await controller.addWall(Offset.zero, const Offset(400, 0));
    controller.setTool(FloorPlanTool.select);
    controller.toggleLock();
    controller.select(controller.wallSegments.single.id);
    expect(controller.selectedIds, isEmpty);
  });

  test('αλλαγή κειμένου και αναίρεσή της', () async {
    await controller.addText(const Offset(10, 10), 'Αποθήκη', 40);
    final id = controller.texts.single.id;
    await controller.updateText(id, 'Αρχείο', 70);
    var stored = (await repo.listElements(1)).single;
    expect((stored.name, stored.fontSize), ('Αρχείο', 70));
    await controller.undo();
    stored = (await repo.listElements(1)).single;
    expect((stored.name, stored.fontSize), ('Αποθήκη', 40));
  });

  test(
    'κείμενο που έμεινε άδειο διαγράφεται, και η αναίρεση το φέρνει πίσω',
    () async {
      await controller.addText(const Offset(10, 10), 'Αποθήκη', 40);
      final id = controller.texts.single.id;
      await controller.updateText(id, '   ', 40);
      expect(await repo.listElements(1), isEmpty);
      await controller.undo();
      expect((await repo.listElements(1)).single.name, 'Αποθήκη');
    },
  );

  Future<int> addRoom() async {
    await controller.addRoom(const [
      Offset(0, 0),
      Offset(400, 0),
      Offset(400, 300),
      Offset(0, 300),
    ], name: 'Αποθήκη');
    return controller.rooms.single.id;
  }

  test('σύρσιμο ονόματος χώρου: γράφεται μόνο η θέση του ονόματος, ως μία '
      'κίνηση', () async {
    final id = await addRoom();
    controller.previewRoomLabel(id, const Offset(300, 0));
    controller.previewRoomLabel(id, const Offset(600, -50));
    await controller.commitPreview();

    var stored = (await repo.listElements(1)).single;
    expect(stored.labelOffset, const Offset(600, -50));
    expect(stored.points.first, Offset.zero);
    await controller.undo();
    stored = (await repo.listElements(1)).single;
    expect(stored.labelOffset, isNull);
  });

  test('μέγεθος ονόματος χώρου και επιστροφή στο κέντρο', () async {
    final id = await addRoom();
    controller.previewRoomLabel(id, const Offset(300, 0));
    await controller.commitPreview();

    await controller.setRoomLabel(id, sizeCm: 45);
    var stored = (await repo.listElements(1)).single;
    expect((stored.fontSize, stored.labelOffset), (45, const Offset(300, 0)));

    await controller.setRoomLabel(id, toCenter: true);
    stored = (await repo.listElements(1)).single;
    expect((stored.fontSize, stored.labelOffset), (45, null));
  });

  test('αλλαγή μήκους τοίχου από την αρχή του: τοίχος και πόρτα γράφονται ως '
      'μία κίνηση, και η αναίρεση τα φέρνει πίσω και τα δύο', () async {
    await controller.addWall(Offset.zero, const Offset(500, 0));
    final wall = controller.elements.single;
    await controller.addOpening(wall.id, 100, 190);

    controller.previewWallEnd(wall.id, 0, const Offset(60, 0), toleranceCm: 10);
    await controller.commitPreview();

    Future<(double, double)> startAndDoor() async {
      final stored = await repo.listElements(1);
      final w = stored.firstWhere((e) => e.kind == FloorPlanElementKind.wall);
      final d = stored.firstWhere(
        (e) => e.kind == FloorPlanElementKind.opening,
      );
      return (w.points[0].dx, d.points[0].dx);
    }

    // Η αρχή πήγε στα 60 εκ.· η πόρτα απέχει πια 40 από αυτήν, άρα μένει στα
    // 100 εκ. του σχεδίου.
    expect(await startAndDoor(), (60.0, 40.0));
    await controller.undo();
    expect(await startAndDoor(), (0.0, 100.0));
    expect(errors, isEmpty);
  });

  test('πάχος σε δύο επιλεγμένους τοίχους: μία κίνηση, μία αναίρεση, και ο '
      'επόμενος τοίχος παίρνει το ίδιο πάχος', () async {
    await controller.addWall(Offset.zero, const Offset(400, 0));
    await controller.addWall(const Offset(400, 0), const Offset(400, 300));
    controller.selectMany({for (final e in controller.elements) e.id});

    await controller.setSelectedWallThickness(40);
    Future<List<double?>> thicknesses() async => [
      for (final e in await repo.listElements(1)) e.thicknessCm,
    ];
    expect(await thicknesses(), [40, 40]);

    await controller.addWall(const Offset(400, 300), const Offset(0, 300));
    expect(await thicknesses(), [40, 40, 40]);

    await controller.undo();
    await controller.undo();
    expect(await thicknesses(), [null, null]);
    expect(errors, isEmpty);
  });

  test(
    'το πάχος μένει μέσα στα όρια, και το συνηθισμένο δεν γράφεται',
    () async {
      await controller.addWall(Offset.zero, const Offset(400, 0));
      final id = controller.elements.single.id;
      controller.select(id);

      await controller.setSelectedWallThickness(500);
      expect((await repo.listElements(1)).single.thicknessCm, 100);
      await controller.setSelectedWallThickness(15);
      expect((await repo.listElements(1)).single.thicknessCm, isNull);
    },
  );

  test('νέα κίνηση μετά από αναίρεση σβήνει την επανάληψη', () async {
    await controller.addWall(Offset.zero, const Offset(400, 0));
    await controller.undo();
    await controller.addWall(Offset.zero, const Offset(0, 300));
    expect(controller.canRedo, isFalse);
  });

  group('Μνήμη τελευταίου εργαλείου', () {
    test('τα μόνιμα εργαλεία αποθηκεύονται και ξαναδιαβάζονται', () {
      for (final tool in [
        FloorPlanTool.select,
        FloorPlanTool.wall,
        FloorPlanTool.room,
        FloorPlanTool.place,
      ]) {
        final back = FloorPlanRememberedTool.decode(
          FloorPlanRememberedTool.encode(tool),
        );
        expect(back?.tool, tool);
      }
      final object = FloorPlanRememberedTool.decode(
        FloorPlanRememberedTool.encode(FloorPlanTool.object, objectKindId: 7),
      );
      expect(object?.tool, FloorPlanTool.object);
      expect(object?.objectKindId, 7);
    });

    test('τα στιγμιαία εργαλεία δεν αποθηκεύονται', () {
      expect(FloorPlanRememberedTool.encode(FloorPlanTool.measure), isNull);
      expect(FloorPlanRememberedTool.encode(FloorPlanTool.calibrate), isNull);
      expect(FloorPlanRememberedTool.encode(FloorPlanTool.movePattern), isNull);
      expect(FloorPlanRememberedTool.decode('measure'), isNull);
      expect(FloorPlanRememberedTool.decode('άγνωστο'), isNull);
      expect(FloorPlanRememberedTool.decode(null), isNull);
    });
  });

  group('Αντικείμενα', () {
    late FloorPlanObjectsRepository objects;
    late FloorPlanEditorController editor;
    late int printerKind;
    late int deskKind;

    setUp(() async {
      await migrateDatabaseToV71(db);
      objects = FloorPlanObjectsRepository(db);
      await objects.addKind(
        name: 'Εκτυπωτής',
        symbol: FloorPlanSymbol.printer,
        hasPorts: true,
      );
      await objects.addKind(
        name: 'Γραφείο',
        symbol: FloorPlanSymbol.furniture,
        hasPorts: false,
      );
      final kinds = await objects.kinds();
      printerKind = kinds.values.firstWhere((k) => k.name == 'Εκτυπωτής').id;
      deskKind = kinds.values.firstWhere((k) => k.name == 'Γραφείο').id;
      editor = FloorPlanEditorController(
        floorId: 1,
        repository: repo,
        objectsRepository: objects,
        onError: errors.add,
      );
      await editor.load();
    });

    tearDown(() => editor.dispose());

    test('ξανανοίγει με το εργαλείο και το είδος που θυμάται ο χρήστης', () {
      editor.restoreTool(FloorPlanTool.object, objectKindId: printerKind);
      expect(editor.tool, FloorPlanTool.object);
      expect(editor.objectKind?.id, printerKind);
    });

    test('είδος που σβήστηκε στο μεταξύ δίνει «Επιλογή»', () {
      editor.restoreTool(FloorPlanTool.object, objectKindId: 999999);
      expect(editor.tool, FloorPlanTool.select);
    });

    test('εργαλείο που διάλεξε ο χρήστης όσο φόρτωνε δεν αλλάζει', () {
      editor.setTool(FloorPlanTool.room);
      editor.restoreTool(FloorPlanTool.text);
      expect(editor.tool, FloorPlanTool.room);
    });

    test('τοποθέτηση γράφεται αμέσως· αναίρεση σβήνει, επανάληψη '
        'ξαναγράφει', () async {
      await editor.addObject(printerKind, const Offset(100, 100));
      expect(await objects.listObjects(1), hasLength(1));

      await editor.undo();
      expect(await objects.listObjects(1), isEmpty);

      await editor.redo();
      expect(await objects.listObjects(1), hasLength(1));
      expect(errors, isEmpty);
    });

    test('τα στοιχεία του αντικειμένου γράφονται και αναιρούνται', () async {
      final printer = await editor.addObject(printerKind, Offset.zero);
      await editor.updateObjectDetails(
        printer!.id,
        name: 'ΕΚΤ-ΥΛ-01',
        ip: '10.1.2.33',
      );
      expect((await objects.listObjects(1)).single.ip, '10.1.2.33');

      await editor.undo();
      expect((await objects.listObjects(1)).single.ip, isNull);
    });

    test('τοίχος και αντικείμενο μετακινούνται μαζί ως μία κίνηση', () async {
      await editor.addWall(Offset.zero, const Offset(400, 0));
      final printer = await editor.addObject(printerKind, const Offset(50, 50));
      final wall = (await repo.listElements(1)).single;

      editor.selectMany({wall.id}, objects: {printer!.id});
      editor.previewMove(const Offset(0, 100));
      await editor.commitPreview();
      expect(
        (await objects.listObjects(1)).single.center,
        const Offset(50, 150),
      );
      expect((await repo.listElements(1)).single.points.first.dy, 100);

      await editor.undo();
      expect(
        (await objects.listObjects(1)).single.center,
        const Offset(50, 50),
      );
      expect((await repo.listElements(1)).single.points.first.dy, 0);
    });

    test('κλειδωμένο σχέδιο: το αντικείμενο επιλέγεται και κινείται, ο '
        'τοίχος όχι', () async {
      await editor.addWall(Offset.zero, const Offset(400, 0));
      final printer = await editor.addObject(printerKind, Offset.zero);
      final wall = (await repo.listElements(1)).single;
      editor.toggleLock();

      editor.selectMany({wall.id}, objects: {printer!.id});
      expect(editor.selectedIds, isEmpty);
      expect(editor.selectedObjectIds, {printer.id});

      await editor.nudgeSelected(const Offset(10, 0));
      expect((await objects.listObjects(1)).single.center, const Offset(10, 0));
      expect((await repo.listElements(1)).single.points.first, Offset.zero);
    });

    test('η επικόλληση φέρνει αντικείμενο χωρίς όνομα και IP', () async {
      final printer = await editor.addObject(printerKind, Offset.zero);
      await editor.updateObjectDetails(
        printer!.id,
        name: 'ΕΚΤ-01',
        ip: '10.0.0.1',
        notes: 'δίπλα στο παράθυρο',
      );
      editor.selectObject(printer.id);
      editor.copySelected();

      await editor.paste();

      final all = await objects.listObjects(1);
      expect(all, hasLength(2));
      final copy = all.firstWhere((o) => o.id != printer.id);
      expect(copy.name, isNull);
      expect(copy.ip, isNull);
      expect(copy.notes, 'δίπλα στο παράθυρο');
      expect(editor.selectedObjectIds, {copy.id});
    });

    test('διαγραφή αντικειμένου και αναίρεσή της με τα στοιχεία του', () async {
      final printer = await editor.addObject(printerKind, Offset.zero);
      await editor.updateObjectDetails(printer!.id, name: 'ΕΚΤ-01');
      editor.selectObject(printer.id);

      await editor.deleteSelected();
      expect(await objects.listObjects(1), isEmpty);

      await editor.undo();
      expect((await objects.listObjects(1)).single.name, 'ΕΚΤ-01');
    });

    test(
      'αλλαγή μεγέθους γραφείου από τη γωνία του, και αναίρεσή της',
      () async {
        final desk = await editor.addObject(
          deskKind,
          Offset.zero,
          size: const Size(160, 80),
        );

        editor.previewResize(desk!.id, 2, const Offset(120, 60));
        await editor.commitPreview();
        expect(
          (await objects.listObjects(1)).single.size,
          const Size(200, 100),
        );

        await editor.undo();
        expect((await objects.listObjects(1)).single.size, const Size(160, 80));
      },
    );
  });

  group('Θέσεις του Καταλόγου', () {
    late FloorPlanPlacementsRepository placements;
    late FloorPlanEditorController editor;

    FloorPlanCatalogEntry entry(FloorPlanPlacementType type, int id) =>
        editor.catalog[(type, id)]!;

    setUp(() async {
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
      await migrateDatabaseToV71(db);
      await db.insert('users', {
        'id': 10,
        'last_name': 'Παπαδόπουλος',
        'first_name': 'Γιώργος',
      });
      await db.insert('phones', {'id': 20, 'number': '2345'});
      placements = FloorPlanPlacementsRepository(db);
      editor = FloorPlanEditorController(
        floorId: 1,
        repository: repo,
        placementsRepository: placements,
        onError: errors.add,
      );
      await editor.load();
    });

    tearDown(() => editor.dispose());

    test('τοποθέτηση υπαλλήλου γράφεται αμέσως και αναιρείται', () async {
      await editor.placeEntry(
        entry(FloorPlanPlacementType.user, 10),
        const Offset(100, 100),
      );
      expect(await placements.listPlacements(1), hasLength(1));
      expect(editor.objectViews.single.label, 'Παπαδόπουλος Γιώργος');

      await editor.undo();
      expect(await placements.listPlacements(1), isEmpty);
      await editor.redo();
      expect(await placements.listPlacements(1), hasLength(1));
      expect(errors, isEmpty);
    });

    test('ο υπάλληλος παίρνει και δεύτερη θέση', () async {
      final user = entry(FloorPlanPlacementType.user, 10);
      await editor.placeEntry(user, Offset.zero);
      await editor.placeEntry(user, const Offset(500, 0));
      expect(await placements.listPlacements(1), hasLength(2));
      expect(editor.placementsOf(user), hasLength(2));
    });

    test('τηλέφωνο με θέση σε άλλον όροφο μεταφέρεται εδώ, και η αναίρεση το '
        'γυρίζει πίσω', () async {
      final id = await placements.insertPlacement(
        const FloorPlanPlacement(
          id: 0,
          type: FloorPlanPlacementType.phone,
          entityId: 20,
          floorId: 2,
          center: Offset(7, 7),
        ),
      );
      await editor.load();

      await editor.placeEntry(
        entry(FloorPlanPlacementType.phone, 20),
        const Offset(50, 50),
      );
      expect(await placements.listPlacements(2), isEmpty);
      final here = (await placements.listPlacements(1)).single;
      expect(here.id, id);
      expect(here.center, const Offset(50, 50));

      await editor.undo();
      expect(await placements.listPlacements(1), isEmpty);
      expect(
        (await placements.listPlacements(2)).single.center,
        const Offset(7, 7),
      );
    });

    test('κλειδωμένο σχέδιο: η θέση επιλέγεται και μετακινείται', () async {
      final placed = await editor.placeEntry(
        entry(FloorPlanPlacementType.user, 10),
        Offset.zero,
      );
      editor.toggleLock();
      editor.selectMany(const {}, placements: {placed!.id});

      await editor.nudgeSelected(const Offset(10, 0));

      expect(
        (await placements.listPlacements(1)).single.center,
        const Offset(10, 0),
      );
    });

    test('η διαγραφή βγάζει τον υπάλληλο μόνο από τον χάρτη', () async {
      final placed = await editor.placeEntry(
        entry(FloorPlanPlacementType.user, 10),
        Offset.zero,
      );
      editor.selectMany(const {}, placements: {placed!.id});

      await editor.deleteSelected();
      expect(await placements.listPlacements(1), isEmpty);
      expect(await db.query('users'), hasLength(1));

      await editor.undo();
      expect(await placements.listPlacements(1), hasLength(1));
    });

    test('οι θέσεις δεν αντιγράφονται', () async {
      final placed = await editor.placeEntry(
        entry(FloorPlanPlacementType.user, 10),
        Offset.zero,
      );
      editor.selectMany(const {}, placements: {placed!.id});
      editor.copySelected();

      await editor.paste();

      expect(await placements.listPlacements(1), hasLength(1));
    });

    test('ο υπολογιστής γυρίζει από τη λαβή, ως μία κίνηση', () async {
      await db.insert('equipment', {'id': 30, 'code_equipment': 'PC-1'});
      await editor.load();
      final placed = await editor.placeEntry(
        entry(FloorPlanPlacementType.equipment, 30),
        const Offset(100, 0),
      );
      editor.selectMany(const {}, placements: {placed!.id});

      editor.previewRotate(Offset.zero, 3.141592653589793 / 2);
      await editor.commitPreview();

      final turned = (await placements.listPlacements(1)).single;
      expect(turned.rotationDegrees, closeTo(90, 1e-9));
      expect(turned.center.dx, closeTo(0, 0.1));
      expect(turned.center.dy, closeTo(100, 0.1));

      await editor.undo();
      expect((await placements.listPlacements(1)).single.rotationDegrees, 0);
    });

    test('κρυμμένη στρώση: τα σύμβολά της ούτε φαίνονται ούτε μένουν '
        'επιλεγμένα', () async {
      final placed = await editor.placeEntry(
        entry(FloorPlanPlacementType.user, 10),
        Offset.zero,
      );
      editor.selectMany(const {}, placements: {placed!.id});

      editor.setHiddenLayers({'user'});

      expect(editor.objectViews, isEmpty);
      expect(editor.selectedPlacementIds, isEmpty);

      editor.setHiddenLayers(const {});
      expect(editor.objectViews, hasLength(1));
    });
  });

  group('Καμπίνες', () {
    late FloorPlanObjectsRepository objects;
    late FloorPlanEditorController editor;
    late int cabinetKind;
    late int switchKind;
    late int upsKind;

    setUp(() async {
      await migrateDatabaseToV74(db);
      objects = FloorPlanObjectsRepository(db);
      for (final (name, symbol) in const [
        ('Καμπίνα', FloorPlanSymbol.cabinet),
        ('Switch', FloorPlanSymbol.networkSwitch),
        ('UPS', FloorPlanSymbol.ups),
      ]) {
        await objects.addKind(name: name, symbol: symbol, hasPorts: false);
      }
      final kinds = await objects.kinds();
      int idOf(String name) =>
          kinds.values.firstWhere((k) => k.name == name).id;
      cabinetKind = idOf('Καμπίνα');
      switchKind = idOf('Switch');
      upsKind = idOf('UPS');
      editor = FloorPlanEditorController(
        floorId: 1,
        repository: repo,
        objectsRepository: objects,
        onError: errors.add,
      );
      await editor.load();
    });

    tearDown(() => editor.dispose());

    Future<FloorPlanObject> cabinet() async => (await editor.addObject(
      cabinetKind,
      const Offset(500, 500),
      size: const Size(60, 80),
    ))!;

    Future<FloorPlanObject> stored(int id) async =>
        (await objects.listObjects(1)).firstWhere((o) => o.id == id);

    test('νέα καμπίνα έχει 42 U· ό,τι μπαίνει πηγαίνει στο πρώτο ελεύθερο U '
        'και δεν ζωγραφίζεται στον χάρτη', () async {
      final rack = await cabinet();
      expect((await stored(rack.id)).rackUnits, 42);

      final first = await editor.addToCabinet(rack.id, switchKind);
      final second = await editor.addToCabinet(rack.id, switchKind);

      expect((await stored(first!.id)).rackU, 1);
      expect((await stored(second!.id)).rackU, 2);
      expect(editor.objectViews.map((v) => v.id), [rack.id]);
    });

    test('νέα καμπίνα αριθμεί από κάτω· η αλλαγή αρίθμησης γράφεται, '
        'αναιρείται και δεν μετακινεί τίποτα', () async {
      final rack = await cabinet();
      expect((await stored(rack.id)).rackFromBottom, isTrue);
      final placed = await editor.addToCabinet(rack.id, switchKind, atU: 5);

      await editor.setCabinetRackFromBottom(rack.id, false);
      expect((await stored(rack.id)).rackFromBottom, isFalse);
      expect((await stored(placed!.id)).rackU, 5);

      await editor.undo();
      expect((await stored(rack.id)).rackFromBottom, isTrue);
    });

    test('τα μηνύματα γράφουν τον αριθμό U της καμπίνας', () async {
      final rack = await cabinet();
      await editor.addToCabinet(rack.id, switchKind, atU: 42);
      await editor.addToCabinet(rack.id, switchKind, atU: 42);
      // Από κάτω: η τελευταία θέση από πάνω είναι το U1.
      expect(errors.last, contains('U1 '));
    });

    test('προσθήκη σε συγκεκριμένο U· πιασμένο U δεν δέχεται τίποτα', () async {
      final rack = await cabinet();

      final placed = await editor.addToCabinet(rack.id, switchKind, atU: 17);
      expect((await stored(placed!.id)).rackU, 17);

      final again = await editor.addToCabinet(rack.id, switchKind, atU: 17);
      expect(again, isNull);
      // Νέα καμπίνα: αριθμεί από κάτω, άρα η θέση 17 από πάνω είναι το U26.
      expect(errors.last, contains('U26'));
      expect(editor.cabinetContents(rack.id), hasLength(1));
    });

    test('αντικείμενο που σύρεται πάνω στην καμπίνα μπαίνει μέσα· μία '
        'αναίρεση το ξαναβγάζει', () async {
      final rack = await cabinet();
      final sw = await editor.addObject(switchKind, const Offset(100, 100));

      editor.selectObject(sw!.id);
      editor.previewMove(const Offset(400, 400));
      await editor.commitPreview(dropIntoCabinets: true);

      final inside = await stored(sw.id);
      expect((inside.cabinetId, inside.rackU), (rack.id, 1));
      expect(editor.objectViews.map((v) => v.id), [rack.id]);

      await editor.undo();
      final back = await stored(sw.id);
      expect((back.cabinetId, back.center), (null, const Offset(100, 100)));
    });

    test('δύο αντικείμενα δεν πιάνουν το ίδιο U', () async {
      final rack = await cabinet();
      final a = await editor.addToCabinet(rack.id, switchKind);
      final b = await editor.addToCabinet(rack.id, switchKind);

      expect(await editor.moveInCabinet(b!.id, 1), isFalse);
      expect((await stored(b.id)).rackU, 2);
      expect(errors, hasLength(1));

      expect(await editor.moveInCabinet(b.id, 10), isTrue);
      expect((await stored(b.id)).rackU, 10);
      expect((await stored(a!.id)).rackU, 1);
    });

    test('ψηλότερο αντικείμενο δεν πατά το από κάτω του', () async {
      final rack = await cabinet();
      final ups = await editor.addToCabinet(rack.id, upsKind);
      await editor.addToCabinet(rack.id, switchKind);

      expect(await editor.setRackHeight(ups!.id, 3), isFalse);
      expect((await stored(ups.id)).heightU, 1);

      await editor.moveInCabinet(ups.id, 40);
      expect(await editor.setRackHeight(ups.id, 3), isTrue);
      expect((await stored(ups.id)).heightU, 3);
    });

    test('οι θέσεις της καμπίνας αλλάζουν και με περιεχόμενο, όχι όμως κάτω '
        'από ό,τι έχει μέσα', () async {
      final rack = await cabinet();
      final ups = await editor.addToCabinet(rack.id, upsKind);
      await editor.moveInCabinet(ups!.id, 40);

      expect(await editor.setCabinetUnits(rack.id, 120), isTrue);
      expect((await stored(rack.id)).rackUnits, 120);

      expect(await editor.setCabinetUnits(rack.id, 2), isFalse);
      expect((await stored(rack.id)).rackUnits, 120);
      // Από κάτω: η θέση 40 από πάνω, σε καμπίνα 42 U, είναι το U3, και με
      // 120 U κρατά τον αριθμό της· σε 2 U δεν χωρά.
      expect(errors.single, contains('U3)'));
      expect(errors.single, contains('πιο πάνω'));
    });

    test('αρίθμηση από κάτω: η αλλαγή των U κρατά τους αριθμούς των '
        'συσκευών· από πάνω, κρατά τις θέσεις', () async {
      final rack = await cabinet();
      final sw = await editor.addToCabinet(rack.id, switchKind, atU: 38);
      String label() => floorPlanCabinetRackLabel(
        editor.objectById(rack.id)!,
        editor.objectById(sw!.id)!.rackU!,
      );
      expect(label(), 'U5');

      await editor.setCabinetUnits(rack.id, 48);
      expect(label(), 'U5');
      await editor.setCabinetUnits(rack.id, 10);
      expect(label(), 'U5');

      await editor.setCabinetRackFromBottom(rack.id, false);
      final position = editor.objectById(sw!.id)!.rackU;
      await editor.setCabinetUnits(rack.id, 20);
      expect(editor.objectById(sw.id)!.rackU, position);
    });

    test('διαγραφή καμπίνας σβήνει και το περιεχόμενο· η αναίρεση τα φέρνει '
        'όλα πίσω', () async {
      final rack = await cabinet();
      final sw = await editor.addToCabinet(rack.id, switchKind);

      editor.selectObject(rack.id);
      await editor.deleteSelected();
      expect(await objects.listObjects(1), isEmpty);

      await editor.undo();
      expect((await stored(sw!.id)).cabinetId, rack.id);
      expect(await objects.listObjects(1), hasLength(2));
    });

    test('«Βγάλε από την καμπίνα» το αφήνει δίπλα της στον χάρτη', () async {
      final rack = await cabinet();
      final sw = await editor.addToCabinet(rack.id, switchKind);

      await editor.takeOutOfCabinet(sw!.id);

      final out = await stored(sw.id);
      expect((out.cabinetId, out.rackU), (null, null));
      expect(out.center.dx, greaterThan(530));
      expect(
        editor.objectViews.map((v) => v.id),
        containsAll([rack.id, sw.id]),
      );
    });
  });

  group('Θύρες', () {
    late FloorPlanObjectsRepository objects;
    late FloorPlanPortsRepository ports;
    late FloorPlanEditorController editor;
    late int switchKind;

    setUp(() async {
      await migrateDatabaseToV74(db);
      objects = FloorPlanObjectsRepository(db);
      ports = FloorPlanPortsRepository(db);
      await objects.addKind(
        name: 'Switch',
        symbol: FloorPlanSymbol.networkSwitch,
        hasPorts: true,
      );
      switchKind = (await objects.kinds()).values.single.id;
      editor = FloorPlanEditorController(
        floorId: 1,
        repository: repo,
        objectsRepository: objects,
        portsRepository: ports,
        onError: errors.add,
      );
      await editor.load();
    });

    tearDown(() => editor.dispose());

    Future<List<int>> numbers() async => [
      for (final p in await ports.listForFloor(1)) p.number,
    ];

    test('switch 48 θυρών: όλες δημιουργούνται, όλες ελεύθερες', () async {
      final sw = await editor.addObject(switchKind, Offset.zero);

      await editor.setPortCount(sw!.id, 48);

      expect(await numbers(), [for (var n = 1; n <= 48; n++) n]);
      expect(editor.occupiedPortIds, isEmpty);
    });

    test('λιγότερες θύρες κρατούν τα γραμμένα ονόματα των υπόλοιπων· η '
        'αναίρεση φέρνει πίσω όσες έφυγαν', () async {
      final sw = await editor.addObject(switchKind, Offset.zero);
      await editor.setPortCount(sw!.id, 4);
      final first = editor.portsOf(sw.id).first;
      await editor.setPortWrittenName(first.id, 'Κάμερα 7');

      await editor.setPortCount(sw.id, 2);
      expect(await numbers(), [1, 2]);
      expect((await ports.listForFloor(1)).first.writtenName, 'Κάμερα 7');

      await editor.undo();
      expect(await numbers(), [1, 2, 3, 4]);
    });

    test('ίδιο όνομα σε άλλον όροφο: βρίσκεται για προειδοποίηση, αλλά η '
        'αποθήκευση γίνεται κανονικά', () async {
      final sw = await editor.addObject(switchKind, Offset.zero);
      await editor.setPortCount(sw!.id, 2);
      final mine = editor.portsOf(sw.id).first;
      await editor.setPortWrittenName(mine.id, 'MC.2.N05');

      final other = FloorPlanEditorController(
        floorId: 2,
        repository: repo,
        objectsRepository: objects,
        portsRepository: ports,
        onError: errors.add,
      );
      addTearDown(other.dispose);
      await other.load();
      final sw2 = await other.addObject(switchKind, Offset.zero);
      await other.setPortCount(sw2!.id, 1);
      final theirs = other.portsOf(sw2.id).single;

      expect(other.writtenNameClash('mc.2.n05')?.portId, mine.id);
      await other.setPortWrittenName(theirs.id, 'MC.2.N05');
      expect(other.portsOf(sw2.id).single.writtenName, 'MC.2.N05');
      // Η θύρα δεν «συγκρούεται» με τον εαυτό της.
      expect(
        other.writtenNameClash('MC.2.N05', exceptPortIds: {mine.id})?.portId,
        theirs.id,
      );
      expect(
        other.writtenNameClash('MC.2.N05', exceptPortIds: {mine.id, theirs.id}),
        isNull,
      );
    });

    test('συνέχεια μοτίβου: οι κενές θύρες παίρνουν όνομα, οι γραμμένες '
        'μένουν, και ένα Ctrl+Z τα παίρνει όλα πίσω', () async {
      final sw = await editor.addObject(switchKind, Offset.zero);
      await editor.setPortCount(sw!.id, 4);
      final third = editor.portsOf(sw.id)[2];
      await editor.setPortWrittenName(third.id, 'Κάμερα 7');
      final first = editor.portsOf(sw.id).first;

      await editor.setPortWrittenName(
        first.id,
        'MC.2.N01',
        continuePattern: true,
      );
      List<String?> names() => [
        for (final p in editor.portsOf(sw.id)) p.writtenName,
      ];
      expect(names(), ['MC.2.N01', 'MC.2.N02', 'Κάμερα 7', 'MC.2.N04']);

      await editor.undo();
      expect(names(), [null, null, 'Κάμερα 7', null]);
    });

    test('το διαχωριστικό θυρών του patch panel: αυτόματο, μετά δικό του — '
        'και η αναζήτηση γράφει το ίδιο όνομα με τη σχεδίαση', () async {
      await objects.addKind(
        name: 'Patch',
        symbol: FloorPlanSymbol.patchPanel,
        hasPorts: true,
      );
      await editor.load();
      final patchKind = editor.kinds.values
          .firstWhere((k) => k.symbol == FloorPlanSymbol.patchPanel)
          .id;
      final panel = await editor.addObject(patchKind, Offset.zero);
      await editor.updateObjectDetails(panel!.id, name: 'Molex 1');
      await editor.setPortCount(panel.id, 2);
      final first = editor.portsOf(panel.id).first;
      Future<String?> searched() async =>
          (await ports.searchablePorts({1}))
              .firstWhere((r) => r.portId == first.id)
              .autoName;

      expect(editor.portName(first), 'Molex 1.1');
      expect(await searched(), 'Molex 1.1');

      await editor.updateObjectDetails(
        panel.id,
        name: 'Molex 1',
        portSeparator: '-',
      );
      expect(editor.portName(first), 'Molex 1-1');
      expect(await searched(), 'Molex 1-1');

      await editor.undo();
      expect(editor.portName(first), 'Molex 1.1');
    });

    test('το γραμμένο όνομα γράφεται και αναιρείται', () async {
      final sw = await editor.addObject(switchKind, Offset.zero);
      await editor.setPortCount(sw!.id, 2);
      final port = editor.portsOf(sw.id).last;

      await editor.setPortWrittenName(port.id, '  Κάμερα 7 ');
      expect((await ports.listForFloor(1)).last.writtenName, 'Κάμερα 7');

      await editor.undo();
      expect((await ports.listForFloor(1)).last.writtenName, isNull);
    });

    test('η διαγραφή του switch παίρνει μαζί τις θύρες του· η αναίρεση τις '
        'φέρνει πίσω με τα γραμμένα ονόματα', () async {
      final sw = await editor.addObject(switchKind, Offset.zero);
      await editor.setPortCount(sw!.id, 3);
      await editor.setPortWrittenName(
        editor.portsOf(sw.id).first.id,
        'Κάμερα 7',
      );

      editor.selectObject(sw.id);
      await editor.deleteSelected();
      expect(await ports.listForFloor(1), isEmpty);

      await editor.undo();
      expect(await numbers(), [1, 2, 3]);
      expect((await ports.listForFloor(1)).first.writtenName, 'Κάμερα 7');

      await editor.redo();
      expect(await ports.listForFloor(1), isEmpty);
    });

    test('αντίγραφο switch παίρνει το ίδιο πλήθος θυρών', () async {
      final sw = await editor.addObject(switchKind, Offset.zero);
      await editor.setPortCount(sw!.id, 8);
      editor.selectObject(sw.id);
      editor.copySelected();

      await editor.paste();

      final copy = editor.objects.firstWhere((o) => o.id != sw.id);
      expect(editor.portsOf(copy.id), hasLength(8));
    });

    test('θύρα με καλώδιο είναι κατειλημμένη, και η μείωση το ξέρει', () async {
      final sw = await editor.addObject(switchKind, Offset.zero);
      await editor.setPortCount(sw!.id, 4);
      final last = editor.portsOf(sw.id).last;
      final cable = await db.rawInsert(
        'INSERT INTO building_map_cables DEFAULT VALUES',
      );
      await db.insert('building_map_cable_ends', {
        'cable_id': cable,
        'port_id': last.id,
      });
      await editor.load();

      expect(editor.occupiedPortIds, {last.id});
      List<FloorPlanPortGroupSpec> one(int count) => [
        (source: 0, count: count, group: const FloorPlanPortGroup()),
      ];
      expect(editor.cabledPortsRemovedBy(sw.id, one(2)).map((p) => p.id), [
        last.id,
      ]);
      expect(editor.cabledPortsRemovedBy(sw.id, one(4)), isEmpty);

      await editor.setPortCount(sw.id, 2);
      expect(await db.query('building_map_cable_ends'), isEmpty);
    });
  });

  group('Stack και άλλος όροφος', () {
    late FloorPlanObjectsRepository objects;
    late FloorPlanPortsRepository ports;
    late FloorPlanEditorController editor;
    late int switchKind;
    late int outletKind;
    late int panelKind;

    setUp(() async {
      await migrateDatabaseToV75(db);
      objects = FloorPlanObjectsRepository(db);
      ports = FloorPlanPortsRepository(db);
      Future<int> kind(String name, FloorPlanSymbol symbol) async {
        await objects.addKind(name: name, symbol: symbol, hasPorts: true);
        return (await objects.kinds()).values
            .firstWhere((k) => k.name == name)
            .id;
      }

      switchKind = await kind('Switch', FloorPlanSymbol.networkSwitch);
      outletKind = await kind('Πρίζα', FloorPlanSymbol.outlet);
      panelKind = await kind('Patch', FloorPlanSymbol.patchPanel);
      editor = FloorPlanEditorController(
        floorId: 1,
        repository: repo,
        objectsRepository: objects,
        portsRepository: ports,
        onError: errors.add,
      );
      await editor.load();
    });

    tearDown(() => editor.dispose());

    Future<int> aSwitch(String name) async {
      final sw = await editor.addObject(switchKind, Offset.zero);
      await editor.updateObjectDetails(sw!.id, name: name);
      await editor.setPortCount(sw.id, 4);
      return sw.id;
    }

    test(
      'νέα ομάδα uplink: δικά της ονόματα, και φεύγει με μία αναίρεση',
      () async {
        final a = await aSwitch('SW-2');

        await editor.setPortGroups(a, [
          (source: 0, count: 4, group: const FloorPlanPortGroup()),
          (
            source: null,
            count: 2,
            group: const FloorPlanPortGroup(prefix: 'Te', speed: '10G SFP+'),
          ),
        ]);
        final ports = editor.portsOf(a);
        expect(ports, hasLength(6));
        expect(editor.portName(ports.last), 'SW-2 Te1/1/2');
        expect(editor.objectById(a)!.portGroups.last.speed, '10G SFP+');

        await editor.undo();
        expect(editor.portsOf(a), hasLength(4));
        expect(editor.objectById(a)!.portGroups, hasLength(1));
      },
    );

    test(
      'η προηγούμενη ομάδα μεγαλώνει: η ομάδα που συνεχίζει αλλάζει αριθμούς '
      'αλλά κρατά καλώδιο και γραμμένο όνομα',
      () async {
        final a = await aSwitch('SW-2');
        await editor.setPortGroups(a, [
          (source: 0, count: 2, group: const FloorPlanPortGroup(prefix: 'Te')),
          (
            source: null,
            count: 2,
            group: const FloorPlanPortGroup(prefix: 'Gi', continues: true),
          ),
        ]);
        final third = editor.portsOf(a)[2];
        expect(editor.portName(third), 'SW-2 Gi1/0/3');
        await editor.setPortWrittenName(third.id, 'Π-3');
        final other = await editor.addObject(switchKind, const Offset(50, 0));
        await editor.setPortCount(other!.id, 1);
        expect(
          await editor.addCable(third.id, editor.portsOf(other.id).single.id),
          isTrue,
        );

        await editor.setPortGroups(a, [
          (source: 0, count: 3, group: const FloorPlanPortGroup(prefix: 'Te')),
          (
            source: 1,
            count: 2,
            group: const FloorPlanPortGroup(prefix: 'Gi', continues: true),
          ),
        ]);
        final moved = editor.portsOf(a).firstWhere((p) => p.id == third.id);
        expect(editor.portName(moved), 'SW-2 Gi1/0/4');
        expect(moved.writtenName, 'Π-3');
        expect(editor.occupiedPortIds, contains(third.id));

        await editor.undo();
        final back = editor.portsOf(a).firstWhere((p) => p.id == third.id);
        expect(editor.portName(back), 'SW-2 Gi1/0/3');
        expect(editor.occupiedPortIds, contains(third.id));
      },
    );

    test(
      'ένωση σε stack: οι θύρες του δεύτερου παίρνουν το όνομα και το μέλος, '
      'και η αναίρεση τα γυρίζει',
      () async {
        final a = await aSwitch('SW-2');
        final b = await aSwitch('SW-3');

        await editor.joinStack(b, a);
        final port = editor.portsOf(b).firstWhere((p) => p.number == 3);
        expect(editor.portName(port), 'SW-2 Gi2/0/3');

        await editor.undo();
        expect(editor.portName(port), 'SW-3 Gi1/0/3');
      },
    );

    test(
      'το πρόθεμα γράφεται στη βάση και αλλάζει το όνομα, το Gi όχι',
      () async {
        final a = await aSwitch('SW-2');
        final port = editor.portsOf(a).first;

        final count = editor.portsOf(a).length;
        await editor.setPortGroups(a, [
          (
            source: 0,
            count: count,
            group: const FloorPlanPortGroup(prefix: 'Te'),
          ),
        ]);
        expect(editor.portName(port), 'SW-2 Te1/0/1');

        await editor.setPortGroups(a, [
          (
            source: 0,
            count: count,
            group: const FloorPlanPortGroup(prefix: 'Gi'),
          ),
        ]);
        expect(editor.objectById(a)!.portType, isNull);
      },
    );

    test('το καλώδιο δείχνει το όνομα Cisco και από την άλλη άκρη', () async {
      final a = await aSwitch('SW-2');
      final b = await aSwitch('SW-3');
      await editor.joinStack(b, a);
      final from = editor.portsOf(a).first.id;
      final to = editor.portsOf(b).last.id;

      await editor.addCable(from, to);

      final other = editor.portCables.otherEnd(from, kFloorPlanCableFront)!;
      expect(floorPlanCableEndName(other), 'SW-2 Gi2/0/4');
    });

    test(
      'πρίζα δεμένη σε patch panel άλλου ορόφου: η διαδρομή το ξέρει',
      () async {
        final panel = await editor.addObject(panelKind, Offset.zero);
        await editor.setPortCount(panel!.id, 2);
        final patch = editor.portsOf(panel.id).first.id;
        final basement = FloorPlanEditorController(
          floorId: 2,
          repository: repo,
          objectsRepository: objects,
          portsRepository: ports,
          onError: errors.add,
        );
        addTearDown(basement.dispose);
        await basement.load();
        final outlet = await basement.addObject(outletKind, Offset.zero);
        await basement.saveOutlet(outlet!.id, [
          FloorPlanOutletPortDraft(number: 1, patchPortId: patch),
          const FloorPlanOutletPortDraft(number: 2),
        ]);

        expect(basement.portLinks.single.panelFloorId, 1);
        expect(basement.portLinks.single.outletFloorId, 2);
      },
    );
  });

  group('Καλώδια', () {
    late FloorPlanObjectsRepository objects;
    late FloorPlanPortsRepository ports;
    late FloorPlanEditorController editor;
    late int switchKind;
    late int printerKind;

    setUp(() async {
      await migrateDatabaseToV74(db);
      objects = FloorPlanObjectsRepository(db);
      ports = FloorPlanPortsRepository(db);
      Future<int> kind(String name, FloorPlanSymbol symbol) async {
        await objects.addKind(name: name, symbol: symbol, hasPorts: true);
        return (await objects.kinds()).values
            .firstWhere((k) => k.name == name)
            .id;
      }

      switchKind = await kind('Switch', FloorPlanSymbol.networkSwitch);
      printerKind = await kind('Εκτυπωτής', FloorPlanSymbol.printer);
      editor = FloorPlanEditorController(
        floorId: 1,
        repository: repo,
        objectsRepository: objects,
        portsRepository: ports,
        onError: errors.add,
      );
      await editor.load();
    });

    tearDown(() => editor.dispose());

    Future<int> aSwitch(int count) async {
      final sw = await editor.addObject(switchKind, Offset.zero);
      await editor.setPortCount(sw!.id, count);
      return sw.id;
    }

    int portOf(int objectId, int number) =>
        editor.portsOf(objectId).firstWhere((p) => p.number == number).id;

    test(
      'καλώδιο: οι δύο θύρες πιάνονται, η αναίρεση τις ελευθερώνει',
      () async {
        final a = await aSwitch(4);
        final b = await aSwitch(4);
        final from = portOf(a, 1);
        final to = portOf(b, 2);

        expect(await editor.addCable(from, to), isTrue);
        expect(editor.occupiedPortIds, {from, to});

        await editor.undo();
        expect(editor.occupiedPortIds, isEmpty);
        expect(await db.query('building_map_cables'), isEmpty);

        await editor.redo();
        expect(editor.occupiedPortIds, {from, to});
      },
    );

    test(
      'πιασμένη θύρα αρνείται, με μήνυμα, και δεν γράφεται τίποτα',
      () async {
        final a = await aSwitch(2);
        final b = await aSwitch(2);
        await editor.addCable(portOf(a, 1), portOf(b, 1));

        expect(await editor.addCable(portOf(a, 2), portOf(b, 1)), isFalse);

        expect(errors.single, contains('έχει ήδη καλώδιο'));
        expect(await db.query('building_map_cables'), hasLength(1));
      },
    );

    test('τύπος καλωδίου: νέο = Cat 5e, αλλάζει με μία αναίρεση, και '
        'επιβιώνει της αφαίρεσης', () async {
      final a = await aSwitch(2);
      final b = await aSwitch(2);
      final from = portOf(a, 1);
      await editor.addCable(from, portOf(b, 1));
      final cable = editor.portCables.cableIdAt(from, kFloorPlanCableFront)!;
      expect(editor.portCables.typeAt(from, kFloorPlanCableFront), 'Cat 5e');

      await editor.setCableType(cable, 'Cat 6A');
      expect(editor.portCables.typeAt(from, kFloorPlanCableFront), 'Cat 6A');

      await editor.removeCable(cable);
      await editor.undo();
      expect(editor.portCables.typeAt(from, kFloorPlanCableFront), 'Cat 6A');

      await editor.undo();
      expect(editor.portCables.typeAt(from, kFloorPlanCableFront), 'Cat 5e');
    });

    test('αφαίρεση καλωδίου: και αναιρείται', () async {
      final a = await aSwitch(2);
      final b = await aSwitch(2);
      final from = portOf(a, 1);
      await editor.addCable(from, portOf(b, 1));
      final cable = editor.portCables.cableIdAt(from, kFloorPlanCableFront)!;

      await editor.removeCable(cable);
      expect(editor.occupiedPortIds, isEmpty);

      await editor.undo();
      expect(editor.occupiedPortIds, hasLength(2));
    });

    test('νέο αντικείμενο με «έχει θύρες» γεννιέται με μία θύρα', () async {
      final printer = await editor.addObject(printerKind, Offset.zero);
      expect(editor.portsOf(printer!.id), hasLength(1));
    });

    test('παλιό αντικείμενο χωρίς θύρα: την αποκτά με το καλώδιο, και η '
        'αναίρεση τα παίρνει και τα δύο', () async {
      final a = await aSwitch(2);
      final old = await objects.insertObject(
        FloorPlanObject(
          id: 0,
          floorId: 1,
          kindId: printerKind,
          center: const Offset(5, 5),
        ),
      );
      await editor.load();
      expect(editor.portsOf(old), isEmpty);

      expect(await editor.addCableToObject(portOf(a, 1), old), isTrue);
      expect(editor.portsOf(old), hasLength(1));
      expect(editor.occupiedPortIds, contains(editor.portsOf(old).single.id));

      await editor.undo();
      expect(editor.portsOf(old), isEmpty);
      expect(await db.query('building_map_cables'), isEmpty);
    });

    test('σβησμένο switch: η αναίρεση φέρνει πίσω και το καλώδιο', () async {
      final a = await aSwitch(2);
      final b = await aSwitch(2);
      await editor.addCable(portOf(a, 1), portOf(b, 1));

      await editor.deleteObjects({a});
      expect(await db.query('building_map_cables'), isEmpty);

      await editor.undo();
      expect(await db.query('building_map_cables'), hasLength(1));
      expect(editor.occupiedPortIds, hasLength(2));
    });
  });

  group('Πρίζες', () {
    late FloorPlanObjectsRepository objects;
    late FloorPlanPortsRepository ports;
    late FloorPlanEditorController editor;
    late int outletKind;
    late int panelKind;
    late int cabinetKind;

    setUp(() async {
      await migrateDatabaseToV74(db);
      objects = FloorPlanObjectsRepository(db);
      ports = FloorPlanPortsRepository(db);
      Future<int> kind(String name, FloorPlanSymbol symbol) async {
        await objects.addKind(name: name, symbol: symbol, hasPorts: true);
        return (await objects.kinds()).values
            .firstWhere((k) => k.name == name)
            .id;
      }

      outletKind = await kind('Πρίζα', FloorPlanSymbol.outlet);
      panelKind = await kind('Patch', FloorPlanSymbol.patchPanel);
      cabinetKind = await kind('Καμπίνα', FloorPlanSymbol.cabinet);
      editor = FloorPlanEditorController(
        floorId: 1,
        repository: repo,
        objectsRepository: objects,
        portsRepository: ports,
        onError: errors.add,
      );
      await editor.load();
    });

    tearDown(() => editor.dispose());

    /// Patch panel «F» στην καμπίνα «RC6», με 24 θύρες.
    Future<int> panelF() async {
      final cabinet = await editor.addObject(
        cabinetKind,
        const Offset(500, 500),
        size: const Size(60, 60),
      );
      await editor.updateObjectDetails(cabinet!.id, name: 'RC6');
      final panel = await editor.addToCabinet(cabinet.id, panelKind);
      await editor.updateObjectDetails(panel!.id, name: 'F');
      await editor.setPortCount(panel.id, 24);
      return panel.id;
    }

    int portOf(int objectId, int number) =>
        editor.portsOf(objectId).firstWhere((p) => p.number == number).id;

    test('νέα πρίζα: δύο θύρες, μία αναίρεση τα παίρνει όλα', () async {
      final outlet = await editor.addObject(outletKind, Offset.zero);
      expect([for (final p in editor.portsOf(outlet!.id)) p.number], [1, 2]);

      await editor.undo();
      expect(editor.objects, isEmpty);
      expect(await ports.listForFloor(1), isEmpty);
    });

    test(
      'κουμπώνει σε τοίχο κοντά της, αλλιώς μένει εκεί που αφέθηκε',
      () async {
        await editor.addWall(Offset.zero, const Offset(1000, 0));

        final near = await editor.addObject(outletKind, const Offset(300, 40));
        expect(near!.center, const Offset(300, 0));

        final far = await editor.addObject(outletKind, const Offset(300, 400));
        expect(far!.center, const Offset(300, 400));
      },
    );

    test('σύρσιμο κοντά σε τοίχο: κουμπώνει όταν αφεθεί', () async {
      await editor.addWall(Offset.zero, const Offset(1000, 0));
      final outlet = await editor.addObject(outletKind, const Offset(300, 400));

      editor.setTool(FloorPlanTool.select);
      editor.selectObject(outlet!.id);
      editor.previewMove(const Offset(0, -350));
      await editor.commitPreview(dropIntoCabinets: true);

      expect(editor.objectById(outlet.id)!.center, const Offset(300, 0));
    });

    test(
      'δένεται με patch panel: όνομα «RC6.F17», και η θύρα 17 πιάνεται',
      () async {
        final panel = await panelF();
        final outlet = await editor.addObject(outletKind, Offset.zero);
        final patch = portOf(panel, 17);

        await editor.saveOutlet(outlet!.id, [
          FloorPlanOutletPortDraft(number: 1, patchPortId: patch),
          const FloorPlanOutletPortDraft(number: 2),
        ]);

        expect(floorPlanLinkName(editor.portLinks.single), 'RC6.F17');
        expect(editor.occupiedPortIds, contains(patch));
        expect(editor.occupiedPortIds, contains(portOf(outlet.id, 1)));
        expect(editor.occupiedPortIds, isNot(contains(portOf(outlet.id, 2))));
      },
    );

    test('όλη η αποθήκευση του πλαισίου είναι μία αναίρεση', () async {
      final panel = await panelF();
      final outlet = await editor.addObject(outletKind, Offset.zero);

      await editor.saveOutlet(outlet!.id, [
        FloorPlanOutletPortDraft(
          number: 1,
          writtenName: 'Κάμερα 7',
          patchPortId: portOf(panel, 17),
          connection: FloorPlanPortConnection.freeText('αναλυτής'),
        ),
      ]);
      expect(editor.portsOf(outlet.id), hasLength(1));

      await editor.undo();

      expect(editor.portsOf(outlet.id), hasLength(2));
      expect(editor.portLinks, isEmpty);
      final first = editor.portsOf(outlet.id).first;
      expect(first.writtenName, isNull);
      expect(first.connection.isEmpty, isTrue);

      await editor.redo();
      expect(editor.portsOf(outlet.id).single.connectedText, 'αναλυτής');
      expect(editor.portLinks, hasLength(1));
    });

    test('σβησμένη πρίζα: η αναίρεση τη φέρνει πίσω δεμένη', () async {
      final panel = await panelF();
      final outlet = await editor.addObject(outletKind, Offset.zero);
      await editor.saveOutlet(outlet!.id, [
        FloorPlanOutletPortDraft(number: 1, patchPortId: portOf(panel, 17)),
        const FloorPlanOutletPortDraft(number: 2),
      ]);

      await editor.deleteObjects({outlet.id});
      expect(editor.portLinks, isEmpty);
      expect(await db.query('building_map_cables'), isEmpty);
      expect(await db.query('building_map_cable_ends'), isEmpty);

      await editor.undo();
      expect(floorPlanLinkName(editor.portLinks.single), 'RC6.F17');

      await editor.redo();
      expect(editor.portLinks, isEmpty);
    });

    test('σβησμένο patch panel: η πρίζα μένει χωρίς σύνδεση, η αναίρεση την '
        'ξαναδένει', () async {
      final panel = await panelF();
      final outlet = await editor.addObject(outletKind, Offset.zero);
      await editor.saveOutlet(outlet!.id, [
        FloorPlanOutletPortDraft(number: 1, patchPortId: portOf(panel, 3)),
        const FloorPlanOutletPortDraft(number: 2),
      ]);

      await editor.deleteObjects({panel});
      expect(editor.portLinks, isEmpty);
      expect(editor.portsOf(outlet.id), hasLength(2));

      await editor.undo();
      expect(editor.portLinks, hasLength(1));
    });

    test('από τη δεύτερη πρίζα η πιασμένη θύρα αρνείται, με μήνυμα', () async {
      final panel = await panelF();
      final first = await editor.addObject(outletKind, Offset.zero);
      final second = await editor.addObject(outletKind, const Offset(9, 9));
      final patch = portOf(panel, 5);
      await editor.saveOutlet(first!.id, [
        FloorPlanOutletPortDraft(number: 1, patchPortId: patch),
        const FloorPlanOutletPortDraft(number: 2),
      ]);

      await editor.saveOutlet(second!.id, [
        FloorPlanOutletPortDraft(number: 1, patchPortId: patch),
        const FloorPlanOutletPortDraft(number: 2),
      ]);

      expect(errors.single, contains('πιάστηκε'));
      expect(editor.portLinks.single.outletPortId, portOf(first.id, 1));
    });

    test('patch panel σε άλλον όροφο: η πρίζα παίρνει κανονικά το όνομά του, '
        'και ο άλλος όροφος βλέπει τη συσκευή', () async {
      final panel = await panelF();
      final patch = portOf(panel, 17);
      final otherFloor = FloorPlanEditorController(
        floorId: 2,
        repository: repo,
        objectsRepository: objects,
        portsRepository: ports,
        onError: errors.add,
      );
      addTearDown(otherFloor.dispose);
      await otherFloor.load();
      final outlet = await otherFloor.addObject(outletKind, Offset.zero);

      final options = await otherFloor.patchPortOptions();
      expect(options.map((o) => o.portId), contains(patch));

      await otherFloor.saveOutlet(outlet!.id, [
        FloorPlanOutletPortDraft(
          number: 1,
          patchPortId: patch,
          connection: FloorPlanPortConnection.freeText('αναλυτής'),
        ),
        const FloorPlanOutletPortDraft(number: 2),
      ]);

      expect(floorPlanLinkName(otherFloor.portLinks.single), 'RC6.F17');
      await editor.load();
      expect(editor.occupiedPortIds, contains(patch));
      expect(editor.portLinks.single.connection.text, 'αναλυτής');
    });

    test('η επικόλληση πρίζας δεν αντιγράφει τη σύνδεση', () async {
      final panel = await panelF();
      final outlet = await editor.addObject(outletKind, Offset.zero);
      await editor.saveOutlet(outlet!.id, [
        FloorPlanOutletPortDraft(number: 1, patchPortId: portOf(panel, 1)),
        const FloorPlanOutletPortDraft(number: 2),
      ]);
      editor.setTool(FloorPlanTool.select);
      editor.selectObject(outlet.id);
      editor.copySelected();

      await editor.paste();

      expect(editor.portLinks, hasLength(1));
      final copy = editor.selectedObjectIds.single;
      expect(editor.portsOf(copy), hasLength(2));
    });
  });
  group('Η εικόνα πατρόν δεν ξανακατεβαίνει όσο δεν άλλαξε', () {
    // Η κάτοψη ζει ως εικόνα μέσα στη βάση, και η βάση σε δικτυακό φάκελο:
    // κάθε περιττό κατέβασμα είναι MB πάνω από τη γραμμή του νοσοκομείου.
    //
    // Αυτό που μετριέται είναι **πόσες φορές ζητήθηκε η εικόνα από τη βάση**.
    // Η αποκωδικοποίηση της εικόνας δεν τρέχει σε αυτό το περιβάλλον ελέγχου
    // (ο codec του flutter_test δεν παράγει εικόνα), αλλά γίνεται **μετά** την
    // απόφαση του κατεβάσματος, οπότε η απόφαση ελέγχεται πλήρως. Το ότι η
    // κάτοψη φαίνεται στην οθόνη είναι δουλειά του Flutter και επαληθεύεται
    // με τα μάτια.
    late _CountingPatternRepository counting;
    late FloorPlanPatternCache cache;

    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8'
      'DwHwAFAAH/q842iQAAAABJRU5ErkJggg==',
    );

    FloorPlanEditorController controllerFor() => FloorPlanEditorController(
      floorId: 1,
      repository: counting,
      onError: errors.add,
      patternCache: cache,
    );

    /// Ό,τι δεν είναι η αδυναμία του codec σε αυτό το περιβάλλον.
    List<String> realErrors() =>
        errors.where((e) => !e.contains('Codec failed')).toList();

    setUp(() {
      counting = _CountingPatternRepository(db);
      cache = FloorPlanPatternCache();
    });

    test('το δεύτερο άνοιγμα του ίδιου ορόφου δεν ρωτά το δίκτυο', () async {
      final first = controllerFor();
      await first.load();
      await first.setPatternImage(png, center: Offset.zero);
      // Η φόρτωση έχει τα bytes στο χέρι — δεν τα ξανακατεβάζει.
      expect(counting.patternReads, 0);
      first.dispose();

      // Νέο άνοιγμα της οθόνης: ο ελεγκτής φτιάχνεται από την αρχή, οπότε μια
      // μνήμη μέσα του δεν θα γλίτωνε τίποτα.
      final second = controllerFor();
      await second.load();

      expect(counting.patternReads, 0, reason: 'απάντησε η μνήμη');
      expect(realErrors(), isEmpty);
      second.dispose();
    });

    test('αλλαγμένη κάτοψη από άλλον σταθμό κατεβαίνει κανονικά', () async {
      final mine = controllerFor();
      await mine.load();
      await mine.setPatternImage(png, center: Offset.zero);
      mine.dispose();

      // Ο συνάδελφος φόρτωσε άλλη κάτοψη: άλλα bytes, άλλο αποτύπωμα. Κανείς
      // δεν «θυμήθηκε» να ακυρώσει τη μνήμη — η ακύρωση είναι το κλειδί της.
      final plain = FloorPlanRepository(db);
      final other = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
        'YPjPAAAAyAEBvbIuqwAAAABJRU5ErkJggg==',
      );
      await plain.setPattern(1, other, await plain.readState(1));

      final next = controllerFor();
      await next.load();

      expect(counting.patternReads, 1, reason: 'το νέο αποτύπωμα κατέβηκε');
      next.dispose();
    });

    test('η σβησμένη κάτοψη δεν ξαναζωντανεύει από τη μνήμη', () async {
      final mine = controllerFor();
      await mine.load();
      await mine.setPatternImage(png, center: Offset.zero);
      await mine.removePattern();
      mine.dispose();

      final next = controllerFor();
      await next.load();

      expect(next.patternImage, isNull);
      expect(counting.patternReads, 0, reason: 'δεν υπάρχει τι να κατέβει');
      next.dispose();
    });
  });
}

class _CountingPatternRepository extends FloorPlanRepository {
  _CountingPatternRepository(super.db);

  int patternReads = 0;

  @override
  Future<Uint8List?> readPatternImage(int floorId) {
    patternReads++;
    return super.readPatternImage(floorId);
  }
}
