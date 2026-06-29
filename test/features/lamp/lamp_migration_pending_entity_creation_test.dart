import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/features/lamp/services/lamp_migration_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

void main() {
  group('LampMigrationService pending entity creation gate', () {
    late LampMigrationService service;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('lamp_pending_create_');
      await DatabaseHelper.bindTestDatabaseFile(
        '${dir.path}/lamp_pending_create.db',
      );
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
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Future<int> userCount() async {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM users');
      return rows.first['c'] as int;
    }

    Future<int> equipmentCount() async {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM equipment');
      return rows.first['c'] as int;
    }

    Map<String, String> equipmentForm({required String ownerName}) {
      return {
        'code_equipment': 'PC-PENDING',
        'owner_name': ownerName,
        'type': 'Desktop',
        'department_name': '',
        'location': '',
        'notes': '',
      };
    }

    test(
      'equipment save blocks bare user creation without confirmation',
      () async {
        const unknownOwner = 'Άγνωστος Χρήστης';

        await expectLater(
          service.save(
            target: LampTransferTarget.equipment,
            formValues: equipmentForm(ownerName: unknownOwner),
            selectedCandidateId: null,
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message.toLowerCase(),
              'message',
              contains('απαιτείται επιβεβαίωση δημιουργίας'),
            ),
          ),
        );

        expect(await userCount(), 0);
        expect(await equipmentCount(), 0);
      },
    );

    test(
      'equipment save creates bare user when confirmation is granted',
      () async {
        const unknownOwner = 'Άγνωστος Χρήστης';

        final result = await service.save(
          target: LampTransferTarget.equipment,
          formValues: equipmentForm(ownerName: unknownOwner),
          selectedCandidateId: null,
          confirmEntityCreations: true,
        );

        expect(result.id, isNotNull);
        expect(await userCount(), 1);
        expect(await equipmentCount(), 1);

        final db = await DatabaseHelper.instance.database;
        final links = await db.query(
          'user_equipment',
          where: 'equipment_id = ?',
          whereArgs: [result.id],
        );
        expect(links, hasLength(1));
      },
    );

    test(
      'owner save blocks bare equipment creation without confirmation',
      () async {
        final db = await DatabaseHelper.instance.database;
        final userId = await db.insert('users', {
          'first_name': 'Γιάννης',
          'last_name': 'Παπαδόπουλος',
          'is_deleted': 0,
        });

        await expectLater(
          service.save(
            target: LampTransferTarget.owner,
            formValues: {
              'first_name': 'Γιάννης',
              'last_name': 'Παπαδόπουλος',
              'phones': '',
              'equipment_codes': 'PC-NEW-LINK',
              'department_name': '',
              'location': '',
              'notes': '',
            },
            selectedCandidateId: userId,
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message.toLowerCase(),
              'message',
              contains('απαιτείται επιβεβαίωση δημιουργίας'),
            ),
          ),
        );

        expect(await equipmentCount(), 0);
      },
    );

    test(
      'owner save creates bare equipment when confirmation is granted',
      () async {
        final db = await DatabaseHelper.instance.database;
        final userId = await db.insert('users', {
          'first_name': 'Γιάννης',
          'last_name': 'Παπαδόπουλος',
          'is_deleted': 0,
        });

        await service.save(
          target: LampTransferTarget.owner,
          formValues: {
            'first_name': 'Γιάννης',
            'last_name': 'Παπαδόπουλος',
            'phones': '',
            'equipment_codes': 'PC-NEW-LINK',
            'department_name': '',
            'location': '',
            'notes': '',
          },
          selectedCandidateId: userId,
          confirmEntityCreations: true,
        );

        expect(await equipmentCount(), 1);
        final links = await db.query(
          'user_equipment',
          where: 'user_id = ?',
          whereArgs: [userId],
        );
        expect(links, hasLength(1));
      },
    );

    test(
      'save proceeds without confirmation when linked entities already exist',
      () async {
        final db = await DatabaseHelper.instance.database;
        await db.insert('users', {
          'first_name': 'Μαρία',
          'last_name': 'Γεωργίου',
          'is_deleted': 0,
        });
        final equipmentId = await db.insert('equipment', {
          'code_equipment': 'PC-EXISTS',
          'is_deleted': 0,
        });

        await service.save(
          target: LampTransferTarget.equipment,
          formValues: equipmentForm(ownerName: 'Μαρία Γεωργίου')
            ..['code_equipment'] = 'PC-EXISTS',
          selectedCandidateId: equipmentId,
        );

        expect(await userCount(), 1);
        expect(await equipmentCount(), 1);
      },
    );

    test('detectPendingEntityCreations does not mutate database', () async {
      final beforeUsers = await userCount();
      final beforeEquipment = await equipmentCount();

      final pending = await service.detectPendingEntityCreations(
        target: LampTransferTarget.equipment,
        formValues: equipmentForm(ownerName: 'Άγνωστος Χρήστης'),
        selectedCandidateId: null,
      );

      expect(pending, hasLength(1));
      expect(pending.first.entityKind, LampPendingEntityKind.user);
      expect(await userCount(), beforeUsers);
      expect(await equipmentCount(), beforeEquipment);
    });
  });
}
