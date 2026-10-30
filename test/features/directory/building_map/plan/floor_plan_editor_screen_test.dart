// Η οθόνη σχεδίασης με το ποντίκι: κλικ σε γωνίες → τοίχοι στη βάση,
// σύρσιμο πάνω σε τοίχο → άνοιγμα στη βάση, Ctrl+Z → σβήνει από τη βάση,
// διπλό κλικ μέσα σε κλειστούς τοίχους → χώρος τμήματος, με τον κανόνα ορόφου,
// εργαλείο «Αντικείμενο» → αντικείμενο στη βάση με τα στοιχεία του,
// «Τοποθέτηση» → θέση υπαλλήλου ή τηλεφώνου στη βάση.
//
//   flutter test test/features/directory/building_map/plan/floor_plan_editor_screen_test.dart

import 'package:call_logger/core/database/database_foreign_keys.dart';
import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/database/floor_plan_objects_repository.dart';
import 'package:call_logger/core/database/floor_plan_placements_repository.dart';
import 'package:call_logger/core/database/floor_plan_repository.dart';
import 'package:call_logger/core/models/building_map_floor.dart';
import 'package:call_logger/core/models/floor_plan_element.dart';
import 'package:call_logger/core/models/floor_plan_object_kind.dart';
import 'package:call_logger/core/models/floor_plan_placement.dart';
import 'package:call_logger/features/directory/building_map/plan/screens/floor_plan_editor_screen.dart';
import 'package:call_logger/features/directory/building_map/plan/services/floor_plan_catalog.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:call_logger/features/directory/building_map/plan/widgets/floor_plan_painter.dart';
import 'package:call_logger/features/directory/building_map/plan/widgets/floor_plan_text_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../test_setup.dart';

/// Κατάλογος με σταθερά τμήματα· θυμάται κάθε μεταφορά ορόφου.
class _FakeCatalog implements FloorPlanCatalog {
  _FakeCatalog(this.list);

  final List<DepartmentModel> list;
  final List<(int, int)> moves = [];
  final List<int> retired = [];

  @override
  Future<List<DepartmentModel>> departments() async => list;

  @override
  Future<List<BuildingMapFloor>> floors() async => [
    BuildingMapFloor(
      id: 1,
      sortOrder: 0,
      label: '2ος',
      imagePath: '',
      rotationDegrees: 0,
    ),
    BuildingMapFloor(
      id: 3,
      sortOrder: 1,
      label: '4ος',
      imagePath: '',
      rotationDegrees: 0,
    ),
  ];

  @override
  Future<void> moveDepartmentToFloor(int departmentId, int floorId) async {
    moves.add((departmentId, floorId));
  }

  @override
  Future<void> retireOldMap(int floorId) async => retired.add(floorId);
}

