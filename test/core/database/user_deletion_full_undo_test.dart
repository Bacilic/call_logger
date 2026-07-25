import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/user_repository.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/directory/screens/widgets/shared_asset_disconnect_dialog.dart';
import 'package:call_logger/features/directory/services/shared_asset_disconnect_apply.dart';
import 'package:call_logger/features/directory/services/user_deletion_undo_record.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

/// Πλήρης αναίρεση διαγραφής υπαλλήλου (υπάλληλος + τηλέφωνα + εξοπλισμός).
void main() {
  group('User deletion · full undo', () {
    late UserRepository repo;
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp(
        'user_deletion_full_undo_test_',
      );
      await DatabaseHelper.bindTestDatabaseFile(
        '${dir.path}/user_deletion_full_undo.db',
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
      repo = UserRepository(db);
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

    Future<int> insertPhone(String number) async {
      return db.insert('phones', {
        'number': number,
        'is_deleted': 0,
      });
    }

    Future<({
      int userId,
      int deptId,
      int dept2Id,
      int phoneId,
      int equipmentId,
    })> seedExclusiveUser() async {
      final deptId = await insertDepartment('Τμήμα Δ');
      final dept2Id = await insertDepartment('Τμήμα Δ2');
      final userId = await db.insert('users', {
        'first_name': 'Υπάλληλος',
        'last_name': 'Υ',
        'department_id': deptId,
        'is_deleted': 0,
      });
      final phoneId = await insertPhone('2310111111');
      await db.insert('user_phones', {
        'user_id': userId,
        'phone_id': phoneId,
      });
      final equipmentId = await db.insert('equipment', {
        'code_equipment': 'EQ-UNDO-1',
        'department_id': null,
        'is_deleted': 0,
      });
      await db.insert('user_equipment', {
        'user_id': userId,
        'equipment_id': equipmentId,
      });
      return (
        userId: userId,
        deptId: deptId,
        dept2Id: dept2Id,
        phoneId: phoneId,
        equipmentId: equipmentId,
      );
    }

    Future<void> deleteWithTransferAndKeep({
      required int userId,
      required int deptId,
      required int dept2Id,
    }) async {
      await repo.deleteUsers([userId]);
      await applyPersonalPhoneDisconnectBatch(
        db,
        SharedAssetDisconnectBatchResult(
          phoneTransfers: {
            '2310111111': SharedAssetTransferTarget.existing(dept2Id),
          },
        ),
        sourceDepartmentId: deptId,
      );
      await applyPersonalEquipmentDisconnectBatch(
        db,
        const SharedAssetDisconnectBatchResult(
          equipmentToKeep: ['EQ-UNDO-1'],
        ),
        sourceDepartmentId: deptId,
      );
    }

    test(
      '(α) τωρινό undo (μόνο restoreUsers): Υ επανέρχεται, P/E όχι στην προηγούμενη κατάσταση',
      () async {
        final seed = await seedExclusiveUser();
        await deleteWithTransferAndKeep(
          userId: seed.userId,
          deptId: seed.deptId,
          dept2Id: seed.dept2Id,
        );

        await repo.restoreUsers([seed.userId]);

        final userRow = (await db.query(
          'users',
          where: 'id = ?',
          whereArgs: [seed.userId],
        )).single;
        expect(userRow['is_deleted'], 0);

        final userPhoneLinks = await db.query(
          'user_phones',
          where: 'user_id = ? AND phone_id = ?',
          whereArgs: [seed.userId, seed.phoneId],
        );
        expect(
          userPhoneLinks,
          isEmpty,
          reason: 'το ελλιπές undo δεν επανασυνδέει το τηλέφωνο',
        );

        final dept2Phone = await db.rawQuery(
          '''
          SELECT 1 AS ok FROM department_phones dp
          JOIN phones p ON p.id = dp.phone_id
          WHERE dp.department_id = ? AND p.number = ?
          LIMIT 1
          ''',
          [seed.dept2Id, '2310111111'],
        );
        expect(
          dept2Phone,
          isNotEmpty,
          reason: 'το P παραμένει direct-phone του Δ2',
        );

        final eqLinks = await db.query(
          'user_equipment',
          where: 'user_id = ? AND equipment_id = ?',
          whereArgs: [seed.userId, seed.equipmentId],
        );
        expect(
          eqLinks,
          isEmpty,
          reason: 'το ελλιπές undo δεν επανασυνδέει τον εξοπλισμό',
        );

        final eqRow = (await db.query(
          'equipment',
          where: 'id = ?',
          whereArgs: [seed.equipmentId],
        )).single;
        expect(
          eqRow['department_id'],
          seed.deptId,
          reason: 'το E κρατά λάθος τμήμα μετά το ελλιπές undo',
        );
      },
    );

    test(
      '(β) πλήρες undo: Υ ενεργός, P ξανά του Υ (όχι Δ2), E ξανά του Υ με department_id NULL',
      () async {
        final seed = await seedExclusiveUser();
        final record = UserDeletionUndoRecord(
          deletedUserIds: [seed.userId],
          originalUserPhones: {
            seed.userId: ['2310111111'],
          },
          originalUserEquipmentIds: {
            seed.userId: [seed.equipmentId],
          },
          phoneDeptAdds: [
            PhoneDeptAdd(
              departmentId: seed.dept2Id,
              phoneNumber: '2310111111',
            ),
          ],
          equipmentDeptSets: [
            EquipmentDeptSet(
              equipmentId: seed.equipmentId,
              departmentId: seed.deptId,
            ),
          ],
          softDeletedPhoneNumbers: const [],
          softDeletedEquipmentCodes: const [],
        );

        await deleteWithTransferAndKeep(
          userId: seed.userId,
          deptId: seed.deptId,
          dept2Id: seed.dept2Id,
        );

        await applyUserDeletionUndo(db, record);

        final userRow = (await db.query(
          'users',
          where: 'id = ?',
          whereArgs: [seed.userId],
        )).single;
        expect(userRow['is_deleted'], 0);

        final userPhoneLinks = await db.query(
          'user_phones',
          where: 'user_id = ? AND phone_id = ?',
          whereArgs: [seed.userId, seed.phoneId],
        );
        expect(userPhoneLinks, hasLength(1));

        final dept2Phone = await db.rawQuery(
          '''
          SELECT 1 AS ok FROM department_phones dp
          JOIN phones p ON p.id = dp.phone_id
          WHERE dp.department_id = ? AND p.number = ?
          LIMIT 1
          ''',
          [seed.dept2Id, '2310111111'],
        );
        expect(dept2Phone, isEmpty);

        final eqLinks = await db.query(
          'user_equipment',
          where: 'user_id = ? AND equipment_id = ?',
          whereArgs: [seed.userId, seed.equipmentId],
        );
        expect(eqLinks, hasLength(1));

        final eqRow = (await db.query(
          'equipment',
          where: 'id = ?',
          whereArgs: [seed.equipmentId],
        )).single;
        expect(eqRow['department_id'], isNull);
        expect(eqRow['is_deleted'], 0);
      },
    );

    test(
      '(γ) διαγραφές P+E: μετά το undo un-soft-deleted και ξανασυνδεδεμένα στον Υ',
      () async {
        final seed = await seedExclusiveUser();
        final record = UserDeletionUndoRecord(
          deletedUserIds: [seed.userId],
          originalUserPhones: {
            seed.userId: ['2310111111'],
          },
          originalUserEquipmentIds: {
            seed.userId: [seed.equipmentId],
          },
          phoneDeptAdds: const [],
          equipmentDeptSets: const [],
          softDeletedPhoneNumbers: const ['2310111111'],
          softDeletedEquipmentCodes: const ['EQ-UNDO-1'],
        );

        await repo.deleteUsers([seed.userId]);
        await applyPersonalPhoneDisconnectBatch(
          db,
          const SharedAssetDisconnectBatchResult(
            phonesToDelete: ['2310111111'],
          ),
          sourceDepartmentId: seed.deptId,
        );
        await applyPersonalEquipmentDisconnectBatch(
          db,
          const SharedAssetDisconnectBatchResult(
            equipmentToDelete: ['EQ-UNDO-1'],
          ),
          sourceDepartmentId: seed.deptId,
        );

        final phoneBefore = (await db.query(
          'phones',
          where: 'id = ?',
          whereArgs: [seed.phoneId],
        )).single;
        final eqBefore = (await db.query(
          'equipment',
          where: 'id = ?',
          whereArgs: [seed.equipmentId],
        )).single;
        expect(phoneBefore['is_deleted'], 1);
        expect(eqBefore['is_deleted'], 1);

        await applyUserDeletionUndo(db, record);

        final phoneAfter = (await db.query(
          'phones',
          where: 'id = ?',
          whereArgs: [seed.phoneId],
        )).single;
        final eqAfter = (await db.query(
          'equipment',
          where: 'id = ?',
          whereArgs: [seed.equipmentId],
        )).single;
        expect(phoneAfter['is_deleted'], 0);
        expect(eqAfter['is_deleted'], 0);

        expect(
          await db.query(
            'user_phones',
            where: 'user_id = ? AND phone_id = ?',
            whereArgs: [seed.userId, seed.phoneId],
          ),
          hasLength(1),
        );
        expect(
          await db.query(
            'user_equipment',
            where: 'user_id = ? AND equipment_id = ?',
            whereArgs: [seed.userId, seed.equipmentId],
          ),
          hasLength(1),
        );
      },
    );

    test(
      '(δ) μη-αποκλειστικό τηλέφωνο: επανασύνδεση στον Υ χωρίς να χαλάει τον άλλον',
      () async {
        final deptId = await insertDepartment('Τμήμα Κοινό');
        final userY = await db.insert('users', {
          'first_name': 'Υ',
          'last_name': 'Διαγραφόμενος',
          'department_id': deptId,
          'is_deleted': 0,
        });
        final userOther = await db.insert('users', {
          'first_name': 'Άλλος',
          'last_name': 'Παραμένει',
          'department_id': deptId,
          'is_deleted': 0,
        });
        final phoneId = await insertPhone('2310222222');
        await db.insert('user_phones', {
          'user_id': userY,
          'phone_id': phoneId,
        });
        await db.insert('user_phones', {
          'user_id': userOther,
          'phone_id': phoneId,
        });

        final record = UserDeletionUndoRecord(
          deletedUserIds: [userY],
          originalUserPhones: {
            userY: ['2310222222'],
          },
          originalUserEquipmentIds: {
            userY: const [],
          },
          phoneDeptAdds: const [],
          equipmentDeptSets: const [],
          softDeletedPhoneNumbers: const [],
          softDeletedEquipmentCodes: const [],
        );

        await repo.deleteUsers([userY]);
        expect(
          await db.query(
            'user_phones',
            where: 'user_id = ? AND phone_id = ?',
            whereArgs: [userY, phoneId],
          ),
          isEmpty,
        );
        expect(
          await db.query(
            'user_phones',
            where: 'user_id = ? AND phone_id = ?',
            whereArgs: [userOther, phoneId],
          ),
          hasLength(1),
        );

        await applyUserDeletionUndo(db, record);

        expect(
          await db.query(
            'user_phones',
            where: 'user_id = ? AND phone_id = ?',
            whereArgs: [userY, phoneId],
          ),
          hasLength(1),
        );
        expect(
          await db.query(
            'user_phones',
            where: 'user_id = ? AND phone_id = ?',
            whereArgs: [userOther, phoneId],
          ),
          hasLength(1),
        );
      },
    );
  });
}
