import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/directory/screens/widgets/department_employee_reassign_dialog.dart';
import 'package:call_logger/features/directory/screens/widgets/shared_asset_disconnect_dialog.dart';
import 'package:call_logger/features/directory/services/department_deletion_orchestrator.dart';
import 'package:call_logger/features/directory/services/department_deletion_undo_record.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

/// Ενιαία & ατομική διαγραφή τμήματος με ΔΙΑΓΡΑΦΗ υπαλλήλου (όχι μόνο μεταφορά),
/// με πλήρη αναίρεση.
void main() {
  late Database db;

  setUpAll(() async {
    initSqfliteFfiForTests();
    final dir = await Directory.systemTemp.createTemp('dept_userdel_test_');
    await DatabaseHelper.bindTestDatabaseFile('${dir.path}/dept_userdel.db');
    db = await DatabaseHelper.instance.database;
  });

  setUp(() async {
    await seedIsolatedTestDatabase();
    for (final t in const [
      'audit_log',
      'user_equipment',
      'user_phones',
      'department_phones',
      'phones',
      'equipment',
      'users',
      'departments',
    ]) {
      await db.delete(t);
    }
  });

  tearDownAll(() async {
    await releaseCallLoggerTestDatabase();
  });

  Future<int> insertDept(String name) => db.insert('departments', {
    'name': name,
    'name_key': SearchTextNormalizer.normalizeForSearch(name),
    'is_deleted': 0,
  });

  Future<int?> intVal(String sql, List<Object?> args) async {
    final rows = await db.rawQuery(sql, args);
    if (rows.isEmpty) return null;
    return (rows.first.values.first as num?)?.toInt();
  }

  test(
    'διαγραφή τμήματος με διαγραφή υπαλλήλου: ατομικό + πλήρες undo',
    () async {
      final deptDel = await insertDept('ΤμήμαΠρος');
      final dept2 = await insertDept('Στόχος');

      final userA = await db.insert('users', {
        'first_name': 'Άννα',
        'last_name': 'Δοκιμή',
        'department_id': deptDel,
        'is_deleted': 0,
      });
      final userB = await db.insert('users', {
        'first_name': 'Βασίλης',
        'last_name': 'Δοκιμή',
        'department_id': deptDel,
        'is_deleted': 0,
      });

      final phoneP = await db.insert('phones', {
        'number': 'P111',
        'is_deleted': 0,
      });
      await db.insert('user_phones', {'user_id': userA, 'phone_id': phoneP});

      final equipE = await db.insert('equipment', {
        'code_equipment': 'E111',
        'department_id': null,
        'is_deleted': 0,
      });
      await db.insert('user_equipment', {
        'user_id': userA,
        'equipment_id': equipE,
      });

      final plan = DepartmentDeletionPlan(
        departmentId: deptDel,
        employeeBatch: DepartmentEmployeeReassignBatch(
          transfers: {userB: SharedAssetTransferTarget.existing(dept2)},
        ),
        sharedBatch: const SharedAssetDisconnectBatchResult(),
        deletedEmployees: [
          DepartmentEmployeeDeletion(
            userId: userA,
            phoneBatch: const SharedAssetDisconnectBatchResult(
              phonesToDelete: ['P111'],
            ),
            equipmentBatch: SharedAssetDisconnectBatchResult(
              equipmentTransfers: {
                'E111': SharedAssetTransferTarget.existing(dept2),
              },
            ),
          ),
        ],
      );

      // ── Εκτέλεση (ατομικά) ──
      final employeesUndo = await applyDepartmentDeletionPlansAtomic(db, [
        plan,
      ]);

      expect(
        await intVal('SELECT is_deleted FROM departments WHERE id=?', [
          deptDel,
        ]),
        1,
      );
      expect(
        await intVal('SELECT department_id FROM users WHERE id=?', [userB]),
        dept2,
      );
      expect(
        await intVal('SELECT is_deleted FROM users WHERE id=?', [userA]),
        1,
      );
      expect(
        await intVal('SELECT is_deleted FROM phones WHERE id=?', [phoneP]),
        1,
      );
      expect(
        await intVal('SELECT department_id FROM equipment WHERE id=?', [
          equipE,
        ]),
        dept2,
      );
      expect(
        await intVal('SELECT COUNT(*) FROM user_phones WHERE user_id=?', [
          userA,
        ]),
        0,
      );
      expect(
        await intVal('SELECT COUNT(*) FROM user_equipment WHERE user_id=?', [
          userA,
        ]),
        0,
      );
      expect(employeesUndo.deletedUserIds, contains(userA));

      // ── Πλήρης αναίρεση ──
      final deptUndo = DepartmentDeletionUndoRecord(
        deletedDepartmentIds: [deptDel],
        reassignedEmployees: [
          DepartmentDeletionReassignedEmployee(
            userId: userB,
            originalDeletedDeptId: deptDel,
          ),
        ],
        phoneTransfers: const [],
        softDeletedPhones: const [],
        equipmentTransfers: const [],
        softDeletedEquipment: const [],
        deletedEmployeesUndo: employeesUndo,
      );
      await applyDepartmentDeletionUndo(db, deptUndo);

      expect(
        await intVal('SELECT is_deleted FROM departments WHERE id=?', [
          deptDel,
        ]),
        0,
      );
      expect(
        await intVal('SELECT department_id FROM users WHERE id=?', [userB]),
        deptDel,
      );
      expect(
        await intVal('SELECT is_deleted FROM users WHERE id=?', [userA]),
        0,
      );
      expect(
        await intVal('SELECT is_deleted FROM phones WHERE id=?', [phoneP]),
        0,
      );
      expect(
        await intVal(
          'SELECT COUNT(*) FROM user_phones WHERE user_id=? AND phone_id=?',
          [userA, phoneP],
        ),
        1,
      );
      expect(
        await intVal('SELECT department_id FROM equipment WHERE id=?', [
          equipE,
        ]),
        isNull,
      );
      expect(
        await intVal(
          'SELECT COUNT(*) FROM user_equipment WHERE user_id=? AND equipment_id=?',
          [userA, equipE],
        ),
        1,
      );
    },
  );

  test(
    'διαγραφή τμήματος με createNew: η αναίρεση soft-διαγράφει το νέο τμήμα',
    () async {
      const newDeptName = 'ΝέοΣτόχοςUndo';
      final deptDel = await insertDept('ΤμήμαΠρος');

      final userA = await db.insert('users', {
        'first_name': 'Άννα',
        'last_name': 'Δοκιμή',
        'department_id': deptDel,
        'is_deleted': 0,
      });
      final userB = await db.insert('users', {
        'first_name': 'Βασίλης',
        'last_name': 'Δοκιμή',
        'department_id': deptDel,
        'is_deleted': 0,
      });

      final phoneP = await db.insert('phones', {
        'number': 'P222',
        'is_deleted': 0,
      });
      await db.insert('user_phones', {'user_id': userA, 'phone_id': phoneP});

      final equipE = await db.insert('equipment', {
        'code_equipment': 'E222',
        'department_id': null,
        'is_deleted': 0,
      });
      await db.insert('user_equipment', {
        'user_id': userA,
        'equipment_id': equipE,
      });

      final target = SharedAssetTransferTarget.createNew(newDeptName);
      final plan = DepartmentDeletionPlan(
        departmentId: deptDel,
        employeeBatch: DepartmentEmployeeReassignBatch(
          transfers: {userB: target},
        ),
        sharedBatch: const SharedAssetDisconnectBatchResult(),
        deletedEmployees: [
          DepartmentEmployeeDeletion(
            userId: userA,
            phoneBatch: const SharedAssetDisconnectBatchResult(
              phonesToDelete: ['P222'],
            ),
            equipmentBatch: SharedAssetDisconnectBatchResult(
              equipmentTransfers: {'E222': target},
            ),
          ),
        ],
      );

      final employeesUndo = await applyDepartmentDeletionPlansAtomic(db, [
        plan,
      ]);

      final createdRows = await db.query(
        'departments',
        columns: ['id'],
        where: 'name_key = ? AND COALESCE(is_deleted, 0) = 0',
        whereArgs: [SearchTextNormalizer.normalizeForSearch(newDeptName)],
        limit: 1,
      );
      expect(createdRows, hasLength(1));
      final createdDeptId = createdRows.first['id'] as int;

      expect(
        await intVal('SELECT department_id FROM users WHERE id=?', [userB]),
        createdDeptId,
      );
      expect(
        await intVal('SELECT department_id FROM equipment WHERE id=?', [
          equipE,
        ]),
        createdDeptId,
      );

      final deptUndo = DepartmentDeletionUndoRecord(
        deletedDepartmentIds: [deptDel],
        reassignedEmployees: [
          DepartmentDeletionReassignedEmployee(
            userId: userB,
            originalDeletedDeptId: deptDel,
          ),
        ],
        phoneTransfers: const [],
        softDeletedPhones: const [],
        equipmentTransfers: const [],
        softDeletedEquipment: const [],
        deletedEmployeesUndo: employeesUndo,
        createdDepartmentIds: [createdDeptId],
      );
      await applyDepartmentDeletionUndo(db, deptUndo);

      expect(
        await intVal('SELECT is_deleted FROM departments WHERE id=?', [
          deptDel,
        ]),
        0,
      );
      expect(
        await intVal('SELECT is_deleted FROM departments WHERE id=?', [
          createdDeptId,
        ]),
        1,
      );
      expect(
        await intVal('SELECT department_id FROM users WHERE id=?', [userB]),
        deptDel,
      );
      expect(
        await intVal('SELECT is_deleted FROM users WHERE id=?', [userA]),
        0,
      );
      expect(
        await intVal('SELECT department_id FROM equipment WHERE id=?', [
          equipE,
        ]),
        isNull,
      );
    },
  );
}
