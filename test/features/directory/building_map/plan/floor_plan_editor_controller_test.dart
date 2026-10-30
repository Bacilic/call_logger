// Η αναίρεση στη σχεδίαση γράφει κι αυτή αμέσως στη βάση: ό,τι αναιρείται
// φεύγει από τη βάση, ό,τι επαναλαμβάνεται ξαναγράφεται. Το ίδιο και για τα
// αντικείμενα του χάρτη, μόνα τους ή μαζί με το σχέδιο.
//
//   flutter test test/features/directory/building_map/plan/floor_plan_editor_controller_test.dart

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
import 'package:flutter/painting.dart' show Size;
import 'package:call_logger/features/directory/building_map/plan/floor_plan_editor_controller.dart';
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

  test('νέα κίνηση μετά από αναίρεση σβήνει την επανάληψη', () async {
    await controller.addWall(Offset.zero, const Offset(400, 0));
    await controller.undo();
    await controller.addWall(Offset.zero, const Offset(0, 300));
    expect(controller.canRedo, isFalse);
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

      expect(await editor.setCabinetUnits(rack.id, 30), isFalse);
      expect((await stored(rack.id)).rackUnits, 120);
      expect(errors.single, contains('U40'));
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
      expect(editor.cabledPortsBeyond(sw.id, 2).map((p) => p.id), [last.id]);
      expect(editor.cabledPortsBeyond(sw.id, 4), isEmpty);

      await editor.setPortCount(sw.id, 2);
      expect(await db.query('building_map_cable_ends'), isEmpty);
    });
  });
}
