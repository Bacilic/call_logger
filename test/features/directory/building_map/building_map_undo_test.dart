// Η Αναίρεση του χάρτη κτιρίου επαναφέρει ό,τι άλλαξε η ενέργεια που αναιρεί —
// όχι μόνο τη θέση.
//
//   flutter test test/features/directory/building_map/building_map_undo_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/department_repository.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/directory/building_map/controllers/building_map_controller.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:call_logger/features/directory/providers/department_directory_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../test_setup.dart';

/// Ο κατάλογος τμημάτων δεν μας αφορά εδώ — μόνο η βάση.
class _QuietDepartmentDirectory extends DepartmentDirectoryNotifier {
  @override
  Future<void> loadDepartments() async {}
}

/// Ο κατάλογος όπως τον βλέπει ο χάρτης: διαβάζεται από τη βάση **μόνο**
/// όταν το ζητήσουμε — ό,τι αλλάξει μετά μένει αόρατο, όπως στην επεξεργασία.
class _SeenDepartments extends DepartmentDirectoryNotifier {
  @override
  Future<void> loadDepartments() async {
    final rows = await DepartmentRepository(
      await DatabaseHelper.instance.database,
    ).getActiveDepartments();
    state = DepartmentDirectoryState(
      allDepartments: rows.map(DepartmentModel.fromMap).toList(),
    );
  }
}

