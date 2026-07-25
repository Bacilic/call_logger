import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/department_repository.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/directory/screens/widgets/department_employee_reassign_dialog.dart';
import 'package:call_logger/features/directory/screens/widgets/shared_asset_disconnect_dialog.dart';
import 'package:call_logger/features/directory/services/department_deletion_orchestrator.dart';
import 'package:call_logger/features/directory/services/department_deletion_undo_policy.dart';
import 'package:call_logger/features/directory/services/department_deletion_undo_record.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

/// Πλήρης αναίρεση διαγραφής τμήματος.
void main() {
  group('Department deletion · full undo', () {
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp(
        'department_deletion_full_undo_test_',
      );
      await DatabaseHelper.bindTestDatabaseFile(
        '${dir.path}/department_deletion_full_undo.db',
      );
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('audit_log');
      await db.delete('user_equipment');
      await db.delete('user_phones');
      await db.delete('department_phones');
      await db.delete('equipment');
      await db.delete('phones');
      await db.delete('users');
      await db.delete('departments');
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

    Future<({
      int deptId,
      int dept2Id,
      int userId,
      int phoneId,
      int equipmentId,
    })> seedDepartmentWithSharedAssets() async {
      final deptId = await insertDepartment('Τμήμα Δ');
      final dept2Id = await insertDepartment('Τμήμα Δ2');
      final userId = await db.insert('users', {
        'first_name': 'Υπάλληλος',
        'last_name': 'Υ',
        'department_id': deptId,
        'is_deleted': 0,
      });
      final phoneId = await db.insert('phones', {
        'number': '2310333333',
        'department_id': deptId,
        'is_deleted': 0,
      });
      await db.insert('department_phones', {
        'department_id': deptId,
        'phone_id': phoneId,
      });
      final equipmentId = await db.insert('equipment', {
        'code_equipment': 'EQ-DEPT-UNDO',
        'department_id': deptId,
        'is_deleted': 0,
      });
      return (
        deptId: deptId,
        dept2Id: dept2Id,
        userId: userId,
        phoneId: phoneId,
        equipmentId: equipmentId,
      );
    }

    DepartmentDeletionPlan transferAllPlan({
      required int deptId,
      required int dept2Id,
      required int userId,
    }) {
      final target = SharedAssetTransferTarget.existing(dept2Id);
      return DepartmentDeletionPlan(
        departmentId: deptId,
        employeeBatch: DepartmentEmployeeReassignBatch(
          transfers: {userId: target},
        ),
        sharedBatch: SharedAssetDisconnectBatchResult(
          phoneTransfers: {'2310333333': target},
          equipmentTransfers: {'EQ-DEPT-UNDO': target},
        ),
      );
    }

    test(
      '(α) τωρινό έλλειμμα: μετά μεταφορές το σκέτο restoreDepartments αφήνει Υ/P/E στο Δ2',
      () async {
        final seed = await seedDepartmentWithSharedAssets();
        final plan = transferAllPlan(
          deptId: seed.deptId,
          dept2Id: seed.dept2Id,
          userId: seed.userId,
        );

        await applyDepartmentDeletionPlansAtomic(db, [plan]);
        await DepartmentRepository(db).restoreDepartments([seed.deptId]);

        final deptRow = (await db.query(
          'departments',
          where: 'id = ?',
          whereArgs: [seed.deptId],
        )).single;
        expect(deptRow['is_deleted'], 0);

        final userRow = (await db.query(
          'users',
          where: 'id = ?',
          whereArgs: [seed.userId],
        )).single;
        expect(
          userRow['department_id'],
          seed.dept2Id,
          reason: 'το ελλιπές undo δεν επιστρέφει τον υπάλληλο στο Δ',
        );

        final dept2Phone = await db.rawQuery(
          '''
          SELECT 1 AS ok FROM department_phones
          WHERE department_id = ? AND phone_id = ?
          LIMIT 1
          ''',
          [seed.dept2Id, seed.phoneId],
        );
        expect(dept2Phone, isNotEmpty);

        final eqRow = (await db.query(
          'equipment',
          where: 'id = ?',
          whereArgs: [seed.equipmentId],
        )).single;
        expect(eqRow['department_id'], seed.dept2Id);

        final policy = resolveDepartmentDeletionUndo(
          deletedDepartmentCount: 1,
          movedEmployeeCount: 1,
          movedOrDeletedAssetCount: 2,
        );
        // Μετά τη διόρθωση πολιτικής: canOfferUndo true.
        // Το (α) τεκμηριώνει ότι το σκέτο restoreDepartments δεν αρκεί.
        expect(policy.canOfferUndo, isTrue);
      },
    );

    test(
      '(β) πλήρες undo: Δ ενεργό, Υ/P/E πίσω στο Δ',
      () async {
        final seed = await seedDepartmentWithSharedAssets();
        final plan = transferAllPlan(
          deptId: seed.deptId,
          dept2Id: seed.dept2Id,
          userId: seed.userId,
        );
        final record = DepartmentDeletionUndoRecord(
          deletedDepartmentIds: [seed.deptId],
          reassignedEmployees: [
            DepartmentDeletionReassignedEmployee(
              userId: seed.userId,
              originalDeletedDeptId: seed.deptId,
            ),
          ],
          phoneTransfers: [
            DepartmentDeletionPhoneTransfer(
              phoneNumber: '2310333333',
              fromDeletedDeptId: seed.deptId,
              toTargetDeptId: seed.dept2Id,
            ),
          ],
          softDeletedPhones: const [],
          equipmentTransfers: [
            DepartmentDeletionEquipmentTransfer(
              code: 'EQ-DEPT-UNDO',
              deletedDeptId: seed.deptId,
              toTargetDeptId: seed.dept2Id,
            ),
          ],
          softDeletedEquipment: const [],
        );

        await applyDepartmentDeletionPlansAtomic(db, [plan]);
        await applyDepartmentDeletionUndo(db, record);

        final deptRow = (await db.query(
          'departments',
          where: 'id = ?',
          whereArgs: [seed.deptId],
        )).single;
        expect(deptRow['is_deleted'], 0);

        final userRow = (await db.query(
          'users',
          where: 'id = ?',
          whereArgs: [seed.userId],
        )).single;
        expect(userRow['department_id'], seed.deptId);

        final phoneOnD = await db.rawQuery(
          '''
          SELECT 1 AS ok FROM department_phones
          WHERE department_id = ? AND phone_id = ?
          LIMIT 1
          ''',
          [seed.deptId, seed.phoneId],
        );
        expect(phoneOnD, isNotEmpty);

        final phoneOnD2 = await db.rawQuery(
          '''
          SELECT 1 AS ok FROM department_phones
          WHERE department_id = ? AND phone_id = ?
          LIMIT 1
          ''',
          [seed.dept2Id, seed.phoneId],
        );
        expect(phoneOnD2, isEmpty);

        final eqRow = (await db.query(
          'equipment',
          where: 'id = ?',
          whereArgs: [seed.equipmentId],
        )).single;
        expect(eqRow['department_id'], seed.deptId);
        expect(eqRow['is_deleted'], 0);
      },
    );

    test(
      '(γ) διαγραφές P+E: μετά το undo un-soft-deleted και ξανά στο Δ',
      () async {
        final seed = await seedDepartmentWithSharedAssets();
        final plan = DepartmentDeletionPlan(
          departmentId: seed.deptId,
          employeeBatch: DepartmentEmployeeReassignBatch(
            transfers: {
              seed.userId: SharedAssetTransferTarget.existing(seed.dept2Id),
            },
          ),
          sharedBatch: const SharedAssetDisconnectBatchResult(
            phonesToDelete: ['2310333333'],
            equipmentToDelete: ['EQ-DEPT-UNDO'],
          ),
        );
        final record = DepartmentDeletionUndoRecord(
          deletedDepartmentIds: [seed.deptId],
          reassignedEmployees: [
            DepartmentDeletionReassignedEmployee(
              userId: seed.userId,
              originalDeletedDeptId: seed.deptId,
            ),
          ],
          phoneTransfers: const [],
          softDeletedPhones: [
            DepartmentDeletionSoftDeletedPhone(
              phoneNumber: '2310333333',
              deletedDeptId: seed.deptId,
            ),
          ],
          equipmentTransfers: const [],
          softDeletedEquipment: [
            DepartmentDeletionSoftDeletedEquipment(
              code: 'EQ-DEPT-UNDO',
              deletedDeptId: seed.deptId,
            ),
          ],
        );

        await applyDepartmentDeletionPlansAtomic(db, [plan]);

        expect(
          (await db.query(
            'phones',
            where: 'id = ?',
            whereArgs: [seed.phoneId],
          )).single['is_deleted'],
          1,
        );
        expect(
          (await db.query(
            'equipment',
            where: 'id = ?',
            whereArgs: [seed.equipmentId],
          )).single['is_deleted'],
          1,
        );

        await applyDepartmentDeletionUndo(db, record);

        final phone = (await db.query(
          'phones',
          where: 'id = ?',
          whereArgs: [seed.phoneId],
        )).single;
        expect(phone['is_deleted'], 0);

        final eq = (await db.query(
          'equipment',
          where: 'id = ?',
          whereArgs: [seed.equipmentId],
        )).single;
        expect(eq['is_deleted'], 0);
        expect(eq['department_id'], seed.deptId);

        final phoneOnD = await db.rawQuery(
          '''
          SELECT 1 AS ok FROM department_phones
          WHERE department_id = ? AND phone_id = ?
          LIMIT 1
          ''',
          [seed.deptId, seed.phoneId],
        );
        expect(phoneOnD, isNotEmpty);
      },
    );

    test(
      '(δ) resolveDepartmentDeletionUndo: canOfferUndo true και με μετακινήσεις',
      () {
        final result = resolveDepartmentDeletionUndo(
          deletedDepartmentCount: 1,
          movedEmployeeCount: 3,
          movedOrDeletedAssetCount: 5,
        );
        expect(result.canOfferUndo, isTrue);
        expect(
          result.snackbarMessage,
          contains('Επαναφέρθηκαν και τα μετακινημένα στοιχεία'),
        );
      },
    );

    test(
      '(ε) μεταφορά σε ΝΕΟ τμήμα: μετά το undo το Δ επανέρχεται και το νέο soft-διαγράφεται',
      () async {
        const newDeptName = 'Νέο Τμήμα Προορισμός Undo';
        final deptId = await insertDepartment('Τμήμα Δ');
        final userId = await db.insert('users', {
          'first_name': 'Υπάλληλος',
          'last_name': 'Υ',
          'department_id': deptId,
          'is_deleted': 0,
        });
        final phoneId = await db.insert('phones', {
          'number': '2310333333',
          'department_id': deptId,
          'is_deleted': 0,
        });
        await db.insert('department_phones', {
          'department_id': deptId,
          'phone_id': phoneId,
        });
        final equipmentId = await db.insert('equipment', {
          'code_equipment': 'EQ-DEPT-UNDO',
          'department_id': deptId,
          'is_deleted': 0,
        });

        final target = SharedAssetTransferTarget.createNew(newDeptName);
        final plan = DepartmentDeletionPlan(
          departmentId: deptId,
          employeeBatch: DepartmentEmployeeReassignBatch(
            transfers: {userId: target},
          ),
          sharedBatch: SharedAssetDisconnectBatchResult(
            phoneTransfers: {'2310333333': target},
            equipmentTransfers: {'EQ-DEPT-UNDO': target},
          ),
        );

        await applyDepartmentDeletionPlansAtomic(db, [plan]);

        final createdRows = await db.query(
          'departments',
          columns: ['id'],
          where: 'name_key = ? AND COALESCE(is_deleted, 0) = 0',
          whereArgs: [SearchTextNormalizer.normalizeForSearch(newDeptName)],
          limit: 1,
        );
        expect(createdRows, hasLength(1));
        final createdDeptId = createdRows.first['id'] as int;

        final record = DepartmentDeletionUndoRecord(
          deletedDepartmentIds: [deptId],
          reassignedEmployees: [
            DepartmentDeletionReassignedEmployee(
              userId: userId,
              originalDeletedDeptId: deptId,
            ),
          ],
          phoneTransfers: [
            DepartmentDeletionPhoneTransfer(
              phoneNumber: '2310333333',
              fromDeletedDeptId: deptId,
              toTargetDeptId: createdDeptId,
            ),
          ],
          softDeletedPhones: const [],
          equipmentTransfers: [
            DepartmentDeletionEquipmentTransfer(
              code: 'EQ-DEPT-UNDO',
              deletedDeptId: deptId,
              toTargetDeptId: createdDeptId,
            ),
          ],
          softDeletedEquipment: const [],
          createdDepartmentIds: [createdDeptId],
        );

        await applyDepartmentDeletionUndo(db, record);

        expect(
          (await db.query(
            'departments',
            where: 'id = ?',
            whereArgs: [deptId],
          )).single['is_deleted'],
          0,
        );
        expect(
          (await db.query(
            'departments',
            where: 'id = ?',
            whereArgs: [createdDeptId],
          )).single['is_deleted'],
          1,
        );
        expect(
          (await db.query(
            'users',
            where: 'id = ?',
            whereArgs: [userId],
          )).single['department_id'],
          deptId,
        );
        expect(
          (await db.query(
            'equipment',
            where: 'id = ?',
            whereArgs: [equipmentId],
          )).single['department_id'],
          deptId,
        );
        final phoneOnD = await db.rawQuery(
          '''
          SELECT 1 AS ok FROM department_phones
          WHERE department_id = ? AND phone_id = ?
          LIMIT 1
          ''',
          [deptId, phoneId],
        );
        expect(phoneOnD, isNotEmpty);
      },
    );
  });
}
