import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/department_repository.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/directory/screens/widgets/department_employee_reassign_dialog.dart';
import 'package:call_logger/features/directory/screens/widgets/shared_asset_disconnect_dialog.dart';
import 'package:call_logger/features/directory/services/department_employee_reassign_apply.dart';
import 'package:call_logger/features/directory/services/shared_asset_disconnect_apply.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../test_setup.dart';

void main() {
  group('department deletion atomicity (executor)', () {
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final tempDir = await Directory.systemTemp.createTemp(
        'department_deletion_atomic_test_',
      );
      await DatabaseHelper.bindTestDatabaseFile(
        '${tempDir.path}/department_deletion_atomic.db',
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

    test(
      'επιτυχία: reassign + shared disconnect + softDelete σε ένα transaction',
      () async {
        final sourceId = await insertDepartment('Πηγή Atomic');
        final targetId = await insertDepartment('Στόχος Atomic');
        final userId = await insertUser(
          firstName: 'Άλφα',
          lastName: 'Υπάλληλος',
          departmentId: sourceId,
        );
        await insertSharedPhone('2310555001', sourceId);
        await insertSharedEquipment('PC-ATOMIC-1', sourceId);

        await db.transaction((txn) async {
          await applyDepartmentEmployeeReassignBatch(
            db,
            DepartmentEmployeeReassignBatch(
              transfers: {
                userId: SharedAssetTransferTarget.existing(targetId),
              },
            ),
            executor: txn,
          );
          await applyDepartmentSharedAssetDisconnectBatch(
            db,
            SharedAssetDisconnectBatchResult(
              phoneTransfers: {
                '2310555001': SharedAssetTransferTarget.existing(targetId),
              },
              equipmentTransfers: {
                'PC-ATOMIC-1': SharedAssetTransferTarget.existing(targetId),
              },
            ),
            sourceDepartmentId: sourceId,
            executor: txn,
          );
          await DepartmentRepository(db).softDeleteDepartments(
            [sourceId],
            executor: txn,
          );
        });

        final userRows = await db.query(
          'users',
          where: 'id = ?',
          whereArgs: [userId],
        );
        expect(userRows.single['department_id'], targetId);

        final phoneRows = await db.query(
          'phones',
          where: 'number = ?',
          whereArgs: ['2310555001'],
        );
        expect(phoneRows.single['department_id'], targetId);
        expect(
          await db.query(
            'department_phones',
            where: 'department_id = ? AND phone_id = ?',
            whereArgs: [targetId, phoneRows.single['id']],
          ),
          hasLength(1),
        );

        final eqRows = await db.query(
          'equipment',
          where: 'code_equipment = ?',
          whereArgs: ['PC-ATOMIC-1'],
        );
        expect(eqRows.single['department_id'], targetId);

        final deptRows = await db.query(
          'departments',
          where: 'id = ?',
          whereArgs: [sourceId],
        );
        expect(deptRows.single['is_deleted'], 1);
      },
    );

    test(
      'rollback: εξαίρεση πριν το commit αφήνει όλα αμετάβλητα',
      () async {
        final sourceId = await insertDepartment('Πηγή Rollback');
        final targetId = await insertDepartment('Στόχος Rollback');
        final userId = await insertUser(
          firstName: 'Βήτα',
          lastName: 'Υπάλληλος',
          departmentId: sourceId,
        );
        final phoneId = await insertSharedPhone('2310555002', sourceId);
        final eqId = await insertSharedEquipment('PC-ATOMIC-2', sourceId);

        await expectLater(
          () => db.transaction((txn) async {
            await applyDepartmentEmployeeReassignBatch(
              db,
              DepartmentEmployeeReassignBatch(
                transfers: {
                  userId: SharedAssetTransferTarget.existing(targetId),
                },
              ),
              executor: txn,
            );
            await applyDepartmentSharedAssetDisconnectBatch(
              db,
              SharedAssetDisconnectBatchResult(
                phoneTransfers: {
                  '2310555002': SharedAssetTransferTarget.existing(targetId),
                },
                equipmentTransfers: {
                  'PC-ATOMIC-2': SharedAssetTransferTarget.existing(targetId),
                },
              ),
              sourceDepartmentId: sourceId,
              executor: txn,
            );
            throw StateError('intentional rollback');
          }),
          throwsA(isA<StateError>()),
        );

        final userRows = await db.query(
          'users',
          where: 'id = ?',
          whereArgs: [userId],
        );
        expect(userRows.single['department_id'], sourceId);

        final deptRows = await db.query(
          'departments',
          where: 'id = ?',
          whereArgs: [sourceId],
        );
        expect(deptRows.single['is_deleted'], 0);

        final phoneRows = await db.query(
          'phones',
          where: 'id = ?',
          whereArgs: [phoneId],
        );
        expect(phoneRows.single['department_id'], sourceId);
        expect(
          await db.query(
            'department_phones',
            where: 'department_id = ? AND phone_id = ?',
            whereArgs: [sourceId, phoneId],
          ),
          hasLength(1),
        );

        final eqRows = await db.query(
          'equipment',
          where: 'id = ?',
          whereArgs: [eqId],
        );
        expect(eqRows.single['department_id'], sourceId);
      },
    );
  });
}
