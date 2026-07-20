import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/directory/screens/widgets/department_employee_reassign_dialog.dart';
import 'package:call_logger/features/directory/screens/widgets/shared_asset_disconnect_dialog.dart';
import 'package:call_logger/features/directory/services/department_employee_reassign_apply.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../test_setup.dart';

void main() {
  group('applyDepartmentEmployeeReassignBatch', () {
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final tempDir = await Directory.systemTemp.createTemp(
        'department_employee_reassign_apply_test_',
      );
      await DatabaseHelper.bindTestDatabaseFile(
        '${tempDir.path}/department_employee_reassign.db',
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

    Future<int> insertPhone(String number) async {
      return db.insert('phones', {
        'number': number,
        'is_deleted': 0,
      });
    }

    Future<int> insertEquipment(String code) async {
      return db.insert('equipment', {
        'code_equipment': code,
        'is_deleted': 0,
      });
    }

    test('μεταφορά σε υπάρχον τμήμα αλλάζει department_id', () async {
      final sourceId = await insertDepartment('Πηγή Υπαλλήλου');
      final targetId = await insertDepartment('Στόχος Υπάρχον');
      final userId = await insertUser(
        firstName: 'Άλφα',
        lastName: 'Υπάλληλος',
        departmentId: sourceId,
      );

      await applyDepartmentEmployeeReassignBatch(
        db,
        DepartmentEmployeeReassignBatch(
          transfers: {
            userId: SharedAssetTransferTarget.existing(targetId),
          },
        ),
      );

      final rows = await db.query(
        'users',
        where: 'id = ?',
        whereArgs: [userId],
      );
      expect(rows, hasLength(1));
      expect(rows.single['department_id'], targetId);
    });

    test('μεταφορά σε νέο τμήμα δημιουργεί τμήμα και θέτει department_id',
        () async {
      const newDeptName = 'Νέο Τμήμα Reassign';
      final sourceId = await insertDepartment('Πηγή Νέου');
      final userId = await insertUser(
        firstName: 'Βήτα',
        lastName: 'Υπάλληλος',
        departmentId: sourceId,
      );

      await applyDepartmentEmployeeReassignBatch(
        db,
        DepartmentEmployeeReassignBatch(
          transfers: {
            userId: SharedAssetTransferTarget.createNew(newDeptName),
          },
        ),
      );

      final deptRows = await db.query(
        'departments',
        where: 'name = ?',
        whereArgs: [newDeptName],
      );
      expect(deptRows, hasLength(1));
      final newDeptId = deptRows.single['id'] as int;

      final userRows = await db.query(
        'users',
        where: 'id = ?',
        whereArgs: [userId],
      );
      expect(userRows.single['department_id'], newDeptId);
    });

    test('προσωπικά τηλέφωνα και εξοπλισμός ακολουθούν τον υπάλληλο', () async {
      final sourceId = await insertDepartment('Πηγή Assets');
      final targetId = await insertDepartment('Στόχος Assets');
      final userId = await insertUser(
        firstName: 'Γάμμα',
        lastName: 'Κάτοχος',
        departmentId: sourceId,
      );
      const phoneNumber = '2310999001';
      const equipmentCode = 'PC-REASSIGN-1';
      final phoneId = await insertPhone(phoneNumber);
      final equipmentId = await insertEquipment(equipmentCode);
      await db.insert('user_phones', {
        'user_id': userId,
        'phone_id': phoneId,
      });
      await db.insert('user_equipment', {
        'user_id': userId,
        'equipment_id': equipmentId,
      });

      await applyDepartmentEmployeeReassignBatch(
        db,
        DepartmentEmployeeReassignBatch(
          transfers: {
            userId: SharedAssetTransferTarget.existing(targetId),
          },
        ),
      );

      final userRows = await db.query(
        'users',
        where: 'id = ?',
        whereArgs: [userId],
      );
      expect(userRows.single['department_id'], targetId);

      expect(
        await db.query(
          'user_phones',
          where: 'user_id = ? AND phone_id = ?',
          whereArgs: [userId, phoneId],
        ),
        hasLength(1),
      );
      expect(
        await db.query(
          'user_equipment',
          where: 'user_id = ? AND equipment_id = ?',
          whereArgs: [userId, equipmentId],
        ),
        hasLength(1),
      );
    });
  });
}
