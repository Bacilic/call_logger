import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/directory_repository.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

/// Κλείδωμα δεδομένων πριν από ομογενοποίηση τύπων (Transaction→DatabaseExecutor, Map dynamic).
void main() {
  group('DirectoryRepository type homogenization — data lock', () {
    late DirectoryRepository repo;
    late Database db;
    late int deptId;
    late int userId;
    late int equipmentId;
    late int categoryId;
    late int linkedPhoneId;
    late int orphanPhoneId;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir =
          await Directory.systemTemp.createTemp('type_homogenization_test_');
      await DatabaseHelper.bindTestDatabaseFile(
        '${dir.path}/type_homogenization.db',
      );
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
      await db.delete('categories');
      await db.delete('departments');
      repo = DirectoryRepository(db);

      deptId = await db.insert('departments', {
        'name': 'Τμήμα Τύπων',
        'name_key': SearchTextNormalizer.normalizeForSearch('Τμήμα Τύπων'),
        'is_deleted': 0,
      });

      userId = await db.insert('users', {
        'first_name': 'Έλεγχος',
        'last_name': 'Τύπων',
        'department_id': deptId,
        'is_deleted': 0,
      });

      linkedPhoneId = await db.insert('phones', {
        'number': '2345999301',
        'is_deleted': 0,
      });
      await db.insert('user_phones', {
        'user_id': userId,
        'phone_id': linkedPhoneId,
      });

      orphanPhoneId = await db.insert('phones', {
        'number': '2345999302',
        'department_id': deptId,
        'is_deleted': 0,
      });

      equipmentId = await db.insert('equipment', {
        'code_equipment': 'PC-TYPE-LOCK',
        'department_id': deptId,
        'is_deleted': 0,
      });
      await db.insert('user_equipment', {
        'user_id': userId,
        'equipment_id': equipmentId,
      });

      categoryId = await db.insert('categories', {
        'name': 'Κατηγορία Τύπων',
        'is_deleted': 0,
      });
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    test('getAllUsers: σωστά κλειδιά, τιμές και πλήθος', () async {
      final users = await repo.getAllUsers();

      expect(users, hasLength(1));
      final row = users.single;
      expect(row['id'], userId);
      expect(row['first_name'], 'Έλεγχος');
      expect(row['last_name'], 'Τύπων');
      expect(row['department_id'], deptId);
      expect(row.containsKey('phones'), isTrue);
      expect(row['phones'], ['2345999301']);
    });

    test('getDepartmentRowById: σωστή εγγραφή τμήματος', () async {
      final row = await repo.getDepartmentRowById(deptId);

      expect(row, isNotNull);
      expect(row!['id'], deptId);
      expect(row['name'], 'Τμήμα Τύπων');
      expect(row.containsKey('name_key'), isTrue);
    });

    test('getActiveCategoryRows: μόνο ενεργές κατηγορίες', () async {
      await db.insert('categories', {
        'name': 'Διαγραμμένη',
        'is_deleted': 1,
      });

      final rows = await repo.getActiveCategoryRows();

      expect(rows, hasLength(1));
      expect(rows.single['id'], categoryId);
      expect(rows.single['name'], 'Κατηγορία Τύπων');
    });

    test('getAllEquipment: σωστός εξοπλισμός', () async {
      await db.insert('equipment', {
        'code_equipment': 'PC-DELETED',
        'is_deleted': 1,
      });

      final rows = await repo.getAllEquipment();

      expect(rows, hasLength(1));
      expect(rows.single['id'], equipmentId);
      expect(rows.single['code_equipment'], 'PC-TYPE-LOCK');
      expect(rows.single['department_id'], deptId);
    });

    test('getNonUserPhonesCatalogRows: μόνο τηλέφωνα χωρίς χρήστη', () async {
      final rows = await repo.getNonUserPhonesCatalogRows();

      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row['phone_id'], orphanPhoneId);
      expect(row['number'], '2345999302');
      expect(row.containsKey('dept_names'), isTrue);
      expect(row.containsKey('primary_department_id'), isTrue);
      expect(
        rows.every((r) => r['phone_id'] != linkedPhoneId),
        isTrue,
      );
    });
  });
}
