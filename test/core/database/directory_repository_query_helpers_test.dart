import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/directory_repository.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

/// Κλείδωμα συμπεριφοράς COALESCE clause, IN-placeholders και PRAGMA phones columns.
void main() {
  group('DirectoryRepository query helpers — lock', () {
    late DirectoryRepository repo;
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('query_helpers_test_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/query_helpers.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('user_phones');
      await db.delete('department_phones');
      await db.delete('phones');
      await db.delete('user_equipment');
      await db.delete('equipment');
      await db.delete('users');
      await db.delete('departments');
      repo = DirectoryRepository(db);
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    test('soft-delete: getAllUsers / getActiveDepartments / getAllEquipment μόνο ενεργές',
        () async {
      final activeDeptId = await db.insert('departments', {
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

      final activeUserId = await db.insert('users', {
        'first_name': 'Ενεργός',
        'last_name': 'Χρήστης',
        'department_id': activeDeptId,
        'is_deleted': 0,
      });
      await db.insert('users', {
        'first_name': 'Διαγραμμένος',
        'last_name': 'Χρήστης',
        'department_id': activeDeptId,
        'is_deleted': 1,
      });

      await db.insert('equipment', {
        'code_equipment': 'PC-ACTIVE',
        'is_deleted': 0,
      });
      await db.insert('equipment', {
        'code_equipment': 'PC-DELETED',
        'is_deleted': 1,
      });

      final users = await repo.getAllUsers();
      final departments = await repo.getActiveDepartments();
      final equipment = await repo.getAllEquipment();

      expect(users, hasLength(1));
      expect(users.single['id'], activeUserId);
      expect(departments, hasLength(1));
      expect(departments.single['id'], activeDeptId);
      expect(equipment, hasLength(1));
      expect(equipment.single['code_equipment'], 'PC-ACTIVE');
    });

    test('IN-placeholders: findExclusivePhonesForUserDelete για 0, 1 και πολλά id',
        () async {
      Future<void> linkPhone(int userId, String number) async {
        final phoneId = await db.insert('phones', {'number': number});
        await db.insert('user_phones', {
          'user_id': userId,
          'phone_id': phoneId,
        });
      }

      final userA = await db.insert('users', {
        'first_name': 'Α',
        'last_name': 'Μόνος',
        'is_deleted': 0,
      });
      final userB = await db.insert('users', {
        'first_name': 'Β',
        'last_name': 'Κοινό',
        'is_deleted': 0,
      });
      final userC = await db.insert('users', {
        'first_name': 'Γ',
        'last_name': 'Κοινό',
        'is_deleted': 0,
      });

      await linkPhone(userA, '2345999101');
      final sharedPhoneId = await db.insert('phones', {'number': '2345999102'});
      await db.insert('user_phones', {
        'user_id': userB,
        'phone_id': sharedPhoneId,
      });
      await db.insert('user_phones', {
        'user_id': userC,
        'phone_id': sharedPhoneId,
      });
      await linkPhone(userB, '2345999103');

      expect(await repo.findExclusivePhonesForUserDelete([]), isEmpty);

      final one = await repo.findExclusivePhonesForUserDelete([userA]);
      expect(one, hasLength(1));
      expect(one.single.userId, userA);
      expect(one.single.number, '2345999101');

      final many = await repo.findExclusivePhonesForUserDelete([userA, userB]);
      expect(many, hasLength(2));
      expect(
        many.map((e) => e.number).toSet(),
        {'2345999101', '2345999103'},
      );
      expect(many.every((e) => e.number != '2345999102'), isTrue);
    });

    test('PRAGMA phones columns: διπλή κλήση updatePhoneDepartment χωρίς σφάλμα',
        () async {
      const phoneNumber = '2345999201';
      final deptId = await db.insert('departments', {
        'name': 'Τμήμα PRAGMA',
        'name_key': SearchTextNormalizer.normalizeForSearch('Τμήμα PRAGMA'),
        'is_deleted': 0,
      });

      await repo.updatePhoneDepartment(phoneNumber, deptId);
      await repo.updatePhoneDepartment(phoneNumber, deptId);

      final info = await db.rawQuery('PRAGMA table_info(phones)');
      final names = info.map((r) => r['name'] as String).toSet();
      expect(names, contains('department_id'));
      expect(names, contains('is_deleted'));

      final row = await db.query(
        'phones',
        where: 'number = ?',
        whereArgs: [phoneNumber],
        limit: 1,
      );
      expect(row, hasLength(1));
      expect(row.single['department_id'], deptId);
    });
  });
}