void main() {
  setUpAll(() async {
    initSqfliteFfiForTests();
    final dir = await Directory.systemTemp.createTemp('building_map_undo_');
    await DatabaseHelper.bindTestDatabaseFile('${dir.path}/undo.db');
  });

  setUp(() async {
    await seedIsolatedTestDatabase();
  });

  tearDownAll(() async {
    await releaseCallLoggerTestDatabase();
  });

  testWidgets(
    'Αναίρεση μετά από «Αφαίρεση από τον χάρτη»: επιστρέφουν επωνυμία, '
    'ετικέτα, χρώμα και «κρυμμένο», όχι μόνο η θέση',
    (tester) async {
      late int deptId;
      late Map<String, dynamic> before;
      await tester.runAsync(() async {
        final db = await DatabaseHelper.instance.database;
        deptId = await db.insert('departments', {
          'name': 'Ακτινολογικό',
          'name_key': SearchTextNormalizer.normalizeForSearch('Ακτινολογικό'),
          'color': '#1976D2',
          'map_floor': '1',
          'map_x': 10.0,
          'map_y': 20.0,
          'map_width': 30.0,
          'map_height': 40.0,
          'map_rotation': 0.0,
          'map_custom_name': 'Ακτινο',
          'map_label_font_scale': 1.5,
          'map_label_width': 120.0,
          'map_label_height': 30.0,
          'map_hidden': 1,
          'is_deleted': 0,
        });
        before = (await DepartmentRepository(db).getDepartmentRowById(deptId))!;
      });

      final container = ProviderContainer(
        overrides: [
          departmentDirectoryProvider.overrideWith(
            _QuietDepartmentDirectory.new,
          ),
        ],
      );
      addTearDown(container.dispose);
      late BuildContext ctx;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (c) {
                  ctx = c;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );

      final controller = container.read(buildingMapControllerProvider);
      final dept = DepartmentModel.fromMap(before);
      // Η ενέργεια ξεκινά σε πραγματικό χρόνο: η βάση δεν προχωρά μέσα στο
      // ψεύτικο ρολόι των τεστ οθόνης.
      late Future<void> removal;
      await tester.runAsync(() async {
        removal = controller.removeDepartmentFromFloorAfterConfirm(
          context: ctx,
          dept: dept,
          sheetStr: '1',
        );
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('Αφαίρεση'));
      await tester.pump();
      await tester.runAsync(() => removal);
      await tester.pumpAndSettle();

      await tester.runAsync(() => controller.undoLastGeometry(ctx));
      await tester.pumpAndSettle();

      late Map<String, dynamic> after;
      await tester.runAsync(() async {
        final db = await DatabaseHelper.instance.database;
        after = (await DepartmentRepository(db).getDepartmentRowById(deptId))!;
      });
      for (final column in const [
        'map_floor',
        'map_x',
        'map_y',
        'map_width',
        'map_height',
        'map_custom_name',
        'map_label_font_scale',
        'map_label_width',
        'map_label_height',
        'map_hidden',
        'color',
      ]) {
        expect(after[column], before[column], reason: column);
      }

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('μαζική αφαίρεση: μία Αναίρεση φέρνει πίσω όλα τα τμήματα', (
    tester,
  ) async {
    late List<DepartmentModel> depts;
    await tester.runAsync(() async {
      final db = await DatabaseHelper.instance.database;
      final repo = DepartmentRepository(db);
      depts = [];
      for (final name in const ['Ακτινολογικό', 'Βιοχημικό']) {
        final id = await db.insert('departments', {
          'name': name,
          'name_key': SearchTextNormalizer.normalizeForSearch(name),
          'color': '#1976D2',
          'map_floor': '1',
          'map_x': 10.0,
          'map_y': 20.0,
          'map_width': 30.0,
          'map_height': 40.0,
          'is_deleted': 0,
        });
        depts.add(
          DepartmentModel.fromMap((await repo.getDepartmentRowById(id))!),
        );
      }
    });

    final container = ProviderContainer(
      overrides: [
        departmentDirectoryProvider.overrideWith(_QuietDepartmentDirectory.new),
      ],
    );
    addTearDown(container.dispose);
    late BuildContext ctx;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) {
                ctx = c;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    final controller = container.read(buildingMapControllerProvider);

    await tester.runAsync(
      () => controller.removeDepartmentsFromFloor(ctx, depts, floorId: 1),
    );
    await tester.runAsync(() => controller.undoLastGeometry(ctx));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      final repo = DepartmentRepository(await DatabaseHelper.instance.database);
      for (final d in depts) {
        final row = (await repo.getDepartmentRowById(d.id!))!;
        expect(row['map_width'], 30.0, reason: d.name);
        expect(row['map_floor'], '1', reason: d.name);
      }
    });

    await tester.pumpWidget(const SizedBox.shrink());
  });

  // Ο POPINIO βγάζει την Καρδιολογική από τον 2ο ενώ ο picinio έχει τον χάρτη
  // σε επεξεργασία. Ο picinio την αφαιρεί κι αυτός → «Κάποιος πρόλαβε» →
  // «Ακύρωσε την αλλαγή μου»: δεν γράφεται τίποτα πάνω στη δουλειά του άλλου.
  testWidgets('αλλαγή άλλου σταθμού που ο χάρτης δεν είδε: ρωτά πριν γράψει', (
    tester,
  ) async {
    late int cardiologyId;
    await tester.runAsync(() async {
      final db = await DatabaseHelper.instance.database;
      cardiologyId = await db.insert('departments', {
        'name': 'Καρδιολογική',
        'name_key': SearchTextNormalizer.normalizeForSearch('Καρδιολογική'),
        'color': '#1976D2',
        'map_floor': '2',
        'map_x': 10.0,
        'map_y': 20.0,
        'map_width': 30.0,
        'map_height': 40.0,
        'map_custom_name': 'Καρδιο',
        'is_deleted': 0,
      });
    });

    final container = ProviderContainer(
      overrides: [
        departmentDirectoryProvider.overrideWith(_SeenDepartments.new),
      ],
    );
    addTearDown(container.dispose);
    await tester.runAsync(
      () => container
          .read(departmentDirectoryProvider.notifier)
          .loadDepartments(),
    );
    late BuildContext ctx;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) {
                ctx = c;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    final seen = container
        .read(departmentDirectoryProvider)
        .allDepartments
        .firstWhere((d) => d.id == cardiologyId);

    // Ο POPINIO: αλλάζει την επωνυμία χάρτη της Καρδιολογικής.
    await tester.runAsync(() async {
      final db = await DatabaseHelper.instance.database;
      await db.update(
        'departments',
        {'map_custom_name': 'Καρδιολογικό Τμήμα'},
        where: 'id = ?',
        whereArgs: [cardiologyId],
      );
    });

    final controller = container.read(buildingMapControllerProvider);
    late Future<void> removal;
    await tester.runAsync(() async {
      removal = controller.removeDepartmentFromFloorAfterConfirm(
        context: ctx,
        dept: seen,
        sheetStr: '2',
      );
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('Αφαίρεση'));
    await tester.pump();
    await tester.runAsync(() async {
      for (var i = 0; i < 40; i++) {
        if (find.text('Κάποιος πρόλαβε').evaluate().isNotEmpty) return;
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await tester.pump();
      }
    });

    expect(find.text('Κάποιος πρόλαβε'), findsOneWidget);
    await tester.tap(find.text('Ακύρωσε την αλλαγή μου'));
    await tester.pump();
    await tester.runAsync(() => removal);
    await tester.pumpAndSettle();

    late Map<String, dynamic> after;
    await tester.runAsync(() async {
      after = (await DepartmentRepository(
        await DatabaseHelper.instance.database,
      ).getDepartmentRowById(cardiologyId))!;
    });
    expect(after['map_custom_name'], 'Καρδιολογικό Τμήμα');
    expect(after['map_width'], 30.0, reason: 'Τίποτα δεν γράφτηκε');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  // Η Αναίρεση αναιρεί την ΤΕΛΕΥΤΑΙΑ ενέργεια: μετά την αφαίρεση του
  // Ακτινολογικού, η αλλαγή επωνυμίας του Βιοχημικού είναι η τελευταία —
  // αυτή γυρίζει πίσω, και το Ακτινολογικό μένει αφαιρεμένο.
  testWidgets('η Αναίρεση αναιρεί την τελευταία ενέργεια, όχι μια παλιότερη', (
    tester,
  ) async {
    late int radiologyId;
    late int biochemId;
    late Map<String, dynamic> radiology;
    await tester.runAsync(() async {
      final db = await DatabaseHelper.instance.database;
      Future<int> insert(String name, String customName) =>
          db.insert('departments', {
            'name': name,
            'name_key': SearchTextNormalizer.normalizeForSearch(name),
            'color': '#1976D2',
            'map_floor': '1',
            'map_x': 10.0,
            'map_y': 20.0,
            'map_width': 30.0,
            'map_height': 40.0,
            'map_rotation': 0.0,
            'map_custom_name': customName,
            'is_deleted': 0,
          });
      radiologyId = await insert('Ακτινολογικό', 'Ακτινο');
      biochemId = await insert('Βιοχημικό', 'Βιοχημ.');
      radiology = (await DepartmentRepository(
        db,
      ).getDepartmentRowById(radiologyId))!;
    });

    final container = ProviderContainer(
      overrides: [
        departmentDirectoryProvider.overrideWith(_QuietDepartmentDirectory.new),
      ],
    );
    addTearDown(container.dispose);
    late BuildContext ctx;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) {
                ctx = c;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    final controller = container.read(buildingMapControllerProvider);

    late Future<void> removal;
    await tester.runAsync(() async {
      removal = controller.removeDepartmentFromFloorAfterConfirm(
        context: ctx,
        dept: DepartmentModel.fromMap(radiology),
        sheetStr: '1',
      );
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('Αφαίρεση'));
    await tester.pump();
    await tester.runAsync(() => removal);
    await tester.pumpAndSettle();

    await tester.runAsync(
      () => controller.saveDepartmentMapDisplayName(
        context: ctx,
        departmentId: biochemId,
        canonicalDepartmentName: 'Βιοχημικό',
        editedText: 'Εργαστήριο',
      ),
    );
    await tester.pumpAndSettle();

    await tester.runAsync(() => controller.undoLastGeometry(ctx));
    await tester.pumpAndSettle();

    late Map<String, dynamic> radiologyAfter;
    late Map<String, dynamic> biochemAfter;
    await tester.runAsync(() async {
      final repo = DepartmentRepository(await DatabaseHelper.instance.database);
      radiologyAfter = (await repo.getDepartmentRowById(radiologyId))!;
      biochemAfter = (await repo.getDepartmentRowById(biochemId))!;
    });
    expect(
      biochemAfter['map_custom_name'],
      'Βιοχημ.',
      reason: 'Η τελευταία ενέργεια (επωνυμία) είναι αυτή που αναιρείται',
    );
    expect(
      radiologyAfter['map_width'],
      isNot(30.0),
      reason: 'Η παλιότερη αφαίρεση του Ακτινολογικού δεν αναιρείται',
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
