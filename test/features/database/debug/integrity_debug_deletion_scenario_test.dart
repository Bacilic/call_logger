import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/equipment_repository.dart';
import 'package:call_logger/core/database/phone_repository.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/database/debug/integrity_debug_seeder_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../test_setup.dart';

void main() {
  group('IntegrityDebugSeeder · σενάριο διαγραφών Πληροφορική', () {
    late Database db;
    late IntegrityDebugSeederService seeder;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp(
        'integrity_debug_deletion_scenario_',
      );
      await DatabaseHelper.bindTestDatabaseFile(
        '${dir.path}/integrity_debug_deletion.db',
      );
      db = await DatabaseHelper.instance.database;
      seeder = IntegrityDebugSeederService();
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('user_equipment');
      await db.delete('user_phones');
      await db.delete('department_phones');
      await db.delete('equipment');
      await db.delete('phones');
      await db.delete('users');
      await db.delete('departments');
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    test(
      'insertInformatikiDeletionScenario: τμήμα, 6 υπάλληλοι, προσωπικά τηλ., owned εξοπλισμός',
      () async {
        await db.transaction((txn) async {
          await seeder.insertInformatikiDeletionScenario(txn);
        });

        final depts = await db.query(
          'departments',
          where: 'name = ? AND COALESCE(is_deleted, 0) = 0',
          whereArgs: [IntegrityDebugSeederService.informatikiDepartmentName],
        );
        expect(depts, hasLength(1));
        final deptId = depts.first['id'] as int;
        expect(
          depts.first['name_key'],
          SearchTextNormalizer.normalizeForSearch(
            IntegrityDebugSeederService.informatikiDepartmentName,
          ),
        );

        final users = await db.query(
          'users',
          where: 'department_id = ? AND COALESCE(is_deleted, 0) = 0',
          whereArgs: [deptId],
          orderBy: 'id ASC',
        );
        expect(users, hasLength(6));

        for (var i = 0; i < 6; i++) {
          final expected = IntegrityDebugSeederService.informatikiEmployees[i];
          expect(users[i]['first_name'], expected.$1);
          expect(users[i]['last_name'], expected.$2);

          final userId = users[i]['id'] as int;
          final phoneRows = await db.rawQuery(
            '''
            SELECT p.number AS number
            FROM user_phones up
            JOIN phones p ON p.id = up.phone_id
            WHERE up.user_id = ? AND COALESCE(p.is_deleted, 0) = 0
            ''',
            [userId],
          );
          expect(phoneRows, hasLength(1));
          expect(
            phoneRows.first['number'],
            IntegrityDebugSeederService.informatikiPersonalPhones[i],
          );

          final eqRows = await db.rawQuery(
            '''
            SELECT e.code_equipment AS code, e.department_id AS department_id
            FROM user_equipment ue
            JOIN equipment e ON e.id = ue.equipment_id
            WHERE ue.user_id = ? AND COALESCE(e.is_deleted, 0) = 0
            ''',
            [userId],
          );
          expect(eqRows, hasLength(1));
          expect(
            eqRows.first['code'],
            IntegrityDebugSeederService.informatikiEquipmentCodes[i],
          );
          expect(eqRows.first['department_id'], isNull);
        }
      },
    );

    test(
      'insertInformatikiDeletionScenario: πολλαπλές συνδέσεις Δρόσου (2854/3604) και Βλάση (2852/3602)',
      () async {
        await db.transaction((txn) async {
          await seeder.insertInformatikiDeletionScenario(txn);
        });

        final phones = PhoneRepository(db);
        final equipment = EquipmentRepository(db);

        Future<int> phoneIdOf(String number) async {
          final rows = await db.query(
            'phones',
            columns: ['id'],
            where: 'number = ? AND COALESCE(is_deleted, 0) = 0',
            whereArgs: [number],
            limit: 1,
          );
          expect(rows, hasLength(1), reason: 'τηλέφωνο $number');
          return rows.first['id'] as int;
        }

        Future<int> equipmentIdOf(String code) async {
          final rows = await db.query(
            'equipment',
            columns: ['id'],
            where: 'code_equipment = ? AND COALESCE(is_deleted, 0) = 0',
            whereArgs: [code],
            limit: 1,
          );
          expect(rows, hasLength(1), reason: 'εξοπλισμός $code');
          return rows.first['id'] as int;
        }

        final drososPhoneId = await phoneIdOf('2854');
        final vlasisPhoneId = await phoneIdOf('2852');
        final drososEqId = await equipmentIdOf('3604');
        final vlasisEqId = await equipmentIdOf('3602');

        expect(
          await phones.countPhoneReferencesExcludingAudit(
            drososPhoneId,
            '2854',
          ),
          9,
        );
        expect(
          await phones.countPhoneReferencesExcludingAudit(
            vlasisPhoneId,
            '2852',
          ),
          5,
        );
        expect(
          await equipment.countEquipmentReferencesExcludingAudit(drososEqId),
          7,
        );
        expect(
          await equipment.countEquipmentReferencesExcludingAudit(vlasisEqId),
          3,
        );
      },
    );
  });
}
