import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/user_repository.dart';
import 'package:call_logger/features/lamp/services/lamp_migration_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

void main() {
  group('ΖΤ-18 residual 10Β — _resolveOwnerId μέσα σε transaction', () {
    late LampMigrationService service;
    late UserRepository users;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('lamp_equip_res_10b_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/lamp_equip_res_10b.db');
      await DatabaseHelper.instance.database;
      service = LampMigrationService();
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      final db = await DatabaseHelper.instance.database;
      await db.delete('user_equipment');
      await db.delete('user_phones');
      await db.delete('phones');
      await db.delete('equipment');
      await db.delete('users');
      users = UserRepository(db);
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    test(
      'repository: insertUser σε αποτυχημένη transaction δεν αφήνει ορφανό χρήστη',
      () async {
        final db = await DatabaseHelper.instance.database;

        await expectLater(
          db.transaction((txn) async {
            await users.insertUser(
              firstName: 'Ορφανός',
              lastName: 'Κάτοχος',
              executor: txn,
            );
            throw StateError('προσομοίωση αποτυχίας αποθήκευσης εξοπλισμού');
          }),
          throwsA(isA<StateError>()),
        );

        expect(
          await db.query('users', where: 'first_name = ?', whereArgs: ['Ορφανός']),
          isEmpty,
        );
      },
    );

    test(
      'service: νέος κάτοχος + εξοπλισμός αποθηκεύονται μαζί (smoke)',
      () async {
        final result = await service.save(
          target: LampTransferTarget.equipment,
          formValues: {
            'code_equipment': 'PC-RES-10B',
            'owner_name': 'Νέος Κάτοχος',
            'type': 'Desktop',
            'department_name': '',
            'location': '',
            'notes': '',
          },
          selectedCandidateId: null,
          confirmEntityCreations: true,
        );

        final db = await DatabaseHelper.instance.database;
        expect(
          await db.query('users', where: 'first_name = ?', whereArgs: ['Νέος']),
          hasLength(1),
        );
        expect(
          await db.query('equipment', where: 'code_equipment = ?', whereArgs: ['PC-RES-10B']),
          hasLength(1),
        );
        final owners = await users.getEquipmentOwnerSnapshots(result.id);
        expect(owners, hasLength(1));
        expect(owners.single['first_name'], 'Νέος');
      },
    );
  });
}
