import 'dart:convert';
import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/remote_tools_repository.dart';
import 'package:call_logger/core/models/remote_tool.dart';
import 'package:call_logger/core/models/remote_tool_role.dart';
import 'package:call_logger/features/settings/widgets/remote_tool_form/remote_tool_form_saver.dart';
import 'package:call_logger/features/settings/widgets/remote_tool_form/remote_tool_form_sort.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../test_setup.dart';

void main() {
  group('RemoteToolFormSaver — lock πριν εξαγωγή', () {
    late RemoteToolsRepository repo;
    late RemoteToolFormSaver saver;
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp
          .createTemp('remote_tool_form_saver_test_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/rt_saver.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('remote_tools');
      repo = RemoteToolsRepository(DatabaseHelper.instance);
      saver = RemoteToolFormSaver(repo);
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Future<int> seedTool({
      required String name,
      required int sortOrder,
      String executablePath = r'C:\tools\base.exe',
      String? argumentsJson,
      String? deletedAt,
    }) async {
      return db.insert('remote_tools', {
        'name': name,
        'role': ToolRole.generic.dbValue,
        'executable_path': executablePath,
        'sort_order': sortOrder,
        'is_active': 1,
        'deleted_at': deletedAt,
        'arguments_json': argumentsJson,
      });
    }

    List<int> sortOrders(List<RemoteTool> tools) =>
        sortedRemoteTools(tools).map((t) => t.sortOrder).toList();

    List<String> namesInOrder(List<RemoteTool> tools) =>
        sortedRemoteTools(tools).map((t) => t.name).toList();

    RemoteTool formTool({
      required int id,
      required String name,
      String executablePath = r'C:\new\tool.exe',
      List<RemoteToolArgument> arguments = const [],
      int sortOrder = 1,
    }) {
      return RemoteTool(
        id: id,
        name: name,
        role: ToolRole.generic,
        executablePath: executablePath,
        sortOrder: sortOrder,
        isActive: true,
        arguments: arguments,
      );
    }

    test('commitNew: νέο εργαλείο στο τέλος → sort_order 1..n+1 χωρίς κενά', () async {
      await seedTool(name: 'Alpha', sortOrder: 1);
      await seedTool(name: 'Beta', sortOrder: 2);
      await seedTool(name: 'Gamma', sortOrder: 3);

      final args = [
        const RemoteToolArgument(value: '-host={TARGET}', description: 'host'),
      ];
      final newId = await saver.commitNew(
        toolFromForm: formTool(
          id: 0,
          name: 'Delta',
          executablePath: r'C:\delta.exe',
          arguments: args,
        ),
      );

      final all = await repo.getAllNonDeletedTools();
      expect(all, hasLength(4));
      expect(namesInOrder(all), ['Alpha', 'Beta', 'Gamma', 'Delta']);
      expect(sortOrders(all), [1, 2, 3, 4]);

      final inserted = await repo.getById(newId);
      expect(inserted!.name, 'Delta');
      expect(inserted.executablePath, r'C:\delta.exe');
      expect(
        jsonDecode(inserted.toMap()['arguments_json'] as String),
        [
          {
            'value': '-host={TARGET}',
            'description': 'host',
            'is_active': true,
          },
        ],
      );
    });

    test('commitEdit: διατηρεί τρέχουσα θέση και ενημερώνει πεδία', () async {
      await seedTool(name: 'A', sortOrder: 1);
      final idB = await seedTool(name: 'B', sortOrder: 2);
      await seedTool(name: 'C', sortOrder: 3);

      await saver.commitEdit(
        toolFromForm: formTool(
          id: idB,
          name: 'B-edited',
          executablePath: r'C:\b2.exe',
          sortOrder: 99,
          arguments: const [
            RemoteToolArgument(value: '/v:{TARGET}', description: 'rdp'),
          ],
        ),
      );

      final all = await repo.getAllNonDeletedTools();
      expect(namesInOrder(all), ['A', 'B-edited', 'C']);
      expect(sortOrders(all), [1, 2, 3]);

      final updated = await repo.getById(idB);
      expect(updated!.name, 'B-edited');
      expect(updated.executablePath, r'C:\b2.exe');
      expect(updated.sortOrder, 2);
      expect(
        jsonDecode(updated.toMap()['arguments_json'] as String),
        [
          {
            'value': '/v:{TARGET}',
            'description': 'rdp',
            'is_active': true,
          },
        ],
      );
    });

    test(
      'commitRestoreSoftDeleted: επαναφορά στο τέλος, soft-delete άλλου id',
      () async {
        final idSoft = await seedTool(
          name: 'Restored',
          sortOrder: 99,
          executablePath: r'C:\old.exe',
          deletedAt: DateTime.utc(2024, 1, 1).toIso8601String(),
        );
        final idCurrent = await seedTool(name: 'Current', sortOrder: 1);
        await seedTool(name: 'Other', sortOrder: 2);

        await saver.commitRestoreSoftDeleted(
          toolFromForm: formTool(
            id: idSoft,
            name: 'Restored',
            executablePath: r'C:\restored.exe',
            arguments: const [
              RemoteToolArgument(value: '-id {TARGET}', description: 'ad'),
            ],
          ),
          editCurrentIdToDelete: idCurrent,
        );

        final soft = await repo.getById(idSoft);
        expect(soft!.deletedAt, isNull);
        expect(soft.name, 'Restored');
        expect(soft.executablePath, r'C:\restored.exe');
        expect(
          jsonDecode(soft.toMap()['arguments_json'] as String),
          [
            {
              'value': '-id {TARGET}',
              'description': 'ad',
              'is_active': true,
            },
          ],
        );

        final current = await repo.getById(idCurrent);
        expect(current!.deletedAt, isNotNull);

        final nonDeleted = await repo.getAllNonDeletedTools();
        expect(namesInOrder(nonDeleted), ['Other', 'Restored']);
        expect(sortOrders(nonDeleted), [1, 2]);
      },
    );

    test('loadNonDeleted / findSoftDeletedConflict / disambiguateSoftDeleted',
        () async {
      await seedTool(name: 'Live', sortOrder: 1);
      final idDeleted = await seedTool(
        name: 'Ghost',
        sortOrder: 2,
        deletedAt: DateTime.utc(2024, 6, 1).toIso8601String(),
      );

      final live = await saver.loadNonDeleted();
      expect(live, hasLength(1));
      expect(live.single.name, 'Live');

      final conflict = await saver.findSoftDeletedConflict('ghost');
      expect(conflict!.id, idDeleted);

      await saver.disambiguateSoftDeleted(idDeleted);
      final renamed = await repo.getById(idDeleted);
      expect(renamed!.name, contains('διεγραμμένο'));
      expect(renamed.name, contains('#$idDeleted'));
    });
  });
}
