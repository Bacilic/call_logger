// Η κοινή εκτέλεση του «μένει πίσω»: την καλούν η φόρμα υπαλλήλου και η
// γρήγορη προσθήκη της κλήσης.
//
//   flutter test test/core/directory/department_change_assets_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/user_repository.dart';
import 'package:call_logger/core/directory/department_change_assets.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/calls/models/equipment_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('applyAssetsStayingBehind — τι μένει στο τμήμα που αφήνει ο υπάλληλος',
      () {
    late Database db;
    late UserRepository users;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp(
        'department_change_assets_test_',
      );
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/assets.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('user_equipment');
      await db.delete('user_phones');
      await db.delete('department_phones');
      await db.delete('phones');
      await db.delete('equipment');
      await db.delete('users');
      await db.delete('departments');
      users = UserRepository(db);
    });

    Future<int> insertDepartment(String name) {
      return db.insert('departments', {
        'name': name,
        'name_key': SearchTextNormalizer.normalizeForSearch(name),
        'is_deleted': 0,
      });
    }

    Future<List<String>> phonesOfUser(int userId) async {
      final rows = await db.rawQuery(
        'SELECT p.number FROM user_phones up '
        'JOIN phones p ON p.id = up.phone_id WHERE up.user_id = ?',
        [userId],
      );
      return [for (final r in rows) r['number'] as String];
    }

    test('το τηλέφωνο φεύγει από τον υπάλληλο και μένει στο τμήμα', () async {
      final deptOld = await insertDepartment('Αιμοδοσία');
      final userId = await users.insertUser(
        firstName: 'Σοφία',
        lastName: 'Σπυροπούλου',
        phones: const ['2511'],
        departmentId: deptOld,
        skipPhonePolicyValidation: true,
      );

      await applyAssetsStayingBehind(
        db: db,
        userId: userId,
        oldDepartmentId: deptOld,
        phones: const ['2511'],
        currentPhones: const ['2511'],
      );

      expect(await phonesOfUser(userId), isEmpty);

      final shared = await db.rawQuery(
        'SELECT dp.department_id FROM department_phones dp '
        'JOIN phones p ON p.id = dp.phone_id WHERE p.number = ?',
        ['2511'],
      );
      expect(shared.map((r) => r['department_id']), contains(deptOld));
    });

    test('όσα ΔΕΝ μένουν πίσω παραμένουν στον υπάλληλο', () async {
      final deptOld = await insertDepartment('Αιμοδοσία');
      final userId = await users.insertUser(
        firstName: 'Σοφία',
        lastName: 'Σπυροπούλου',
        phones: const ['2511', '2200'],
        departmentId: deptOld,
        skipPhonePolicyValidation: true,
      );

      await applyAssetsStayingBehind(
        db: db,
        userId: userId,
        oldDepartmentId: deptOld,
        phones: const ['2511'],
        currentPhones: const ['2511', '2200'],
      );

      expect(await phonesOfUser(userId), ['2200']);
    });

    test('το μηχάνημα αποδεσμεύεται και δεν μένει ορφανό', () async {
      final deptOld = await insertDepartment('Αιμοδοσία');
      final userId = await users.insertUser(
        firstName: 'Σοφία',
        lastName: 'Σπυροπούλου',
        departmentId: deptOld,
        skipPhonePolicyValidation: true,
      );
      final eqId = await db.insert('equipment', {
        'code_equipment': '3564',
        'is_deleted': 0,
      });
      await db.insert('user_equipment', {
        'user_id': userId,
        'equipment_id': eqId,
      });

      await applyAssetsStayingBehind(
        db: db,
        userId: userId,
        oldDepartmentId: deptOld,
        equipment: [EquipmentModel(id: eqId, code: '3564')],
      );

      final owners = await db.rawQuery(
        'SELECT user_id FROM user_equipment WHERE equipment_id = ?',
        [eqId],
      );
      expect(owners, isEmpty, reason: 'ο υπάλληλος δεν το κρατά πια');

      final rows = await db.query(
        'equipment',
        columns: ['department_id'],
        where: 'id = ?',
        whereArgs: [eqId],
      );
      expect(
        rows.single['department_id'],
        deptOld,
        reason: 'ο εξοπλισμός δεν μένει ποτέ ορφανός',
      );
    });

    test('χωρίς αποφάσεις δεν αγγίζει τίποτα', () async {
      final deptOld = await insertDepartment('Αιμοδοσία');
      final userId = await users.insertUser(
        firstName: 'Σοφία',
        lastName: 'Σπυροπούλου',
        phones: const ['2511'],
        departmentId: deptOld,
        skipPhonePolicyValidation: true,
      );

      await applyAssetsStayingBehind(
        db: db,
        userId: userId,
        oldDepartmentId: deptOld,
        currentPhones: const ['2511'],
      );

      expect(await phonesOfUser(userId), ['2511']);
    });
  });
}
