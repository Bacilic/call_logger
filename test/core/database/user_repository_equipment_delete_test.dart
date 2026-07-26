import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/user_repository.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/directory/screens/widgets/shared_asset_disconnect_dialog.dart';
import 'package:call_logger/features/directory/services/shared_asset_disconnect_apply.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

/// Διαγραφή υπαλλήλου: εξοπλισμός χωρίς κάτοχο δεν πρέπει να μένει χωρίς τμήμα.
void main() {
  group('UserRepository · exclusive equipment on user delete', () {
    late UserRepository repo;
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp(
        'user_repository_equipment_delete_test_',
      );
      await DatabaseHelper.bindTestDatabaseFile(
        '${dir.path}/user_equip_delete.db',
      );
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('audit_log');
      await db.delete('user_equipment');
      await db.delete('user_phones');
      await db.delete('equipment');
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

    test(
      '(α) σκέτο deleteUsers: μοναδικός κάτοχος + NULL department_id → ορφανός',
      () async {
        final deptId = await insertDepartment('Τμήμα Ορφανού Εξοπλισμού');
        final userId = await db.insert('users', {
          'first_name': 'Μόνος',
          'last_name': 'Κάτοχος',
          'department_id': deptId,
          'is_deleted': 0,
        });
        final equipmentId = await db.insert('equipment', {
          'code_equipment': 'EQ-ORPHAN-SEED',
          'department_id': null,
          'is_deleted': 0,
        });
        await db.insert('user_equipment', {
          'user_id': userId,
          'equipment_id': equipmentId,
        });

        await repo.deleteUsers([userId]);

        final row = (await db.query(
          'equipment',
          where: 'id = ?',
          whereArgs: [equipmentId],
        )).single;
        final remainingLinks = await db.query(
          'user_equipment',
          where: 'equipment_id = ?',
          whereArgs: [equipmentId],
        );

        expect(remainingLinks, isEmpty);
        expect(row['department_id'], isNull);
      },
    );

    test(
      '(β) find+apply κράτηση: μετά τη διαγραφή ο εξοπλισμός κρατά το τμήμα Τ',
      () async {
        final deptId = await insertDepartment('Τμήμα Κράτησης');
        final userId = await db.insert('users', {
          'first_name': 'Κράτηση',
          'last_name': 'Κατόχου',
          'department_id': deptId,
          'is_deleted': 0,
        });
        const code = 'EQ-KEEP-DEPT';
        final equipmentId = await db.insert('equipment', {
          'code_equipment': code,
          'department_id': null,
          'is_deleted': 0,
        });
        await db.insert('user_equipment', {
          'user_id': userId,
          'equipment_id': equipmentId,
        });

        final atRisk = await repo.findExclusiveEquipmentForUserDelete([userId]);
        expect(atRisk, hasLength(1));
        expect(atRisk.single.equipmentId, equipmentId);
        expect(atRisk.single.codeEquipment, code);
        expect(atRisk.single.userId, userId);
        expect(atRisk.single.departmentId, deptId);
        expect(atRisk.single.departmentName, 'Τμήμα Κράτησης');

        await repo.deleteUsers([userId]);

        await applyPersonalEquipmentDisconnectBatch(
          db,
          SharedAssetDisconnectBatchResult(equipmentToKeep: [code]),
          sourceDepartmentId: deptId,
        );

        final row = (await db.query(
          'equipment',
          where: 'id = ?',
          whereArgs: [equipmentId],
        )).single;
        expect(row['department_id'], deptId);
      },
    );

    test(
      '(γ) ήδη μη-NULL department_id: δεν εμφανίζεται «σε κίνδυνο» και μένει ίδιο',
      () async {
        final ownerDeptId = await insertDepartment('Τμήμα Κατόχου');
        final equipmentDeptId = await insertDepartment('Τμήμα Εξοπλισμού');
        final userId = await db.insert('users', {
          'first_name': 'Ήδη',
          'last_name': 'Τμήμα',
          'department_id': ownerDeptId,
          'is_deleted': 0,
        });
        const code = 'EQ-HAS-DEPT';
        final equipmentId = await db.insert('equipment', {
          'code_equipment': code,
          'department_id': equipmentDeptId,
          'is_deleted': 0,
        });
        await db.insert('user_equipment', {
          'user_id': userId,
          'equipment_id': equipmentId,
        });

        final atRisk = await repo.findExclusiveEquipmentForUserDelete([userId]);
        expect(atRisk, isEmpty);

        await repo.deleteUsers([userId]);

        final row = (await db.query(
          'equipment',
          where: 'id = ?',
          whereArgs: [equipmentId],
        )).single;
        expect(row['department_id'], equipmentDeptId);
      },
    );

    test(
      '(δ) δεύτερος κάτοχος εκτός διαγραφόμενων: δεν εμφανίζεται «σε κίνδυνο»',
      () async {
        final deptId = await insertDepartment('Τμήμα Διπλού');
        final deletedUserId = await db.insert('users', {
          'first_name': 'Διαγραφόμενος',
          'last_name': 'Κάτοχος',
          'department_id': deptId,
          'is_deleted': 0,
        });
        final otherUserId = await db.insert('users', {
          'first_name': 'Άλλος',
          'last_name': 'Κάτοχος',
          'department_id': deptId,
          'is_deleted': 0,
        });
        final equipmentId = await db.insert('equipment', {
          'code_equipment': 'EQ-SHARED-OWNERS',
          'department_id': null,
          'is_deleted': 0,
        });
        await db.insert('user_equipment', {
          'user_id': deletedUserId,
          'equipment_id': equipmentId,
        });
        await db.insert('user_equipment', {
          'user_id': otherUserId,
          'equipment_id': equipmentId,
        });

        final atRisk = await repo.findExclusiveEquipmentForUserDelete([
          deletedUserId,
        ]);
        expect(atRisk, isEmpty);

        await repo.deleteUsers([deletedUserId]);

        final row = (await db.query(
          'equipment',
          where: 'id = ?',
          whereArgs: [equipmentId],
        )).single;
        expect(row['department_id'], isNull);
        final remaining = await db.query(
          'user_equipment',
          where: 'equipment_id = ?',
          whereArgs: [equipmentId],
        );
        expect(remaining, hasLength(1));
        expect(remaining.single['user_id'], otherUserId);
      },
    );
  });
}
