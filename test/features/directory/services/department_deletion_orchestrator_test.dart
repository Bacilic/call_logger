import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/directory/screens/widgets/department_employee_reassign_dialog.dart';
import 'package:call_logger/features/directory/screens/widgets/shared_asset_disconnect_dialog.dart';
import 'package:call_logger/features/directory/services/department_deletion_orchestrator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../test_setup.dart';

void main() {
  group('department_deletion_orchestrator', () {
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final tempDir = await Directory.systemTemp.createTemp(
        'department_deletion_orchestrator_test_',
      );
      await DatabaseHelper.bindTestDatabaseFile(
        '${tempDir.path}/department_deletion_orchestrator.db',
      );
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('audit_log');
      await db.delete('user_equipment');
      await db.delete('user_phones');
      await db.delete('department_phones');
      await db.delete('phones');
      await db.delete('equipment');
      await db.delete('users');
      await db.delete('departments');
      LookupService.instance.resetForReload();
      await LookupService.instance.loadFromDatabase();
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Future<int> insertDepartment(String name) async {
      return db.insert('departments', {
        'name': name,
        'name_key': SearchTextNormalizer.normalizeForSearch(name),
        'is_deleted': 0,
      });
    }

    Future<int> insertUser({
      required String firstName,
      required String lastName,
      required int departmentId,
    }) async {
      return db.insert('users', {
        'first_name': firstName,
        'last_name': lastName,
        'department_id': departmentId,
        'is_deleted': 0,
      });
    }

    Future<int> insertSharedPhone(String number, int departmentId) async {
      final phoneId = await db.insert('phones', {
        'number': number,
        'department_id': departmentId,
        'is_deleted': 0,
      });
      await db.insert('department_phones', {
        'department_id': departmentId,
        'phone_id': phoneId,
      });
      return phoneId;
    }

    Future<int> insertSharedEquipment(String code, int departmentId) async {
      return db.insert('equipment', {
        'code_equipment': code,
        'department_id': departmentId,
        'is_deleted': 0,
      });
    }

    DepartmentDeletionPlan planFor({
      required int sourceId,
      required int targetId,
      required int userId,
      required String phone,
      required String equipmentCode,
    }) {
      return DepartmentDeletionPlan(
        departmentId: sourceId,
        employeeBatch: DepartmentEmployeeReassignBatch(
          transfers: {
            userId: SharedAssetTransferTarget.existing(targetId),
          },
        ),
        sharedBatch: SharedAssetDisconnectBatchResult(
          phoneTransfers: {
            phone: SharedAssetTransferTarget.existing(targetId),
          },
          equipmentTransfers: {
            equipmentCode: SharedAssetTransferTarget.existing(targetId),
          },
        ),
      );
    }

    test(
      'επιτυχία: δύο plans → μεταφορές και soft-delete εφαρμόζονται',
      () async {
        final targetId = await insertDepartment('Στόχος Orchestrator');
        final source1 = await insertDepartment('Πηγή A');
        final source2 = await insertDepartment('Πηγή B');
        final user1 = await insertUser(
          firstName: 'Άλφα',
          lastName: 'Ένα',
          departmentId: source1,
        );
        final user2 = await insertUser(
          firstName: 'Βήτα',
          lastName: 'Δύο',
          departmentId: source2,
        );
        await insertSharedPhone('2310666001', source1);
        await insertSharedPhone('2310666002', source2);
        await insertSharedEquipment('PC-ORCH-1', source1);
        await insertSharedEquipment('PC-ORCH-2', source2);

        await applyDepartmentDeletionPlansAtomic(db, [
          planFor(
            sourceId: source1,
            targetId: targetId,
            userId: user1,
            phone: '2310666001',
            equipmentCode: 'PC-ORCH-1',
          ),
          planFor(
            sourceId: source2,
            targetId: targetId,
            userId: user2,
            phone: '2310666002',
            equipmentCode: 'PC-ORCH-2',
          ),
        ]);

        expect(
          (await db.query('users', where: 'id = ?', whereArgs: [user1]))
              .single['department_id'],
          targetId,
        );
        expect(
          (await db.query('users', where: 'id = ?', whereArgs: [user2]))
              .single['department_id'],
          targetId,
        );
        expect(
          (await db.query(
            'phones',
            where: 'number = ?',
            whereArgs: ['2310666001'],
          )).single['department_id'],
          targetId,
        );
        expect(
          (await db.query(
            'phones',
            where: 'number = ?',
            whereArgs: ['2310666002'],
          )).single['department_id'],
          targetId,
        );
        expect(
          (await db.query(
            'equipment',
            where: 'code_equipment = ?',
            whereArgs: ['PC-ORCH-1'],
          )).single['department_id'],
          targetId,
        );
        expect(
          (await db.query(
            'equipment',
            where: 'code_equipment = ?',
            whereArgs: ['PC-ORCH-2'],
          )).single['department_id'],
          targetId,
        );
        expect(
          (await db.query(
            'departments',
            where: 'id = ?',
            whereArgs: [source1],
          )).single['is_deleted'],
          1,
        );
        expect(
          (await db.query(
            'departments',
            where: 'id = ?',
            whereArgs: [source2],
          )).single['is_deleted'],
          1,
        );
      },
    );

    test(
      'rollback: σφάλμα στο δεύτερο plan → καμία αλλαγή στα δύο τμήματα',
      () async {
        final targetId = await insertDepartment('Στόχος Rollback Orch');
        final source1 = await insertDepartment('Πηγή Rollback A');
        final source2 = await insertDepartment('Πηγή Rollback B');
        final user1 = await insertUser(
          firstName: 'Γάμμα',
          lastName: 'Ένα',
          departmentId: source1,
        );
        final user2 = await insertUser(
          firstName: 'Δέλτα',
          lastName: 'Δύο',
          departmentId: source2,
        );
        final phone1 = await insertSharedPhone('2310666011', source1);
        final phone2 = await insertSharedPhone('2310666012', source2);
        final eq1 = await insertSharedEquipment('PC-ORCH-R1', source1);
        final eq2 = await insertSharedEquipment('PC-ORCH-R2', source2);

        // Αποτυχία κατά το soft-delete του δεύτερου τμήματος → όλο το txn.
        await db.execute('''
          CREATE TRIGGER IF NOT EXISTS fail_second_dept_soft_delete
          BEFORE UPDATE OF is_deleted ON departments
          WHEN NEW.is_deleted = 1 AND OLD.id = $source2
          BEGIN
            SELECT RAISE(ABORT, 'intentional orchestrator rollback');
          END;
        ''');

        await expectLater(
          () => applyDepartmentDeletionPlansAtomic(db, [
            planFor(
              sourceId: source1,
              targetId: targetId,
              userId: user1,
              phone: '2310666011',
              equipmentCode: 'PC-ORCH-R1',
            ),
            planFor(
              sourceId: source2,
              targetId: targetId,
              userId: user2,
              phone: '2310666012',
              equipmentCode: 'PC-ORCH-R2',
            ),
          ]),
          throwsA(isA<DatabaseException>()),
        );

        await db.execute(
          'DROP TRIGGER IF EXISTS fail_second_dept_soft_delete',
        );

        expect(
          (await db.query('users', where: 'id = ?', whereArgs: [user1]))
              .single['department_id'],
          source1,
        );
        expect(
          (await db.query('users', where: 'id = ?', whereArgs: [user2]))
              .single['department_id'],
          source2,
        );
        expect(
          (await db.query(
            'departments',
            where: 'id = ?',
            whereArgs: [source1],
          )).single['is_deleted'],
          0,
        );
        expect(
          (await db.query(
            'departments',
            where: 'id = ?',
            whereArgs: [source2],
          )).single['is_deleted'],
          0,
        );
        expect(
          (await db.query('phones', where: 'id = ?', whereArgs: [phone1]))
              .single['department_id'],
          source1,
        );
        expect(
          (await db.query('phones', where: 'id = ?', whereArgs: [phone2]))
              .single['department_id'],
          source2,
        );
        expect(
          (await db.query('equipment', where: 'id = ?', whereArgs: [eq1]))
              .single['department_id'],
          source1,
        );
        expect(
          (await db.query('equipment', where: 'id = ?', whereArgs: [eq2]))
              .single['department_id'],
          source2,
        );
      },
    );
  });
}
