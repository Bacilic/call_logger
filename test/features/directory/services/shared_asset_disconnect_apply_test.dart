import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/directory/screens/widgets/shared_asset_disconnect_dialog.dart';
import 'package:call_logger/features/directory/services/shared_asset_disconnect_apply.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../test_setup.dart';

/// Lock συμπεριφοράς shared_asset_disconnect_apply (Φάση Γ.4 / Tier 4d-1).
void main() {
  group('shared_asset_disconnect_apply — lock πριν refactor', () {
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final tempDir = await Directory.systemTemp.createTemp(
        'shared_asset_disconnect_apply_test_',
      );
      await DatabaseHelper.bindTestDatabaseFile(
        '${tempDir.path}/shared_asset_disconnect.db',
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

    Future<int> insertPhone(String number, {int? departmentId}) async {
      return db.insert('phones', {
        'number': number,
        'department_id': departmentId,
        'is_deleted': 0,
      });
    }

    Future<void> linkPhoneToDepartment(int deptId, int phoneId) async {
      await db.insert('department_phones', {
        'department_id': deptId,
        'phone_id': phoneId,
      });
    }

    Future<int> insertEquipment(String code, {int? departmentId}) async {
      return db.insert('equipment', {
        'code_equipment': code,
        'department_id': departmentId,
        'is_deleted': 0,
      });
    }

    test(
      'applyPersonalPhoneDisconnectBatch: keep / transfer (νέο τμήμα) / delete',
      () async {
        const phoneKeep = '2310777701';
        const phoneTransfer = '2310777702';
        const phoneDelete = '2310777703';
        const newDeptName = 'Νέο Τμήμα Personal Transfer';

        final sourceDeptId = await insertDepartment('Τμήμα Πηγής Personal');
        final deletePhoneId = await insertPhone(phoneDelete);

        final batch = SharedAssetDisconnectBatchResult(
          phonesToKeep: [phoneKeep],
          phoneTransfers: {
            phoneTransfer: SharedAssetTransferTarget.createNew(newDeptName),
          },
          phonesToDelete: [phoneDelete],
          newDepartmentNamesToCreate: {
            newDeptName: {phoneTransfer},
          },
        );

        await applyPersonalPhoneDisconnectBatch(
          db,
          batch,
          sourceDepartmentId: sourceDeptId,
        );

        final keepRows = await db.query(
          'phones',
          where: 'number = ?',
          whereArgs: [phoneKeep],
        );
        expect(keepRows, hasLength(1));
        expect(keepRows.single['department_id'], sourceDeptId);
        expect(
          await db.query(
            'department_phones',
            where: 'department_id = ? AND phone_id = ?',
            whereArgs: [sourceDeptId, keepRows.single['id']],
          ),
          hasLength(1),
        );

        final newDeptRows = await db.query(
          'departments',
          where: 'name = ?',
          whereArgs: [newDeptName],
        );
        expect(newDeptRows, hasLength(1));
        final newDeptId = newDeptRows.single['id'] as int;

        final transferRows = await db.query(
          'phones',
          where: 'number = ?',
          whereArgs: [phoneTransfer],
        );
        expect(transferRows, hasLength(1));
        expect(
          await db.query(
            'department_phones',
            where: 'department_id = ? AND phone_id = ?',
            whereArgs: [newDeptId, transferRows.single['id']],
          ),
          hasLength(1),
        );

        final deletedRow = await db.query(
          'phones',
          where: 'id = ?',
          whereArgs: [deletePhoneId],
        );
        expect(deletedRow.single['is_deleted'], 1);
      },
    );

    test(
      'applyDepartmentSharedAssetDisconnectBatch: phones + equipment keep/transfer/delete',
      () async {
        const phoneKeep = '2310777801';
        const phoneTransfer = '2310777802';
        const phoneDelete = '2310777803';
        const eqKeep = 'PC-SAD-KEEP';
        const eqTransfer = 'PC-SAD-TRANSFER';
        const eqDelete = 'PC-SAD-DELETE';
        const newEqDeptName = 'Νέο Τμήμα Eq Transfer';

        final sourceDeptId = await insertDepartment('Τμήμα Πηγής Shared');
        final targetDeptId = await insertDepartment('Τμήμα Στόχος Phone');

        final transferPhoneId = await insertPhone(phoneTransfer, departmentId: sourceDeptId);
        await linkPhoneToDepartment(sourceDeptId, transferPhoneId);
        final deletePhoneId = await insertPhone(phoneDelete, departmentId: sourceDeptId);
        await linkPhoneToDepartment(sourceDeptId, deletePhoneId);

        final eqTransferId =
            await insertEquipment(eqTransfer, departmentId: sourceDeptId);
        final eqDeleteId =
            await insertEquipment(eqDelete, departmentId: sourceDeptId);

        final batch = SharedAssetDisconnectBatchResult(
          phonesToKeep: [phoneKeep],
          equipmentToKeep: [eqKeep],
          phoneTransfers: {
            phoneTransfer: SharedAssetTransferTarget.existing(targetDeptId),
          },
          equipmentTransfers: {
            eqTransfer: SharedAssetTransferTarget.createNew(newEqDeptName),
          },
          phonesToDelete: [phoneDelete],
          equipmentToDelete: [eqDelete],
          newDepartmentNamesToCreate: {
            newEqDeptName: <String>{},
          },
        );

        await applyDepartmentSharedAssetDisconnectBatch(
          db,
          batch,
          sourceDepartmentId: sourceDeptId,
        );

        final keepPhoneRows = await db.query(
          'phones',
          where: 'number = ?',
          whereArgs: [phoneKeep],
        );
        expect(keepPhoneRows.single['department_id'], sourceDeptId);

        final keepEqRows = await db.query(
          'equipment',
          where: 'code_equipment = ?',
          whereArgs: [eqKeep],
        );
        expect(keepEqRows, hasLength(1));
        expect(keepEqRows.single['department_id'], sourceDeptId);

        final transferredPhoneLinks = await db.query(
          'department_phones',
          where: 'department_id = ? AND phone_id = ?',
          whereArgs: [targetDeptId, transferPhoneId],
        );
        expect(transferredPhoneLinks, hasLength(1));
        expect(
          await db.query(
            'department_phones',
            where: 'department_id = ? AND phone_id = ?',
            whereArgs: [sourceDeptId, transferPhoneId],
          ),
          isEmpty,
        );

        final newEqDeptRows = await db.query(
          'departments',
          where: 'name = ?',
          whereArgs: [newEqDeptName],
        );
        expect(newEqDeptRows, hasLength(1));
        final newEqDeptId = newEqDeptRows.single['id'] as int;

        final eqTransferRow = await db.query(
          'equipment',
          where: 'id = ?',
          whereArgs: [eqTransferId],
        );
        expect(eqTransferRow.single['department_id'], newEqDeptId);

        final deletedPhone = await db.query(
          'phones',
          where: 'id = ?',
          whereArgs: [deletePhoneId],
        );
        expect(deletedPhone.single['is_deleted'], 1);

        final deletedEq = await db.query(
          'equipment',
          where: 'id = ?',
          whereArgs: [eqDeleteId],
        );
        expect(deletedEq.single['is_deleted'], 1);
      },
    );
  });
}
