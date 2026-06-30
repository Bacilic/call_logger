import 'dart:convert';
import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/directory_repository.dart';
import 'package:call_logger/core/directory/phone_department_policy.dart';
import 'package:call_logger/core/services/audit_service.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

/// Κλείδωμα συμπεριφοράς χρηστών πριν από Φάση Γ.2δ (UserRepository).
void main() {
  group('UserRepository behavior — lock πριν εξαγωγή', () {
    late DirectoryRepository repo;
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir =
          await Directory.systemTemp.createTemp('user_repository_test_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/user_repo.db');
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
      repo = DirectoryRepository(db);
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Future<void> reloadLookup() async {
      LookupService.instance.resetForReload();
      await LookupService.instance.loadFromDatabase();
    }

    Map<String, dynamic>? decodeJson(String? raw) {
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
      return null;
    }

    Future<int> insertDepartment(String name) async {
      return db.insert('departments', {
        'name': name,
        'name_key': SearchTextNormalizer.normalizeForSearch(name),
        'is_deleted': 0,
      });
    }

    test('getAllUsers: μόνο ενεργοί, με σωστά συνδεδεμένα τηλέφωνα', () async {
      const phoneActive = '2346111101';
      const phoneDeleted = '2346111102';

      final activeId = await db.insert('users', {
        'first_name': 'Ενεργός',
        'last_name': 'Χρήστης',
        'is_deleted': 0,
      });
      await db.insert('users', {
        'first_name': 'Διαγραμμένος',
        'last_name': 'Χρήστης',
        'is_deleted': 1,
      });

      final phoneId = await db.insert('phones', {
        'number': phoneActive,
        'is_deleted': 0,
      });
      await db.insert('phones', {'number': phoneDeleted, 'is_deleted': 0});
      await db.insert('user_phones', {
        'user_id': activeId,
        'phone_id': phoneId,
      });

      final users = await repo.getAllUsers();
      expect(users, hasLength(1));
      expect(users.single['id'], activeId);
      expect(users.single['phones'], [phoneActive]);
    });

    test(
      'insertUser: τηλέφωνα + εξοπλισμό + τμήμα → users/user_phones/user_equipment + audit',
      () async {
        const phoneNumber = '2346111103';
        const eqCode = 'PC-USER-INSERT';
        final deptId = await insertDepartment('Τμήμα Insert User');

        final equipmentId = await db.insert('equipment', {
          'code_equipment': eqCode,
          'is_deleted': 0,
        });

        await db.delete('audit_log');
        final userId = await repo.insertUser(
          firstName: 'Νέος',
          lastName: 'Χρήστης',
          phones: [phoneNumber],
          departmentId: deptId,
          location: 'Αίθουσα 1',
          skipPhonePolicyValidation: true,
        );

        await db.insert('user_equipment', {
          'user_id': userId,
          'equipment_id': equipmentId,
        });

        final userRow = await db.query('users', where: 'id = ?', whereArgs: [userId]);
        expect(userRow.single['department_id'], deptId);
        expect(userRow.single['location'], 'Αίθουσα 1');

        expect(
          await db.query('user_phones', where: 'user_id = ?', whereArgs: [userId]),
          hasLength(1),
        );
        expect(
          await db.query(
            'user_equipment',
            where: 'user_id = ?',
            whereArgs: [userId],
          ),
          hasLength(1),
        );

        final createAudit = await db.query(
          'audit_log',
          where: 'action = ? AND entity_type = ? AND entity_id = ?',
          whereArgs: ['ΔΗΜΙΟΥΡΓΙΑ ΧΡΗΣΤΗ', AuditEntityTypes.user, userId],
        );
        expect(createAudit, hasLength(1));
        final nv = decodeJson(createAudit.single['new_values_json'] as String?);
        expect(nv?['linked_phone_numbers'], [phoneNumber]);
        expect(nv?['department_id'], deptId);
      },
    );

    test(
      'insertUser: δημιουργία τμήματος από όνομα μία φορά εντός ίδιας transaction',
      () async {
        const deptName = 'Νέο Τμήμα Από Όνομα';

        await db.delete('audit_log');
        await db.transaction((txn) async {
          await repo.insertUser(
            firstName: 'Txn',
            lastName: 'Dept',
            department: deptName,
            executor: txn,
            skipPhonePolicyValidation: true,
          );
        });

        final deptRows = await db.query('departments');
        expect(deptRows, hasLength(1));
        expect(deptRows.single['name'], deptName);

        await expectLater(
          db.transaction((txn) async {
            await repo.insertUser(
              firstName: 'Rollback',
              lastName: 'Dept',
              department: 'Τμήμα Rollback',
              executor: txn,
              skipPhonePolicyValidation: true,
            );
            throw StateError('rollback dept');
          }),
          throwsA(isA<StateError>()),
        );

        expect(await db.query('departments', where: 'name = ?', whereArgs: ['Τμήμα Rollback']),
            isEmpty);
      },
    );

    test(
      'updateUser: αλλαγή ονόματος/τμήματος/τηλεφώνων → link-delta audit + old/new department',
      () async {
        const oldPhone = '2346111104';
        const newPhone = '2346111105';
        final oldDeptId = await insertDepartment('Παλιό Τμήμα User');
        final newDeptId = await insertDepartment('Νέο Τμήμα User');

        final userId = await repo.insertUser(
          firstName: 'Παλιό',
          lastName: 'Όνομα',
          phones: [oldPhone],
          departmentId: oldDeptId,
          skipPhonePolicyValidation: true,
        );

        await db.delete('audit_log');
        await repo.updateUser(
          userId,
          {
            'first_name': 'Νέο',
            'department_id': newDeptId,
            'phones': [newPhone],
          },
          skipPhonePolicyValidation: true,
        );

        final userRow = await db.query('users', where: 'id = ?', whereArgs: [userId]);
        expect(userRow.single['first_name'], 'Νέο');
        expect(userRow.single['department_id'], newDeptId);

        final updateAudit = await db.query(
          'audit_log',
          where: 'action = ? AND entity_type = ? AND entity_id = ?',
          whereArgs: ['ΤΡΟΠΟΠΟΙΗΣΗ ΧΡΗΣΤΗ', AuditEntityTypes.user, userId],
        );
        expect(updateAudit, hasLength(1));

        final oldV = decodeJson(updateAudit.single['old_values_json'] as String?);
        final newV = decodeJson(updateAudit.single['new_values_json'] as String?);
        expect(oldV?['department_id'], oldDeptId);
        expect(oldV?['department_text'], 'Παλιό Τμήμα User');
        expect(newV?['department_id'], newDeptId);
        expect(newV?['department_text'], 'Νέο Τμήμα User');
        expect(oldV?['linked_phone_numbers'], [oldPhone]);
        expect(newV?['linked_phone_numbers'], [newPhone]);

        final newPhoneId = (await db.query(
          'phones',
          columns: ['id'],
          where: 'number = ?',
          whereArgs: [newPhone],
        ))
            .single['id'] as int;
        final linkAudit = await db.query(
          'audit_log',
          where:
              'action = ? AND entity_type = ? AND entity_id = ? AND details = ?',
          whereArgs: [
            'ΤΡΟΠΟΠΟΙΗΣΗ',
            AuditEntityTypes.phone,
            newPhoneId,
            'phones id=$newPhoneId (σύνδεση χρήστη)',
          ],
        );
        expect(linkAudit, hasLength(1));
      },
    );

    test('replaceUserPhones: υπάρχων + νέος αριθμός', () async {
      const existingNumber = '2346111106';
      const newNumber = '2346111107';

      final userId = await db.insert('users', {
        'first_name': 'Replace',
        'last_name': 'Phones',
        'is_deleted': 0,
      });
      await db.insert('phones', {'number': existingNumber, 'is_deleted': 0});

      await repo.replaceUserPhones(userId, [existingNumber, newNumber]);

      final links = await db.query(
        'user_phones',
        where: 'user_id = ?',
        whereArgs: [userId],
      );
      expect(links, hasLength(2));
      expect(
        await db.query('phones', where: 'number = ?', whereArgs: [existingNumber]),
        hasLength(1),
      );
    });

    test('deleteUsers: soft-delete + αποσύνδεση + audit· restoreUsers', () async {
      const phoneNumber = '2346111108';
      const eqCode = 'PC-DELETE-USER';

      final equipmentId = await db.insert('equipment', {
        'code_equipment': eqCode,
        'is_deleted': 0,
      });
      final userId = await repo.insertUser(
        firstName: 'Διαγραφή',
        lastName: 'Χρήστη',
        phones: [phoneNumber],
        skipPhonePolicyValidation: true,
      );
      await db.insert('user_equipment', {
        'user_id': userId,
        'equipment_id': equipmentId,
      });

      await db.delete('audit_log');
      await repo.deleteUsers([userId]);

      final userRow = await db.query('users', where: 'id = ?', whereArgs: [userId]);
      expect(userRow.single['is_deleted'], 1);
      expect(await db.query('user_phones', where: 'user_id = ?', whereArgs: [userId]),
          isEmpty);
      expect(
        await db.query('user_equipment', where: 'user_id = ?', whereArgs: [userId]),
        isEmpty,
      );

      final deleteAudit = await db.query(
        'audit_log',
        where: 'action = ? AND entity_type = ? AND entity_id = ?',
        whereArgs: [DatabaseHelper.auditActionDelete, AuditEntityTypes.user, userId],
      );
      expect(deleteAudit, hasLength(1));

      await db.delete('audit_log');
      await repo.restoreUsers([userId]);

      expect(
        (await db.query('users', where: 'id = ?', whereArgs: [userId])).single['is_deleted'],
        0,
      );
      final restoreAudit = await db.query(
        'audit_log',
        where: 'action = ? AND entity_type = ? AND entity_id = ?',
        whereArgs: [DatabaseHelper.auditActionRestore, AuditEntityTypes.user, userId],
      );
      expect(restoreAudit, hasLength(1));
    });

    test(
      'phone assignment policy: επιτρέπεται ίδιο τμήμα· απορρίπτεται cross-department',
      () async {
        const sharedPhone = '2346111109';
        final deptA = await insertDepartment('Τμήμα Policy A');
        final deptB = await insertDepartment('Τμήμα Policy B');

        await repo.addDepartmentDirectPhone(deptA, sharedPhone);
        await reloadLookup();

        final allowedId = await repo.insertUser(
          firstName: 'Επιτρεπτός',
          lastName: 'Χρήστης',
          phones: [sharedPhone],
          departmentId: deptA,
        );
        expect(allowedId, greaterThan(0));

        await reloadLookup();

        await expectLater(
          repo.insertUser(
            firstName: 'Απορριπτέος',
            lastName: 'Χρήστης',
            phones: [sharedPhone],
            departmentId: deptB,
          ),
          throwsA(isA<PhoneDepartmentPolicyException>()),
        );
      },
    );

    test(
      'ατομικότητα: αποτυχία μέσα σε εξωτερική transaction κάνει rollback insertUser',
      () async {
        await expectLater(
          db.transaction((txn) async {
            await repo.insertUser(
              firstName: 'Rollback',
              lastName: 'Insert',
              phones: ['2346111110'],
              executor: txn,
              skipPhonePolicyValidation: true,
            );
            throw StateError('rollback insert');
          }),
          throwsA(isA<StateError>()),
        );

        expect(await db.query('users'), isEmpty);
        expect(await db.query('user_phones'), isEmpty);
      },
    );

    test(
      'ατομικότητα: αποτυχία μέσα σε εξωτερική transaction κάνει rollback updateUser',
      () async {
        final userId = await repo.insertUser(
          firstName: 'Rollback',
          lastName: 'Update',
          skipPhonePolicyValidation: true,
        );

        await expectLater(
          db.transaction((txn) async {
            await repo.updateUser(
              userId,
              {'notes': 'θα γίνει rollback'},
              executor: txn,
              skipPhonePolicyValidation: true,
            );
            throw StateError('rollback update');
          }),
          throwsA(isA<StateError>()),
        );

        final row = await db.query('users', where: 'id = ?', whereArgs: [userId]);
        expect(row.single['notes'], isNull);
      },
    );
  });
}
