import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/features/lamp/services/lamp_migration_service.dart';
import 'package:call_logger/features/lamp/services/lamp_transfer_preview.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

void main() {
  group('Lamp department transfer — floor level as text', () {
    late LampMigrationService service;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('lamp_dept_floor_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/lamp_dept_floor.db');
      await DatabaseHelper.instance.database;
      service = LampMigrationService();
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      final db = await DatabaseHelper.instance.database;
      await db.delete('departments');
      await db.delete('building_map_floors');
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Future<int> insertFloorSheet({
      required String label,
      int? id,
    }) async {
      final db = await DatabaseHelper.instance.database;
      return db.insert('building_map_floors', {
        'id': ?id,
        'sort_order': 0,
        'label': label,
        'image_path': 'maps_images/test.png',
        'rotation_degrees': 0,
      });
    }

    Map<String, String> departmentForm({
      String name = 'Φαρμακείο',
      String building = '',
      String level = '',
      String notes = '',
    }) {
      return {
        'name': name,
        'building': building,
        'level': level,
        'notes': notes,
      };
    }

    test(
      'Lamp level «4» + φύλλο «4ος όροφος» → floor_id = id φύλλου, όχι 4',
      () async {
        const sheetId = 7;
        await insertFloorSheet(id: sheetId, label: '4ος όροφος');

        final result = await service.save(
          target: LampTransferTarget.department,
          formValues: departmentForm(level: '4'),
          selectedCandidateId: null,
        );

        final db = await DatabaseHelper.instance.database;
        final row = await db.query(
          'departments',
          where: 'id = ?',
          whereArgs: [result.id],
        );
        expect(row.first['floor_id'], sheetId);
        expect(row.first['floor_id'], isNot(4));
        expect(row.first['map_floor'], sheetId.toString());
      },
    );

    test(
      'Lamp level «9» χωρίς φύλλο → floor_id null + προειδοποίηση preview',
      () async {
        final result = await service.save(
          target: LampTransferTarget.department,
          formValues: departmentForm(level: '9'),
          selectedCandidateId: null,
        );

        final db = await DatabaseHelper.instance.database;
        final row = await db.query(
          'departments',
          where: 'id = ?',
          whereArgs: [result.id],
        );
        expect(row.first['floor_id'], isNull);
        expect(row.first['map_floor'], isNull);

        final draft = await service.buildDraft(
          target: LampTransferTarget.department,
          sourceRow: {
            'office_name': 'Φαρμακείο',
            'level': '9',
          },
        );
        final preview = buildLampTransferPreview(
          draft: draft,
          currentFormValues: draft.formValues,
          selectedCandidateId: null,
        );
        final levelField = preview.fields.firstWhere((f) => f.formKey == 'level');
        expect(levelField.hasWarning, isTrue);
        expect(
          levelField.warningMessage,
          contains('δεν αντιστοιχίστηκε σε φύλλο χάρτη'),
        );
        expect(levelField.lampValue, '9');
      },
    );

    test('κενό level → floor_id και map_floor null', () async {
      final result = await service.save(
        target: LampTransferTarget.department,
        formValues: departmentForm(level: ''),
        selectedCandidateId: null,
      );

      final db = await DatabaseHelper.instance.database;
      final row = await db.query(
        'departments',
        where: 'id = ?',
        whereArgs: [result.id],
      );
      expect(row.first['floor_id'], isNull);
      expect(row.first['map_floor'], isNull);
    });

    test(
      'κτίριο ελληνικό «Β» vs λατινικό «B» → αμετάβλητο στη σύγκριση',
      () async {
        final db = await DatabaseHelper.instance.database;
        final deptId = await db.insert('departments', {
          'name': 'Φαρμακείο',
          'name_key': 'φαρμακειο',
          'building': 'Β',
          'is_deleted': 0,
        });

        final draft = await service.buildDraft(
          target: LampTransferTarget.department,
          sourceRow: {
            'office_name': 'Φαρμακείο',
            'building': 'B',
          },
        );

        final preview = buildLampTransferPreview(
          draft: draft,
          currentFormValues: <String, String>{
            ...draft.formValues,
            'building': 'B',
          },
          selectedCandidateId: deptId,
        );
        final buildingField = preview.fields.firstWhere(
          (f) => f.formKey == 'building',
        );
        expect(buildingField.action, TransferFieldAction.unchanged);
        expect(buildingField.hasWarning, isFalse);
      },
    );
  });
}
