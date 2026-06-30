import 'dart:convert';
import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/directory_repository.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

/// Κλείδωμα συμπεριφοράς τηλεφώνων πριν από Φάση Γ.2γ (PhoneRepository).
void main() {
  group('PhoneRepository behavior — lock πριν εξαγωγή', () {
    late DirectoryRepository repo;
    late Database db;
    late int userId;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir =
          await Directory.systemTemp.createTemp('phone_repository_test_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/phone_repo.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('audit_log');
      await db.delete('user_phones');
      await db.delete('department_phones');
      await db.delete('phones');
      await db.delete('departments');
      await db.delete('users');
      userId = await db.insert('users', {
        'first_name': 'Κάτοχος',
        'last_name': 'Τηλεφώνου',
        'is_deleted': 0,
      });
      repo = DirectoryRepository(db);
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

    Map<String, dynamic>? decodeJson(String? raw) {
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
      return null;
    }

    test(
      'addDepartmentDirectPhone: department_phones, department_id, audit, idempotent',
      () async {
        const phoneNumber = '2310999901';
        final deptId = await insertDepartment('Τμήμα Direct Phone');

        await db.delete('audit_log');
        await repo.addDepartmentDirectPhone(deptId, phoneNumber);

        final phoneRows = await db.query(
          'phones',
          where: 'number = ?',
          whereArgs: [phoneNumber],
        );
        expect(phoneRows, hasLength(1));
        final phoneId = phoneRows.single['id'] as int;
        expect(phoneRows.single['department_id'], deptId);
        expect(phoneRows.single['is_deleted'], 0);

        final deptLinks = await db.query(
          'department_phones',
          where: 'phone_id = ?',
          whereArgs: [phoneId],
        );
        expect(deptLinks, hasLength(1));

        final auditAfterFirst = await db.query('audit_log');
        expect(auditAfterFirst, hasLength(1));

        await repo.addDepartmentDirectPhone(deptId, phoneNumber);

        expect(await db.query('phones', where: 'number = ?', whereArgs: [phoneNumber]),
            hasLength(1));
        expect(
          await db.query('department_phones', where: 'phone_id = ?', whereArgs: [phoneId]),
          hasLength(1),
        );
        expect(await db.query('audit_log'), hasLength(1));
      },
    );

    test('softDeletePhones / getPhoneIdByNumber / phoneNumberExists', () async {
      const phoneNumber = '2310999902';
      final phoneId = await db.insert('phones', {
        'number': phoneNumber,
        'is_deleted': 0,
      });

      expect(await repo.phoneNumberExists(phoneNumber), isTrue);
      expect(await repo.getPhoneIdByNumber(phoneNumber), phoneId);

      await db.delete('audit_log');
      await repo.softDeletePhones([phoneId]);

      expect(await repo.phoneNumberExists(phoneNumber), isFalse);
      expect(await repo.getPhoneIdByNumber(phoneNumber), isNull);

      final row = await db.query('phones', where: 'id = ?', whereArgs: [phoneId]);
      expect(row.single['is_deleted'], 1);

      final auditRows = await db.query(
        'audit_log',
        where: 'entity_id = ? AND action = ?',
        whereArgs: [phoneId, DatabaseHelper.auditActionDelete],
      );
      expect(auditRows, hasLength(1));
    });

    test('getDepartmentDirectPhonesMap', () async {
      final dept1 = await insertDepartment('Τμήμα Α');
      final dept2 = await insertDepartment('Τμήμα Β');
      const phoneA = '2310999903';
      const phoneB = '2310999904';

      await repo.addDepartmentDirectPhone(dept1, phoneA);
      await repo.addDepartmentDirectPhone(dept2, phoneB);

      final map = await repo.getDepartmentDirectPhonesMap();
      expect(map[dept1], contains(phoneA));
      expect(map[dept2], contains(phoneB));
    });

    test('updatePhoneDepartment: νέος αριθμός + audit', () async {
      const phoneNumber = '2310999905';
      final deptId = await insertDepartment('Τμήμα Νέου Αριθμού');

      await db.delete('audit_log');
      await repo.updatePhoneDepartment(phoneNumber, deptId);

      final phoneRows = await db.query(
        'phones',
        where: 'number = ?',
        whereArgs: [phoneNumber],
      );
      expect(phoneRows.single['department_id'], deptId);

      final phoneId = phoneRows.single['id'] as int;
      final auditRows = await db.query(
        'audit_log',
        where: 'entity_id = ?',
        whereArgs: [phoneId],
      );
      expect(auditRows, hasLength(1));
      final newV = decodeJson(auditRows.single['new_values_json'] as String?);
      expect(newV?['department_id'], deptId);
    });

    test('updatePhoneDepartment: υπάρχων αριθμός — audit old/new department', () async {
      const phoneNumber = '2310999906';
      final oldDeptId = await insertDepartment('Παλιό Τμήμα Phone');
      final newDeptId = await insertDepartment('Νέο Τμήμα Phone');

      final phoneId = await db.insert('phones', {
        'number': phoneNumber,
        'department_id': oldDeptId,
        'is_deleted': 0,
      });
      await db.insert('department_phones', {
        'department_id': oldDeptId,
        'phone_id': phoneId,
      });

      await db.delete('audit_log');
      await repo.updatePhoneDepartment(phoneNumber, newDeptId);

      final phoneRows = await db.query('phones', where: 'id = ?', whereArgs: [phoneId]);
      expect(phoneRows.single['department_id'], newDeptId);

      final deptLinks = await db.query(
        'department_phones',
        where: 'phone_id = ?',
        whereArgs: [phoneId],
      );
      expect(deptLinks.single['department_id'], newDeptId);

      final auditRows = await db.query(
        'audit_log',
        where: 'entity_id = ?',
        whereArgs: [phoneId],
      );
      expect(auditRows, hasLength(1));
      final oldV = decodeJson(auditRows.single['old_values_json'] as String?);
      final newV = decodeJson(auditRows.single['new_values_json'] as String?);
      expect(oldV?['department_id'], oldDeptId);
      expect(newV?['department_id'], newDeptId);
    });

    test('removePhoneFromAllUsers: audit + χωρίς executor', () async {
      const phoneNumber = '2310999907';
      final phoneId = await db.insert('phones', {
        'number': phoneNumber,
        'is_deleted': 0,
      });
      await db.insert('user_phones', {
        'user_id': userId,
        'phone_id': phoneId,
      });

      await db.delete('audit_log');
      await repo.removePhoneFromAllUsers(phoneNumber);

      expect(await db.query('user_phones', where: 'phone_id = ?', whereArgs: [phoneId]),
          isEmpty);

      final auditRows = await db.query(
        'audit_log',
        where: 'entity_id = ? AND details LIKE ?',
        whereArgs: [phoneId, '%αφαίρεση από χρήστη%'],
      );
      expect(auditRows, hasLength(1));
    });

    test('removePhoneFromAllUsers: executor awareness', () async {
      const phoneNumber = '2310999908';
      final phoneId = await db.insert('phones', {
        'number': phoneNumber,
        'is_deleted': 0,
      });
      await db.insert('user_phones', {
        'user_id': userId,
        'phone_id': phoneId,
      });

      await db.transaction((txn) async {
        await repo.removePhoneFromAllUsers(phoneNumber, executor: txn);
      });

      expect(await db.query('user_phones', where: 'phone_id = ?', whereArgs: [phoneId]),
          isEmpty);
    });

    test(
      'ατομικότητα: αποτυχία μέσα σε εξωτερική transaction κάνει rollback addDepartmentDirectPhone',
      () async {
        const phoneNumber = '2310999909';
        final deptId = await insertDepartment('Τμήμα Rollback Phone');

        await expectLater(
          db.transaction((txn) async {
            await repo.addDepartmentDirectPhone(
              deptId,
              phoneNumber,
              executor: txn,
            );
            throw StateError('προσομοίωση σφάλματος');
          }),
          throwsA(isA<StateError>()),
        );

        expect(
          await db.query('phones', where: 'number = ?', whereArgs: [phoneNumber]),
          isEmpty,
        );
        expect(await db.query('department_phones'), isEmpty);
      },
    );
  });
}
