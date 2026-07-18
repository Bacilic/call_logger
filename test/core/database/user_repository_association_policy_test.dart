// updateAssociationsIfNeeded σέβεται πολιτική τηλεφώνου ανά τμήμα.
//
//   flutter test test/core/database/user_repository_association_policy_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/user_repository.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/utils/phone_list_parser.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  late Directory tempDir;
  late Database db;
  late UserRepository users;

  setUp(() async {
    initSqfliteFfiForTests();
    tempDir = await Directory.systemTemp.createTemp('assoc_policy_');
    await DatabaseHelper.bindTestDatabaseFile('${tempDir.path}/assoc.db');
    db = await DatabaseHelper.instance.database;
    users = UserRepository(db);
    await seedIsolatedTestDatabase();
    await db.delete('audit_log');
    await db.delete('user_equipment');
    await db.delete('user_phones');
    await db.delete('department_phones');
    await db.delete('phones');
    await db.delete('equipment');
    await db.delete('users');
    await db.delete('departments');
  });

  tearDown(() async {
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<int> insertDept(String name) async {
    return db.insert('departments', {
      'name': name,
      'name_key': SearchTextNormalizer.normalizeForSearch(name),
      'is_deleted': 0,
    });
  }

  Future<int> insertUser({
    required String first,
    required String last,
    required int deptId,
    required String phone,
  }) async {
    final id = await users.insertUser(
      firstName: first,
      lastName: last,
      departmentId: deptId,
      phones: PhoneListParser.splitPhones(phone),
      skipPhonePolicyValidation: true,
    );
    return id;
  }

  Future<void> syncLookup(List<UserModel> userModels, List<DepartmentModel> depts) async {
    LookupService.instance.resetForReload();
    LookupService.instance.injectInMemoryCatalogForTests(
      users: userModels,
      equipment: const [],
      departmentRows: depts,
    );
  }

  Future<List<String>> phonesOf(int userId) async {
    final rows = await db.rawQuery(
      '''
      SELECT p.number AS number FROM user_phones up
      JOIN phones p ON p.id = up.phone_id
      WHERE up.user_id = ?
      ''',
      [userId],
    );
    return rows.map((r) => r['number'] as String).toList();
  }

  test(
    'updateAssociationsIfNeeded δεν συνδέει τηλέφωνο κατόχου άλλου τμήματος',
    () async {
      final deptA = await insertDept('Φαρμακείο');
      final deptB = await insertDept('Χειρουργείο');
      final ownerId = await insertUser(
        first: 'Κάτοχος',
        last: 'Αλλού',
        deptId: deptB,
        phone: '2531',
      );
      final targetId = await insertUser(
        first: 'Στόχος',
        last: 'Εδώ',
        deptId: deptA,
        phone: '9999',
      );

      await syncLookup(
        [
          UserModel(
            id: ownerId,
            firstName: 'Κάτοχος',
            lastName: 'Αλλού',
            phones: const ['2531'],
            departmentId: deptB,
          ),
          UserModel(
            id: targetId,
            firstName: 'Στόχος',
            lastName: 'Εδώ',
            phones: const ['9999'],
            departmentId: deptA,
          ),
        ],
        [
          DepartmentModel(id: deptA, name: 'Φαρμακείο'),
          DepartmentModel(id: deptB, name: 'Χειρουργείο'),
        ],
      );

      await users.updateAssociationsIfNeeded(targetId, '2531', null);

      final phones = await phonesOf(targetId);
      expect(phones, isNot(contains('2531')));
      expect(phones, contains('9999'));
    },
  );

  test(
    'updateAssociationsIfNeeded συνδέει τηλέφωνο συναδέλφου ίδιου τμήματος',
    () async {
      final deptA = await insertDept('Φαρμακείο');
      final colleagueId = await insertUser(
        first: 'Πρωινή',
        last: 'Βάρδια',
        deptId: deptA,
        phone: '2531',
      );
      final targetId = await insertUser(
        first: 'Απογευματινή',
        last: 'Βάρδια',
        deptId: deptA,
        phone: '8888',
      );

      await syncLookup(
        [
          UserModel(
            id: colleagueId,
            firstName: 'Πρωινή',
            lastName: 'Βάρδια',
            phones: const ['2531'],
            departmentId: deptA,
          ),
          UserModel(
            id: targetId,
            firstName: 'Απογευματινή',
            lastName: 'Βάρδια',
            phones: const ['8888'],
            departmentId: deptA,
          ),
        ],
        [DepartmentModel(id: deptA, name: 'Φαρμακείο')],
      );

      await users.updateAssociationsIfNeeded(targetId, '2531', null);

      final phones = await phonesOf(targetId);
      expect(phones, contains('2531'));
      expect(phones, contains('8888'));
    },
  );
}
