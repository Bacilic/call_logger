import 'dart:io';

import 'package:call_logger/core/database/building_map_repository.dart';
import 'package:call_logger/core/database/category_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/department_repository.dart';
import 'package:call_logger/core/database/directory_support.dart';
import 'package:call_logger/core/database/equipment_repository.dart';
import 'package:call_logger/core/database/phone_repository.dart';
import 'package:call_logger/core/database/settings_repository.dart';
import 'package:call_logger/core/database/user_repository.dart';
import 'package:call_logger/core/errors/department_exists_exception.dart';
import 'package:call_logger/core/database/integrity_service.dart';
import 'package:call_logger/core/database/audit_service.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

/// Κλείδωμα κατασκευής standalone repositories (Φάση Γ.4 / Tier 1).
void main() {
  group('Repository standalone construction — single-arg db', () {
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp(
        'repository_standalone_construction_test_',
      );
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/standalone.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('audit_log');
      await db.delete('user_equipment');
      await db.delete('equipment');
      await db.delete('categories');
      await db.delete('departments');
      await db.delete('building_map_floors');
      await db.delete('user_phones');
      await db.delete('department_phones');
      await db.delete('phones');
      await db.delete('users');
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    test('DepartmentRepository(db).getActiveDepartments()', () async {
      final activeId = await db.insert('departments', {
        'name': 'Ενεργό Τμήμα',
        'name_key': SearchTextNormalizer.normalizeForSearch('Ενεργό Τμήμα'),
        'is_deleted': 0,
      });
      await db.insert('departments', {
        'name': 'Διαγραμμένο Τμήμα',
        'name_key':
            SearchTextNormalizer.normalizeForSearch('Διαγραμμένο Τμήμα'),
        'is_deleted': 1,
      });

      final active = await DepartmentRepository(db).getActiveDepartments();
      expect(active, hasLength(1));
      expect(active.single['id'], activeId);
      expect(active.single['name'], 'Ενεργό Τμήμα');
    });

    test('CategoryRepository(db).getCategoryNames() / getActiveCategoryRows()',
        () async {
      await db.insert('categories', {'name': 'Zebra', 'is_deleted': 0});
      await db.insert('categories', {'name': 'Alpha', 'is_deleted': 0});
      await db.insert('categories', {'name': 'Deleted', 'is_deleted': 1});

      final repo = CategoryRepository(db);
      final names = await repo.getCategoryNames();
      expect(names, ['Alpha', 'Zebra']);

      final rows = await repo.getActiveCategoryRows();
      expect(rows, hasLength(2));
      expect(rows.map((r) => r['name']), ['Alpha', 'Zebra']);
      expect(rows.every((r) => r['id'] != null), isTrue);
    });

    test('EquipmentRepository(db).getEquipmentDefaultRemoteToolUsageCounts()',
        () async {
      await db.insert('equipment', {
        'code_equipment': 'PC-TOOL-1',
        'default_remote_tool': '7',
        'is_deleted': 0,
      });
      await db.insert('equipment', {
        'code_equipment': 'PC-TOOL-2',
        'default_remote_tool': '7',
        'is_deleted': 0,
      });
      await db.insert('equipment', {
        'code_equipment': 'PC-TOOL-DELETED',
        'default_remote_tool': '7',
        'is_deleted': 1,
      });

      final counts =
          await EquipmentRepository(db).getEquipmentDefaultRemoteToolUsageCounts();
      expect(counts[7], 2);
    });

    test('DepartmentRepository(db).backfillDepartmentFloorIdsFromMapFloor()', () async {
      final floorId = await db.insert('building_map_floors', {
        'sort_order': 0,
        'label': 'Όροφος Backfill',
        'image_path': 'f.png',
        'rotation_degrees': 0.0,
      });
      final deptId = await db.insert('departments', {
        'name': 'Τμήμα Map Floor',
        'name_key': SearchTextNormalizer.normalizeForSearch('Τμήμα Map Floor'),
        'is_deleted': 0,
        'map_floor': floorId.toString(),
        'floor_id': null,
      });

      final count =
          await DepartmentRepository(db).backfillDepartmentFloorIdsFromMapFloor();
      expect(count, 1);

      final row =
          await db.query('departments', where: 'id = ?', whereArgs: [deptId]);
      expect(row.single['floor_id'], floorId);
    });

    test('DepartmentRepository(db).backfillAllDepartmentNameKeys()', () async {
      final canonicalKey =
          SearchTextNormalizer.normalizeForSearch('ΤΜΗΜΑ ΠΛΗΡΟΦΟΡΙΚΗΣ');
      await db.insert('departments', {
        'name': 'ΤΜΗΜΑ ΠΛΗΡΟΦΟΡΙΚΗΣ',
        'name_key': canonicalKey,
        'is_deleted': 0,
      });
      await db.insert('departments', {
        'name': 'Τμήμα Πληροφορικής',
        'name_key': 'τμήμα πληροφορικής',
        'is_deleted': 0,
      });

      final result =
          await DepartmentRepository(db).backfillAllDepartmentNameKeys();
      expect(result.updated, 0);
      expect(result.skippedCollision, 1);
      expect(result.alreadyCorrect, greaterThanOrEqualTo(1));
    });

    test(
      'CategoryRepository(db).insertCategoryAndGetId — id/restored + callback',
      () async {
        final repo = CategoryRepository(db);

        final created = await repo.insertCategoryAndGetId(
          'Νέα Standalone Κατηγορία',
          rebuildSearchIndexInTxn: (txn, categoryId) async {},
        );
        expect(created.restored, isFalse);
        expect(created.id, greaterThan(0));

        final softId = await db.insert('categories', {
          'name': 'Παλιά Standalone',
          'is_deleted': 1,
        });

        int? rebuildCategoryId;
        Object? rebuildTxn;

        final restored = await repo.insertCategoryAndGetId(
          'παλιά standalone',
          rebuildSearchIndexInTxn: (txn, categoryId) async {
            rebuildTxn = txn;
            rebuildCategoryId = categoryId;
          },
        );

        expect(restored.restored, isTrue);
        expect(restored.id, softId);
        expect(rebuildCategoryId, softId);
        expect(rebuildTxn, isNotNull);
      },
    );

    test('CategoryRepository(db).softDeleteCategories / restoreCategories',
        () async {
      final repo = CategoryRepository(db);
      final id1 = await db.insert('categories', {
        'name': 'Standalone Διαγραφή 1',
        'is_deleted': 0,
      });
      final id2 = await db.insert('categories', {
        'name': 'Standalone Διαγραφή 2',
        'is_deleted': 0,
      });

      await SettingsRepository(db).saveSetting(
        DatabaseHelper.auditUserPerformingSettingsKey,
        'Admin Standalone Κατηγοριών',
      );

      await repo.softDeleteCategories([id1, id2]);

      final deleted = await db.query(
        'categories',
        where: 'id IN (?, ?)',
        whereArgs: [id1, id2],
      );
      expect(deleted.every((r) => r['is_deleted'] == 1), isTrue);

      await db.delete('audit_log');
      await repo.restoreCategories([id1]);

      final restored =
          await db.query('categories', where: 'id = ?', whereArgs: [id1]);
      expect(restored.single['is_deleted'], 0);

      final stillDeleted =
          await db.query('categories', where: 'id = ?', whereArgs: [id2]);
      expect(stillDeleted.single['is_deleted'], 1);

      final restoreAudits = await db.query(
        'audit_log',
        where: 'action = ? AND entity_id = ?',
        whereArgs: [DatabaseHelper.auditActionRestore, id1],
      );
      expect(restoreAudits, hasLength(1));
      expect(restoreAudits.single['user_performing'], 'Admin Standalone Κατηγοριών');
    });

    test('UserRepository(db).insertUserFromMap / updateUser + audit', () async {
      final repo = UserRepository(db);
      final deptId = await db.insert('departments', {
        'name': 'Τμήμα Standalone User',
        'name_key': SearchTextNormalizer.normalizeForSearch('Τμήμα Standalone User'),
        'is_deleted': 0,
      });

      await db.delete('audit_log');
      final userId = await repo.insertUserFromMap({
        'first_name': 'Standalone',
        'last_name': 'Χρήστης',
        'department_id': deptId,
        'phones': ['2346111199'],
        'is_deleted': 0,
      }, skipPhonePolicyValidation: true);

      expect(userId, greaterThan(0));

      final createAudit = await db.query(
        'audit_log',
        where: 'action = ? AND entity_type = ? AND entity_id = ?',
        whereArgs: ['ΔΗΜΙΟΥΡΓΙΑ ΧΡΗΣΤΗ', AuditEntityTypes.user, userId],
      );
      expect(createAudit, hasLength(1));

      await db.delete('audit_log');
      await repo.updateUser(
        userId,
        {'first_name': 'Ενημερωμένος', 'last_name': 'Χρήστης'},
      );

      final updateAudit = await db.query(
        'audit_log',
        where: 'action = ? AND entity_type = ? AND entity_id = ?',
        whereArgs: ['ΤΡΟΠΟΠΟΙΗΣΗ ΧΡΗΣΤΗ', AuditEntityTypes.user, userId],
      );
      expect(updateAudit, hasLength(1));

      final userRow =
          await db.query('users', where: 'id = ?', whereArgs: [userId]);
      expect(userRow.single['first_name'], 'Ενημερωμένος');
    });

    test(
      'PhoneRepository(db).addDepartmentDirectPhone / removePhoneFromAllUsers',
      () async {
        const phoneNumber = '2310999911';
        final deptId = await db.insert('departments', {
          'name': 'Τμήμα Standalone Phone',
          'name_key':
              SearchTextNormalizer.normalizeForSearch('Τμήμα Standalone Phone'),
          'is_deleted': 0,
        });
        final userId = await db.insert('users', {
          'first_name': 'Κάτοχος',
          'last_name': 'Standalone',
          'is_deleted': 0,
        });
        final phoneId = await db.insert('phones', {
          'number': phoneNumber,
          'is_deleted': 0,
        });
        await db.insert('user_phones', {
          'user_id': userId,
          'phone_id': phoneId,
        });

        final phones = PhoneRepository(db);
        await db.delete('audit_log');
        await phones.addDepartmentDirectPhone(deptId, phoneNumber);

        final deptLinks = await db.query(
          'department_phones',
          where: 'phone_id = ?',
          whereArgs: [phoneId],
        );
        expect(deptLinks, hasLength(1));

        await db.delete('audit_log');
        await phones.removePhoneFromAllUsers(phoneNumber);

        expect(
          await db.query('user_phones', where: 'user_id = ?', whereArgs: [userId]),
          isEmpty,
        );

        final removeAudit = await db.query('audit_log');
        expect(removeAudit, isNotEmpty);
      },
    );

    test(
      'DepartmentRepository(db) — CRUD/audit standalone paths',
      () async {
        final repo = DepartmentRepository(db);

        expect(
          await repo.departmentNameExistsExcluding('Άγνωστο', 999),
          isFalse,
        );

        await db.delete('audit_log');
        final id = await repo.insertDepartment({
          'name': 'Standalone Dept CRUD',
          'name_key':
              SearchTextNormalizer.normalizeForSearch('Standalone Dept CRUD'),
          'is_deleted': 0,
        });
        expect(id, greaterThan(0));

        expect(
          await repo.departmentNameExistsExcluding('standalone dept crud', id),
          isFalse,
        );
        expect(
          await repo.departmentNameExistsExcluding('Standalone Dept CRUD', id + 999),
          isTrue,
        );

        await expectLater(
          repo.insertDepartment({
            'name': 'Standalone Dept CRUD',
            'name_key':
                SearchTextNormalizer.normalizeForSearch('Standalone Dept CRUD'),
            'is_deleted': 0,
          }),
          throwsA(isA<DepartmentExistsException>()),
        );

        await repo.updateDepartment(id, {'notes': 'Standalone σημείωση'});

        await SettingsRepository(db).saveSetting(
          DatabaseHelper.auditUserPerformingSettingsKey,
          'Admin Standalone Dept',
        );

        await db.delete('audit_log');
        await repo.bulkUpdateDepartments([id], {'building': 'Κτίριο Α'});

        final bulkAudit = await db.query(
          'audit_log',
          where: 'entity_type = ?',
          whereArgs: [AuditEntityTypes.bulkDepartments],
        );
        expect(bulkAudit, hasLength(1));

        await db.delete('audit_log');
        await repo.softDeleteDepartments([id]);

        final deleted =
            await db.query('departments', where: 'id = ?', whereArgs: [id]);
        expect(deleted.single['is_deleted'], 1);

        await repo.restoreDepartmentByName(
          'Standalone Dept CRUD',
          notes: 'Επαναφορά standalone',
        );

        final restored =
            await db.query('departments', where: 'id = ?', whereArgs: [id]);
        expect(restored.single['is_deleted'], 0);
        expect(restored.single['notes'], 'Επαναφορά standalone');

        await db.delete('audit_log');
        await repo.restoreDepartments([id]);

        final restoreAudit = await db.query(
          'audit_log',
          where: 'entity_id = ? AND action = ?',
          whereArgs: [id, DatabaseHelper.auditActionRestore],
        );
        expect(restoreAudit, isNotEmpty);
      },
    );

    test(
      'BuildingMapRepository.clearedBuildingMapPlacementColumns static helpers',
      () {
        final defaults = BuildingMapRepository.clearedBuildingMapPlacementColumns();
        expect(defaults['map_floor'], isNull);
        expect(defaults['map_x'], 0.0);

        final withExtras = BuildingMapRepository.clearedBuildingMapPlacementColumns(
          clearFloorId: true,
          clearDepartmentHex: true,
        );
        expect(withExtras['floor_id'], isNull);
        expect(withExtras['color'], isNull);
        expect(
          BuildingMapRepository.buildingMapPlacementColumnNames.toList(),
          hasLength(defaults.keys.length),
        );
      },
    );

    test(
      'EquipmentRepository(db) + UserRepository + DepartmentRepository — provider paths',
      () async {
        final equipment = EquipmentRepository(db);
        final users = UserRepository(db);
        final departments = DepartmentRepository(db);

        final deptId = await db.insert('departments', {
          'name': 'Τμήμα Standalone Eq',
          'name_key':
              SearchTextNormalizer.normalizeForSearch('Τμήμα Standalone Eq'),
          'is_deleted': 0,
        });
        final userId = await db.insert('users', {
          'first_name': 'Κάτοχος',
          'last_name': 'Standalone Eq',
          'is_deleted': 0,
        });

        final eqId = await equipment.insertEquipmentFromMap({
          'code_equipment': 'PC-STANDALONE-EQ',
          'department_id': deptId,
          'is_deleted': 0,
        });
        expect(eqId, greaterThan(0));

        expect((await equipment.getAllEquipment()).any((r) => r['id'] == eqId),
            isTrue);

        await equipment.replaceEquipmentUsers(eqId, [userId]);
        expect(await equipment.countUsersLinkedToEquipment(eqId), 1);

        final links = await equipment.getAllUserEquipmentLinks();
        expect(
          links.any(
            (r) => r['user_id'] == userId && r['equipment_id'] == eqId,
          ),
          isTrue,
        );

        await equipment.updateEquipment(eqId, {
          'code_equipment': 'PC-STANDALONE-EQ-UPD',
          'department_id': deptId,
          'is_deleted': 0,
        });

        await equipment.unlinkUserFromEquipment(userId, eqId);
        expect(await equipment.countUsersLinkedToEquipment(eqId), 0);

        await equipment.linkUserToEquipment(userId, eqId);
        expect(await equipment.countUsersLinkedToEquipment(eqId), 1);

        await db.delete('audit_log');
        await equipment.bulkUpdateEquipments([eqId], {'notes': 'Bulk standalone'});

        final bulkAudit = await db.query(
          'audit_log',
          where: 'entity_type = ?',
          whereArgs: [AuditEntityTypes.bulkEquipment],
        );
        expect(bulkAudit, hasLength(1));

        await db.delete('audit_log');
        await equipment.deleteEquipments([eqId]);
        expect(
          (await db.query('equipment', where: 'id = ?', whereArgs: [eqId]))
              .single['is_deleted'],
          1,
        );

        await equipment.restoreEquipment([eqId]);
        expect(
          (await db.query('equipment', where: 'id = ?', whereArgs: [eqId]))
              .single['is_deleted'],
          0,
        );

        final allUsers = await users.getAllUsers();
        expect(allUsers.any((u) => u['id'] == userId), isTrue);

        expect(
          await departments.getDepartmentNameById(deptId),
          'Τμήμα Standalone Eq',
        );
        expect(await departments.getDepartmentNameById(99999), isNull);
      },
    );

    test(
      'Tier 4d-2 — User/Department/Phone/Equipment query paths',
      () async {
        final users = UserRepository(db);
        final departments = DepartmentRepository(db);
        final phones = PhoneRepository(db);
        final equipment = EquipmentRepository(db);

        final deptId = await db.insert('departments', {
          'name': 'Τμήμα Tier 4d-2',
          'name_key':
              SearchTextNormalizer.normalizeForSearch('Τμήμα Tier 4d-2'),
          'is_deleted': 0,
        });

        final deptRow = await departments.getDepartmentRowById(deptId);
        expect(deptRow, isNotNull);
        expect(deptRow!['name'], 'Τμήμα Tier 4d-2');

        const phoneNumber = '2310666601';
        const eqCode = 'PC-TIER-4D2';
        final phoneId = await db.insert('phones', {
          'number': phoneNumber,
          'is_deleted': 0,
        });
        final userExclusive = await db.insert('users', {
          'first_name': 'Μόνος',
          'last_name': 'Κάτοχος',
          'department_id': deptId,
          'is_deleted': 0,
        });
        final userShared = await db.insert('users', {
          'first_name': 'Κοινός',
          'last_name': 'Κάτοχος',
          'is_deleted': 0,
        });
        await db.insert('user_phones', {
          'user_id': userExclusive,
          'phone_id': phoneId,
        });
        await db.insert('user_phones', {
          'user_id': userShared,
          'phone_id': phoneId,
        });

        final exclusive = await users.findExclusivePhonesForUserDelete([]);
        expect(exclusive, isEmpty);

        final eqId = await db.insert('equipment', {
          'code_equipment': eqCode,
          'is_deleted': 0,
        });
        await db.insert('user_equipment', {
          'user_id': userExclusive,
          'equipment_id': eqId,
        });
        await db.insert('calls', {
          'equipment_id': eqId,
          'is_deleted': 0,
        });

        expect(await phones.getPhoneIdByNumber(phoneNumber), phoneId);
        expect(await phones.getPhoneIdByNumber('000'), isNull);
        expect(
          await phones.countPhoneReferencesExcludingAudit(phoneId, phoneNumber),
          greaterThanOrEqualTo(2),
        );

        expect(await equipment.getEquipmentIdByCode(eqCode), eqId);
        expect(await equipment.getEquipmentIdByCode('MISSING'), isNull);
        expect(
          await equipment.countEquipmentReferencesExcludingAudit(eqId),
          greaterThanOrEqualTo(2),
        );
      },
    );

    test(
      'Tier 4d-3 — Department/User/BuildingMap widget paths',
      () async {
        final departments = DepartmentRepository(db);
        final users = UserRepository(db);
        final buildingMap = BuildingMapRepository(db, DirectorySupport(db));

        await db.insert('departments', {
          'name': 'Τμήμα Tier 4d-3',
          'name_key':
              SearchTextNormalizer.normalizeForSearch('Τμήμα Tier 4d-3'),
          'is_deleted': 0,
        });
        expect(await departments.departmentNameExists('Τμήμα Tier 4d-3'), isTrue);
        expect(await departments.departmentNameExists('Άγνωστο'), isFalse);

        final createdId =
            await departments.getOrCreateDepartmentIdByName('Νέο Tier 4d-3');
        expect(createdId, isNotNull);
        final reusedId =
            await departments.getOrCreateDepartmentIdByName('νέο tier 4d-3');
        expect(reusedId, createdId);

        await departments.updateDepartment(createdId!, {'notes': 'Tier 4d-3'});
        final updated = await departments.getDepartmentRowById(createdId);
        expect(updated!['notes'], 'Tier 4d-3');

        final userId = await users.insertUser(
          firstName: 'Widget',
          lastName: 'Tier4d3',
        );
        expect(userId, greaterThan(0));

        await db.insert('building_map_floors', {
          'sort_order': 1,
          'label': 'Όροφος Tier 4d-3',
          'image_path': 'f.png',
          'rotation_degrees': 0.0,
        });
        final floors = await buildingMap.listBuildingMapFloors();
        expect(floors, hasLength(1));
        expect(floors.single.label, 'Όροφος Tier 4d-3');
      },
    );

    test(
      'Tier 5b — IntegrityService(db) integrity + task paths',
      () async {
        final integrity = IntegrityService(db);
        final userId = await db.insert('users', {
          'first_name': 'Integrity',
          'last_name': 'Standalone',
          'is_deleted': 0,
        });

        expect(await integrity.integrityUserLabel(db, userId), contains('Integrity Standalone'));
        expect(await integrity.integrityUserLabel(db, null), '—');

        final phoneId = await db.insert('phones', {
          'number': '2100555501',
          'is_deleted': 0,
        });
        await integrity.softDeletePhoneForIntegrity(
          phoneId: phoneId,
          details: 'Tier 5b standalone',
        );
        final integrityAudits = await db.query(
          'audit_log',
          where: 'action = ?',
          whereArgs: [DatabaseHelper.auditActionIntegrityFix],
        );
        expect(integrityAudits, hasLength(1));
        expect(integrityAudits.single['details'], 'Tier 5b standalone');

        await db.delete('audit_log');
        final now = DateTime.now().toIso8601String();
        final taskId = await db.insert('tasks', {
          'title': 'Tier 5b Task',
          'status': 'open',
          'search_index': 'x',
          'caller_id': 9,
          'created_at': now,
          'updated_at': now,
          'is_deleted': 0,
        });

        final oldRow =
            await integrity.integrityUpdateTaskFk(db, taskId, 'caller_id', null);
        expect(oldRow!['caller_id'], 9);
        expect(
          (await db.query('tasks', where: 'id = ?', whereArgs: [taskId]))
              .single['caller_id'],
          isNull,
        );

        await expectLater(
          integrity.integrityUpdateTaskFk(db, taskId, 'invalid_field', 1),
          throwsA(isA<ArgumentError>()),
        );

        await db.delete('audit_log');
        await integrity.softDeleteTask(taskId);
        expect(
          (await db.query('tasks', where: 'id = ?', whereArgs: [taskId]))
              .single['is_deleted'],
          1,
        );
        final deleteAudits = await db.query(
          'audit_log',
          where: 'action = ? AND entity_id = ?',
          whereArgs: [DatabaseHelper.auditActionDelete, taskId],
        );
        expect(deleteAudits, hasLength(1));
        expect(deleteAudits.single['entity_type'], AuditEntityTypes.task);
      },
    );

    test(
      'Tier 5c — Phone/Equipment/User/Department/BuildingMap lookup paths',
      () async {
        final phones = PhoneRepository(db);
        final equipment = EquipmentRepository(db);
        final users = UserRepository(db);
        final departments = DepartmentRepository(db);
        final buildingMap = BuildingMapRepository(db, DirectorySupport(db));

        final deptId = await db.insert('departments', {
          'name': 'Τμήμα Tier 5c',
          'name_key': SearchTextNormalizer.normalizeForSearch('Τμήμα Tier 5c'),
          'is_deleted': 0,
        });
        final phoneId = await db.insert('phones', {
          'number': '2345111501',
          'department_id': deptId,
          'is_deleted': 0,
        });
        await db.insert('department_phones', {
          'department_id': deptId,
          'phone_id': phoneId,
        });
        final linkedPhoneId = await db.insert('phones', {
          'number': '2345111502',
          'is_deleted': 0,
        });
        final userId = await db.insert('users', {
          'first_name': 'Tier',
          'last_name': '5c',
          'is_deleted': 0,
        });
        await db.insert('user_phones', {
          'user_id': userId,
          'phone_id': linkedPhoneId,
        });

        final directMap = await phones.getDepartmentDirectPhonesMap();
        expect(directMap[deptId], contains('2345111501'));

        final catalog = await phones.getNonUserPhonesCatalogRows();
        expect(catalog.any((r) => r['phone_id'] == phoneId), isTrue);
        expect(catalog.any((r) => r['phone_id'] == linkedPhoneId), isFalse);

        final eqId = await equipment.insertEquipmentFromMap({
          'code_equipment': 'PC-TIER-5C',
          'department_id': deptId,
          'is_deleted': 0,
        });
        await equipment.replaceEquipmentUsers(eqId, [userId]);
        final sourceUserId = userId;
        final newUserId = await users.insertUser(
          firstName: 'Κλώνος',
          lastName: '5c',
        );
        await equipment.copyUserEquipmentLinks(sourceUserId, newUserId);
        expect(await equipment.countUsersLinkedToEquipment(eqId), 2);

        expect((await users.getAllUsers()).any((r) => r['id'] == newUserId), isTrue);
        expect((await equipment.getAllEquipment()).any((r) => r['id'] == eqId), isTrue);
        expect(
          (await equipment.getAllUserEquipmentLinks()).any(
            (r) => r['user_id'] == newUserId && r['equipment_id'] == eqId,
          ),
          isTrue,
        );

        final active = await departments.getActiveDepartments();
        expect(active.any((r) => r['id'] == deptId), isTrue);

        await db.insert('building_map_floors', {
          'sort_order': 0,
          'label': 'Όροφος Tier 5c',
          'image_path': 'f.png',
          'rotation_degrees': 0.0,
        });
        expect((await buildingMap.listBuildingMapFloors()), hasLength(1));
      },
    );

    test(
      'Tier 6 — Lamp migration repository paths',
      () async {
        final users = UserRepository(db);
        final equipment = EquipmentRepository(db);
        final departments = DepartmentRepository(db);

        final deptId = await departments.insertDepartment({
          'name': 'Τμήμα Tier 6',
          'name_key': SearchTextNormalizer.normalizeForSearch('Τμήμα Tier 6'),
          'is_deleted': 0,
        });
        final allDepts = await departments.getDepartments();
        expect(allDepts.any((r) => r['id'] == deptId), isTrue);

        final userId = await db.insert('users', {
          'first_name': 'Κάτοχος',
          'last_name': 'Tier6',
          'is_deleted': 0,
        });
        final eqId = await equipment.insertEquipmentFromMap({
          'code_equipment': 'PC-TIER-6',
          'is_deleted': 0,
        });
        await equipment.linkUserToEquipment(userId, eqId);

        final snapshots = await users.getEquipmentOwnerSnapshots(eqId);
        expect(snapshots.any((r) => r['id'] == userId), isTrue);

        final otherUserId = await db.insert('users', {
          'first_name': 'Άλλος',
          'last_name': 'Κάτοχος',
          'is_deleted': 0,
        });
        await equipment.linkUserToEquipment(otherUserId, eqId);
        await equipment.removeEquipmentFromAllUsers('PC-TIER-6');
        expect(await equipment.countUsersLinkedToEquipment(eqId), 0);

        await equipment.linkUserToEquipment(userId, eqId);
        await equipment.unlinkUserFromEquipment(userId, eqId);
        expect(await equipment.countUsersLinkedToEquipment(eqId), 0);
      },
    );
  });
}