void main() {
  late Database db;
  late FloorPlanRepository repo;
  late _FakeCatalog catalog;

  setUp(() async {
    initSqfliteFfiForTests();
    db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
    await migrateDatabaseToV69(db);
    repo = FloorPlanRepository(db);
    catalog = _FakeCatalog([
      DepartmentModel(id: 10, name: 'Ακτινολογικό', floorId: 1),
      DepartmentModel(id: 11, name: 'Ορθοπαιδική', floorId: 3),
    ]);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpEditor(
    WidgetTester tester, {
    FloorPlanObjectsRepository? objects,
    FloorPlanPlacementsRepository? placements,
  }) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: FloorPlanEditorScreen(
            floor: BuildingMapFloor(
              id: 1,
              sortOrder: 0,
              label: '2ος',
              imagePath: '',
              rotationDegrees: 0,
            ),
            repository: repo,
            objectsRepository: objects,
            placementsRepository: placements,
            catalog: catalog,
            readFloorPlanImage: () async => null,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
  }

  Offset canvasPoint(WidgetTester tester, double fx, double fy) {
    final rect = tester.getRect(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is FloorPlanPainter,
      ),
    );
    return Offset(rect.left + rect.width * fx, rect.top + rect.height * fy);
  }

  /// Ένα κλικ, και αναμονή ώστε η εγγραφή να φτάσει στη βάση.
  Future<void> click(WidgetTester tester, Offset at) async {
    await tester.runAsync(() async {
      await tester.tapAt(at, kind: PointerDeviceKind.mouse);
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await tester.pump();
  }

  testWidgets('κλικ σε τρεις γωνίες → δύο τοίχοι στη βάση, Esc τελειώνει', (
    tester,
  ) async {
    await pumpEditor(tester);

    await click(tester, canvasPoint(tester, 0.3, 0.3));
    await click(tester, canvasPoint(tester, 0.7, 0.3));
    await click(tester, canvasPoint(tester, 0.7, 0.7));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    final walls = await tester.runAsync(() => repo.listElements(1));
    expect(walls, hasLength(2));
    // Ο δεύτερος ξεκινά ακριβώς εκεί που τελείωσε ο πρώτος: γωνία χωρίς κενό.
    expect(walls![1].points.first, walls[0].points.last);

    // Μετά το Esc, ένα κλικ ξεκινά νέο τοίχο — δεν γράφει τίποτα.
    await click(tester, canvasPoint(tester, 0.2, 0.8));
    expect(await tester.runAsync(() => repo.listElements(1)), hasLength(2));
  });

  testWidgets('Ctrl+Z σβήνει τον τελευταίο τοίχο από τη βάση', (tester) async {
    await pumpEditor(tester);
    await click(tester, canvasPoint(tester, 0.3, 0.3));
    await click(tester, canvasPoint(tester, 0.7, 0.3));
    expect(await tester.runAsync(() => repo.listElements(1)), hasLength(1));

    await tester.runAsync(() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await tester.pump();

    expect(await tester.runAsync(() => repo.listElements(1)), isEmpty);
  });

  testWidgets('σύρσιμο πάνω σε τοίχο με το εργαλείο «Άνοιγμα» → πόρτα', (
    tester,
  ) async {
    await pumpEditor(tester);
    await click(tester, canvasPoint(tester, 0.2, 0.5));
    await click(tester, canvasPoint(tester, 0.8, 0.5));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);

    await tester.tap(find.byTooltip('Άνοιγμα (πόρτα)'));
    await tester.pump();

    await tester.runAsync(() async {
      final gesture = await tester.startGesture(
        canvasPoint(tester, 0.4, 0.5),
        kind: PointerDeviceKind.mouse,
      );
      for (var i = 1; i <= 10; i++) {
        await gesture.moveTo(canvasPoint(tester, 0.4 + 0.02 * i, 0.5));
      }
      await gesture.up();
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await tester.pump();

    final elements = (await tester.runAsync(() => repo.listElements(1)))!;
    final opening = elements.singleWhere(
      (e) => e.kind == FloorPlanElementKind.opening,
    );
    final wall = elements.singleWhere(
      (e) => e.kind == FloorPlanElementKind.wall,
    );
    expect(opening.parentId, wall.id);
    expect(opening.points[1].dx, greaterThan(opening.points[0].dx));
  });

  /// Κλειστό δωμάτιο 4×3 μ. γραμμένο στη βάση πριν ανοίξει η οθόνη.
  Future<void> seedBox() async {
    const corners = [
      Offset(0, 0),
      Offset(400, 0),
      Offset(400, 300),
      Offset(0, 300),
    ];
    for (var i = 0; i < 4; i++) {
      await repo.insertElement(
        FloorPlanElement(
          id: 0,
          floorId: 1,
          kind: FloorPlanElementKind.wall,
          points: [corners[i], corners[(i + 1) % 4]],
        ),
      );
    }
  }

  /// Πού φαίνεται στην οθόνη ένα σημείο του σχεδίου.
  Offset screenOf(WidgetTester tester, Offset world) {
    final finder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is FloorPlanPainter,
    );
    final painter =
        tester.widget<CustomPaint>(finder).painter! as FloorPlanPainter;
    return tester.getTopLeft(finder) + painter.view.toScreen(world);
  }

  Future<void> doubleClick(WidgetTester tester, Offset at) async {
    await tester.runAsync(() async {
      await tester.tapAt(at, kind: PointerDeviceKind.mouse);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await tester.tapAt(at, kind: PointerDeviceKind.mouse);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
  }

  Future<void> settleAsync(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('διπλό κλικ μέσα σε κλειστούς τοίχους → χώρος του τμήματος', (
    tester,
  ) async {
    await tester.runAsync(seedBox);
    await pumpEditor(tester);
    await tester.tap(find.byTooltip('Χώρος'));
    await tester.pump();

    await doubleClick(tester, screenOf(tester, const Offset(200, 150)));
    expect(find.text('Νέος χώρος'), findsOneWidget);
    await tester.tap(find.text('Ακτινολογικό'));
    await settleAsync(tester);

    final rooms = (await tester.runAsync(() => repo.listElements(1)))!
        .where((e) => e.kind == FloorPlanElementKind.room)
        .toList();
    expect(rooms, hasLength(1));
    expect(rooms.single.departmentId, 10);
    expect(rooms.single.points, hasLength(4));
    expect(catalog.moves, isEmpty);
  });

  testWidgets('τμήμα άλλου ορόφου: «Μεταφορά» γράφει τον όροφο, «Παραμονή» '
      'δεν φτιάχνει χώρο', (tester) async {
    await tester.runAsync(seedBox);
    await pumpEditor(tester);
    await tester.tap(find.byTooltip('Χώρος'));
    await tester.pump();
    final inside = screenOf(tester, const Offset(200, 150));

    await doubleClick(tester, inside);
    await tester.tap(find.text('Ορθοπαιδική'));
    await settleAsync(tester);
    await tester.tap(find.textContaining('Παραμονή στον όροφο'));
    await settleAsync(tester);
    expect(await tester.runAsync(() => repo.listElements(1)), hasLength(4));
    expect(catalog.moves, isEmpty);

    // Αναμονή ώστε τα δύο επόμενα κλικ να μη μετρηθούν ως συνέχεια.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 600)),
    );
    await doubleClick(tester, inside);
    await tester.tap(find.text('Ορθοπαιδική'));
    await settleAsync(tester);
    await tester.tap(find.textContaining('Μεταφορά του τμήματος'));
    await settleAsync(tester);

    expect(catalog.moves, [(11, 1)]);
    final room = (await tester.runAsync(() => repo.listElements(1)))!
        .singleWhere((e) => e.kind == FloorPlanElementKind.room);
    expect(room.departmentId, 11);
  });

  Future<void> seedElement(
    FloorPlanElementKind kind,
    List<Offset> points, {
    String? name,
    int? departmentId,
  }) => repo.insertElement(
    FloorPlanElement(
      id: 0,
      floorId: 1,
      kind: kind,
      points: points,
      name: name,
      departmentId: departmentId,
    ),
  );

  testWidgets('εργαλείο «Κείμενο» πάνω σε υπάρχον κείμενο → το ανοίγει για '
      'αλλαγή, όχι νέο', (tester) async {
    await tester.runAsync(() async {
      await seedBox();
      await seedElement(FloorPlanElementKind.text, const [
        Offset(200, 100),
      ], name: 'Διάδρομος');
    });
    await pumpEditor(tester);
    await tester.tap(find.byTooltip('Κείμενο'));
    await tester.pump();

    await click(tester, screenOf(tester, const Offset(200, 100)));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Διάδρομος'), findsOneWidget);
  });

  Future<List<FloorPlanElement>> storedTexts(WidgetTester tester) async =>
      (await tester.runAsync(() => repo.listElements(1)))!
          .where((e) => e.kind == FloorPlanElementKind.text)
          .toList();

  /// Εργαλείο «Κείμενο», κλικ σε κενό σημείο και πληκτρολόγηση.
  Future<void> typeNewText(WidgetTester tester, String text) async {
    await tester.runAsync(seedBox);
    await pumpEditor(tester);
    await tester.tap(find.byTooltip('Κείμενο'));
    await tester.pump();
    await click(tester, screenOf(tester, const Offset(200, 100)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
  }

  testWidgets('νέο κείμενο: γράφεται πάνω στον χάρτη, Ctrl+Enter το '
      'αποθηκεύει με το μέγεθος του A+', (tester) async {
    await typeNewText(tester, 'Διάδρομος\nΥπογείου');
    await tester.tap(find.byTooltip('Μεγαλύτερα γράμματα'));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settleAsync(tester);

    final text = (await storedTexts(tester)).single;
    expect(text.name, 'Διάδρομος\nΥπογείου');
    expect(text.fontSize, greaterThan(kFloorPlanDefaultTextSizeCm));
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('νέο κείμενο: Esc το ακυρώνει χωρίς τίποτα στη βάση', (
    tester,
  ) async {
    await typeNewText(tester, 'Πρόχειρο');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settleAsync(tester);

    expect(await storedTexts(tester), isEmpty);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('νέο κείμενο: κλικ έξω από το πλαίσιο το αποθηκεύει', (
    tester,
  ) async {
    await typeNewText(tester, 'Αποθήκη');
    await click(tester, screenOf(tester, const Offset(350, 250)));
    await settleAsync(tester);

    expect((await storedTexts(tester)).single.name, 'Αποθήκη');
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('εργαλείο «Κείμενο» πάνω στο όνομα χώρου → αλλαγή χώρου', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seedBox();
      await seedElement(FloorPlanElementKind.room, const [
        Offset(0, 0),
        Offset(400, 0),
        Offset(400, 300),
        Offset(0, 300),
      ], departmentId: 10);
    });
    await pumpEditor(tester);
    await tester.tap(find.byTooltip('Κείμενο'));
    await tester.pump();

    await click(tester, screenOf(tester, const Offset(200, 150)));
    await tester.pumpAndSettle();

    expect(find.text('Αλλαγή χώρου'), findsOneWidget);
    expect(find.byType(FloorPlanTextEditor), findsNothing);
  });

  Future<void> drag(WidgetTester tester, Offset from, Offset to) async {
    await tester.runAsync(() async {
      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      for (var i = 1; i <= 10; i++) {
        await gesture.moveTo(Offset.lerp(from, to, i / 10)!);
      }
      await gesture.up();
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await tester.pump();
  }

  testWidgets('«Επιλογή»: σύρσιμο του ονόματος μετακινεί μόνο το όνομα, και '
      'το A+ της μπάρας το μεγαλώνει', (tester) async {
    await tester.runAsync(() async {
      await seedBox();
      await seedElement(FloorPlanElementKind.room, const [
        Offset(0, 0),
        Offset(400, 0),
        Offset(400, 300),
        Offset(0, 300),
      ], name: 'Αποθήκη');
    });
    await pumpEditor(tester);
    await tester.tap(find.byTooltip('Επιλογή'));
    await tester.pump();

    await drag(
      tester,
      screenOf(tester, const Offset(200, 150)),
      screenOf(tester, const Offset(300, 230)),
    );
    var room = (await tester.runAsync(() => repo.listElements(1)))!
        .singleWhere((e) => e.kind == FloorPlanElementKind.room);
    expect((room.labelOffset! - const Offset(100, 80)).distance, lessThan(2));
    expect(room.points.first, Offset.zero);

    // Δύο γρήγορα πατήματα: το δεύτερο ξεκινά από το πρώτο, δεν χάνεται.
    await tester.tap(find.byTooltip('Μεγαλύτερο όνομα χώρου'));
    await tester.pump();
    await tester.tap(find.byTooltip('Μεγαλύτερο όνομα χώρου'));
    await settleAsync(tester);
    room = (await tester.runAsync(() => repo.listElements(1)))!
        .singleWhere((e) => e.kind == FloorPlanElementKind.room);
    expect(
      room.fontSize,
      closeTo(
        stepFloorPlanTextSize(
          stepFloorPlanTextSize(
            kFloorPlanDefaultRoomLabelSizeCm,
            increase: true,
          ),
          increase: true,
        ),
        1e-9,
      ),
    );
  });

  testWidgets('«Μέτρηση απόστασης»: κλικ και Enter δείχνουν το σύνολο, '
      'χωρίς τίποτα στη βάση', (tester) async {
    await tester.runAsync(seedBox);
    await pumpEditor(tester);
    await tester.tap(find.byTooltip('Μέτρηση απόστασης'));
    await tester.pump();

    await click(tester, screenOf(tester, const Offset(0, 0)));
    await click(tester, screenOf(tester, const Offset(400, 0)));
    await click(tester, screenOf(tester, const Offset(400, 300)));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(find.textContaining('Σύνολο 7,00 μ.'), findsOneWidget);
    expect(await tester.runAsync(() => repo.listElements(1)), hasLength(4));
  });

  testWidgets('ορθογώνιο επιλογής γύρω από το δωμάτιο → Delete τα σβήνει', (
    tester,
  ) async {
    await tester.runAsync(seedBox);
    await pumpEditor(tester);
    await tester.tap(find.byTooltip('Επιλογή'));
    await tester.pump();

    await drag(
      tester,
      screenOf(tester, const Offset(-10, -10)),
      screenOf(tester, const Offset(410, 310)),
    );
    await tester.runAsync(() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await tester.pump();

    expect(await tester.runAsync(() => repo.listElements(1)), isEmpty);
  });

  testWidgets('σύρσιμο ενός τοίχου τον μετακινεί και γράφεται στη βάση', (
    tester,
  ) async {
    await tester.runAsync(seedBox);
    await pumpEditor(tester);
    await tester.tap(find.byTooltip('Επιλογή'));
    await tester.pump();

    // Ο πάνω τοίχος, από τη μέση του, 1 μ. προς τα πάνω.
    await drag(
      tester,
      screenOf(tester, const Offset(200, 0)),
      screenOf(tester, const Offset(200, -100)),
    );

    final top = (await tester.runAsync(() => repo.listElements(1)))!.first;
    expect(top.points.first.dy, closeTo(-100, 2));
    expect(top.points.last.dy, closeTo(-100, 2));
  });

  testWidgets('«Ενεργοποίηση νέου χάρτη» δείχνει ποιο τμήμα λείπει, και με '
      'το «ναι» ο όροφος γίνεται ενεργός και ο παλιός χάρτης σβήνει', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.tap(find.text('Ενεργοποίηση νέου χάρτη'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    // Το «Ακτινολογικό» ανήκει στον όροφο αλλά δεν έχει χώρο.
    expect(find.text('• Ακτινολογικό'), findsOneWidget);
    expect(find.text('• Ορθοπαιδική'), findsNothing);

    await tester.tap(find.text('Ενεργοποίηση'));
    // Η ενεργοποίηση γράφει στη βάση και ξαναδιαβάζει τον όροφο σε βήματα·
    // όσο διαβάζει, ο δείκτης φόρτωσης γυρίζει και δεν «ησυχάζει» ποτέ.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
    }
    await tester.pump(const Duration(milliseconds: 50));

    expect(await tester.runAsync(() => repo.activeFloorIds()), {1});
    expect(catalog.retired, [1]);
    expect(find.text('Ενεργός: τον βλέπουν όλοι'), findsOneWidget);
  });

  testWidgets('το κουμπί «Πατρόν» ανοίγει το πάνελ, και το ξαναπάτημα το '
      'κλείνει', (tester) async {
    await pumpEditor(tester);
    expect(find.text('Από αρχείο εικόνας…'), findsNothing);

    await tester.tap(find.byIcon(Icons.wallpaper_outlined));
    await tester.pump();
    expect(find.text('Από αρχείο εικόνας…'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.wallpaper_outlined));
    await tester.pump();
    expect(find.text('Από αρχείο εικόνας…'), findsNothing);
  });

  testWidgets('«Άκυρο» στην ενεργοποίηση: τίποτα δεν αλλάζει', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Ενεργοποίηση νέου χάρτη'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Άκυρο'));
    await tester.pumpAndSettle();

    expect(await tester.runAsync(() => repo.activeFloorIds()), isEmpty);
    expect(catalog.retired, isEmpty);
  });

  group('Αντικείμενα', () {
    late FloorPlanObjectsRepository objects;

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
    });

    Future<void> chooseKind(WidgetTester tester, String name) async {
      await tester.tap(find.byTooltip('Αντικείμενο'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name).last);
      await tester.pumpAndSettle();
    }

    testWidgets('εκτυπωτής: κλικ → στη βάση, και το πλαίσιο γράφει όνομα και '
        'IP', (tester) async {
      await pumpEditor(tester, objects: objects);
      await chooseKind(tester, 'Εκτυπωτής');

      await click(tester, canvasPoint(tester, 0.5, 0.5));
      expect(await tester.runAsync(() => objects.listObjects(1)), hasLength(1));

      await tester.enterText(
        find.widgetWithText(TextField, 'Όνομα'),
        'ΕΚΤ-ΥΛ-01',
      );
      await tester.enterText(find.widgetWithText(TextField, 'IP'), '10.1.2.33');
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Αποθήκευση (Enter)'));
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      await tester.pump();

      final printer = (await tester.runAsync(() => objects.listObjects(1)))!
          .single;
      expect(printer.name, 'ΕΚΤ-ΥΛ-01');
      expect(printer.ip, '10.1.2.33');
    });

    testWidgets('γραφείο: κλικ σε δύο γωνίες → έπιπλο με το μέγεθός του· το '
        'πλαίσιο δεν ρωτά IP', (tester) async {
      await pumpEditor(tester, objects: objects);
      await chooseKind(tester, 'Γραφείο');

      final a = screenOf(tester, Offset.zero);
      await click(tester, a);
      await click(tester, screenOf(tester, const Offset(200, 100)));

      final desk = (await tester.runAsync(() => objects.listObjects(1)))!
          .single;
      expect(desk.size!.width, closeTo(200, 10));
      expect(desk.size!.height, closeTo(100, 10));
      expect(find.widgetWithText(TextField, 'IP'), findsNothing);
      expect(find.widgetWithText(TextField, 'Σημειώσεις'), findsOne);
    });

    testWidgets('κλειδωμένο σχέδιο: το αντικείμενο σέρνεται και γράφεται '
        'στη βάση', (tester) async {
      await tester.runAsync(() async {
        final kinds = await objects.kinds();
        final printer = kinds.values.firstWhere((k) => k.name == 'Εκτυπωτής');
        await db.insert('building_map_objects', {
          'floor_id': 1,
          'kind_id': printer.id,
          'x': 0,
          'y': 0,
        });
        await seedBox();
      });
      await pumpEditor(tester, objects: objects);
      await tester.tap(find.byTooltip('Επιλογή'));
      await tester.tap(
        find.byTooltip('Κλείδωμα σχεδίου (τίποτα δεν πιάνεται με το ποντίκι)'),
      );
      await tester.pump();

      await drag(
        tester,
        screenOf(tester, Offset.zero),
        screenOf(tester, const Offset(100, 50)),
      );

      final moved = (await tester.runAsync(() => objects.listObjects(1)))!
          .single;
      expect(moved.center.dx, closeTo(100, 3));
      expect(moved.center.dy, closeTo(50, 3));
    });
  });

  group('Τοποθέτηση', () {
    late FloorPlanPlacementsRepository placements;

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
        'id': 1,
        'last_name': 'Παπαδόπουλος',
        'first_name': 'Γιώργος',
        'department_id': 10,
      });
      await db.insert('phones', {'id': 2, 'number': '2345'});
      await db.insert('department_phones', {
        'department_id': 10,
        'phone_id': 2,
      });
      placements = FloorPlanPlacementsRepository(db);
    });

    Future<void> openPlacement(WidgetTester tester) async {
      await pumpEditor(tester, placements: placements);
      await tester.tap(
        find.byTooltip('Τοποθέτηση υπαλλήλων, τηλεφώνων, εξοπλισμού'),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('σύρσιμο υπαλλήλου από το πάνελ στον χάρτη → θέση στη βάση', (
      tester,
    ) async {
      await openPlacement(tester);

      await drag(
        tester,
        tester.getCenter(find.text('Παπαδόπουλος Γιώργος')),
        screenOf(tester, const Offset(100, 50)),
      );

      final placed = (await tester.runAsync(
        () => placements.listPlacements(1),
      ))!.single;
      expect(placed.type, FloorPlanPlacementType.user);
      expect(placed.entityId, 1);
      expect(placed.center.dx, closeTo(100, 5));
      expect(placed.center.dy, closeTo(50, 5));
    });

    testWidgets('κλικ στη λίστα και κλικ στον χάρτη → θέση στη βάση', (
      tester,
    ) async {
      await openPlacement(tester);
      await tester.tap(find.text('Τηλέφωνα'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('2345'));
      await tester.pump();
      await click(tester, screenOf(tester, const Offset(200, 100)));

      final placed = (await tester.runAsync(
        () => placements.listPlacements(1),
      ))!.single;
      expect(placed.type, FloorPlanPlacementType.phone);
    });

    testWidgets('τηλέφωνο με θέση σε άλλον όροφο: ρωτά «Μεταφορά», και '
        'μεταφέρεται', (tester) async {
      await tester.runAsync(
        () => placements.insertPlacement(
          const FloorPlanPlacement(
            id: 0,
            type: FloorPlanPlacementType.phone,
            entityId: 2,
            floorId: 3,
            center: Offset.zero,
          ),
        ),
      );
      await openPlacement(tester);
      await tester.tap(find.text('Τηλέφωνα'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2345'));
      await tester.pump();

      await click(tester, screenOf(tester, const Offset(200, 100)));
      await tester.pumpAndSettle();
      expect(find.textContaining('βρίσκεται στον όροφο «4ος»'), findsOne);
      await tester.runAsync(() async {
        await tester.tap(find.text('Μεταφορά'));
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      await tester.pump();

      expect(
        await tester.runAsync(() => placements.listPlacements(3)),
        isEmpty,
      );
      expect(
        await tester.runAsync(() => placements.listPlacements(1)),
        hasLength(1),
      );
    });

    testWidgets('υπάλληλος σε χώρο άλλου τμήματος: τοποθετείται, με '
        'προειδοποίηση', (tester) async {
      await tester.runAsync(
        () => seedElement(FloorPlanElementKind.room, const [
          Offset(0, 0),
          Offset(400, 0),
          Offset(400, 300),
          Offset(0, 300),
        ], departmentId: 11),
      );
      await openPlacement(tester);
      await tester.tap(find.text('Παπαδόπουλος Γιώργος'));
      await tester.pump();

      await click(tester, screenOf(tester, const Offset(200, 150)));
      await tester.pump();

      expect(
        find.textContaining(
          'ανήκει στο «Ακτινολογικό» · ο χώρος είναι του '
          '«Ορθοπαιδική»',
        ),
        findsOne,
      );
      expect(
        await tester.runAsync(() => placements.listPlacements(1)),
        hasLength(1),
      );
    });
  });
}
