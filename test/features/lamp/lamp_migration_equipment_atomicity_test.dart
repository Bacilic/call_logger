import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/user_repository.dart';
import 'package:call_logger/features/lamp/services/lamp_migration_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

void main() {
  group('Lamp equipment transfer — atomicity (_saveEquipment)', () {
    late LampMigrationService service;
    late int userXId;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('lamp_equip_atomicity_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/lamp_equip_atomicity.db');
      await DatabaseHelper.instance.database;
      service = LampMigrationService();
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      final db = await DatabaseHelper.instance.database;
      await db.delete('user_equipment');
      await db.delete('equipment');
      await db.delete('users');

      userXId = await db.insert('users', {
        'first_name': 'Γιάννης',
        'last_name': 'Χριστού',
        'is_deleted': 0,
      });
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Future<Set<int>> ownerIdsForEquipment(int id) async {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query(
        'user_equipment',
        columns: ['user_id'],
        where: 'equipment_id = ?',
        whereArgs: [id],
      );
      return rows.map((r) => r['user_id'] as int).toSet();
    }

    test(
      'αποτυχία στη μέση (ανεπίλυτη σύγκρουση κατόχου) → καμία μερική ενημέρωση εξοπλισμού',
      () async {
        const equipmentCode = 'PC-K';
        final db = await DatabaseHelper.instance.database;
        final equipmentId = await db.insert('equipment', {
          'code_equipment': equipmentCode,
          'type': 'Desktop',
          'is_deleted': 0,
        });
        await db.insert('user_equipment', {
          'user_id': userXId,
          'equipment_id': equipmentId,
        });

        await db.insert('users', {
          'first_name': 'Μαρία',
          'last_name': 'Γεωργίου',
          'is_deleted': 0,
        });

        await expectLater(
          service.save(
            target: LampTransferTarget.equipment,
            formValues: {
              'code_equipment': equipmentCode,
              'owner_name': 'Μαρία Γεωργίου',
              'type': 'Laptop',
              'department_name': '',
              'location': '',
              'notes': 'νέα σημείωση',
            },
            selectedCandidateId: equipmentId,
          ),
          throwsA(isA<StateError>()),
        );

        final row = await db.query(
          'equipment',
          where: 'id = ?',
          whereArgs: [equipmentId],
        );
        expect(row.single['type'], 'Desktop');
        expect(row.single['notes'], isNot('νέα σημείωση'));
        expect(await ownerIdsForEquipment(equipmentId), {userXId});
      },
    );

    test(
      'επιτυχής αποθήκευση νέου εξοπλισμού με κάτοχο παραμένει ατομική (smoke)',
      () async {
        final result = await service.save(
          target: LampTransferTarget.equipment,
          formValues: {
            'code_equipment': 'PC-NEW-ATOMIC',
            'owner_name': 'Γιάννης Χριστού',
            'type': 'Desktop',
            'department_name': '',
            'location': '',
            'notes': '',
          },
          selectedCandidateId: null,
        );

        final db = await DatabaseHelper.instance.database;
        final users = UserRepository(db);
        final owners = await users.getEquipmentOwnerSnapshots(result.id);
        expect(owners, hasLength(1));
        expect(owners.single['id'], userXId);
      },
    );
  });
}
