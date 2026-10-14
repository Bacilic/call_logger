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
}
