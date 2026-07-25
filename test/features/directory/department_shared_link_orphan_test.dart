// Αφαίρεση κοινόχρηστου εξοπλισμού χωρίς κάτοχο δεν πρέπει να ορφανοποιεί τμήμα.
//
//   flutter test test/features/directory/department_shared_link_orphan_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/equipment_repository.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/directory/providers/department_directory_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

Future<ProviderContainer> _container() async {
  final container = ProviderContainer(
    overrides: callLoggerTestProviderOverrides(),
  );
  await container.read(lookupServiceProvider.future);
  return container;
}

Future<void> _reloadLookup(ProviderContainer container) async {
  LookupService.instance.resetForReload();
  await LookupService.instance.loadFromDatabase();
  container.invalidate(lookupServiceProvider);
  await container.read(lookupServiceProvider.future);
}

Future<int> _insertDepartment(String name) async {
  final db = await DatabaseHelper.instance.database;
  return db.insert('departments', {
    'name': name,
    'name_key': SearchTextNormalizer.normalizeForSearch(name),
    'is_deleted': 0,
  });
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('Department shared equipment · orphan-risk on remove', () {
    late ProviderContainer container;

    setUp(() async {
      await bindCallLoggerIsolatedTestDatabase();
      final db = await DatabaseHelper.instance.database;
      await db.delete('audit_log');
      await db.delete('user_equipment');
      await db.delete('equipment');
      await db.delete('users');
      await db.delete('departments');
      container = await _container();
    });

    tearDown(() {
      container.dispose();
    });

    test(
      '(α) clear χωρίς κάτοχο → ορφανός· update χωρίς disposition → StateError',
      () async {
        final deptId = await _insertDepartment('Τμήμα Κοινόχρηστου');
        const code = 'EQ-ORPHAN-SHARED';
        final db = await DatabaseHelper.instance.database;
        final equipmentId = await db.insert('equipment', {
          'code_equipment': code,
          'department_id': deptId,
          'is_deleted': 0,
        });

        await EquipmentRepository(db).clearEquipmentSharedDepartment(
          code,
          deptId,
        );
        final afterClear = (await db.query(
          'equipment',
          where: 'id = ?',
          whereArgs: [equipmentId],
        )).single;
        expect(afterClear['department_id'], isNull);

        await db.update(
          'equipment',
          {'department_id': deptId},
          where: 'id = ?',
          whereArgs: [equipmentId],
        );
        LookupService.instance.resetForReload();
        await LookupService.instance.loadFromDatabase();
        container.invalidate(lookupServiceProvider);
        await container.read(lookupServiceProvider.future);
        await container
            .read(departmentDirectoryProvider.notifier)
            .loadDepartments();

        await expectLater(
          container.read(departmentDirectoryProvider.notifier)
              .updateDepartmentSharedAssets(
            deptId,
            sharedPhones: const [],
            sharedEquipmentCodes: const [],
          ),
          throwsA(isA<StateError>()),
        );

        final afterGuard = (await db.query(
          'equipment',
          where: 'id = ?',
          whereArgs: [equipmentId],
        )).single;
        expect(afterGuard['department_id'], deptId);
      },
    );

    test(
      '(β) μεταφορά σε τμήμα Τ2: department_id == Τ2.id',
      () async {
        final deptId = await _insertDepartment('Τμήμα Πηγή');
        final targetId = await _insertDepartment('Τμήμα Στόχος');
        const code = 'EQ-TRANSFER-SHARED';
        final db = await DatabaseHelper.instance.database;
        final equipmentId = await db.insert('equipment', {
          'code_equipment': code,
          'department_id': deptId,
          'is_deleted': 0,
        });

        await _reloadLookup(container);
        await container
            .read(departmentDirectoryProvider.notifier)
            .loadDepartments();

        await container
            .read(departmentDirectoryProvider.notifier)
            .updateDepartmentSharedAssets(
          deptId,
          sharedPhones: const [],
          sharedEquipmentCodes: const [],
          equipmentTransfers: {code: targetId},
        );

        final row = (await db.query(
          'equipment',
          where: 'id = ?',
          whereArgs: [equipmentId],
        )).single;
        expect(row['department_id'], targetId);
        expect(row['is_deleted'], 0);
      },
    );

    test(
      '(γ) διαγραφή: soft-deleted',
      () async {
        final deptId = await _insertDepartment('Τμήμα Διαγραφής');
        const code = 'EQ-DELETE-SHARED';
        final db = await DatabaseHelper.instance.database;
        final equipmentId = await db.insert('equipment', {
          'code_equipment': code,
          'department_id': deptId,
          'is_deleted': 0,
        });

        await _reloadLookup(container);
        await container
            .read(departmentDirectoryProvider.notifier)
            .loadDepartments();

        await container
            .read(departmentDirectoryProvider.notifier)
            .updateDepartmentSharedAssets(
          deptId,
          sharedPhones: const [],
          sharedEquipmentCodes: const [],
          equipmentToSoftDelete: [code],
        );

        final row = (await db.query(
          'equipment',
          where: 'id = ?',
          whereArgs: [equipmentId],
        )).single;
        expect(row['is_deleted'], 1);
      },
    );

    test(
      '(δ) με κάτοχο: όχι «σε κίνδυνο» — αφαίρεση χωρίς ερώτηση, πέφτει στον κάτοχο',
      () async {
        final deptId = await _insertDepartment('Τμήμα Με Κάτοχο');
        final ownerDeptId = await _insertDepartment('Τμήμα Κατόχου');
        const code = 'EQ-OWNED-SHARED';
        final db = await DatabaseHelper.instance.database;
        final equipmentId = await db.insert('equipment', {
          'code_equipment': code,
          'department_id': deptId,
          'is_deleted': 0,
        });
        final userId = await db.insert('users', {
          'first_name': 'Κάτοχος',
          'last_name': 'Εξοπλισμού',
          'department_id': ownerDeptId,
          'is_deleted': 0,
        });
        await db.insert('user_equipment', {
          'user_id': userId,
          'equipment_id': equipmentId,
        });

        await _reloadLookup(container);
        await container
            .read(departmentDirectoryProvider.notifier)
            .loadDepartments();

        final usage = LookupService.instance.checkEquipmentUsage(code);
        expect(usage.hasUserOwners, isTrue);

        await container
            .read(departmentDirectoryProvider.notifier)
            .updateDepartmentSharedAssets(
          deptId,
          sharedPhones: const [],
          sharedEquipmentCodes: const [],
        );

        final row = (await db.query(
          'equipment',
          where: 'id = ?',
          whereArgs: [equipmentId],
        )).single;
        expect(row['department_id'], isNull);
        final links = await db.query(
          'user_equipment',
          where: 'equipment_id = ?',
          whereArgs: [equipmentId],
        );
        expect(links, hasLength(1));
        expect(links.single['user_id'], userId);
      },
    );
  });
}
