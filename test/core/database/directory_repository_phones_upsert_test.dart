import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/phone_repository.dart';
import 'package:call_logger/core/database/user_repository.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

/// Κλείδωμα συμπεριφοράς upsert τηλεφώνου (insert ignore + lookup id) πριν από Φάση Β.
void main() {
  group('DirectoryRepository phone upsert pattern — lock', () {
    late UserRepository users;
    late PhoneRepository phones;
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('phones_upsert_test_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/phones_upsert.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('user_phones');
      await db.delete('department_phones');
      await db.delete('phones');
      await db.delete('users');
      await db.delete('departments');
      users = UserRepository(db);
      phones = PhoneRepository(db);
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
      'replaceUserPhones: υπάρχων + νέος αριθμός, χωρίς διπλότυπο phones, σωστά user_phones',
      () async {
        const existingNumber = '2345777701';
        const newNumber = '2345777702';

        final existingPhoneId = await db.insert('phones', {
          'number': existingNumber,
          'is_deleted': 0,
        });
        final userId = await db.insert('users', {
          'first_name': 'Upsert',
          'last_name': 'Χρήστης',
          'is_deleted': 0,
        });

        await users.replaceUserPhones(userId, [existingNumber, newNumber]);

        final phonesForExisting = await db.query(
          'phones',
          where: 'number = ?',
          whereArgs: [existingNumber],
        );
        expect(phonesForExisting, hasLength(1));
        expect(phonesForExisting.single['id'], existingPhoneId);

        final phonesForNew = await db.query(
          'phones',
          where: 'number = ?',
          whereArgs: [newNumber],
        );
        expect(phonesForNew, hasLength(1));

        final links = await db.query(
          'user_phones',
          where: 'user_id = ?',
          whereArgs: [userId],
        );
        expect(links, hasLength(2));
        final linkedPhoneIds =
            links.map((r) => r['phone_id'] as int).toSet();
        expect(linkedPhoneIds, contains(existingPhoneId));
        expect(linkedPhoneIds, contains(phonesForNew.single['id'] as int));
      },
    );

    test(
      'addDepartmentDirectPhone: department_id, is_deleted=0, department_phones',
      () async {
        const phoneNumber = '2310888801';
        final deptId = await insertDepartment('Τμήμα Upsert Τηλεφώνου');

        await phones.addDepartmentDirectPhone(deptId, phoneNumber);

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
        expect(deptLinks.single['department_id'], deptId);
      },
    );

    test(
      'updatePhoneDepartment: νέος αριθμός — department_id και department_phones',
      () async {
        const phoneNumber = '2310888802';
        final deptId = await insertDepartment('Τμήμα Update Νέου');

        await phones.updatePhoneDepartment(phoneNumber, deptId);

        final phoneRows = await db.query(
          'phones',
          where: 'number = ?',
          whereArgs: [phoneNumber],
        );
        expect(phoneRows, hasLength(1));
        final phoneId = phoneRows.single['id'] as int;
        expect(phoneRows.single['department_id'], deptId);

        final deptLinks = await db.query(
          'department_phones',
          where: 'phone_id = ?',
          whereArgs: [phoneId],
        );
        expect(deptLinks, hasLength(1));
        expect(deptLinks.single['department_id'], deptId);
      },
    );

    test(
      'updatePhoneDepartment: υπάρχων αριθμός — ενημέρωση department_id και department_phones',
      () async {
        const phoneNumber = '2310888803';
        final oldDeptId = await insertDepartment('Παλιό Τμήμα');
        final newDeptId = await insertDepartment('Νέο Τμήμα');

        final phoneId = await db.insert('phones', {
          'number': phoneNumber,
          'department_id': oldDeptId,
          'is_deleted': 0,
        });
        await db.insert('department_phones', {
          'department_id': oldDeptId,
          'phone_id': phoneId,
        });

        await phones.updatePhoneDepartment(phoneNumber, newDeptId);

        final phoneRows = await db.query(
          'phones',
          where: 'number = ?',
          whereArgs: [phoneNumber],
        );
        expect(phoneRows, hasLength(1));
        expect(phoneRows.single['id'], phoneId);
        expect(phoneRows.single['department_id'], newDeptId);

        final deptLinks = await db.query(
          'department_phones',
          where: 'phone_id = ?',
          whereArgs: [phoneId],
        );
        expect(deptLinks, hasLength(1));
        expect(deptLinks.single['department_id'], newDeptId);
      },
    );
  });
}
