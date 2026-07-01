import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/integrity_service.dart';
import 'package:call_logger/core/services/audit_service.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

/// Κλείδωμα συμπεριφοράς integrity πριν από Φάση Γ.3β (IntegrityService).
void main() {
  group('Integrity behavior — lock πριν εξαγωγή', () {
    late IntegrityService repo;
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir =
          await Directory.systemTemp.createTemp('integrity_service_test_');
      await DatabaseHelper.bindTestDatabaseFile(
        '${dir.path}/integrity_service.db',
      );
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('audit_log');
      await db.delete('call_external_links');
      await db.delete('user_equipment');
      await db.delete('department_phones');
      await db.delete('user_phones');
      await db.delete('phones');
      await db.delete('tasks');
      await db.delete('equipment');
      await db.delete('users');
      await db.delete('departments');
      await db.insert(
        'app_settings',
        {
          'key': DatabaseHelper.auditUserPerformingSettingsKey,
          'value': 'Tester Integrity',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      repo = IntegrityService(db);
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Future<List<Map<String, dynamic>>> integrityAuditRows() => db.query(
          'audit_log',
          where: 'action = ?',
          whereArgs: [DatabaseHelper.auditActionIntegrityFix],
          orderBy: 'id ASC',
        );

    test('softDeletePhoneForIntegrity: καθαρισμός junctions + is_deleted + audit',
        () async {
      final deptId = await db.insert('departments', {
        'name': 'Τμήμα Τηλ',
        'name_key': SearchTextNormalizer.normalizeForSearch('Τμήμα Τηλ'),
        'is_deleted': 0,
      });
      final userId = await db.insert('users', {
        'first_name': 'Χ',
        'last_name': 'Ρήστης',
        'is_deleted': 0,
      });
      final phoneId = await db.insert('phones', {
        'number': '21009999',
        'department_id': deptId,
        'is_deleted': 0,
      });
      await db.insert('department_phones', {
        'department_id': deptId,
        'phone_id': phoneId,
      });
      await db.insert('user_phones', {
        'user_id': userId,
        'phone_id': phoneId,
      });

      await repo.softDeletePhoneForIntegrity(
        phoneId: phoneId,
        details: 'test soft delete phone',
      );

      expect(await db.query('department_phones', where: 'phone_id = ?', whereArgs: [phoneId]), isEmpty);
      expect(await db.query('user_phones', where: 'phone_id = ?', whereArgs: [phoneId]), isEmpty);
      final phoneRow = await db.query('phones', where: 'id = ?', whereArgs: [phoneId]);
      expect(phoneRow.single['is_deleted'], 1);
      expect(phoneRow.single['department_id'], isNull);

      final audits = await integrityAuditRows();
      expect(audits, hasLength(1));
      expect(audits.single['action'], DatabaseHelper.auditActionIntegrityFix);
      expect(audits.single['user_performing'], 'Tester Integrity');
      expect(audits.single['entity_type'], AuditEntityTypes.phone);
      expect(audits.single['entity_id'], phoneId);
      expect(audits.single['details'], 'test soft delete phone');
    });

    test('deleteOrphanUserPhonesJunction: αφαιρεί σύνδεση + audit', () async {
      final userId = await db.insert('users', {
        'first_name': 'Orphan',
        'last_name': 'User',
        'is_deleted': 1,
      });
      final phoneId = await db.insert('phones', {'number': '2200', 'is_deleted': 0});
      await db.insert('user_phones', {'user_id': userId, 'phone_id': phoneId});

      await repo.deleteOrphanUserPhonesJunction(
        userId: userId,
        phoneId: phoneId,
        details: 'orphan user_phones',
      );

      expect(
        await db.query('user_phones', where: 'user_id = ? AND phone_id = ?', whereArgs: [userId, phoneId]),
        isEmpty,
      );
      final audits = await integrityAuditRows();
      expect(audits, hasLength(1));
      expect(audits.single['entity_type'], AuditEntityTypes.phone);
      expect(audits.single['entity_id'], phoneId);
    });

    test('deleteOrphanDepartmentPhonesJunction: αφαιρεί σύνδεση + audit', () async {
      final deptId = await db.insert('departments', {
        'name': 'Διαγραμμένο',
        'name_key': 'διαγραμμενο',
        'is_deleted': 1,
      });
      final phoneId = await db.insert('phones', {'number': '2300', 'is_deleted': 0});
      await db.insert('department_phones', {
        'department_id': deptId,
        'phone_id': phoneId,
      });

      await repo.deleteOrphanDepartmentPhonesJunction(
        departmentId: deptId,
        phoneId: phoneId,
        details: 'orphan department_phones',
      );

      expect(
        await db.query(
          'department_phones',
          where: 'department_id = ? AND phone_id = ?',
          whereArgs: [deptId, phoneId],
        ),
        isEmpty,
      );
      expect(await integrityAuditRows(), hasLength(1));
    });

    test('deleteOrphanUserEquipmentJunction: αφαιρεί σύνδεση + audit', () async {
      final userId = await db.insert('users', {
        'first_name': 'X',
        'last_name': 'Y',
        'is_deleted': 1,
      });
      final eqId = await db.insert('equipment', {
        'code_equipment': 'EQ-ORPH',
        'is_deleted': 0,
      });
      await db.insert('user_equipment', {
        'user_id': userId,
        'equipment_id': eqId,
      });

      await repo.deleteOrphanUserEquipmentJunction(
        userId: userId,
        equipmentId: eqId,
        details: 'orphan user_equipment',
      );

      expect(
        await db.query(
          'user_equipment',
          where: 'user_id = ? AND equipment_id = ?',
          whereArgs: [userId, eqId],
        ),
        isEmpty,
      );
      final audits = await integrityAuditRows();
      expect(audits.single['entity_type'], AuditEntityTypes.equipment);
      expect(audits.single['entity_id'], eqId);
    });

    test('linkOrphanPhoneToDepartmentForIntegrity: department_id + junction + audit',
        () async {
      final deptId = await db.insert('departments', {
        'name': 'Στόχος',
        'name_key': 'στοχος',
        'is_deleted': 0,
      });
      final phoneId = await db.insert('phones', {
        'number': '2400',
        'is_deleted': 1,
      });

      await repo.linkOrphanPhoneToDepartmentForIntegrity(
        phoneId: phoneId,
        departmentId: deptId,
        details: 'link phone to dept',
      );

      final phoneRow = await db.query('phones', where: 'id = ?', whereArgs: [phoneId]);
      expect(phoneRow.single['department_id'], deptId);
      expect(phoneRow.single['is_deleted'], 0);
      final junction = await db.query(
        'department_phones',
        where: 'department_id = ? AND phone_id = ?',
        whereArgs: [deptId, phoneId],
      );
      expect(junction, hasLength(1));
      expect(await integrityAuditRows(), hasLength(1));
    });

    test('linkOrphanPhoneToUserForIntegrity: προσθήκη τηλεφώνου σε χρήστη + audit',
        () async {
      final userId = await db.insert('users', {
        'first_name': 'Νέος',
        'last_name': 'Χρήστης',
        'is_deleted': 0,
      });
      final phoneId = await db.insert('phones', {
        'number': '2500',
        'is_deleted': 0,
      });

      await repo.linkOrphanPhoneToUserForIntegrity(
        phoneId: phoneId,
        userId: userId,
        details: 'link phone to user',
      );

      final links = await db.query(
        'user_phones',
        where: 'user_id = ? AND phone_id = ?',
        whereArgs: [userId, phoneId],
      );
      expect(links, hasLength(1));
      final audits = await integrityAuditRows();
      expect(audits, hasLength(1));
      expect(audits.single['entity_name'], '2500');
    });

    test('softDeleteUserForIntegrity: deleteUsers + ξεχωριστό audit integrity-fix',
        () async {
      final userId = await db.insert('users', {
        'first_name': 'Διαγραφή',
        'last_name': 'Integrity',
        'is_deleted': 0,
      });

      await repo.softDeleteUserForIntegrity(
        userId: userId,
        details: 'soft delete user integrity',
      );

      final row = await db.query('users', where: 'id = ?', whereArgs: [userId]);
      expect(row.single['is_deleted'], 1);

      final integrityAudits = await integrityAuditRows();
      expect(integrityAudits, hasLength(1));
      expect(integrityAudits.single['entity_type'], AuditEntityTypes.user);
      expect(integrityAudits.single['entity_id'], userId);
      expect(integrityAudits.single['details'], 'soft delete user integrity');

      final deleteAudits = await db.query(
        'audit_log',
        where: 'action = ? AND entity_id = ?',
        whereArgs: [DatabaseHelper.auditActionDelete, userId],
      );
      expect(deleteAudits, hasLength(1));
    });

    test('updateUserDepartmentForIntegrity: updateUser + ξεχωριστό audit integrity-fix',
        () async {
      final deptId = await db.insert('departments', {
        'name': 'Νέο Τμήμα',
        'name_key': 'νεο τμημα',
        'is_deleted': 0,
      });
      final userId = await db.insert('users', {
        'first_name': 'Μετακίνηση',
        'last_name': 'Χρήστη',
        'department_id': null,
        'is_deleted': 0,
      });

      await repo.updateUserDepartmentForIntegrity(
        userId: userId,
        departmentId: deptId,
        details: 'assign department',
      );

      final row = await db.query('users', where: 'id = ?', whereArgs: [userId]);
      expect(row.single['department_id'], deptId);

      final audits = await integrityAuditRows();
      expect(audits, hasLength(1));
      expect(audits.single['entity_id'], userId);
      expect(audits.single['details'], 'assign department');
    });

    test('fixDepartmentNameKeyForIntegrity: ενημέρωση name_key + audit', () async {
      final deptId = await db.insert('departments', {
        'name': 'Παλιό Όνομα',
        'name_key': 'παλιο',
        'is_deleted': 0,
      });

      await repo.fixDepartmentNameKeyForIntegrity(
        departmentId: deptId,
        nameKey: 'νεο κλειδι',
        details: 'fix name_key',
      );

      final row = await db.query('departments', where: 'id = ?', whereArgs: [deptId]);
      expect(row.single['name_key'], 'νεο κλειδι');
      final audits = await integrityAuditRows();
      expect(audits.single['entity_type'], AuditEntityTypes.department);
      expect(audits.single['entity_id'], deptId);
    });

    test('integrityDepartmentLabel: ενεργό / διαγραμμένο / ανύπαρκτο / null', () async {
      expect(await repo.integrityDepartmentLabel(db, null), '—');

      final activeId = await db.insert('departments', {
        'name': 'Ενεργό',
        'name_key': 'ενεργο',
        'is_deleted': 0,
      });
      expect(
        await repo.integrityDepartmentLabel(db, activeId),
        'Τμήμα Ενεργό [Ενεργό] (ID $activeId)',
      );

      final deletedId = await db.insert('departments', {
        'name': 'Παλιό',
        'name_key': 'παλιο',
        'is_deleted': 1,
      });
      expect(
        await repo.integrityDepartmentLabel(db, deletedId),
        contains('[Διαγραμμένο]'),
      );

      expect(
        await repo.integrityDepartmentLabel(db, 99999),
        'Τμήμα ID 99999 [Ανύπαρκτο]',
      );
    });

    test('integrityUserLabel: ενεργός / διαγραμμένος / ανύπαρκτος / null', () async {
      expect(await repo.integrityUserLabel(db, null), '—');

      final activeId = await db.insert('users', {
        'first_name': 'Γιάννης',
        'last_name': 'Δοκιμή',
        'is_deleted': 0,
      });
      expect(
        await repo.integrityUserLabel(db, activeId),
        'Χρήστης Γιάννης Δοκιμή [Ενεργός] (ID $activeId)',
      );

      final deletedId = await db.insert('users', {
        'first_name': 'Παλιός',
        'last_name': 'Χρήστης',
        'is_deleted': 1,
      });
      expect(
        await repo.integrityUserLabel(db, deletedId),
        contains('[Διαγραμμένος]'),
      );

      expect(
        await repo.integrityUserLabel(db, 88888),
        'Χρήστης ID 88888 [Ανύπαρκτος]',
      );
    });

    test('integrityUpdateTaskFk: έγκυρο πεδίο ενημερώνει + επιστρέφει παλιά γραμμή',
        () async {
      final now = DateTime.now().toIso8601String();
      final taskId = await db.insert('tasks', {
        'title': 'FK task',
        'status': 'open',
        'search_index': 'x',
        'caller_id': 5,
        'created_at': now,
        'updated_at': now,
        'is_deleted': 0,
      });

      final oldRow = await repo.integrityUpdateTaskFk(db, taskId, 'caller_id', null);
      expect(oldRow, isNotNull);
      expect(oldRow!['caller_id'], 5);

      final updated = await db.query('tasks', where: 'id = ?', whereArgs: [taskId]);
      expect(updated.single['caller_id'], isNull);
    });

    test('integrityUpdateTaskFk: άκυρο πεδίο → ArgumentError', () async {
      await expectLater(
        repo.integrityUpdateTaskFk(db, 1, 'invalid_field', 1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('integritySyncTaskTimestamps: updated_at = created_at', () async {
      final created = '2026-06-10T12:00:00.000';
      final updated = '2026-06-09T12:00:00.000';
      final taskId = await db.insert('tasks', {
        'title': 'sync task',
        'status': 'open',
        'search_index': 'x',
        'created_at': created,
        'updated_at': updated,
        'is_deleted': 0,
      });

      final oldRow = await repo.integritySyncTaskTimestamps(db, taskId);
      expect(oldRow, isNotNull);
      expect(oldRow!['updated_at'], updated);

      final row = await db.query('tasks', where: 'id = ?', whereArgs: [taskId]);
      expect(row.single['updated_at'], created);
    });

    test('softDeleteTask: is_deleted=1 + audit ΔΙΑΓΡΑΦΗ', () async {
      final now = DateTime.now().toIso8601String();
      final taskId = await db.insert('tasks', {
        'title': 'Διαγραφή Task',
        'status': 'open',
        'search_index': 'x',
        'created_at': now,
        'updated_at': now,
        'is_deleted': 0,
      });

      await repo.softDeleteTask(taskId);

      final row = await db.query('tasks', where: 'id = ?', whereArgs: [taskId]);
      expect(row.single['is_deleted'], 1);

      final audits = await db.query(
        'audit_log',
        where: 'action = ? AND entity_id = ?',
        whereArgs: [DatabaseHelper.auditActionDelete, taskId],
      );
      expect(audits, hasLength(1));
      expect(audits.single['entity_type'], AuditEntityTypes.task);
      expect(audits.single['entity_name'], 'Διαγραφή Task');
    });
  });
}
